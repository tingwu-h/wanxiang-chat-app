import 'dart:async';

import 'package:flutter/material.dart';

/// 助手回复「等待首个字」时显示的三个跳动圆点。
///
/// 超过 [slowAfter] 之后会额外显示已等待秒数：
/// 服务商异常时可能出现"一直转圈但没有内容"，让用户看见等了多久，
/// 比一个什么也不说的转圈更有用——他可以据此决定是否按停止。
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    this.label = '正在思考',
    this.slowAfter = const Duration(seconds: 15),
    this.waitingLabelBuilder,
  });

  final String label;

  /// 等待超过这个时长才开始显示秒数，避免正常响应也闪一下计时
  final Duration slowAfter;

  /// 把已等待秒数拼成可显示的文案（由调用方接入三语本地化）。
  ///
  /// 不在这里直接调 tr()：本组件被单独测试过，不希望它依赖 Localizations。
  final String Function(int seconds)? waitingLabelBuilder;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  final Stopwatch _waited = Stopwatch()..start();
  Timer? _ticker;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    // 每秒刷新一次已等待秒数；到 slowAfter 之前不显示，避免正常响应闪烁
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final int s = _waited.elapsed.inSeconds;
      if (s != _seconds) setState(() => _seconds = s);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool showElapsed = _seconds >= widget.slowAfter.inSeconds;
    return Row(
      children: <Widget>[
        Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          widget.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (showElapsed) ...<Widget>[
          const SizedBox(width: 6),
          Text(
            widget.waitingLabelBuilder?.call(_seconds) ?? '已等待 $_seconds 秒',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(width: 6),
        AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) {
            return Row(
              children: List<Widget>.generate(3, (int i) {
                // 每个点错开 1/3 个周期
                final double t = (_controller.value + i / 3) % 1.0;
                final double scale = 0.6 + 0.4 * (1 - (t - 0.5).abs() * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}
