import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'package:deepseek_chat/services/docx_builder.dart';
import 'package:deepseek_chat/services/document_spec.dart';
import 'package:deepseek_chat/services/pptx_builder.dart';
import 'package:deepseek_chat/services/xlsx_builder.dart';

enum DocType { word, excel, ppt }

/// 文档生成的统一入口：模型返回 JSON，这里负责校验、生成字节与文件名。
class DocumentService {
  static const Map<DocType, String> mimeTypes = <DocType, String>{
    DocType.word:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    DocType.excel:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    DocType.ppt:
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };

  static const Map<DocType, String> extensions = <DocType, String>{
    DocType.word: 'docx',
    DocType.excel: 'xlsx',
    DocType.ppt: 'pptx',
  };

  static String systemPrompt(DocType type) {
    final String schema = switch (type) {
      DocType.word =>
        '{"title":"文档标题","sections":[{"heading":"一级标题",'
            '"paragraphs":["段落"],"bullets":["要点"],'
            '"table":{"headers":["列1","列2"],"rows":[["值1","值2"]]}}]}',
      DocType.excel =>
        '{"sheets":[{"name":"工作表名","rows":[["表头1","表头2"],'
            '["值1","值2"]]}]}',
      DocType.ppt =>
        '{"title":"演示标题","slides":[{"title":"页标题",'
            '"bullets":["要点1","要点2"]}]}',
    };
    return '你是文档生成器。根据用户给出的主题，输出且只输出一个 JSON 对象，'
        '不要 Markdown 代码块、不要解释。JSON 必须符合下面的结构：\n$schema\n'
        '内容使用简体中文；不要编造用户没有提供的关键数据，缺少数据时写“待补充”。';
  }

  static String userPrompt(DocType type, String topic, String contextText) {
    final String kind = switch (type) {
      DocType.word => 'Word 文档',
      DocType.excel => 'Excel 表格',
      DocType.ppt => 'PPT 演示',
    };
    final StringBuffer sb = StringBuffer('请生成一份$kind，主题：$topic');
    if (contextText.trim().isNotEmpty) {
      sb.write('\n\n可参考的对话内容（可提炼，不要照抄无关部分）：\n');
      sb.write(contextText.trim());
    }
    return sb.toString();
  }

  static Future<Uint8List> build(DocType type, String rawJson) async {
    final Map<String, dynamic> json = parseJsonObject(rawJson);
    switch (type) {
      case DocType.word:
        return DocxBuilder.build(WordSpec.fromJson(json));
      case DocType.excel:
        return XlsxBuilder.build(XlsxSpec.fromJson(json));
      case DocType.ppt:
        final ByteData template = await rootBundle.load(
          'assets/templates/blank.pptx',
        );
        return PptxBuilder.build(
          template.buffer.asUint8List(),
          PptxSpec.fromJson(json),
        );
    }
  }

  static String fileName(DocType type, String title) {
    final String cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .trim();
    final String base = cleaned.isEmpty ? 'wanxiang-document' : cleaned;
    final String stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    return '$base-$stamp.${extensions[type]}';
  }

  static String encodeJson(Object value) =>
      const JsonEncoder.withIndent('  ').convert(value);
}
