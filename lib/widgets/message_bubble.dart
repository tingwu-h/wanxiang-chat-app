import 'package:deepseek_chat/models/provider_catalog.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/utils/formatters.dart';
import 'package:deepseek_chat/widgets/typing_indicator.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';

/// 单条聊天气泡：用户消息靠右，助手消息靠左。
///
/// 需要是 StatefulWidget：思考过程的展开/收起是每条气泡自己的界面状态。
class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showTyping = false,
  });

  final ChatMessage message;

  /// 助手消息还没有任何内容时，显示跳动圆点
  final bool showTyping;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  /// 思考过程是否展开。默认收起——用户只想看正文，想看得自己点开。
  bool _thinkingExpanded = false;

  /// 一旦用户手动点过开关，就不再自动展开/收起，免得跟用户抢
  bool _userToggledThinking = false;

  ChatMessage get message => widget.message;

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

    final Color bubbleColor = isError
        ? scheme.errorContainer
        : isUser
        ? scheme.primary
        : scheme.surfaceContainerLowest;

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

          // 气泡本体：限制最大宽度，长按可复制
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.80,
            ),
            child: GestureDetector(
              onLongPress: () => _copy(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: radius,
                  border: isError
                      ? Border.all(color: scheme.error.withValues(alpha: 0.5))
                      : (!isUser
                            ? Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                              )
                            : null),
                ),
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
                    if (message.content.isEmpty && widget.showTyping)
                      TypingIndicator(label: tr(context, '正在生成回答'))
                    else if (message.content.isEmpty &&
                        (message.attachments.isNotEmpty || message.hasThinking))
                      // 只有附件或只有思考内容时，不显示空正文
                      const SizedBox.shrink()
                    else if (isUser || isError)
                      SelectableText(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.42,
                        ),
                      )
                    else if (widget.showTyping)
                      // 正在流式输出：先用纯文本渲染。
                      // MarkdownBody 每来一个字都要重新解析整段内容，
                      // 回答越长越慢，是切换会话/长回答时卡顿的主因之一。
                      // 等生成完再切成 Markdown 渲染（见下面的 else）。
                      SelectableText(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.45,
                        ),
                      )
                    else
                      MarkdownBody(
                        data: message.content,
                        styleSheet: _markdownStyle(theme, textColor),
                      ),
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

  void _copy(BuildContext context) {
    if (message.content.isEmpty) return;
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr(context, '已复制这条消息')),
          duration: const Duration(milliseconds: 1200),
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
