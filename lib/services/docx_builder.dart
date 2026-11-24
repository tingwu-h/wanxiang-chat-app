import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:deepseek_chat/services/document_spec.dart';

/// 最小可用的 DOCX 生成器：标题、正文、项目符号、表格。
///
/// 不依赖模板，直接组装 OOXML；样式只用直接格式，避免样式表缺失导致
/// Word/WPS 显示异常。
class DocxBuilder {
  static Uint8List build(WordSpec spec) {
    final String document = _documentXml(spec);
    final Map<String, String> files = <String, String>{
      '[Content_Types].xml': _contentTypes,
      '_rels/.rels': _rootRels,
      'word/document.xml': document,
      'word/styles.xml': _styles,
      'word/_rels/document.xml.rels': _documentRels,
    };
    final Archive archive = Archive();
    for (final MapEntry<String, String> entry in files.entries) {
      final List<int> bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final List<int>? encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded ?? <int>[]);
  }

  static const String _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';

  static const String _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  static const String _documentRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  static const String _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Calibri" w:eastAsia="宋体" w:hAnsi="Calibri"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/>'
      '</w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/><w:qFormat/></w:style>'
      '</w:styles>';

  static String _documentXml(WordSpec spec) {
    final StringBuffer body = StringBuffer();
    body.write(_paragraph(spec.title, size: 40, bold: true, spaceAfter: 240));
    for (final DocSection section in spec.sections) {
      if (section.heading.isNotEmpty) {
        body.write(
          _paragraph(
            section.heading,
            size: 30,
            bold: true,
            spaceBefore: 260,
            spaceAfter: 120,
          ),
        );
      }
      for (final String p in section.paragraphs) {
        body.write(_paragraph(p));
      }
      for (final String bullet in section.bullets) {
        body.write(_paragraph('• $bullet', indent: 420));
      }
      if (section.table != null) {
        body.write(_table(section.table!));
      }
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/>'
        '</w:sectPr></w:body></w:document>';
  }

  static String _paragraph(
    String text, {
    int size = 22,
    bool bold = false,
    int indent = 0,
    int spaceAfter = 120,
    int spaceBefore = 0,
  }) {
    final String runProps = '<w:rPr>${bold ? '<w:b/>' : ''}'
        '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>';
    return '<w:p><w:pPr>'
        '${indent > 0 ? '<w:ind w:left="$indent"/>' : ''}'
        '<w:spacing w:before="$spaceBefore" w:after="$spaceAfter"/>'
        '</w:pPr>'
        '<w:r>$runProps<w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r>'
        '</w:p>';
  }

  static String _table(DocTable table) {
    const String border =
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="999999"/>'
        '<w:left w:val="single" w:sz="4" w:color="999999"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
        '<w:right w:val="single" w:sz="4" w:color="999999"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="999999"/>'
        '<w:insideV w:val="single" w:sz="4" w:color="999999"/>'
        '</w:tblBorders>';
    final StringBuffer sb = StringBuffer(
      '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>$border</w:tblPr>',
    );
    if (table.headers.isNotEmpty) {
      sb.write('<w:tr>');
      for (final String header in table.headers) {
        sb.write(_cell(header, bold: true));
      }
      sb.write('</w:tr>');
    }
    for (final List<String> row in table.rows) {
      sb.write('<w:tr>');
      for (final String cell in row) {
        sb.write(_cell(cell));
      }
      sb.write('</w:tr>');
    }
    sb.write('</w:tbl>');
    // 表格后补一个空段落，避免两个表格贴在一起
    sb.write(_paragraph('', spaceAfter: 60));
    return sb.toString();
  }

  static String _cell(String text, {bool bold = false}) =>
      '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>'
      '${_paragraph(text, size: 20, bold: bold, spaceAfter: 20)}</w:tc>';
}
