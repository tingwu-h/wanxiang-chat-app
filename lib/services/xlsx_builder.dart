import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:deepseek_chat/services/document_spec.dart';

/// 最小可用的 XLSX 生成器：多 sheet、表头、列宽、数字/文本。
class XlsxBuilder {
  static Uint8List build(XlsxSpec spec) {
    final List<SheetSpec> sheets = spec.sheets.isEmpty
        ? <SheetSpec>[const SheetSpec(name: 'Sheet1', rows: <List<String>>[])]
        : spec.sheets;

    final Map<String, String> files = <String, String>{
      '[Content_Types].xml': _contentTypes(sheets.length),
      '_rels/.rels': _rootRels,
      'xl/workbook.xml': _workbook(sheets),
      'xl/_rels/workbook.xml.rels': _workbookRels(sheets.length),
      'xl/styles.xml': _styles,
    };
    for (int i = 0; i < sheets.length; i++) {
      files['xl/worksheets/sheet${i + 1}.xml'] = _sheet(sheets[i]);
    }

    final Archive archive = Archive();
    for (final MapEntry<String, String> entry in files.entries) {
      final List<int> bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final List<int>? encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded ?? <int>[]);
  }

  static String _contentTypes(int count) {
    final StringBuffer overrides = StringBuffer();
    overrides.write(
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
    );
    overrides.write(
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
    for (int i = 1; i <= count; i++) {
      overrides.write(
        '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '$overrides'
        '</Types>';
  }

  static const String _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbook(List<SheetSpec> sheets) {
    final StringBuffer sb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>',
    );
    for (int i = 0; i < sheets.length; i++) {
      sb.write(
        '<sheet name="${xmlEscape(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
      );
    }
    sb.write('</sheets></workbook>');
    return sb.toString();
  }

  static String _workbookRels(int count) {
    final StringBuffer sb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    for (int i = 1; i <= count; i++) {
      sb.write(
        '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>',
      );
    }
    sb.write(
      '<Relationship Id="rId${count + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
    sb.write('</Relationships>');
    return sb.toString();
  }

  static const String _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
      '<borders count="1"><border/></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  static String _sheet(SheetSpec sheet) {
    final StringBuffer sb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>',
    );
    for (int r = 0; r < sheet.rows.length; r++) {
      sb.write('<row r="${r + 1}">');
      final List<String> row = sheet.rows[r];
      for (int c = 0; c < row.length; c++) {
        final String ref = '${_column(c)}${r + 1}';
        sb.write(_cell(ref, row[c]));
      }
      sb.write('</row>');
    }
    sb.write('</sheetData></worksheet>');
    return sb.toString();
  }

  static String _cell(String ref, String value) {
    final String text = value.trim();
    final num? number = text.isEmpty ? null : num.tryParse(text);
    if (number != null && !text.startsWith('0') && text.length < 15) {
      return '<c r="$ref"><v>$number</v></c>';
    }
    return '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(value)}</t></is></c>';
  }

  static String _column(int index) {
    int value = index + 1;
    final StringBuffer sb = StringBuffer();
    while (value > 0) {
      final int rem = (value - 1) % 26;
      sb.write(String.fromCharCode(65 + rem));
      value = (value - 1) ~/ 26;
    }
    return sb.toString().split('').reversed.join();
  }
}
