import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepseek_chat/services/docx_builder.dart';
import 'package:deepseek_chat/services/document_spec.dart';
import 'package:deepseek_chat/services/pptx_builder.dart';
import 'package:deepseek_chat/services/xlsx_builder.dart';

Map<String, String> _parts(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  return <String, String>{
    for (final ArchiveFile f in archive.files)
      if (f.isFile)
        f.name: utf8.decode(f.content as List<int>, allowMalformed: true),
  };
}

void main() {
  group('JSON 解析', () {
    test('去掉 ```json 围栏', () {
      final Map<String, dynamic> json = parseJsonObject(
        '```json\n{"title":"T"}\n```',
      );
      expect(json['title'], 'T');
    });

    test('不是对象时报错', () {
      expect(() => parseJsonObject('no json'), throwsFormatException);
    });
  });

  test('Word 生成结构完整', () {
    final WordSpec spec = WordSpec.fromJson(<String, dynamic>{
      'title': '季度总结',
      'sections': <dynamic>[
        <String, dynamic>{
          'heading': '一、完成情况',
          'paragraphs': <dynamic>['本季度完成 A。'],
          'bullets': <dynamic>['上线 A', '修复 B'],
          'table': <String, dynamic>{
            'headers': <dynamic>['项目', '进度'],
            'rows': <dynamic>[
              <dynamic>['A', '100%'],
            ],
          },
        },
      ],
    });
    final Uint8List bytes = DocxBuilder.build(spec);
    final Map<String, String> parts = _parts(bytes);
    expect(parts.keys, contains('word/document.xml'));
    expect(parts.keys, contains('word/styles.xml'));
    expect(parts['word/document.xml'], contains('季度总结'));
    expect(parts['word/document.xml'], contains('上线 A'));
    expect(parts['word/document.xml'], contains('<w:tbl>'));
    expect(parts['[Content_Types].xml'], contains('wordprocessingml'));

    Directory('build/doc-test').createSync(recursive: true);
    File('build/doc-test/sample.docx').writeAsBytesSync(bytes);
  });

  test('Excel 生成多 sheet 与数字', () {
    final XlsxSpec spec = XlsxSpec.fromJson(<String, dynamic>{
      'sheets': <dynamic>[
        <String, dynamic>{
          'name': '销售',
          'rows': <dynamic>[
            <dynamic>['月份', '金额'],
            <dynamic>['1 月', '12000'],
          ],
        },
        <String, dynamic>{
          'name': '汇总',
          'rows': <dynamic>[
            <dynamic>['合计', '12000'],
          ],
        },
      ],
    });
    final Uint8List bytes = XlsxBuilder.build(spec);
    final Map<String, String> parts = _parts(bytes);
    expect(parts.keys, contains('xl/worksheets/sheet1.xml'));
    expect(parts.keys, contains('xl/worksheets/sheet2.xml'));
    expect(parts['xl/workbook.xml'], contains('销售'));
    expect(parts['xl/worksheets/sheet1.xml'], contains('inlineStr'));
    expect(parts['xl/worksheets/sheet1.xml'], contains('<v>12000</v>'));

    Directory('build/doc-test').createSync(recursive: true);
    File('build/doc-test/sample.xlsx').writeAsBytesSync(bytes);
  });

  test('PPT 按 slide 数量复制并重建关系', () {
    final Uint8List template = File(
      'assets/templates/blank.pptx',
    ).readAsBytesSync();
    final PptxSpec spec = PptxSpec.fromJson(<String, dynamic>{
      'title': '汇报',
      'slides': <dynamic>[
        <String, dynamic>{
          'title': '背景',
          'bullets': <dynamic>['市场变化', '内部目标'],
        },
        <String, dynamic>{
          'title': '数据',
          'bullets': <dynamic>['增长 18%'],
        },
        <String, dynamic>{'title': '下一步', 'bullets': <dynamic>[]},
      ],
    });
    final Uint8List bytes = PptxBuilder.build(template, spec);
    final Map<String, String> parts = _parts(bytes);
    expect(parts.keys, contains('ppt/slides/slide1.xml'));
    expect(parts.keys, contains('ppt/slides/slide3.xml'));
    expect(parts.keys, isNot(contains('ppt/slides/slide4.xml')));
    expect(
      'ppt/presentation.xml'.length,
      greaterThan(0),
    );
    final String presentation = parts['ppt/presentation.xml']!;
    expect(RegExp(r'<p:sldId ').allMatches(presentation).length, 3);
    final String types = parts['[Content_Types].xml']!;
    expect(
      RegExp(
        r'PartName="/ppt/slides/slide\d+\.xml"',
      ).allMatches(types).length,
      3,
    );
    expect(parts['ppt/slides/slide1.xml'], contains('背景'));
    expect(parts['ppt/slides/slide2.xml'], contains('增长 18%'));

    Directory('build/doc-test').createSync(recursive: true);
    File('build/doc-test/sample.pptx').writeAsBytesSync(bytes);
  });
}
