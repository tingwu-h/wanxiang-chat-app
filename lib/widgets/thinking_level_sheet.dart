import 'package:flutter/material.dart';

import 'package:deepseek_chat/utils/app_localizations.dart';
import 'package:deepseek_chat/widgets/thinking_level_slider.dart';

/// 点输入栏「思考」胶囊后升起的四档面板。
///
/// 高度由内容决定，不占满屏；面板内改档后不自动关闭，
/// 方便来回对比 Low / High / Max，点「完成」或面板外空白才收起。
class ThinkingLevelSheet extends StatelessWidget {
  const ThinkingLevelSheet({
    super.key,
    required this.level,
    required this.onCommit,
  });

  /// 打开时的档位（0 = No）。
  final int level;

  /// 档位落盘回调。
  final ValueChanged<int> onCommit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      // 键盘正收起来时面板跟着上移，避免被输入法盖住。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(tr(context, '思考强度'), style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(tr(context, '完成')),
                  ),
                ],
              ),
              ThinkingLevelSlider(level: level, onCommit: onCommit),
            ],
          ),
        ),
      ),
    );
  }
}
