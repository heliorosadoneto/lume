// Texto puro (.txt) no leitor de texto do Lume: detecta a codificação (UTF-8,
// UTF-16 com BOM ou Latin-1/Windows-1252), refaz os parágrafos e acha títulos
// simples ("CAPÍTULO I", linhas curtas em maiúsculas).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'epub.dart';
import 'pdf.dart';

class TxtBook {
  static const _probe = 256 * 1024;

  /// Identificador estável pelo conteúdo (como no PDF).
  static String idFor(Uint8List bytes) {
    final head = bytes.length <= 2 * _probe ? bytes : Uint8List.fromList([...bytes.sublist(0, _probe), ...bytes.sublist(bytes.length - _probe)]);
    return 'txt:${sha1.convert([...utf8.encode('${bytes.length}:'), ...head])}';
  }

  // Windows-1252: 0x80–0x9F (aspas curvas, travessão, reticências…).
  static const _cp1252 = {
    0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, //
    0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
    0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
    0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
  };

  /// Decodifica o texto: BOM UTF-8/UTF-16, UTF-8 válido ou, se não for,
  /// Latin-1 com os caracteres extras do Windows-1252.
  static String decode(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return utf8.decode(b.sublist(3), allowMalformed: true);
    }
    if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
      final le = b[0] == 0xFF;
      final units = <int>[];
      for (var i = 2; i + 1 < b.length; i += 2) {
        units.add(le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    try {
      return utf8.decode(b);
    } on FormatException {
      return String.fromCharCodes([for (final c in b) _cp1252[c] ?? c]);
    }
  }

  static final _meta = RegExp(r'^\s*(title|t[íi]tulo|author|autor)\s*:\s*(.+)$', caseSensitive: false);

  static ({String title, String author}) _header(List<String> lines, String path) {
    String? title, author;
    for (final l in lines.take(80)) {
      final m = _meta.firstMatch(l);
      if (m == null) continue;
      final k = m.group(1)!.toLowerCase();
      if (k.startsWith('t')) {
        title ??= m.group(2)!.trim();
      } else {
        author ??= m.group(2)!.trim();
      }
    }
    return (title: title ?? PdfMeta.titleFromFile(path), author: author ?? '');
  }

  static BookMeta readMeta(String path) => metaFromBytes(File(path).readAsBytesSync(), path);

  static BookMeta metaFromBytes(Uint8List bytes, String path) {
    final text = decode(bytes.length > 64 * 1024 ? bytes.sublist(0, 64 * 1024) : bytes);
    final h = _header(const LineSplitter().convert(text), path);
    return BookMeta(id: idFor(bytes), title: h.title, author: h.author, path: path, format: BookFormat.txt);
  }

  static Book parseFile(String path) => parse(File(path).readAsBytesSync(), path);

  static Book parse(Uint8List bytes, String path) {
    var lines = const LineSplitter().convert(decode(bytes));
    final meta = metaFromBytes(bytes, path);
    // Project Gutenberg: só o que fica entre "*** START OF" e "*** END OF".
    final start = lines.indexWhere((l) => l.startsWith('*** START OF'));
    final end = lines.indexWhere((l) => l.startsWith('*** END OF'));
    if (start >= 0) lines = lines.sublist(start + 1, end > start ? end : lines.length);
    final r = paragraphs(lines);
    return Book(meta, r.blocks, r.toc);
  }

  static final _chapter = RegExp(r'^(cap[íi]tulo|chapter|parte|part|livro|book|pr[óo]logo|ep[íi]logo|pref[áa]cio)\b', caseSensitive: false);
  static final _roman = RegExp(r'^[IVXLC]+\.?$');

  /// Parágrafos: separados por linha em branco. Se o arquivo não tiver linhas
  /// em branco, cada linha é um parágrafo.
  static ({List<Block> blocks, List<TocEntry> toc}) paragraphs(List<String> lines) {
    final blankSeparated = lines.where((l) => l.trim().isEmpty).length >= lines.length * .05;
    final groups = <List<String>>[];
    var cur = <String>[];
    for (final raw in lines) {
      final l = raw.trimRight();
      if (l.trim().isEmpty) {
        if (cur.isNotEmpty) groups.add(cur);
        cur = [];
      } else if (!blankSeparated) {
        groups.add([l]);
      } else {
        cur.add(l);
      }
    }
    if (cur.isNotEmpty) groups.add(cur);

    final blocks = <Block>[];
    final toc = <TocEntry>[];
    for (final g in groups) {
      final text = g.map((l) => l.trim()).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      if (RegExp(r'^[*\s.·~-]{3,}$').hasMatch(text)) {
        blocks.add(Block(BlockKind.separator, const [Run('* * *')]));
        continue;
      }
      final letters = text.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
      final upper = letters.isNotEmpty && letters == letters.toUpperCase() && letters.length >= 2;
      final heading = g.length <= 2 && text.length <= 70 && (_chapter.hasMatch(text) || _roman.hasMatch(text) || (upper && !RegExp(r'[.,;:]$').hasMatch(text)));
      if (heading) {
        blocks.add(Block(BlockKind.heading, [Run(text)], level: 2));
        toc.add(TocEntry(text, blocks.length - 1, 0));
      } else {
        blocks.add(Block(BlockKind.paragraph, [Run(text)]));
      }
    }
    return (blocks: blocks, toc: toc);
  }

  static bool isTxt(String path) => p.extension(path).toLowerCase() == '.txt';
}
