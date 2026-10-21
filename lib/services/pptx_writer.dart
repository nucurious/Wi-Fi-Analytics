import 'dart:io';

import 'package:archive/archive_io.dart';

/// One slide: a title, optional subtitle and text lines, optional table (first row is the header).
class PptxSlide {
  final String title;
  final String? subtitle;
  final List<String> lines;
  final List<List<String>>? table;
  const PptxSlide(this.title, {this.subtitle, this.lines = const [], this.table});
}

const _h = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const _relNs = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

const _emptyTree = '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree>';

String _clr(String n, String c) => '<a:$n><a:srgbClr val="$c"/></a:$n>';

String _contentTypes(int n) => '$_h<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
    '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
    '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
    '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
    '${[for (var i = 1; i <= n; i++) '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'].join()}'
    '</Types>';

const _rootRels = '$_h<Relationships xmlns="$_relNs"><Relationship Id="rId1" Type="$_rel/officeDocument" Target="ppt/presentation.xml"/></Relationships>';

String _presentation(int n) => '$_h<p:presentation $_ns><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
    '<p:sldIdLst>${[for (var i = 0; i < n; i++) '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>'].join()}</p:sldIdLst>'
    '<p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>';

String _presentationRels(int n) => '$_h<Relationships xmlns="$_relNs">'
    '<Relationship Id="rId1" Type="$_rel/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
    '${[for (var i = 0; i < n; i++) '<Relationship Id="rId${i + 2}" Type="$_rel/slide" Target="slides/slide${i + 1}.xml"/>'].join()}'
    '<Relationship Id="rId99" Type="$_rel/theme" Target="theme/theme1.xml"/></Relationships>';

const _master = '$_h<p:sldMaster $_ns><p:cSld>$_emptyTree</p:cSld>'
    '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" '
    'accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
    '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>';

const _masterRels = '$_h<Relationships xmlns="$_relNs">'
    '<Relationship Id="rId1" Type="$_rel/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
    '<Relationship Id="rId2" Type="$_rel/theme" Target="../theme/theme1.xml"/></Relationships>';

const _layout = '$_h<p:sldLayout $_ns type="blank" preserve="1"><p:cSld name="Blank">$_emptyTree</p:cSld>'
    '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';

const _layoutRels = '$_h<Relationships xmlns="$_relNs">'
    '<Relationship Id="rId1" Type="$_rel/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>';

const _slideRels = '$_h<Relationships xmlns="$_relNs">'
    '<Relationship Id="rId1" Type="$_rel/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>';

final _theme = '$_h<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="WiFiAnalytics"><a:themeElements>'
    '<a:clrScheme name="W"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="1F3A5F"/></a:dk2><a:lt2><a:srgbClr val="EEEEEE"/></a:lt2>'
    '${_clr('accent1', '1F3A5F')}${_clr('accent2', '2A9D8F')}${_clr('accent3', 'E76F51')}${_clr('accent4', 'F4A261')}'
    '${_clr('accent5', '6B7280')}${_clr('accent6', '264653')}${_clr('hlink', '0563C1')}${_clr('folHlink', '954F72')}</a:clrScheme>'
    '<a:fontScheme name="W"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
    '<a:fmtScheme name="W"><a:fillStyleLst>${'<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>' * 3}</a:fillStyleLst>'
    '<a:lnStyleLst>${'<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>' * 3}</a:lnStyleLst>'
    '<a:effectStyleLst>${'<a:effectStyle><a:effectLst/></a:effectStyle>' * 3}</a:effectStyleLst>'
    '<a:bgFillStyleLst>${'<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>' * 3}</a:bgFillStyleLst></a:fmtScheme>'
    '</a:themeElements></a:theme>';

String _run(String text, int sz, bool bold, String color) =>
    '<a:r><a:rPr lang="en-US" sz="$sz" b="${bold ? 1 : 0}" dirty="0"><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr>'
    '<a:t>${_esc(text)}</a:t></a:r>';

