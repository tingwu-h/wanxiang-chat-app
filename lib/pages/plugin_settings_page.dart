import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/prompt_plugin.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/services/attachment_service.dart';
import 'package:deepseek_chat/services/builtin_plugins.dart';
import 'package:deepseek_chat/services/platform_service.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';
import 'package:deepseek_chat/utils/prompt_assembler.dart';

/// 指令插件（提示词层）。
class PluginSettingsPage extends StatelessWidget {
  const PluginSettingsPage({super.key});

  static const String routeName = '/plugins';

  Future<void> _replaceAt(
    AppSettingsProvider provider,
    List<PromptPlugin> plugins,
    int index,
    PromptPlugin next,
  ) {
    final List<PromptPlugin> copy = List<PromptPlugin>.from(plugins);
    copy[index] = next;
    return provider.updatePlugins(plugins: copy);
  }

  Future<void> _normalize(
    AppSettingsProvider provider,
    List<PromptPlugin> plugins,
  ) {
    final List<PromptPlugin> copy = <PromptPlugin>[
      for (int i = 0; i < plugins.length; i++)
        plugins[i].copyWith(priority: i),
    ];
    return provider.updatePlugins(plugins: copy);
  }

  Future<void> _import(
    BuildContext context,
    AppSettingsProvider provider,
  ) async {
    final List<ChatAttachment> picked;
    try {
      picked = await AttachmentService().pickFiles(
        edit: (String path) async => File(path),
      );
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
      return;
    }
    final String text = picked
        .where((ChatAttachment a) => !a.isImage)
        .map((ChatAttachment a) => a.textContent ?? '')
        .where((String t) => t.trim().isNotEmpty)
        .join('\n\n')
        .trim();
    if (text.isEmpty) {
      if (context.mounted) _snack(context, tr(context, '没有可导入的文本'));
      return;
    }
    final PromptPlugin plugin = PromptPlugin(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: picked.first.name,
      body: text.length > PromptPlugin.maxBodyChars
          ? text.substring(0, PromptPlugin.maxBodyChars)
          : text,
      priority: provider.settings.plugins.length,
    );
    await provider.updatePlugins(
      plugins: <PromptPlugin>[...provider.settings.plugins, plugin],
    );
    if (context.mounted) _snack(context, tr(context, '已导入插件'));
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _viewBuiltin(
    BuildContext context,
    AppSettingsProvider provider,
    PromptPlugin plugin,
  ) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(plugin.name),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(plugin.body)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyBuiltin(context, provider, plugin);
            },
            child: Text(tr(ctx, '复制为自定义')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, '关闭')),
          ),
        ],
      ),
    );
  }

  Future<void> _copyBuiltin(
    BuildContext context,
    AppSettingsProvider provider,
    PromptPlugin plugin,
  ) async {
    final PromptPlugin copy = PromptPlugin(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '${plugin.name}${tr(context, '（副本）')}',
      body: plugin.body,
      priority: 100 + provider.settings.plugins.length,
    );
    await provider.updatePlugins(
      plugins: <PromptPlugin>[...provider.settings.plugins, copy],
    );
    if (context.mounted) _snack(context, tr(context, '已复制为自定义插件'));
  }

  void _preview(BuildContext context, AppSettingsProvider provider) {
    final String sample = PromptAssembler.build(
      plugins: PromptAssembler.resolve(provider.settings, null),
      dateLine: '当前时间是 2026-01-01 12:00（星期四，设备本地时间）。',
      basePrompt: provider.settings.systemPrompt,
      searchContext: '',
      overrideAppLines: provider.settings.pluginOverrideAppLines,
      model: provider.settings.model,
    );
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr(ctx, '预览最终提示词')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              sample.isEmpty ? tr(ctx, '（当前没有可发送的提示词）') : sample,
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, '关闭')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSettingsProvider provider = context.watch<AppSettingsProvider>();
    final List<PromptPlugin> plugins = provider.settings.plugins;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '指令插件'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr(
                context,
                '提示词层，只影响发送给模型的 system prompt；不保证模型一定遵从。',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, '覆盖应用注入的说明')),
            subtitle: Text(
              tr(context, '去掉时间行与检索引导语；问日期可能不准确'),
            ),
            value: provider.settings.pluginOverrideAppLines,
            onChanged: (bool v) => provider.updatePlugins(overrideAppLines: v),
          ),
          const Divider(),
          // 注意：全局 filledButtonTheme 的 minimumSize 是 Size.fromHeight(48)
          // （宽度 infinity），放进 Row 会拿到无界宽度把第二个按钮挤出去。
          // 这里显式把最小宽度收回来，并用 Wrap 防窄屏溢出。
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PluginEditorPage(
                      plugins: plugins,
                      index: -1,
                    ),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(tr(context, '新建插件')),
              ),
              OutlinedButton.icon(
                onPressed: () => _import(context, provider),
                icon: const Icon(Icons.file_open_outlined),
                label: Text(tr(context, '导入插件')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(tr(context, '内置'), style: theme.textTheme.titleSmall),
          for (final PromptPlugin plugin in kBuiltinPlugins)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: Row(
                children: <Widget>[
                  Text(plugin.name),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tr(context, '内置'),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                '${plugin.body.length} 字 · ${tr(context, '随应用内置')}',
              ),
              onTap: () => _viewBuiltin(context, provider, plugin),
              trailing: Switch(
                value: provider.settings.enabledBuiltinPlugins.contains(
                  plugin.id,
                ),
                onChanged: (bool v) =>
                    provider.toggleBuiltinPlugin(plugin.id, v),
              ),
            ),
          const Divider(),
          Text(tr(context, '自定义'), style: theme.textTheme.titleSmall),
          if (plugins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr(context, '还没有插件。新建或导入一个文本文件即可。'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (int i = 0; i < plugins.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.psychology_alt_outlined),
                title: Text(
                  plugins[i].name.trim().isEmpty
                      ? tr(context, '未命名插件')
                      : plugins[i].name,
                ),
                subtitle: Text(
                  '${plugins[i].body.length} 字 · '
                  '${plugins[i].enabled ? tr(context, '已启用') : tr(context, '已停用')}',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PluginEditorPage(
                      plugins: plugins,
                      index: i,
                    ),
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: tr(context, '插件操作'),
                  onSelected: (String value) async {
                    if (value == 'toggle') {
                      await _replaceAt(
                        provider,
                        plugins,
                        i,
                        plugins[i].copyWith(enabled: !plugins[i].enabled),
                      );
                    } else if (value == 'up' && i > 0) {
                      final List<PromptPlugin> copy =
                          List<PromptPlugin>.from(plugins);
                      final PromptPlugin item = copy.removeAt(i);
                      copy.insert(i - 1, item);
                      await _normalize(provider, copy);
                    } else if (value == 'down' && i < plugins.length - 1) {
                      final List<PromptPlugin> copy =
                          List<PromptPlugin>.from(plugins);
                      final PromptPlugin item = copy.removeAt(i);
                      copy.insert(i + 1, item);
                      await _normalize(provider, copy);
                    } else if (value == 'delete') {
                      final List<PromptPlugin> copy =
                          List<PromptPlugin>.from(plugins)..removeAt(i);
                      await _normalize(provider, copy);
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'toggle',
                      child: Text(
                        plugins[i].enabled
                            ? tr(context, '停用')
                            : tr(context, '启用'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'up',
                      enabled: i > 0,
                      child: Text(tr(context, '上移')),
                    ),
                    PopupMenuItem<String>(
                      value: 'down',
                      enabled: i < plugins.length - 1,
                      child: Text(tr(context, '下移')),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(tr(context, '删除')),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _preview(context, provider),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(tr(context, '预览最终提示词')),
          ),
        ],
      ),
    );
  }
}

class _PluginEditorPage extends StatefulWidget {
  const _PluginEditorPage({required this.plugins, required this.index});

  final List<PromptPlugin> plugins;

  /// -1 表示新建
  final int index;

  @override
  State<_PluginEditorPage> createState() => _PluginEditorPageState();
}

class _PluginEditorPageState extends State<_PluginEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _body;

  bool get _isNew => widget.index < 0;
  PromptPlugin? get _current =>
      _isNew ? null : widget.plugins[widget.index];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _current?.name ?? '');
    _body = TextEditingController(text: _current?.body ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettingsProvider provider) async {
    final String body = _body.text.trim();
    if (body.isEmpty) {
      _snack(tr(context, '插件正文不能为空'));
      return;
    }
    if (body.length > PromptPlugin.maxBodyChars) {
      _snack(tr(context, '单条插件不能超过 4000 字'));
      return;
    }
    final List<PromptPlugin> copy = List<PromptPlugin>.from(widget.plugins);
    final PromptPlugin next = (_current ??
            PromptPlugin(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: '',
              body: '',
              priority: copy.length,
            ))
        .copyWith(
          name: _name.text.trim().isEmpty
              ? tr(context, '未命名插件')
              : _name.text.trim(),
          body: body,
        );
    if (_isNew) {
      copy.add(next);
    } else {
      copy[widget.index] = next;
    }
    await provider.updatePlugins(plugins: copy);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _export() async {
    final bool ok = await PlatformService.exportChatText(_body.text.trim());
    if (!mounted) return;
    _snack(
      ok
          ? tr(context, '插件已导出')
          : tr(context, '已取消导出'),
    );
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final AppSettingsProvider provider = context.watch<AppSettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? tr(context, '新建插件') : tr(context, '编辑插件')),
        actions: <Widget>[
          IconButton(
            onPressed: _export,
            tooltip: tr(context, '导出插件'),
            icon: const Icon(Icons.file_download_outlined),
          ),
          TextButton(
            onPressed: () => _save(provider),
            child: Text(tr(context, '保存')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: tr(context, '插件名称'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 10,
            maxLines: 22,
            maxLength: PromptPlugin.maxBodyChars,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: tr(context, '插件正文'),
              alignLabelWithHint: true,
              helperText: tr(context, '支持 {{date}}、{{time}}、{{model}}'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              '插件只在请求时拼接，不会写入聊天记录，也不会出现在导出文件里。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
