import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/prompt_plugin.dart';

/// 把「插件 + 时间行 + 用户提示词 + 检索资料」拼成最终 system prompt。
///
/// 所有请求都必须走这里，避免聊天页、设置预览、测试各拼一套。
class PromptAssembler {
  PromptAssembler._();

  /// 解析本次实际生效的插件。
  ///
  /// [sessionIds] 为 null 表示跟随全局；空列表表示本会话明确不用。
  static List<PromptPlugin> resolve(
    AppSettings settings,
    List<String>? sessionIds,
  ) {
    if (sessionIds == null) return settings.plugins;
    final Set<String> ids = sessionIds.toSet();
    return settings.plugins
        .where((PromptPlugin p) => ids.contains(p.id))
        .toList();
  }

  /// 拼装最终提示词。
  ///
  /// 顺序：插件（按 priority）→ 时间行 → 用户提示词 → 检索资料。
  /// [overrideAppLines] 为 true 时跳过时间行与检索引导语（引导语由
  /// SearchService 在生成 context 时就不写）。
  static String build({
    required List<PromptPlugin> plugins,
    required String dateLine,
    required String basePrompt,
    required String searchContext,
    required bool overrideAppLines,
    DateTime? now,
    String? model,
  }) {
    final DateTime clock = now ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final Map<String, String> vars = <String, String>{
      'date': '${clock.year}-${two(clock.month)}-${two(clock.day)}',
      'time': '${two(clock.hour)}:${two(clock.minute)}',
      'model': model ?? '',
    };

    final List<PromptPlugin> usable =
        plugins.where((PromptPlugin p) => p.isUsable).toList()
          ..sort(
            (PromptPlugin a, PromptPlugin b) =>
                a.priority.compareTo(b.priority),
          );

    final List<String> parts = <String>[];
    int used = 0;
    for (final PromptPlugin plugin in usable) {
      String text = _applyVars(plugin.body.trim(), vars);
      if (text.length > PromptPlugin.maxBodyChars) {
        text = text.substring(0, PromptPlugin.maxBodyChars);
      }
      // 超出总预算的插件直接跳过，而不是悄悄截断正文。
      if (used + text.length > PromptPlugin.maxTotalChars) continue;
      used += text.length;
      parts.add(text);
    }

    if (!overrideAppLines && dateLine.trim().isNotEmpty) {
      parts.add(dateLine.trim());
    }
    if (basePrompt.trim().isNotEmpty) parts.add(basePrompt.trim());
    if (searchContext.trim().isNotEmpty) parts.add(searchContext.trim());
    return parts.join('\n\n');
  }

  static String _applyVars(String text, Map<String, String> vars) {
    String out = text;
    for (final MapEntry<String, String> entry in vars.entries) {
      out = out.replaceAll('{{${entry.key}}}', entry.value);
    }
    return out;
  }
}