String _textBox(int id, int x, int y, int w, int h, List<(String, int, bool, String)> paras) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Text $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
    '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>'
    '${[for (final (t, sz, b, c) in paras) '<a:p>${_run(t, sz, b, c)}</a:p>'].join()}'
    '</p:txBody></p:sp>';

String _table(int id, int x, int y, int w, List<List<String>> rows, List<int> colW, {int rowH = 330000}) {
  final grid = [for (final c in colW) '<a:gridCol w="$c"/>'].join();
  final trs = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final tcs = StringBuffer();
    for (var c = 0; c < rows[r].length; c++) {
      final hdr = r == 0;
      final fill = hdr ? '1F3A5F' : (r.isEven ? 'EAF0F6' : 'FFFFFF');
      final color = hdr ? 'FFFFFF' : '000000';
      final algn = c == 0 ? 'l' : 'r';
      tcs.write('<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:pPr algn="$algn"/>${_run(rows[r][c], 1400, hdr, color)}</a:p></a:txBody>'
          '<a:tcPr><a:solidFill><a:srgbClr val="$fill"/></a:solidFill></a:tcPr></a:tc>');
    }
    trs.write('<a:tr h="$rowH">$tcs</a:tr>');
  }
  return '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Table $id"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="${rowH * rows.length}"/></p:xfrm>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="1"/>'
      '<a:tblGrid>$grid</a:tblGrid>$trs</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
}

String _slide(PptxSlide s) {
  final b = StringBuffer(_textBox(2, 457200, 300000, 11277600, 900000, [
    (s.title, 2800, true, '1F3A5F'),
    if (s.subtitle != null) (s.subtitle!, 1400, false, '6B7280'),
  ]));
  var y = 1400000;
  if (s.lines.isNotEmpty) {
    b.write(_textBox(3, 457200, y, 11277600, 300000 * s.lines.length + 200000, [for (final l in s.lines) (l, 1600, false, '000000')]));
    y += 300000 * s.lines.length + 300000;
  }
  final t = s.table;
  if (t != null && t.isNotEmpty) {
    final n = t.first.length;
    const first = 4200000;
    final rest = n > 1 ? (11277600 - first) ~/ (n - 1) : 0;
    b.write(_table(4, 457200, y, first + rest * (n - 1), t, [first, for (var i = 1; i < n; i++) rest]));
  }
  return '$_h<p:sld $_ns><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '$b</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
}

/// Writes a simple PowerPoint file (16:9): title, text lines and tables, no charts.
Future<void> writePptx(List<PptxSlide> slides, String outPath) async {
  final tmp = Directory('$outPath.parts');
  if (await tmp.exists()) await tmp.delete(recursive: true);
  await tmp.create(recursive: true);
  try {
    final n = slides.length;
    final parts = <String, String>{
      '[Content_Types].xml': _contentTypes(n),
      '_rels/.rels': _rootRels,
      'ppt/presentation.xml': _presentation(n),
      'ppt/_rels/presentation.xml.rels': _presentationRels(n),
      'ppt/slideMasters/slideMaster1.xml': _master,
      'ppt/slideMasters/_rels/slideMaster1.xml.rels': _masterRels,
      'ppt/slideLayouts/slideLayout1.xml': _layout,
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels': _layoutRels,
      'ppt/theme/theme1.xml': _theme,
      for (var i = 0; i < n; i++) 'ppt/slides/slide${i + 1}.xml': _slide(slides[i]),
      for (var i = 0; i < n; i++) 'ppt/slides/_rels/slide${i + 1}.xml.rels': _slideRels,
    };
    final out = File(outPath);
    if (await out.exists()) await out.delete();
    final zip = ZipFileEncoder();
    zip.create(outPath);
    var k = 0;
    for (final e in parts.entries) {
      final f = File('${tmp.path}/part${k++}.xml')..writeAsStringSync(e.value);
      await zip.addFile(f, e.key);
    }
    await zip.close();
  } finally {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  }
}
