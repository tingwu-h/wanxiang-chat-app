import 'package:deepseek_chat/models/chat_message.dart';

/// 一个会话（对话）。
///
/// 之前只保存「一份当前历史」，无法新建对话、无法回看以前的对话；
/// 现在把每个会话独立保存，标题取第一条用户消息。
class Conversation {
  Conversation({
    required this.id,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.customTitle,
    this.providerId,
    this.model,
    this.systemPrompt,
  }) : messages = messages ?? <ChatMessage>[],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// 唯一 id（用时间戳，够用且不引入额外依赖）
  final String id;

  final List<ChatMessage> messages;

  final DateTime createdAt;

  DateTime updatedAt;

  /// 用户手动改的名字。为 null 时按第一条用户消息自动生成标题。
  ///
  /// 用 String? 而不是空串表示"没改名"，这样用户把名字清空等于恢复自动标题。
  String? customTitle;
  String? providerId;
  String? model;

  /// 本会话专属的系统提示词。
  ///
  /// null / 空串表示「本会话没有单独设置」，发送时回落到设置页的
  /// 默认提示词——这样老用户升级后行为不变，不会突然丢提示词。
  String? systemPrompt;

  /// 是否单独设置过提示词
  bool get hasOwnSystemPrompt => (systemPrompt ?? '').trim().isNotEmpty;

  /// 用户是否手动命名过
  bool get hasCustomTitle => (customTitle ?? '').trim().isNotEmpty;

  /// 列表里显示的标题：优先用户改过的名字，否则取第一条用户消息的前 20 个字
  String get title {
    final String custom = (customTitle ?? '').trim();
    if (custom.isNotEmpty) return custom;
    for (final ChatMessage m in messages) {
      if (m.isUser && m.content.trim().isNotEmpty) {
        final String t = m.content.replaceAll('\n', ' ').trim();
        return t.length <= 20 ? t : '${t.substring(0, 20)}…';
      }
    }
    // 只有图片没文字的情况
    for (final ChatMessage m in messages) {
      if (m.isUser && m.attachments.isNotEmpty) return '（图片/文件）';
    }
    return '新对话';
  }

  /// 列表右侧的摘要：最后一条有内容的消息
  String get preview {
    for (int i = messages.length - 1; i >= 0; i--) {
      final ChatMessage m = messages[i];
      if (m.content.trim().isNotEmpty) {
        final String t = m.content.replaceAll('\n', ' ').trim();
        return t.length <= 40 ? t : '${t.substring(0, 40)}…';
      }
    }
    return '暂无消息';
  }

  bool get isEmpty => messages.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'providerId': providerId,
    'model': model,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    if (hasCustomTitle) 'customTitle': customTitle,
    if (hasOwnSystemPrompt) 'systemPrompt': systemPrompt,
    'messages': messages.map((ChatMessage m) => m.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw =
        (json['messages'] as List<dynamic>?) ?? <dynamic>[];
    return Conversation(
      id:
          (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      messages: raw
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList(),
      createdAt: json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : null,
      updatedAt: json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : null,
      customTitle: json['customTitle'] as String?,
      providerId: json['providerId'] as String?,
      model: json['model'] as String?,
      // 旧数据没有这个字段，读成 null 即「沿用默认提示词」
      systemPrompt: json['systemPrompt'] as String?,
    );
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
