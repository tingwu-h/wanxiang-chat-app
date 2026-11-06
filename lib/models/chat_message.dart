import 'dart:convert';

import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_source.dart';

/// 消息失败类别（v1.3.4 起）。
///
/// 分三类是为了给出不同提示语：超时是「等太久了」，
/// 服务商错误是「对方挂了」，网络错误是「你自己的网断了」。
/// 三者的用户下一步动作完全不同，所以不能合并成一句话。
class MessageFailure {
  /// 等待超时（连接超时或长时间零字节）
  static const String timeout = 'timeout';

  /// 服务商返回错误（429 / 5xx / 流内 error 字段等）
  static const String provider = 'provider';

  /// 本机网络问题（连接被重置、DNS 失败、TLS 失败等）
  static const String network = 'network';

  static bool isValid(String? kind) =>
      kind == timeout || kind == provider || kind == network;
}

/// 对话中的一条消息。
///
/// 与 DeepSeek `/chat/completions` 的 message 结构保持一致：
/// `{"role": "system|user|assistant", "content": "..."}`，
/// 另外多存一个本地时间戳，用于列表右侧的时间显示与排序。
///
/// 带附件时 content 会变成 block 数组（图片走 image_url），
/// 具体拼装见 [toApiJsonWithAttachments]。
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.error = false,
    this.failureKind,
    this.providerId,
    this.model,
    this.thinking = '',
    List<ChatAttachment>? attachments,
    List<ChatSource>? sources,
  }) : timestamp = timestamp ?? DateTime.now(),
       attachments = attachments ?? <ChatAttachment>[],
       sources = sources ?? <ChatSource>[];

  /// 便捷构造：用户消息
  ChatMessage.user(String content, {List<ChatAttachment>? attachments})
    : this(role: MessageRole.user, content: content, attachments: attachments);

  /// 便捷构造：助手消息
  ChatMessage.assistant(String content)
    : this(role: MessageRole.assistant, content: content);

  /// `system` / `user` / `assistant`
  final String role;
  String? providerId;
  String? model;

  /// 消息正文（流式输出时会被不断追加）
  String content;

  /// 本地时间
  final DateTime timestamp;

  /// 是否是「本地生成的错误提示气泡」（不参与下次请求的上下文）
  ///
  /// 注意：必须是可变的。ChatProvider 在流式接收失败时会把已经插入的空气泡
  /// 就地标记成错误气泡（`assistant.error = true`），final 会导致编译失败。
  bool error;

  /// 失败类别，取值见 [MessageFailure]；null 表示这条不是失败气泡。
  ///
  /// 只在失败时写入。旧版本存下来的历史没有这个字段，读成 null 即可，
  /// 仍按 [error] 渲染成同一个错误气泡，不会因为缺字段而报错。
  String? failureKind;

  /// 是否已经根据 [failureKind] 认出是哪一类失败
  bool get hasFailureKind => MessageFailure.isValid(failureKind);

  /// 附件（图片 / 文本类文件）。只有用户消息会有。
  final List<ChatAttachment> attachments;

  /// 本条回答引用的联网来源。只有助手消息可能非空。
  ///
  /// 存在消息里而不是内存里，是为了重开应用后来源仍然可见。
  List<ChatSource> sources;

  /// 模型的思考过程（`reasoning_content`）。
  ///
  /// 必须和 [content] 分开存：思考内容是给用户「想看才看」的，
  /// 混进正文会让回答看起来一团糟，而且会被当成正式回答发给下一轮上下文。
  String thinking;

  /// 是否有思考过程可看
  bool get hasThinking => thinking.trim().isNotEmpty;

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isSystem => role == MessageRole.system;

  /// 内容和附件都空才算空消息
  bool get isBlank =>
      content.trim().isEmpty && attachments.isEmpty && !hasThinking;

  /// 发送给 API 的 JSON（纯文本，无附件时用）。
  /// 注意：错误气泡与空内容不能进入上下文，否则会被服务端拒绝。
  Map<String, dynamic> toApiJson() => <String, dynamic>{
    'role': role,
    'content': content,
  };

  /// 发送给 API 的 JSON（带附件时用 block 数组）。
  ///
  /// 官方限制：图片只能出现在 user 消息里，且 content 必须是块数组。
  ///
  /// [imageDetail] 透传给图片块（'' / low / original）。
  Future<Map<String, dynamic>> toApiJsonWithAttachments({
    String imageDetail = '',
  }) async {
    final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
    if (content.trim().isNotEmpty) {
      blocks.add(<String, dynamic>{'type': 'text', 'text': content});
    }
    for (final ChatAttachment a in attachments) {
      final Map<String, dynamic>? b = await a.toApiBlock(detail: imageDetail);
      if (b != null) blocks.add(b);
    }
    return <String, dynamic>{'role': role, 'content': blocks};
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'role': role,
    'content': content,
    'timestamp': timestamp.millisecondsSinceEpoch,
    if (providerId != null) 'providerId': providerId,
    if (model != null) 'model': model,
    'error': error,
    if (hasFailureKind) 'failureKind': failureKind,
    if (thinking.isNotEmpty) 'thinking': thinking,
    if (sources.isNotEmpty) 'sources': ChatSource.listToJson(sources),
    if (attachments.isNotEmpty)
      'attachments': attachments.map((ChatAttachment a) => a.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawA =
        (json['attachments'] as List<dynamic>?) ?? <dynamic>[];
    return ChatMessage(
      role: (json['role'] as String?) ?? MessageRole.assistant,
      content: (json['content'] as String?) ?? '',
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : (DateTime.tryParse('${json['timestamp']}') ?? DateTime.now()),
      error: json['error'] == true,
      // 旧数据没有这个字段，或存了未知值，都退回 null（仍按 error 渲染）
      failureKind: MessageFailure.isValid(json['failureKind'] as String?)
          ? json['failureKind'] as String
          : null,
      providerId: json['providerId'] as String?,
      model: json['model'] as String?,
      thinking: (json['thinking'] as String?) ?? '',
      sources: ChatSource.listFromJson(json['sources']),
      attachments: rawA
          .whereType<Map<String, dynamic>>()
          .map(ChatAttachment.fromJson)
          .toList(),
    );
  }

  static List<ChatMessage> listFromJsonString(String raw) {
    if (raw.trim().isEmpty) return <ChatMessage>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <ChatMessage>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .where((ChatMessage m) => !m.isBlank)
          .toList();
    } catch (_) {
      // 历史数据损坏时直接丢弃，避免整个 App 起不来
      return <ChatMessage>[];
    }
  }

  static String listToJsonString(List<ChatMessage> messages) =>
      jsonEncode(messages.map((ChatMessage m) => m.toJson()).toList());
}

/// role 常量，避免魔法字符串写错。
class MessageRole {
  const MessageRole._();

  static const String system = 'system';
  static const String user = 'user';
  static const String assistant = 'assistant';
}
