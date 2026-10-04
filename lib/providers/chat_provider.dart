import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

/// 对话状态：多会话管理 + 流式接收 + 中断控制 + 本地持久化。
class ChatProvider extends ChangeNotifier {
  ChatProvider({required this._api, required this._storage});

  final ChatService _api;
  final StorageService _storage;

  /// 全部会话
  final List<Conversation> _conversations = <Conversation>[];

  /// 当前会话
  Conversation? _active;

  bool _loading = false;
  String? _error;
  bool _initialized = false;

  /// 每次发送分配一个自增 token，只有 token 匹配的流才允许写入界面。
  /// 这样「停止生成」之后旧流的残余数据不会污染新的一轮对话。
  int _activeToken = 0;
  StreamSubscription<ChatChunk>? _subscription;
  Completer<void>? _requestDone;
  Timer? _checkpoint;
  bool _disposed = false;
  int _chromeRevision = 0;

  /// Structural/status changes rebuild controls; stream chunks only update messages.
  int get chromeRevision => _chromeRevision;

  void _cancelRequest() {
    _activeToken++;
    _loading = false;
    _api.cancel();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final done = _requestDone;
    _requestDone = null;
    if (done != null && !done.isCompleted) done.complete();
    _checkpoint?.cancel();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      _chromeRevision++;
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _cancelRequest();
    _api.dispose();
    _disposed = true;
    super.dispose();
  }

  // ------------------------------------------------------------ 对外读取

  /// 当前会话的消息（UI 直接绑定这个）
  List<ChatMessage> get messages =>
      List<ChatMessage>.unmodifiable(_active?.messages ?? <ChatMessage>[]);

  /// 会话列表（最近更新在前）
  List<Conversation> get conversations {
    final List<Conversation> copy = List<Conversation>.from(_conversations);
    copy.sort(
      (Conversation a, Conversation b) => b.updatedAt.compareTo(a.updatedAt),
    );
    return List<Conversation>.unmodifiable(copy);
  }

  String? get activeProviderId => _active?.providerId;
  String? get activeModel => _active?.model;
  Future<void> bindModel(AppSettings settings) async {
    if (_active == null) return;
    _active!.providerId = settings.providerId;
    _active!.model = settings.model;
    await _persist(_active!);
    notifyListeners();
  }

  String? get activeConversationId => _active?.id;

  /// 当前会话标题（顶栏显示）
  String get activeTitle => _active?.title ?? '新对话';

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isInitialized => _initialized;
  bool get hasMessages => _active?.messages.isNotEmpty ?? false;
  Future<String> exportHistory() async {
    if (_active != null) await _persist(_active!);
    return _storage.exportHistory();
  }

  // ---------------------------------------------------------------- 初始化

