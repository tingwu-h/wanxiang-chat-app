import 'package:deepseek_chat/models/model_info.dart';

import 'dart:async';
import 'dart:io';

import 'package:deepseek_chat/pages/image_editor_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/attachment_service.dart';
import 'package:deepseek_chat/services/platform_service.dart';
import 'package:deepseek_chat/widgets/chat_input_bar.dart';
import 'package:deepseek_chat/widgets/conversation_drawer.dart';
import 'package:deepseek_chat/widgets/message_list_view.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';

/// 主页面：悬浮操作栏、消息列表、悬浮输入框及当前服务商模型选择。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AttachmentService _attachments = AttachmentService();
  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 140;

  /// 已选、还没发出去的附件
  final List<ChatAttachment> _pending = <ChatAttachment>[];

  String? _shownError;
  Timer? _backTimer;
  bool _backArmed = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backArmed = false;
      unawaited(context.read<ChatProvider>().stopAndPersist());
    }
  }

  Future<void> _handleBack() async {
    if (_leaving) return;
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
      return;
    }
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      _backArmed = false;
      return;
    }
    if (!_backArmed) {
      _backArmed = true;
      _backTimer?.cancel();
      _backTimer = Timer(const Duration(seconds: 2), () => _backArmed = false);
      _showSnack(tr(context, '再按一次回到桌面'));
      return;
    }
    _leaving = true;
    try {
      await context.read<ChatProvider>().stopAndPersist();
      if (mounted) await PlatformService.goToDesktop();
    } finally {
      _backArmed = false;
      _leaving = false;
    }
  }

  // -------------------------------------------------------------- 发送

  Future<bool> _handleSend(String text) async {
    final ChatProvider chat = context.read<ChatProvider>();
    final AppSettingsProvider settings = context.read<AppSettingsProvider>();

    if (!settings.hasApiKey) {
      // 提示里带上开放平台入口：新用户不用自己去找申请地址
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(tr(context, '请先配置所选服务商的 API Key')),
            action: SnackBarAction(
              label: tr(context, '去设置'),
              onPressed: _openSettings,
            ),
          ),
        );
      _openSettings();
      return false;
    }
    if (text.trim().isEmpty && _pending.isEmpty) return false;
    if (!settings.settings.supportsImages &&
        (_pending.any((a) => a.isImage) ||
            chat.messages.any((m) => m.attachments.any((a) => a.isImage)))) {
      _showSnack(tr(context, '这个对话包含图片，请切换到支持图片的模型，并在设置中确认图片能力。'));
      return false;
    }

    final List<ChatAttachment> sending = List<ChatAttachment>.from(_pending);
    setState(_pending.clear);

    // 故意不 await：让界面立刻回到可输入状态，内容由流式回调驱动刷新
    unawaited(chat.send(text, settings.settings, attachments: sending));
    return true;
  }

  // -------------------------------------------------------------- 附件

  Future<void> _pickImages() async {
    try {
      final List<ChatAttachment> picked = await _attachments.pickImages(
        edit: _editImage,
      );
      await _acceptAttachments(picked);
    } on AttachmentException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      if (mounted) _showSnack(tr(context, '选择图片失败，请重试'));
    }
  }

  Future<void> _pickFiles() async {
    try {
      final List<ChatAttachment> picked = await _attachments.pickFiles(
        edit: _editImage,
      );
      await _acceptAttachments(picked);
    } on AttachmentException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      if (mounted) _showSnack(tr(context, '选择文件失败，请重试'));
    }
  }

  void _removePending(ChatAttachment a) {
    setState(() => _pending.remove(a));
    if (a.isImage) unawaited(_deletePending([a]));
  }

  Future<File?> _editImage(String path) async {
    if (!mounted) return null;
    return ImageEditorPage.open(context, path);
  }

  Future<void> _acceptAttachments(List<ChatAttachment> picked) async {
    if (!mounted) {
      await _deletePending(picked);
      return;
    }
    try {
      AttachmentService.validateSelection([..._pending, ...picked]);
    } catch (_) {
      await _deletePending(picked);
      rethrow;
    }
    setState(() => _pending.addAll(picked));
  }

  Future<void> _deletePending(List<ChatAttachment> items) async {
    try {
      for (final a in items.where((a) => a.isImage)) {
        await AttachmentService.removeOwnedFile(a.path);
      }
    } catch (_) {
      if (mounted) _showSnack(tr(context, '部分临时图片未能清理，请稍后重试。'));
    }
  }

  Future<void> _clearPending() async {
    final items = List<ChatAttachment>.from(_pending);
    if (mounted) setState(_pending.clear);
    await _deletePending(items);
  }

  // -------------------------------------------------------------- 会话

  Future<void> _newConversation() async {
    await context.read<ChatProvider>().newConversation();
    if (!mounted) return;
    await _clearPending();
  }

  Future<void> _openSettings() async {
    final chat = context.read<ChatProvider>();
    await chat.stopAndPersist();
    if (!mounted) return;
    await Navigator.of(context).pushNamed(SettingsPage.routeName);
    if (!mounted) return;
    await chat.bindModel(context.read<AppSettingsProvider>().settings);
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmClearCurrent() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(tr(context, '清空当前对话？')),
        content: Text(tr(context, '这个对话里的消息会被删除，此操作无法撤销。')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, '清空')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final ChatProvider chat = context.read<ChatProvider>();
      final String? id = chat.activeConversationId;
      if (id != null) await chat.deleteConversation(id);
      if (mounted) _showSnack(tr(context, '已清空当前对话'));
    }
  }

  /// 把 Provider 里的错误转成 SnackBar（同一条错误只提示一次）
  void _maybeShowError(ChatProvider chat) {
    final String? error = chat.error;
    if (error == null || error == _shownError) return;
    _shownError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showSnack(error);
      _shownError = null;
      chat.dismissError();
    });
  }

  // -------------------------------------------------------------- 构建

  void _measureComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          box.hasSize &&
          (box.size.height - _composerHeight).abs() > .5) {
        setState(() => _composerHeight = box.size.height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ChatProvider chat = context.watch<ChatProvider>();
    final AppSettingsProvider settings = context.watch<AppSettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final appearance = settings.settings;
    final customBackground =
        appearance.chatBackgroundImage.isNotEmpty ||
        appearance.chatBackgroundColor.isNotEmpty;
    final systemStyle =
        (Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
              // Flutter paints the tinted surfaces behind transparent system bars.
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: customBackground
                  ? Colors.transparent
                  : scheme.surface,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: false,
            );

    _maybeShowError(chat);
    _measureComposer();

    return PopScope(
      // 正在生成时先拦一次返回：中断流式请求并保留已收到的内容，然后再退出
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) await _handleBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemStyle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (customBackground)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    key: const ValueKey('chat-backdrop'),
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Color(
                          int.tryParse(
                                appearance.chatBackgroundColor,
                                radix: 16,
                              ) ??
                              scheme.surface.toARGB32(),
                        ),
                      ),
                      if (appearance.chatBackgroundImage.isNotEmpty)
                        Image.file(
                          File(appearance.chatBackgroundImage),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      if (appearance.chatBackgroundImage.isNotEmpty)
                        ColoredBox(
                          color: scheme.surface.withValues(alpha: .25),
                        ),
                    ],
                  ),
                ),
              ),
            Scaffold(
              backgroundColor: customBackground ? Colors.transparent : null,
              key: _scaffoldKey,
              drawer: ConversationDrawer(
                conversations: chat.conversations,
                activeId: chat.activeConversationId,
                onSelect: (String id) async {
                  await _clearPending();
                  await chat.switchConversation(id);
                  if (!mounted) return;
                  final route = chat.activeProviderId;
                  if (route != null) {
                    await settings.replace(
                      settings.settings
                          .forProvider(route)
                          .copyWith(model: chat.activeModel),
                    );
                  }
                },
                onRename: (String id, String name) =>
                    chat.renameConversation(id, name),
                onDelete: (String id) => chat.deleteConversation(id),
                onOpenSettings: _openSettings,
                onClearAll: () => chat.clearAllConversations(),
              ),
              body: SafeArea(
                top: true,
                bottom: false,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    MessageListView(
                      messages: chat.messages,
                      isLoading: chat.isLoading,
                      topPadding: 88,
                      bottomPadding: _composerHeight + 12,
                      edgeColor: customBackground ? scheme.surface : null,
                    ),
                    Positioned(
                      top: 8,
                      left: 16,
                      right: 16,
                      child: _buildFloatingTopBar(chat),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child:
                          NotificationListener<SizeChangedLayoutNotification>(
                            onNotification: (_) {
                              _measureComposer();
                              return false;
                            },
                            child: SizeChangedLayoutNotifier(
                              child: ChatInputBar(
                                key: _composerKey,
                                translucent: customBackground,
                                modelSelector: _buildModelSelector(
                                  settings,
                                  chat,
                                ),
                                isLoading: chat.isLoading,
                                enabled: settings.hasApiKey,
                                attachments: _pending,
                                onSend: _handleSend,
                                onStop: chat.stop,
                                onPickImages: _pickImages,
                                onPickFiles: _pickFiles,
                                onRemoveAttachment: _removePending,
                              ),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingTopBar(ChatProvider chat) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    Widget capsule(Widget child) => Material(
      color: scheme.surface.withValues(alpha: .92),
      elevation: 5,
      shadowColor: scheme.shadow.withValues(alpha: .18),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .42)),
      ),
      child: child,
    );
    return Row(
      key: const ValueKey('floating-top-bar'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        capsule(
          IconButton(
            tooltip: tr(context, '历史对话'),
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        capsule(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: tr(context, '新建对话'),
                  icon: const Icon(Icons.edit_square),
                  onPressed: _newConversation,
                ),
                PopupMenuButton<String>(
                  clipBehavior: Clip.antiAlias,
                  tooltip: tr(context, '对话操作'),
                  onSelected: (String value) {
                    if (value == 'new') _newConversation();
                    if (value == 'clear') _confirmClearCurrent();
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'new',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.add_comment_outlined),
                            title: Text(tr(context, '新建对话')),
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'clear',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.delete_outline),
                            title: Text(tr(context, '清空当前对话')),
                          ),
                        ),
                      ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 输入框下方只展示当前服务商的模型。
  Widget _buildModelSelector(AppSettingsProvider provider, ChatProvider chat) {
    final String current = provider.model;
    // Saved custom models belong to the selected provider's profile.
    final models = provider.settings.modelChoices;
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.padding.vertical - media.viewInsets.bottom;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Theme(
      // The selected model has its own rounded card highlight.
      data: theme.copyWith(highlightColor: Colors.transparent),
      child: PopupMenuButton<String>(
        clipBehavior: Clip.antiAlias,
        key: const ValueKey('chat-model-selector'),
        // Show a few models at a time; the popup scrolls the remaining choices.
        constraints: BoxConstraints(
          minWidth: 112,
          maxWidth: 280,
          // 两个模型卡片的高度刚好可见，更多模型通过上下滑动选择。
          maxHeight: (availableHeight * .28).clamp(132.0, 168.0),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        enabled: !chat.isLoading,
        tooltip: tr(context, '切换模型'),
        initialValue: current,
        onSelected: (String value) async {
          try {
            if (value == current) return;
            await provider.update(model: value);
            await chat.bindModel(provider.settings);
          } catch (_) {
            if (mounted) _showSnack(tr(context, '配置未能保存，请重试'));
            return;
          }
          if (!mounted) return;
          _showSnack(tr(context, '已切换到 {model}', {'model': provider.model}));
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          for (final String m in models.where((m) => m.isNotEmpty))
            PopupMenuItem<String>(
              value: m,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Semantics(
                selected: m == current,
                child: Container(
                  key: ValueKey('model-option-$m'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: m == current
                        ? scheme.primaryContainer.withValues(alpha: .55)
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: m == current
                          ? scheme.primary.withValues(alpha: .65)
                          : scheme.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        m == current
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 18,
                        color: m == current
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              m,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: m == current
                                    ? scheme.primary
                                    : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              modelInfo(
                                provider.settings.providerId,
                                m,
                              ).tags.map((tag) => tr(context, tag)).join(' · '),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        child: Semantics(
          button: true,
          label: tr(context, '当前模型：{model}', {
            'model': '${provider.settings.preset.name}, $current',
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40, maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '${provider.settings.preset.name.split(' · ').first} · ${AppSettings.modelShortName(current)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: chat.isLoading
                          ? Theme.of(context).disabledColor
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: chat.isLoading
                      ? Theme.of(context).disabledColor
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
