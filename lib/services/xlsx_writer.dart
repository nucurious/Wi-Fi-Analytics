import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

/// One worksheet: a CSV file, or a byte range of one (a session's rows).
class SheetSource {
  final String name; // worksheet name (max 31 chars)
  final String csvPath;
  final int start; // byte offset of the first row to include
  final int? end; // exclusive; null = to end of file
  final String? header; // header line, when [start] skips the file's own header
  const SheetSource(this.name, this.csvPath, {this.start = 0, this.end, this.header});
}

/// Writes an Excel workbook (.xlsx) with one sheet per [SheetSource].
///
/// Streams row by row, so large logs don't need to fit in memory. Numbers are
/// stored as numbers (so they chart), everything else as text; the header row
/// is bold and frozen. Run it on a background isolate (Isolate.run): it is
/// CPU-heavy for big logs. Returns the number of sheets written.
Future<int> writeXlsx(List<SheetSource> sources, String outPath) async {
  final tmp = Directory('$outPath.parts');
  if (await tmp.exists()) await tmp.delete(recursive: true);
  await tmp.create(recursive: true);
  final sheets = <String>[];
  try {
    for (final src in sources) {
      final f = File(src.csvPath);
      if (!await f.exists()) continue;
      final len = await f.length();
      final end = src.end == null ? len : (src.end! > len ? len : src.end!);
      final start = src.start > end ? 0 : src.start;
      if (end - start <= 0) continue;
      final idx = sheets.length + 1;
      final sheetFile = File('${tmp.path}/sheet$idx.xml');
      final rows = await _writeSheet(f, start, end, src.header, sheetFile);
      if (rows <= 1) {
        await sheetFile.delete();
        continue; // header only
      }
      sheets.add(src.name.length > 31 ? src.name.substring(0, 31) : src.name);
    }
    if (sheets.isEmpty) return 0;

    Future<File> part(String name, String text) async => File('${tmp.path}/$name')..writeAsStringSync(text);

    final ct = await part('ct.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    final rels = await part('rels.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    final wb = await part('workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(sheets[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>');
    final wbRels = await part('workbook.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    final styles = await part('styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>');

    final out = File(outPath);
    if (await out.exists()) await out.delete();
    final zip = ZipFileEncoder();
    zip.create(outPath);
    await zip.addFile(ct, '[Content_Types].xml');
    await zip.addFile(rels, '_rels/.rels');
    await zip.addFile(wb, 'xl/workbook.xml');
    await zip.addFile(wbRels, 'xl/_rels/workbook.xml.rels');
    await zip.addFile(styles, 'xl/styles.xml');
    for (var i = 1; i <= sheets.length; i++) {
      await zip.addFile(File('${tmp.path}/sheet$i.xml'), 'xl/worksheets/sheet$i.xml');
    }
    await zip.close();
    return sheets.length;
  } finally {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  }
}

const int _maxRows = 1048576; // Excel's limit

/// Converts CSV bytes [start, end) to worksheet XML. Returns rows written.
Future<int> _writeSheet(File csv, int start, int end, String? header, File out) async {
  final sink = out.openWrite();
  sink.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews><sheetData>');
  var rows = 0;
  void writeRow(List<String> fields) {
    if (rows >= _maxRows) return;
    final bold = rows == 0;
    final b = StringBuffer('<row>');
    for (final v in fields) {
      if (v.isEmpty) {
        b.write('<c/>');
      } else if (!bold && _isNumber(v)) {
        b.write('<c><v>$v</v></c>');
      } else {
        b.write('<c t="inlineStr"${bold ? ' s="1"' : ''}><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
      }
    }
    b.write('</row>');
    sink.write(b.toString());
    rows++;
  }

  if (header != null) writeRow(_parseLine(header));
  final parser = _CsvParser(writeRow);
  await for (final chunk in csv.openRead(start, end).transform(utf8.decoder)) {
    parser.add(chunk);
  }
  parser.close();
  sink.write('</sheetData></worksheet>');
  await sink.close();
  return rows;
}

final _num = RegExp(r'^-?(0|[1-9]\d{0,14})(\.\d+)?([eE][-+]?\d+)?$');
bool _isNumber(String v) => v.length <= 20 && _num.hasMatch(v);

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

List<String> _parseLine(String line) {
  final out = <List<String>>[];
  _CsvParser(out.add)
    ..add(line)
    ..close();
  return out.isEmpty ? <String>[] : out.first;
}

/// Minimal RFC 4180 parser (quoted fields, doubled quotes, newlines in quotes).
class _CsvParser {
  final void Function(List<String>) onRow;
  _CsvParser(this.onRow);

  final _field = StringBuffer();
  final _row = <String>[];
  bool _inQuotes = false;
  bool _quotePending = false; // saw a quote while in quotes: end or escaped quote
  bool _any = false;

  void add(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (_quotePending) {
        _quotePending = false;
        if (c == '"') {
          _field.write('"');
          continue;
        }
        _inQuotes = false; // closing quote; fall through to handle c
      }
      if (_inQuotes) {
        if (c == '"') {
          _quotePending = true;
        } else {
          _field.write(c);
        }
        continue;
      }
      switch (c) {
        case '"':
          _inQuotes = true;
          _any = true;
        case ',':
          _row.add(_field.toString());
          _field.clear();
          _any = true;
        case '\r':
          break;
        case '\n':
          _endRow();
        default:
          _field.write(c);
          _any = true;
      }
    }
  }

  void _endRow() {
    if (!_any && _row.isEmpty && _field.isEmpty) return; // blank line
    _row.add(_field.toString());
    _field.clear();
    onRow(List<String>.of(_row));
    _row.clear();
    _any = false;
  }

  void close() {
    if (_quotePending) {
      _quotePending = false;
      _inQuotes = false;
    }
    if (_any || _row.isNotEmpty || _field.isNotEmpty) _endRow();
  }
}
