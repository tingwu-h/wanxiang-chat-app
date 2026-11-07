import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';
import 'package:deepseek_chat/widgets/thinking_level_slider.dart';

/// 模型行为设置：深度思考、推理强度、图片档位、时间注入。
///
/// 之前这些被塞在「联网搜索」子页里，跟联网毫无关系，很难找。
/// 现在单独成页，入口在设置页单独列出。
class ModelBehaviourPage extends StatefulWidget {
  const ModelBehaviourPage({super.key});

  static const String routeName = '/model-behaviour';

  @override
  State<ModelBehaviourPage> createState() => _ModelBehaviourPageState();
}

class _ModelBehaviourPageState extends State<ModelBehaviourPage> {
  bool _busy = false;

  Future<void> _update(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr(context, '保存失败，请重试'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettingsProvider provider = context.watch<AppSettingsProvider>();
    final AppSettings s = provider.settings;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool deepseek = s.providerId == 'deepseek';

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '模型行为'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),

          Text(tr(context, '思考强度'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          // 与聊天输入栏的「思考」胶囊共用同一个组件：
          // 四档（No / Low / High / Max）一处定义，两处一致。
          ThinkingLevelSlider(
            level: s.thinkingLevel,
            enabled: deepseek,
            onCommit: (int level) => _update(
              () => provider.updateModelBehaviour(
                thinkingEnabled: level > 0,
                // 0 档传 null：保留上次强度，滑回开启时恢复原档。
                reasoningEffort: AppSettings.effortForLevel(level),
              ),
            ),
          ),
          if (!deepseek)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(context, '推理强度仅对 DeepSeek 生效'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),

          Text(tr(context, '图片细节档位'), style: theme.textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: Text(tr(context, '原始')),
                selected: s.imageDetail != 'low',
                onSelected: (_) => _update(
                  () => provider.updateModelBehaviour(imageDetail: ''),
                ),
              ),
              ChoiceChip(
                label: Text(tr(context, '低（更快更省）')),
                selected: s.imageDetail == 'low',
                onSelected: (_) => _update(
                  () => provider.updateModelBehaviour(imageDetail: 'low'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.schedule),
            title: Text(tr(context, '自动告知当前时间')),
            subtitle: Text(
              tr(
                context,
                '模型本身不知道今天是哪天，开启后日期类问题才能准确回答',
              ),
            ),
            value: s.injectCurrentTime,
            onChanged: (bool v) => _update(
              () => provider.updateModelBehaviour(injectCurrentTime: v),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            tr(context, '思考模式下温度设置不生效'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
