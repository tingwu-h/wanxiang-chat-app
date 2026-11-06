import 'package:deepseek_chat/utils/app_localizations.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deepseek_chat/models/chat_attachment.dart';

/// 底部输入栏：附件预览 + 多行输入框 + 发送 / 停止按钮。
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.onPickImages,
    required this.onPickFiles,
    required this.onTakePhoto,
    required this.onRemoveAttachment,
    required this.isLoading,
    required this.enabled,
    this.attachments = const <ChatAttachment>[],
    this.quotedText = '',
    this.onClearQuote,
    this.modelSelector,
    this.translucent = false,
    this.searchEnabled = false,
    this.onToggleSearch,
    this.searchAvailable = true,
    this.isSearching = false,
    this.thinkingEnabled = true,
    this.thinkingAvailable = false,
    this.onToggleThinking,
  });

  /// 点击发送（文字已 trim，可能为空串——表示只发附件）
  final Future<bool> Function(String) onSend;

  /// 点击停止生成
  final VoidCallback onStop;

  /// 选图片 / 选文件 / 拍照
  final VoidCallback onPickImages;
  final VoidCallback onPickFiles;
  final VoidCallback onTakePhoto;

  /// 移除某个待发送附件
  final ValueChanged<ChatAttachment> onRemoveAttachment;

  final bool isLoading;

  /// false 表示还没配置 API Key，禁止发送
  final bool enabled;

  /// 当前已选、还没发出去的附件
  final List<ChatAttachment> attachments;

  /// 从气泡「追问」引用过来的文字，显示在输入框上方；空串表示没有引用
  final String quotedText;

  /// 点引用条右侧的 ✕
  final VoidCallback? onClearQuote;

  final Widget? modelSelector;
  final bool translucent;

  /// 联网搜索开关状态（与设置页联动）
  final bool searchEnabled;

  /// 点击联网开关
  final VoidCallback? onToggleSearch;

  /// 是否具备联网条件（配了 DeepSeek Key）；false 时开关置灰
  final bool searchAvailable;

  /// 正在检索中，显示「正在搜索…」
  final bool isSearching;

  /// 深度思考是否开启（仅 DeepSeek 有效）
  final bool thinkingEnabled;

  /// 当前服务商是否支持深度思考开关；false 时该按钮不显示
  final bool thinkingAvailable;

  /// 点击深度思考开关
  final VoidCallback? onToggleThinking;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final bool hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  Future<void> _submit() async {
    if (widget.isLoading) return;
    final String text = _controller.text.trim();
    // 有附件时允许只发附件、不写文字
    if (text.isEmpty && widget.attachments.isEmpty) return;
    if (!widget.enabled) return;
    if (!await widget.onSend(text) || !mounted) return;
    _controller.clear();
    _hasText = false;
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      key: const ValueKey('chat-bottom-surface'),
      // 输入卡片和消息列表共享底层背景，避免底部出现割裂的色块。
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('message-composer'),
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              decoration: BoxDecoration(
                color: widget.translucent
                    ? scheme.surfaceContainerLow.withValues(alpha: .82)
                    : scheme.surface.withValues(alpha: .96),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.52),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: .08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.quotedText.trim().isNotEmpty) _buildQuoteBar(),
                  if (widget.attachments.isNotEmpty) _buildAttachmentStrip(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      _buildAddButton(),
                      const SizedBox(width: 4),
                      _buildSearchToggle(),
                      if (widget.thinkingAvailable) _buildThinkingToggle(),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines:
                              MediaQuery.sizeOf(context).height -
                                      MediaQuery.viewInsetsOf(context).bottom <
                                  400
                              ? 2
                              : 5,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !widget.isLoading,
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: InputDecoration(
                            fillColor: widget.translucent
                                ? scheme.surfaceContainerLow.withValues(
                                    alpha: .5,
                                  )
                                : null,
                            hintText: widget.enabled
                                ? (widget.isLoading
                                      ? tr(context, '正在回复…')
                                      : tr(context, '给万象发消息…'))
                                : tr(context, '请先在设置里填写 API Key'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(),
                    ],
                  ),
                  if (widget.modelSelector != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: widget.modelSelector,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 已选附件的小卡片（图片显示缩略图，文本显示文件名）
  /// 引用条：显示从气泡追问过来的选中文字，可一键清除。
  ///
  /// 只显示一行并省略号截断——引用可能很长，展开会把输入框顶得没地方；
  /// 实际发送的是完整文字（见 chat_page 里拼 Markdown 引用块那段）。
  Widget _buildQuoteBar() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: scheme.primary, width: 3),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.format_quote, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.quotedText.replaceAll('\n', ' ').trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              tooltip: tr(context, '清除引用'),
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: widget.onClearQuote,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentStrip() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: widget.attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final ChatAttachment a = widget.attachments[i];
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant),
                  color: scheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: a.isImage
                    ? Image.file(
                        File(a.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      )
                    : _fileTile(a),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: () => widget.onRemoveAttachment(a),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.error,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 13, color: scheme.onError),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fileTile(ChatAttachment a) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.description_outlined, size: 22, color: scheme.primary),
          const SizedBox(height: 2),
          Text(
            a.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }

  /// 联网开关：状态可见、可点、不可用时置灰并说明原因。
  ///
  /// 它会即时反映到设置里（由聊天页处理联动），
  /// 所以这里只负责展示与回调，不自己存状态。
  Widget _buildSearchToggle() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool on = widget.searchEnabled;
    final bool canTap = widget.searchAvailable && widget.onToggleSearch != null;

    final String tooltip = !widget.searchAvailable
        ? tr(context, '联网搜索需要 DeepSeek API Key')
        : on
        ? tr(context, '联网搜索：已开启（点击关闭）')
        : tr(context, '联网搜索：已关闭（点击开启）');

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: canTap ? widget.onToggleSearch : null,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        icon: widget.isSearching
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              )
            // 用项目自带图标（用户提供），比 Material 的 travel_explore 更贴合品牌；
            // 源图只有 26px，所以按 18dp 小尺寸渲染并开启中等插值，尽量减轻发虚。
            : Opacity(
                opacity: on
                    ? 1
                    : (widget.searchAvailable ? 0.62 : 0.28),
                child: Image.asset(
                  'assets/branding/search_icon.png',
                  width: 18,
                  height: 18,
                  filterQuality: FilterQuality.medium,
                ),
              ),
      ),
    );
  }

  /// 深度思考快捷开关。
  ///
  /// 只在 DeepSeek 下显示——这是 DeepSeek 专有参数，
  /// 对其它服务商显示出来会让人误以为能控制。
  Widget _buildThinkingToggle() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool on = widget.thinkingEnabled;
    return Tooltip(
      message: on
          ? tr(context, '深度思考：已开启（点击关闭）')
          : tr(context, '深度思考：已关闭（点击开启）'),
      child: IconButton(
        onPressed: widget.onToggleThinking,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          on ? Icons.psychology : Icons.psychology_outlined,
          color: on ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildAddButton() {    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active = widget.enabled && !widget.isLoading;
    return PopupMenuButton<String>(
      clipBehavior: Clip.antiAlias,
      tooltip: tr(context, '添加图片或文件'),
      enabled: active,
      onSelected: (String v) {
        if (v == 'camera') widget.onTakePhoto();
        if (v == 'image') widget.onPickImages();
        if (v == 'file') widget.onPickFiles();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'camera',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr(context, '拍照')),
            subtitle: Text(tr(context, '直接调用相机拍摄')),
          ),
        ),
        PopupMenuItem<String>(
          value: 'image',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image_outlined),
            title: Text(tr(context, '图片')),
            subtitle: const Text('png / jpg / gif / webp'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'file',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.attach_file),
            title: Text(tr(context, '文件')),
            subtitle: Text(tr(context, 'txt / md / json / csv / 代码')),
          ),
        ),
      ],
      child: Container(
        width: 44,
        height: 48,
        alignment: Alignment.center,
        child: Icon(
          Icons.add_circle_outline,
          size: 26,
          color: active
              ? scheme.primary
              : scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (widget.isLoading) {
      return IconButton.filledTonal(
        onPressed: () {
          HapticFeedback.selectionClick();
          widget.onStop();
        },
        tooltip: tr(context, '停止生成'),
        icon: const Icon(Icons.stop_rounded),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
      );
    }

    final bool canSend =
        (_hasText ||
            widget.attachments.isNotEmpty ||
            widget.quotedText.trim().isNotEmpty) &&
        widget.enabled;
    return IconButton.filled(
      onPressed: canSend
          ? () {
              HapticFeedback.lightImpact();
              _submit();
            }
          : null,
      tooltip: tr(context, '发送'),
      icon: const Icon(Icons.arrow_upward_rounded),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}
