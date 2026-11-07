import 'package:flutter/material.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';

/// 四档思考强度滑条：No / Low / High / Max。
///
/// 聊天输入栏的弹出面板和「设置 → 模型行为」共用这一个组件，
/// 保证两处的档位、文案和点击行为完全一致，不会出现同一状态两种说法。
///
/// 只有拖动结束（或点了刻度标签）才回调 [onCommit]：
/// 一次拖动会连续触发几十次 onChanged，逐次写盘既慢又没必要。
class ThinkingLevelSlider extends StatefulWidget {
  const ThinkingLevelSlider({
    super.key,
    required this.level,
    required this.onCommit,
    this.enabled = true,
  });

  /// 当前档位 0..3；0 表示不思考。
  final int level;

  /// 真正生效时回调：拖动结束或点刻度标签。
  final ValueChanged<int> onCommit;

  /// false 时整体置灰且不可拖动（非 DeepSeek 服务商）。
  final bool enabled;

  @override
  State<ThinkingLevelSlider> createState() => ThinkingLevelSliderState();
}

class ThinkingLevelSliderState extends State<ThinkingLevelSlider> {
  static final int _maxLevel = AppSettings.thinkingLevelLabels.length - 1;

  late int _level = _clamp(widget.level);
  bool _dragging = false;

  static int _clamp(int value) => value.clamp(0, _maxLevel);

  @override
  void didUpdateWidget(covariant ThinkingLevelSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改动（设置页 / 输入栏另一处）要同步过来，
    // 但拖动过程中不能改值，否则手指还按着滑条就被拽回去了。
    if (!_dragging && widget.level != oldWidget.level) {
      _level = _clamp(widget.level);
    }
  }

  void _select(int level) {
    final int next = _clamp(level);
    if (next != _level) setState(() => _level = next);
    widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool on = widget.enabled;
    final String description = _level == 0
        ? tr(context, '直接回答，更快更省')
        : tr(context, '先输出推理过程，更慢通常更准');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 5,
            activeTrackColor: on ? scheme.primary : scheme.outlineVariant,
            inactiveTrackColor: scheme.outlineVariant.withValues(alpha: .45),
            thumbColor: on ? scheme.primary : scheme.outline,
            overlayColor: scheme.primary.withValues(alpha: .12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2.5),
            // 刻度由下面的文字标签承担，轨道上不再画点，避免视觉噪音。
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
          ),
          child: Semantics(
            label: tr(context, '思考强度'),
            child: Slider(
              key: const ValueKey('thinking-level-slider'),
              value: _level.toDouble(),
              min: 0,
              max: _maxLevel.toDouble(),
              divisions: _maxLevel,
              label: AppSettings.thinkingLevelLabels[_level],
              semanticFormatterCallback: (double value) =>
                  AppSettings.thinkingLevelLabels[value.round()],
              onChanged: on
                  ? (double value) {
                      _dragging = true;
                      final int next = _clamp(value.round());
                      if (next != _level) {
                        setState(() => _level = next);
                      }
                    }
                  : null,
              onChangeEnd: on
                  ? (double value) {
                      _dragging = false;
                      widget.onCommit(_clamp(value.round()));
                    }
                  : null,
            ),
          ),
        ),
        Row(
          children: <Widget>[
            for (int i = 0; i <= _maxLevel; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: on ? () => _select(i) : null,
                  child: Padding(
                    // 纵向 8 + 文字高度 ≈ 40，接近 48dp 的最小可点区域；
                    // 四个标签平分整行，不会出现“点不准”。
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      AppSettings.thinkingLevelLabels[i],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: !on
                            ? scheme.onSurface.withValues(alpha: .35)
                            : i == _level
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: i == _level
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: on
                ? scheme.onSurfaceVariant
                : scheme.onSurface.withValues(alpha: .35),
          ),
        ),
      ],
    );
  }
}
