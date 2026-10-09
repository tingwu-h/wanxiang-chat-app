import 'package:flutter/material.dart';

/// 长按气泡时弹出的轻量操作菜单。
///
/// 形状按选项数量自动切换（项目约定）：
/// - **只有 1 项** → 胶囊形（两端半圆），菜单很窄时看起来不笨重
/// - **2 项及以上** → 圆角矩形，多行排列时更整齐
///
/// 为什么不用 `showMenu`：系统菜单的圆角固定，无法按选项数量改变形状，
/// 而且样式跟随 Material 主题，很难做到「胶囊/圆角」两种形态。
enum BubbleMenuShape { auto, capsule, rounded }

class BubbleMenuAction {
  const BubbleMenuAction({
    required this.label,
    required this.icon,
    this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onSelected;
}

/// 在 [anchor] 附近弹出操作菜单；点某项会执行它的 onSelected，点空白处取消。
Future<void> showBubbleMenu(
  BuildContext context, {
  required List<BubbleMenuAction> actions,
  required Rect anchor,
}) async {
  if (actions.isEmpty) return;
  final int? picked = await showDialog<int>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    useSafeArea: false,
    builder: (BuildContext ctx) => _BubbleMenuOverlay(
      actions: actions,
      anchor: anchor,
    ),
  );
  if (picked == null) return;
  actions[picked].onSelected?.call();
}

class _BubbleMenuOverlay extends StatelessWidget {
  const _BubbleMenuOverlay({required this.actions, required this.anchor});

  final List<BubbleMenuAction> actions;
  final Rect anchor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);

    // 单项 → 胶囊；多项 → 圆角矩形
    final bool capsule = actions.length == 1;
    final BorderRadius radius = capsule
        ? BorderRadius.circular(999)
        : BorderRadius.circular(14);

    const double itemHeight = 44;
    const double width = 208;
    final double height = actions.length * itemHeight + 8;

    // 默认贴在气泡上方；上方放不下就翻到下方
    double top = anchor.top - height - 6;
    if (top < padding.top + 8) top = anchor.bottom + 6;
    top = top.clamp(padding.top + 8, screen.height - height - padding.bottom - 8);

    // 横向尽量与气泡对齐，但不越界
    double left = anchor.right - width;
    left = left.clamp(8, screen.width - width - 8);

    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: radius,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < actions.length; i++)
                      _MenuItem(
                        action: actions[i],
                        height: itemHeight,
                        onTap: () => Navigator.of(context).pop(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.action,
    required this.height,
    required this.onTap,
  });

  final BubbleMenuAction action;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Icon(action.icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
