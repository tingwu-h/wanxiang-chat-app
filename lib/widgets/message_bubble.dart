import 'package:deepseek_chat/models/provider_catalog.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/utils/formatters.dart';
import 'package:deepseek_chat/widgets/typing_indicator.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';

/// 单条聊天气泡：用户消息靠右，助手消息靠左。
///
/// 需要是 StatefulWidget：思考过程的展开/收起、以及「选取文本」模式
/// 都是每条气泡自己的界面状态。
class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showTyping = false,
    this.bubbleOpacity = AppSettings.defaultBubbleOpacity,
    this.frosted = true,
    this.onFollowUp,
  });

  final ChatMessage message;

  /// 助手消息还没有任何内容时，显示跳动圆点
  final bool showTyping;

  /// 气泡不透明度（0.3 ~ 1.0），来自用户设置
  final double bubbleOpacity;

  /// 是否启用磨砂玻璃。没设自定义背景时为 false——没有背景可透，
  /// 白白付 BackdropFilter 的开销不值当（项目历史上卡顿过）。
  final bool frosted;

  /// 点「追问」时把选中的文字交给聊天页，由它放进输入框
  final ValueChanged<String>? onFollowUp;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  /// 思考过程是否展开。默认收起——用户只想看正文，想看得自己点开。
  bool _thinkingExpanded = false;

  /// 一旦用户手动点过开关，就不再自动展开/收起，免得跟用户抢
  bool _userToggledThinking = false;

  /// 「选取文本」模式：正文变成可自由框选的文本
  bool _selectionMode = false;

  /// 当前选中的文字（由 onSelectionChanged 维护）
  String _selectedText = '';

  ChatMessage get message => widget.message;
  (String, ThemeData, Color)? _markdownInputs;
  Widget? _markdown;

  Widget _completedMarkdown(ThemeData theme, Color color) {
    final inputs = (message.content, theme, color);
    if (_markdownInputs != inputs) {
      _markdownInputs = inputs;
      _markdown = MarkdownBody(
        data: message.content,
        styleSheet: _markdownStyle(theme, color),
      );
    }
    return _markdown!;
  }

  /// 把不透明度应用到气泡底色。
  ///
  /// 只降透明度不加模糊的话，后面的背景会"透"上来干扰文字，
  /// 所以真正启用磨砂时由 frostedBubble 再叠一层模糊。
  Color _applyOpacity(Color base) =>
      base.withValues(alpha: base.a * widget.bubbleOpacity);


  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isUser = message.isUser;
    final bool isError = message.error;

    // 正在思考、还没出正文时，自动展开让用户知道模型在做什么
    final bool autoExpanded =
        widget.showTyping &&
        message.content.isEmpty &&
        message.hasThinking &&
        !_userToggledThinking;
    final bool thinkingOpen = _thinkingExpanded || autoExpanded;

    final Color bubbleColor = _applyOpacity(
      isError
          ? scheme.errorContainer
          : isUser
          ? scheme.primary
          : scheme.surfaceContainerLowest,
    );

    final Color textColor = isError
        ? scheme.onErrorContainer
        : isUser
        ? scheme.onPrimary
        : scheme.onSurface;

    final BorderRadius radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    message.providerId == null
                        ? tr(context, '万象')
                        : presetFor(message.providerId!).name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // 气泡本体：限制最大宽度。长按弹出操作菜单（复制 / 选取文本）
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.80,
            ),
            child: _frostedBubble(
              color: bubbleColor,
              radius: radius,
              border: isError
                  ? Border.all(
                      color: _applyOpacity(
                        scheme.error.withValues(alpha: 0.5),
                      ),
                    )
                  : (!isUser
                        ? Border.all(
                            color: _applyOpacity(
                              scheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                          )
                        : null),
              // 用 SelectionArea 而不是 GestureDetector.onLongPress：
              // 气泡里有可选中文本时，长按手势会被文本选择机制抢走，
              // 外层 GestureDetector 根本收不到（实测确认过）。
              // SelectionArea 本来就是「长按选中 → 弹菜单」的正规机制，
              // 这里用它的自定义菜单承载「复制 / 选取文本」两项。
              child: SelectionArea(
                onSelectionChanged: (SelectedContent? content) {
                  _selectedText = _selectedFromContent(content);
                },
                contextMenuBuilder: _bubbleContextMenu,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 思考过程（reasoning_content）：单独一块，默认收起
                    if (!isUser && message.hasThinking) ...<Widget>[
                      _buildThinkingBlock(context, textColor, thinkingOpen),
                      const SizedBox(height: 6),
                    ],
                    // 附件：图片缩略图（点开可看大图）/ 文本文件标签
                    if (message.attachments.isNotEmpty) ...<Widget>[
                      _buildAttachments(context),
                      if (message.content.trim().isNotEmpty)
                        const SizedBox(height: 6),
                    ],
                    ..._buildBody(context, theme, textColor, isUser, isError),
                    if (!isUser) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(
                          formatTime(message.timestamp),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: textColor.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 磨砂玻璃气泡。
  ///
  /// 之所以要 ClipRRect 包住 BackdropFilter：BackdropFilter 会把**整块矩形**
  /// 背后的内容都模糊掉，不裁剪的话圆角外围会出现一圈方形的糊斑。
  ///
  /// 没开磨砂时直接用普通容器：没有背景可透时 BackdropFilter 纯属浪费 GPU，
  /// 而流式输出每秒要重绘很多次。
  Widget _frostedBubble({
    required Color color,
    required BorderRadius radius,
    required Widget child,
    Border? border,
  }) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: child,
    );

    if (!widget.frosted) {
      return Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: radius,
          border: border,
        ),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // 6 是实测在"看得出磨砂"和"不糊成一片"之间的折中值
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: radius,
            border: border,
          ),
          child: content,
        ),
      ),
    );
  }

  /// 正文区域。
  ///
  /// 一律用普通 Text：选中能力由外层的 SelectionArea 统一提供。
  /// 这里不能再嵌 SelectableText —— 那会形成第二个选区，
  /// 长按时会同时冒出两套菜单（实测过）。
  List<Widget> _buildBody(
    BuildContext context,
    ThemeData theme,
    Color textColor,
    bool isUser,
    bool isError,
  ) {
    final TextStyle? style = theme.textTheme.bodyMedium?.copyWith(
      color: textColor,
      height: 1.45,
    );

    if (message.content.isEmpty && widget.showTyping) {
      return <Widget>[TypingIndicator(label: tr(context, '正在生成回答'))];
    }
    if (message.content.isEmpty &&
        (message.attachments.isNotEmpty || message.hasThinking)) {
      // 只有附件或只有思考内容时，不显示空正文
      return <Widget>[const SizedBox.shrink()];
    }

    if (isUser || isError) {
      return <Widget>[Text(message.content, style: style)];
    }
    if (widget.showTyping || _selectionMode) {
      // 流式输出期间先用纯文本渲染：
      // MarkdownBody 每来一个字都要重新解析整段内容，回答越长越慢。
      //
      // 用户点了「选取文本」时也走这里：Markdown 渲染出来的文字
      // 在 SelectionArea 里无法选中，换成纯文本才能自由框选。
      return <Widget>[Text(message.content, style: style)];
    }
    return <Widget>[_completedMarkdown(theme, textColor)];
  }

  /// 从选中内容里取出文字。
  ///
  /// 这个 Flutter 版本的 SelectedContent 只暴露 plainText（没有区间偏移），
  /// 所以直接用它的纯文本；气泡里的时间戳等短文本可能被一起选中，
  /// 调用方会再处理一次引用前缀，不影响主要用途。
  String _selectedFromContent(SelectedContent? content) {
    if (content == null) return '';
    return content.plainText.trim();
  }

  /// 长按选中文字后弹出的菜单。
  ///
  /// 菜单项顺序：先给最常用的「复制当前选中文本」与「追问」，
  /// 最后放「复制全文」——用户长按某处往往只是想复制整条回答。
  Widget _bubbleContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final String selected = _selectedText;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          label: tr(context, '复制当前选中文本'),
          onPressed: () {
            ContextMenuController.removeAny();
            if (selected.trim().isEmpty) return;
            _copyText(context, selected, tr(context, '已复制选中文字'));
          },
        ),
        if (widget.onFollowUp != null)
          ContextMenuButtonItem(
            label: tr(context, '追问'),
            onPressed: () {
              ContextMenuController.removeAny();
              if (selected.trim().isEmpty) return;
              widget.onFollowUp!(selected);
            },
          ),
        ContextMenuButtonItem(
          label: tr(context, '复制全文'),
          onPressed: () {
            ContextMenuController.removeAny();
            _copyText(context, message.content, tr(context, '已复制这条消息'));
          },
        ),
        // Markdown 渲染出来的文字在 SelectionArea 里选不了，
        // 想逐字框选就切到纯文本模式——这就是「选取文本」这一项的作用。
        if (!message.isUser && !_selectionMode && message.content.isNotEmpty)
          ContextMenuButtonItem(
            label: tr(context, '选取文本'),
            onPressed: () {
              ContextMenuController.removeAny();
              setState(() {
                _selectionMode = true;
                _selectedText = '';
              });
            },
          ),
      ],
    );
  }

  void _copyText(BuildContext context, String text, String toast) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(toast), duration: const Duration(milliseconds: 1200)),
      );
  }

  /// 思考过程区块：默认收起，只显示一行提示；点一下才展开看全文。
  ///
  /// 为什么不直接混在正文里：思考过程往往很长，混进去会让回答难以阅读，
  /// 而且用户要的答案通常只有最后那几句。
  Widget _buildThinkingBlock(
    BuildContext context,
    Color textColor,
    bool expanded,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int chars = message.thinking.length;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: scheme.outlineVariant, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() {
              _userToggledThinking = true;
              _thinkingExpanded = !expanded;
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    expanded
                        ? tr(context, '思考过程（点击收起）')
                        : tr(context, '思考过程（{count} 字，点击展开）', {'count': chars}),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: SelectableText(
                message.thinking,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor.withValues(alpha: 0.75),
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 气泡里的附件展示：图片缩略图 + 文本文件标签
  Widget _buildAttachments(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Widget> children = <Widget>[];

    for (final ChatAttachment a in message.attachments) {
      if (a.isImage) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: () => _showFullImage(context, a),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(a.path),
                  width: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 200,
                    height: 80,
                    alignment: Alignment.center,
                    color: scheme.surface.withValues(alpha: 0.5),
                    child: Text(tr(context, '图片已不在本地')),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${a.name}（${a.sizeLabel}）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// 点缩略图看大图
  void _showFullImage(BuildContext context, ChatAttachment a) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.file(
              File(a.path),
              errorBuilder: (_, __, ___) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr(context, '图片已不在本地'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Markdown 渲染样式（深色模式下自动适配）
  MarkdownStyleSheet _markdownStyle(ThemeData theme, Color textColor) {
    final ColorScheme scheme = theme.colorScheme;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.45),
      h1: theme.textTheme.titleLarge?.copyWith(color: textColor),
      h2: theme.textTheme.titleMedium?.copyWith(color: textColor),
      h3: theme.textTheme.titleSmall?.copyWith(color: textColor),
      listBullet: theme.textTheme.bodyMedium?.copyWith(color: textColor),
      strong: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w700,
      ),
      em: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      a: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: textColor,
        backgroundColor: scheme.surface.withValues(alpha: 0.6),
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
      ),
      blockquoteDecoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.45),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
    );
  }
}
