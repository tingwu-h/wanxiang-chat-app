import 'dart:convert';
import 'dart:io';

import 'package:deepseek_chat/services/attachment_service.dart';

/// 一条消息上挂的附件（图片或文本类文件）。
///
/// 设计要点：
/// - 只存**本地文件路径**，不把 base64 塞进 shared_preferences（否则历史会爆掉）；
///   图片解析成 base64 是在发请求那一刻才做的。
/// - 文本类文件在「选中的那一刻」就把内容读出来存进 [textContent]，
///   因为 DeepSeek 不接受文件本身，只接受文本（PDF/Word 不支持）。
class ChatAttachment {
  ChatAttachment({
    required this.name,
    required this.path,
    required this.kind,
    this.size = 0,
    this.textContent,
  });

  /// 原始文件名
  final String name;

  /// 本地绝对路径（应用私有目录下的副本）
  final String path;

  /// 'image' 或 'text'
  final String kind;

  /// 字节数
  final int size;

  /// 文本类文件的内容（kind == 'text' 时才有值）
  final String? textContent;

  bool get isImage => kind == 'image';
  bool get isText => kind == 'text';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'path': path,
    'kind': kind,
    'size': size,
    if (textContent != null) 'textContent': textContent,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    name: (json['name'] as String?) ?? '附件',
    path: (json['path'] as String?) ?? '',
    kind: (json['kind'] as String?) ?? 'image',
    size: (json['size'] as int?) ?? 0,
    textContent: json['textContent'] as String?,
  );

  /// 用于界面展示的大小文案
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// 转成 API 需要的 content block。
  /// 读取失败时明确报错，避免界面展示图片但模型实际未收到。
  ///
  /// [detail] 为图片细节档位（'' / low / original），空串表示不发送该字段。
  /// 官方说明：low 会把图缩到 512×512，更快更省 token。
  Future<Map<String, dynamic>?> toApiBlock({String detail = ''}) async {
    try {
      if (isImage) {
        final File f = File(path);
        if (!await f.exists()) {
          throw AttachmentException('图片 $name 已丢失，请重新添加，或新建对话继续。');
        }
        if (await f.length() > AttachmentService.maxImageBytes) {
          throw AttachmentException('图片 $name 超过 5 MB，请缩小后重新添加。');
        }
        final List<int> bytes = await f.readAsBytes();
        // Recheck after reading in case the file changed during the operation.
        if (bytes.length > AttachmentService.maxImageBytes) {
          throw AttachmentException('图片 $name 过大。');
        }
        final String b64 = base64Encode(bytes);
        return <String, dynamic>{
          'type': 'image_url',
          'image_url': <String, dynamic>{
            'url': 'data:${_mimeOf(name)};base64,$b64',
            if (detail.isNotEmpty) 'detail': detail,
          },
        };
      }
      final String? text = textContent;
      if (text == null || text.isEmpty) {
        throw AttachmentException('文件 $name 没有可读取的文字。');
      }
      return <String, dynamic>{'type': 'text', 'text': '【文件：$name】\n$text'};
    } on AttachmentException {
      rethrow;
    } catch (_) {
      throw AttachmentException('附件 $name 读取失败，请重新添加后再试。');
    }
  }

  /// 根据扩展名猜 MIME（官方按内容判断，这里只是给 data URL 一个合理声明）
  static String _mimeOf(String fileName) {
    final String ext = fileName.toLowerCase().split('.').last;
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      _ => 'image/jpeg',
    };
  }
}
