import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deepseek_chat/models/app_settings.dart';

/// 思考强度悬浮框：挂在「思考」胶囊上方的一排四档胶囊。
///
/// 不再是底部弹层——那里太占地方、还要一个「完成」按钮。
/// 这里点开即选、选完即收，卡片宽度只够放四个胶囊。
class ThinkingLevelPopover {
  /// 在根 Overlay 上插入浮层，返回可手动移除的 [OverlayEntry]。
  static OverlayEntry show({
    required BuildContext context,
    required LayerLink link,
    required int level,
    required ValueChanged<int> onPick,
    required VoidCallback onDismiss,
    bool showAbove = true,
  }) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => _ThinkingPopoverLayer(
        link: link,
        level: level,
        showAbove: showAbove,
        onPick: onPick,
        onDismiss: onDismiss,
      ),
    );
    overlay.insert(entry);
    return entry;
  }
}

class _ThinkingPopoverLayer extends StatefulWidget {
  const _ThinkingPopoverLayer({
    required this.link,
    required this.level,
    required this.showAbove,
    required this.onPick,
    required this.onDismiss,
  });

  final LayerLink link;
  final int level;
  final bool showAbove;
  final ValueChanged<int> onPick;
  final VoidCallback onDismiss;

  @override
  State<_ThinkingPopoverLayer> createState() => _ThinkingPopoverLayerState();
}

class _ThinkingPopoverLayerState extends State<_ThinkingPopoverLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  )..forward();

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // 透明遮罩：只负责“点外面收起”，不改暗背景，避免弹层感。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          // 右边缘对齐胶囊右边缘，向左展开，避免贴到屏幕右边被裁掉。
          targetAnchor: widget.showAbove
              ? Alignment.topRight
              : Alignment.bottomRight,
          followerAnchor: widget.showAbove
              ? Alignment.bottomRight
              : Alignment.topRight,
          offset: Offset(0, widget.showAbove ? -6 : 6),
          child: FadeTransition(
            opacity: _curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: .96, end: 1).animate(_curve),
              alignment: widget.showAbove
                  ? Alignment.bottomRight
                  : Alignment.topRight,
              child: _buildCard(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('thinking-level-popover'),
      elevation: 10,
      shadowColor: scheme.shadow.withValues(alpha: .18),
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < AppSettings.thinkingLevelLabels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _buildPill(context, i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context, int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool selected = index == widget.level;
    final String label = AppSettings.thinkingLevelLabels[index];

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onPick(index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: ShapeDecoration(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: .75)
                  : Colors.transparent,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected
                      ? scheme.primary.withValues(alpha: .55)
                      : scheme.outlineVariant,
                ),
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 12.5,
                height: 1.05,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