  Future<void> init() async {
    final List<Conversation> loaded = await _storage.loadConversations();
    _conversations
      ..clear()
      ..addAll(loaded);

    final String? activeId = await _storage.loadActiveConversationId();
    if (_conversations.isEmpty) {
      _active = Conversation(id: Conversation.newId());
      _conversations.add(_active!);
    } else {
      _active = _conversations.firstWhere(
        (Conversation c) => c.id == activeId,
        orElse: () => _conversations.first,
      );
    }
    _initialized = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ 会话操作

  /// 开一个新会话（当前会话本来就是空的就不重复新建）
  Future<void> newConversation() async {
    await stopAndPersist();
    _error = null;

    if (_active != null && _active!.isEmpty) {
      notifyListeners();
      return;
    }
    final Conversation c = Conversation(id: Conversation.newId());
    _conversations.insert(0, c);
    _active = c;
    notifyListeners();
    // 立刻落盘：否则这个空会话只存在于内存里，
    // 下次打开应用时它不在存储索引中，会静默消失（已实测复现）。
    await _storage.saveConversation(c);
    await _storage.saveActiveConversationId(c.id);
  }

  /// 切换到指定会话
  Future<void> switchConversation(String id) async {
    final int idx = _conversations.indexWhere((Conversation c) => c.id == id);
    if (idx < 0) return;
    await stopAndPersist();
    _error = null;
    _active = _conversations[idx];
    notifyListeners();
    await _storage.saveActiveConversationId(id);
  }

  /// 删除一个会话
  Future<void> deleteConversation(String id) async {
    if (_active?.id == id) await stopAndPersist();
    _conversations.removeWhere((Conversation c) => c.id == id);
    await _storage.deleteConversation(id);
    if (_active?.id == id) {
      _activeToken++;
      _loading = false;
      if (_conversations.isEmpty) {
        _active = Conversation(id: Conversation.newId());
        _conversations.add(_active!);
      } else {
        _active = _conversations.first;
      }
      await _storage.saveActiveConversationId(_active!.id);
    }
    notifyListeners();
  }

  /// 给会话改名。
  ///
  /// [name] 传空串表示恢复自动标题（取第一条用户消息）。
  /// 改名不改变 updatedAt 的排序语义，但因为会重新保存一次，
  /// 该会话会被排到列表最前——这是可接受的，符合「刚操作过的在最上面」。
  Future<void> renameConversation(String id, String name) async {
    final int idx = _conversations.indexWhere((Conversation c) => c.id == id);
    if (idx < 0) return;
    final String trimmed = name.trim();
    _conversations[idx].customTitle = trimmed.isEmpty ? null : trimmed;
    notifyListeners();
    await _storage.saveConversation(_conversations[idx]);
  }

  /// 清空全部会话
  Future<void> clearAllConversations() async {
    await stopAndPersist();
    _error = null;
    _conversations.clear();
    await _storage.deleteAllConversations();
    _active = Conversation(id: Conversation.newId());
    _conversations.add(_active!);
    notifyListeners();
    // 同 newConversation：新会话要落盘，否则下次打开时索引是空的
    await _storage.saveConversation(_active!);
    await _storage.saveActiveConversationId(_active!.id);
  }

  // ---------------------------------------------------------------- 发送

  /// 发送一条用户消息，并流式接收助手回复。
  ///
  /// [settings] 由 AppSettingsProvider 传入，避免两个 Provider 之间互相依赖。
  /// [attachments] 图片 / 文本文件；可以只发附件不写文字。
  Future<void> send(
    String text,
    AppSettings settings, {
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) async {
    final String content = text.trim();
    if (content.isEmpty && attachments.isEmpty) return;
    if (_loading) return;

    final Conversation? conv = _active;
    if (conv == null) return;

    conv.providerId = settings.providerId;
    conv.model = settings.model;
    final int token = ++_activeToken;
    _error = null;

    conv.messages.add(
      ChatMessage.user(
        content,
        attachments: List<ChatAttachment>.from(attachments),
      ),
    );

    // 先放一个空气泡，流式内容会一段段追加进去，形成打字机效果
    final ChatMessage assistant = ChatMessage.assistant('')
      ..providerId = settings.providerId
      ..model = settings.model;
    conv.messages.add(assistant);
    _loading = true;
    notifyListeners();
    await _persist(conv);
    if (token != _activeToken) {
      if (assistant.isBlank) conv.messages.remove(assistant);
      await _persist(conv);
      return;
    }

    // 发给 API 的上下文：必须排除刚插入的那条空助手消息
    final List<ChatMessage> context = conv.messages
        .where((ChatMessage m) => !identical(m, assistant))
        .toList();

    bool receivedAny = false;
    // 流式输出时不要每收到一个 chunk 就重建界面：
    // 服务端可能每秒推几十次，每次都重建整棵组件树 + 重解析 Markdown 会明显卡顿。
    // 这里按帧节流（约 30fps），视觉上仍是"逐字出现"，但渲染压力降一个量级。
    bool pendingNotify = false;
    Timer? notifier;
    void scheduleNotify() {
      if (pendingNotify) return;
      pendingNotify = true;
      notifier = Timer(const Duration(milliseconds: 32), () {
        pendingNotify = false;
        if (!_disposed && token == _activeToken) super.notifyListeners();
      });
    }

    final done = Completer<void>();
    _requestDone = done;
    _checkpoint = Timer.periodic(const Duration(seconds: 2), (_) {
      if (token == _activeToken) unawaited(_persist(conv));
    });
    try {
      _subscription = _api
          .streamChat(settings: settings, history: context)
          .listen(
            (chunk) {
              if (chunk.done) {
                if (!done.isCompleted) done.complete();
                return;
              }
              if (token != _activeToken || chunk.isEmpty) return;
              receivedAny = true;
              // 思考过程和正文分开存：混在一起会让回答一团糟
              if (chunk.thinking) {
                assistant.thinking += chunk.text;
              } else {
                assistant.content += chunk.text;
              }
              scheduleNotify();
            },
            onError: (Object error, StackTrace stack) {
              if (!done.isCompleted) done.completeError(error, stack);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      await done.future;

      final bool finished = token == _activeToken;
      if (finished &&
          assistant.content.trim().isEmpty &&
          !assistant.hasThinking) {
        assistant.content = '（模型没有返回内容，请重试或换一个模型）';
        assistant.error = true;
      }
    } catch (e) {
      final String msg = e is DeepSeekException
          ? e.message
          : '请求失败：${e.toString()}';

      if (token == _activeToken && !receivedAny) {
        // 一个字都没收到：把空气泡换成错误气泡，不留空白
        assistant.content = msg;
        assistant.error = true;
      } else if (token == _activeToken) {
        // 已经收到一部分：保留内容，把错误追加在后面
        assistant.content += '\n\n> ⚠️ 连接中断：$msg';
      }
      if (token == _activeToken) _error = msg;
    } finally {
      // 收尾：先取消尚未触发的节流定时器，避免它在 _loading 变 false 后再通知一次
      notifier?.cancel();
      // 空内容气泡直接丢掉，避免历史里出现空白消息
      if (assistant.isBlank) {
        conv.messages.remove(assistant);
      }
      if (token == _activeToken) _loading = false;
      if (identical(_requestDone, done)) {
        _checkpoint?.cancel();
        _api.cancel();
        final subscription = _subscription;
        if (subscription != null) unawaited(subscription.cancel());
        _subscription = null;
        _requestDone = null;
      }
      notifyListeners();
      await _persist(conv);
    }
  }

  /// 停止生成：中断流式接收，已经收到的内容保留。
  void stop() {
    if (!_loading) return;
    final conv = _active;
    _cancelRequest();
    _error = '已停止生成。';
    notifyListeners();
    if (conv != null) unawaited(_persist(conv));
  }

  /// 离开页面时调用：中断流式请求，但保留已经收到的内容。
  Future<void> stopAndPersist() async {
    final conv = _active;
    _cancelRequest();
    notifyListeners();
    if (conv != null) await _persist(conv);
  }

  /// 只清掉提示信息
  void dismissError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _persist(Conversation conv) async {
    if (!_conversations.contains(conv)) return;
    try {
      await _storage.saveConversation(conv);
      if (identical(_active, conv)) {
        await _storage.saveActiveConversationId(conv.id);
      }
    } catch (_) {
      _error = '聊天记录暂时保存失败，请先导出重要内容。';
      notifyListeners();
    }
  }
}
