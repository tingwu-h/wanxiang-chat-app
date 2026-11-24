import 'dart:convert';

/// 三种文档的中间结构：模型返回 JSON，App 负责校验与生成。
class DocTable {
  const DocTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  static DocTable fromJson(Map<String, dynamic> json) => DocTable(
    headers: (json['headers'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => '$e')
        .toList(),
    rows: (json['rows'] as List<dynamic>? ?? <dynamic>[])
        .whereType<List<dynamic>>()
        .map(
          (List<dynamic> row) => row.map((dynamic e) => '$e').toList(),
        )
        .toList(),
  );
}

class DocSection {
  const DocSection({
    required this.heading,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
    this.table,
  });

  final String heading;
  final List<String> paragraphs;
  final List<String> bullets;
  final DocTable? table;

  static DocSection fromJson(Map<String, dynamic> json) => DocSection(
    heading: (json['heading'] as String? ?? '').trim(),
    paragraphs: (json['paragraphs'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => '$e')
        .toList(),
    bullets: (json['bullets'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => '$e')
        .toList(),
    table: json['table'] is Map<String, dynamic>
        ? DocTable.fromJson(json['table'] as Map<String, dynamic>)
        : null,
  );
}

class WordSpec {
  const WordSpec({required this.title, required this.sections});

  final String title;
  final List<DocSection> sections;

  static WordSpec fromJson(Map<String, dynamic> json) => WordSpec(
    title: (json['title'] as String? ?? '未命名文档').trim(),
    sections: (json['sections'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(DocSection.fromJson)
        .where(
          (DocSection s) =>
              s.heading.isNotEmpty ||
              s.paragraphs.isNotEmpty ||
              s.bullets.isNotEmpty ||
              s.table != null,
        )
        .toList(),
  );
}

class SheetSpec {
  const SheetSpec({required this.name, required this.rows});

  final String name;
  final List<List<String>> rows;

  static SheetSpec fromJson(Map<String, dynamic> json, int index) => SheetSpec(
    name: _safeSheetName((json['name'] as String? ?? 'Sheet${index + 1}')),
    rows: (json['rows'] as List<dynamic>? ?? <dynamic>[])
        .whereType<List<dynamic>>()
        .map(
          (List<dynamic> row) => row.map((dynamic e) => '$e').toList(),
        )
        .toList(),
  );

  static String _safeSheetName(String raw) {
    String name = raw.replaceAll(RegExp(r'[\[\]\:\*\?\/\\]'), ' ').trim();
    if (name.isEmpty) name = 'Sheet';
    return name.length > 31 ? name.substring(0, 31) : name;
  }
}

class XlsxSpec {
  const XlsxSpec({required this.sheets});

  final List<SheetSpec> sheets;

  static XlsxSpec fromJson(Map<String, dynamic> json) => XlsxSpec(
    sheets: (json['sheets'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList()
        .asMap()
        .entries
        .map(
          (MapEntry<int, Map<String, dynamic>> e) =>
              SheetSpec.fromJson(e.value, e.key),
        )
        .toList(),
  );
}

class SlideSpec {
  const SlideSpec({required this.title, this.bullets = const <String>[]});

  final String title;
  final List<String> bullets;

  static SlideSpec fromJson(Map<String, dynamic> json) => SlideSpec(
    title: (json['title'] as String? ?? '').trim(),
    bullets: (json['bullets'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => '$e')
        .toList(),
  );
}

class PptxSpec {
  const PptxSpec({required this.title, required this.slides});

  final String title;
  final List<SlideSpec> slides;

  static PptxSpec fromJson(Map<String, dynamic> json) => PptxSpec(
    title: (json['title'] as String? ?? '未命名演示').trim(),
    slides: (json['slides'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(SlideSpec.fromJson)
        .toList(),
  );
}

/// 去掉模型可能附带的 ```json 围栏，再解析。
Map<String, dynamic> parseJsonObject(String raw) {
  String text = raw.trim();
  final int start = text.indexOf('{');
  final int end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('模型没有返回 JSON 对象');
  }
  text = text.substring(start, end + 1);
  final Object? decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('模型返回的 JSON 不是对象');
  }
  return decoded;
}

String xmlEscape(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
