import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:deepseek_chat/services/document_spec.dart';

/// 基于内置空白模板生成 PPTX。
///
/// 模板里只有一页（标题 + 正文占位符）；这里复制该页为 N 页，并重建
/// presentation.xml / rels / [Content_Types].xml，避免依赖第三方 pptx 库。
class PptxBuilder {
  static Uint8List build(Uint8List template, PptxSpec spec) {
    final Archive source = ZipDecoder().decodeBytes(template);
    final Map<String, List<int>> files = <String, List<int>>{};
    List<int>? slideRels;
    for (final ArchiveFile file in source.files) {
      if (!file.isFile) continue;
      if (file.name.startsWith('ppt/slides/')) {
        if (file.name == 'ppt/slides/_rels/slide1.xml.rels') {
          slideRels = file.content as List<int>;
        }
        continue;
      }
      files[file.name] = file.content as List<int>;
    }

    final List<SlideSpec> slides = spec.slides.isEmpty
        ? <SlideSpec>[SlideSpec(title: spec.title)]
        : spec.slides;

    final String presentation = utf8.decode(
      files['ppt/presentation.xml']!,
      allowMalformed: true,
    );
    final StringBuffer sldIds = StringBuffer('<p:sldIdLst>');
    for (int i = 0; i < slides.length; i++) {
      sldIds.write('<p:sldId id="${256 + i}" r:id="rId${100 + i}"/>');
    }
    sldIds.write('</p:sldIdLst>');
    files['ppt/presentation.xml'] = utf8.encode(
      presentation.replaceFirst(
        RegExp(r'<p:sldIdLst>.*?</p:sldIdLst>', dotAll: true),
        sldIds.toString(),
      ),
    );

    final String rels = utf8.decode(
      files['ppt/_rels/presentation.xml.rels']!,
      allowMalformed: true,
    );
    final StringBuffer slideRelsXml = StringBuffer();
    for (int i = 0; i < slides.length; i++) {
      slideRelsXml.write(
        '<Relationship Id="rId${100 + i}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
        'Target="slides/slide${i + 1}.xml"/>',
      );
    }
    final String cleanedRels = rels.replaceAll(
      RegExp(
        r'<Relationship [^>]*Type="[^"]*/slide"[^>]*/>',
      ),
      '',
    );
    files['ppt/_rels/presentation.xml.rels'] = utf8.encode(
      cleanedRels.replaceFirst('</Relationships>', '$slideRelsXml</Relationships>'),
    );

    final String contentTypes = utf8.decode(
      files['[Content_Types].xml']!,
      allowMalformed: true,
    );
    final StringBuffer slideOverrides = StringBuffer();
    for (int i = 0; i < slides.length; i++) {
      slideOverrides.write(
        '<Override PartName="/ppt/slides/slide${i + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }
    final String cleanedTypes = contentTypes.replaceAll(
      RegExp(r'<Override PartName="/ppt/slides/slide\d+\.xml"[^>]*/>'),
      '',
    );
    files['[Content_Types].xml'] = utf8.encode(
      cleanedTypes.replaceFirst('</Types>', '$slideOverrides</Types>'),
    );

    for (int i = 0; i < slides.length; i++) {
      files['ppt/slides/slide${i + 1}.xml'] = utf8.encode(
        _slideXml(slides[i]),
      );
      if (slideRels != null) {
        files['ppt/slides/_rels/slide${i + 1}.xml.rels'] = slideRels;
      }
    }

    final Archive out = Archive();
    for (final MapEntry<String, List<int>> entry in files.entries) {
      out.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final List<int>? encoded = ZipEncoder().encode(out);
    return Uint8List.fromList(encoded ?? <int>[]);
  }

  static String _slideXml(SlideSpec slide) {
    final List<String> bullets = slide.bullets
        .map((String b) => b.trim())
        .where((String b) => b.isNotEmpty)
        .take(6)
        .toList();
    final StringBuffer body = StringBuffer();
    if (bullets.isEmpty) {
      body.write('<a:p/>');
    } else {
      for (final String bullet in bullets) {
        body.write(
          '<a:p><a:r><a:t>${xmlEscape(bullet)}</a:t></a:r></a:p>',
        );
      }
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
        '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
        '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:t>${xmlEscape(slide.title)}</a:t></a:r></a:p>'
        '</p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content Placeholder 2"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
        '<p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr>'
        '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>$body</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }
}
