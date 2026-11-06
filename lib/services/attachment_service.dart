import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:deepseek_chat/models/chat_attachment.dart';

/// 选择附件的异常：message 已经是可以直接展示给用户的中文。
class AttachmentException implements Exception {
  AttachmentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 负责「选图片 / 选文件 → 存进应用私有目录 → 返回 ChatAttachment」。
///
/// 为什么不直接用用户选中的原路径：Android 上选中的文件常常在一个临时缓存目录里，
/// 系统随时可能清理，历史记录里的图片就会变成裂图。所以统一复制一份到自己目录。
class AttachmentService {
  AttachmentService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  static const maxImageBytes = 5 * 1024 * 1024;
  static const maxTextBytes = 256 * 1024;
  static const maxAttachments = 6;
  static const maxTotalBytes = 15 * 1024 * 1024;

  static Future<void> removeOwnedFile(String filePath) async {
    if (filePath.isEmpty) return;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/attachments');
    if (!await dir.exists()) return;
    final file = File(filePath);
    if (!await file.exists()) return;
    // Never delete arbitrary originals, symlinks, or paths outside our own folder.
    if (await FileSystemEntity.isLink(filePath)) return;
    if (await file.parent.resolveSymbolicLinks() !=
        await dir.resolveSymbolicLinks()) {
      return;
    }
    await file.delete();
  }

  static void validateSelection(List<ChatAttachment> attachments) {
    if (attachments.length > maxAttachments) {
      throw AttachmentException('一次最多添加 6 个附件，请分开发送。');
    }
    if (attachments.fold<int>(0, (total, a) => total + a.size) >
        maxTotalBytes) {
      throw AttachmentException('本次附件合计超过 15 MB，请减少一些。');
    }
  }

  /// 文本类文件允许的扩展名（DeepSeek 不接受文件本身，只接受文本内容）
  static const List<String> textExtensions = <String>[
    'txt',
    'md',
    'markdown',
    'json',
    'csv',
    'log',
    'yaml',
    'yml',
    'xml',
    'html',
    'dart',
    'js',
    'ts',
    'py',
    'java',
    'kt',
    'c',
    'cpp',
    'h',
    'cs',
    'go',
    'rs',
    'swift',
    'php',
    'rb',
    'sh',
    'sql',
    'ini',
    'conf',
    'properties',
    'gradle',
  ];

  /// 单个文本文件最多读多少字符（避免把接口撑爆）
  static const int maxTextChars = 60000;

  /// 直接调起相机拍照（单张）。
  ///
  /// 说明：Android 侧用的是系统相机 Intent，**不需要 CAMERA 权限**；
  /// 反过来说，如果 Manifest 里声明了 CAMERA 权限，系统会要求运行时申请，
  /// 反而多出一套权限流程。所以这里刻意不申请权限。
  Future<List<ChatAttachment>> pickFromCamera({
    required Future<File?> Function(String) edit,
  }) async {
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    // 用户取消拍照：返回空列表，不当作错误
    if (shot == null) return <ChatAttachment>[];

    final File? saved = await edit(shot.path);
    if (saved == null) return <ChatAttachment>[];
    return <ChatAttachment>[
      ChatAttachment(
        name: saved.path.split(RegExp(r'[/\\]')).last,
        path: saved.path,
        kind: 'image',
        size: await saved.length(),
      ),
    ];
  }

  /// 选取图片（可多选）
  Future<List<ChatAttachment>> pickImages({
    required Future<File?> Function(String) edit,
  }) async {
    final List<XFile> picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return <ChatAttachment>[];
    if (picked.length > maxAttachments) {
      throw AttachmentException('一次最多选择 6 张图片。');
    }
    final List<ChatAttachment> result = <ChatAttachment>[];
    try {
      for (final XFile x in picked) {
        final saved = await edit(x.path);
        if (saved == null) continue;
        result.add(
          ChatAttachment(
            name: saved.path.split(RegExp(r'[/\\]')).last,
            path: saved.path,
            kind: 'image',
            size: await saved.length(),
          ),
        );
      }
      return result;
    } catch (_) {
      for (final a in result) {
        await removeOwnedFile(a.path);
      }
      rethrow;
    }
  }

  /// 选取文件（文本类直接读入内容；图片走图像通道）
  ///
  /// 注意：file_picker 13.x 起 API 变了——
  /// 不再有 FilePickerResult，pickFiles 直接返回 List<PlatformFile>，
  /// PlatformFile.size 也换成了 await file.length()。
  /// 用 8.x 的写法会编译不过，而 8.x 又因为 compileSdk 34 无法在本项目构建。
  Future<List<ChatAttachment>> pickFiles({
    required Future<File?> Function(String) edit,
  }) async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (files.isEmpty) return <ChatAttachment>[];
    if (files.length > maxAttachments) {
      throw AttachmentException('一次最多选择 6 个附件。');
    }

    final List<ChatAttachment> out = <ChatAttachment>[];
    final List<String> rejected = <String>[];

    for (final PlatformFile f in files) {
      final String? p = f.path;
      if (p == null) {
        rejected.add('${f.name}（无法读取）');
        continue;
      }
      final String ext = f.name.toLowerCase().contains('.')
          ? f.name.toLowerCase().split('.').last
          : '';
      final bool isImage = <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
      ].contains(ext);

      if (isImage) {
        final File? saved;
        try {
          saved = await edit(p);
        } catch (_) {
          for (final a in out.where((a) => a.isImage)) {
            await removeOwnedFile(a.path);
          }
          rethrow;
        }
        if (saved == null) continue;
        out.add(
          ChatAttachment(
            name: saved.path.split(RegExp(r'[/\\]')).last,
            path: saved.path,
            kind: 'image',
            size: await saved.length(),
          ),
        );
        continue;
      }

      if (!textExtensions.contains(ext)) {
        rejected.add(f.name);
        continue;
      }

      // 文本类：读进来（限制长度）
      String content;
      try {
        if (await File(p).length() > maxTextBytes) {
          rejected.add('${f.name}（文本文件超过 256 KB）');
          continue;
        }
        content = await File(p).readAsString();
      } catch (_) {
        // 不是 UTF-8 就当二进制，放弃
        rejected.add('${f.name}（无法按文本读取）');
        continue;
      }
      if (content.length > maxTextChars) {
        rejected.add('${f.name}（超过 60000 字符，请拆分文件）');
        continue;
      }
      out.add(
        ChatAttachment(
          name: f.name,
          path: p,
          kind: 'text',
          size: (f.lengthSync() ?? await f.length()) ?? content.length,
          textContent: content,
        ),
      );
    }

    if (rejected.isNotEmpty) {
      for (final a in out.where((a) => a.isImage)) {
        await removeOwnedFile(a.path);
      }
      throw AttachmentException(
        '不支持这些文件：${rejected.join('、')}\n'
        '图片支持 jpg/png/gif/webp；文档支持 txt/md/json/csv/代码等纯文本。',
      );
    }
    return out;
  }
}
