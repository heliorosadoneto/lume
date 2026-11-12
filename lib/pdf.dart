// PDF no Lume: metadados lidos direto do arquivo (sem abrir o PDFium), um
// identificador estável por conteúdo e a capa gerada da primeira página.
//
// A renderização das páginas é do pacote pdfrx (PDFium, licença MIT/BSD),
// tudo local e sem internet.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'epub.dart';

class PdfMeta {
  static const _probe = 256 * 1024;

  /// Identificador estável: muda só se o conteúdo mudar. Usa o tamanho e o
  /// começo e o fim do arquivo, para não ler PDFs grandes inteiros.
  static String idFor(String path) {
    final f = File(path).openSync();
    try {
      final len = f.lengthSync();
      final head = f.readSync(len < _probe ? len : _probe);
      Uint8List tail = Uint8List(0);
      if (len > _probe) {
        f.setPositionSync(len - _probe);
        tail = f.readSync(_probe);
      }
      final d = sha1.convert([...utf8.encode('$len:'), ...head, ...tail]);
      return 'pdf:$d';
    } finally {
      f.closeSync();
    }
  }

  /// Lê título e autor do dicionário /Info (quando não está comprimido) ou do
  /// XMP. Sem metadados, o título vem do nome do arquivo.
  static BookMeta read(String path) {
    final f = File(path).openSync();
    String text;
    try {
      final len = f.lengthSync();
      if (len < 5) throw EpubException('Arquivo PDF inválido');
      final head = f.readSync(len < _probe ? len : _probe);
      if (latin1.decode(head.sublist(0, 5), allowInvalid: true) != '%PDF-') {
        throw EpubException('Arquivo PDF inválido');
      }
      Uint8List tail = Uint8List(0);
      if (len > _probe) {
        f.setPositionSync(len - _probe);
        tail = f.readSync(_probe);
      }
      text = latin1.decode([...head, ...tail], allowInvalid: true);
    } finally {
      f.closeSync();
    }
    final info = infoFrom(text);
    final title = info.title?.trim();
    final author = info.author?.trim();
    return BookMeta(
      id: idFor(path),
      title: (title == null || title.isEmpty || _junkTitle(title)) ? titleFromFile(path) : title,
      author: (author == null || author.isEmpty) ? '' : author,
      path: path,
      format: BookFormat.pdf,
    );
  }

  // Títulos que programas colocam sozinhos e que não dizem nada.
  static bool _junkTitle(String t) {
    final l = t.toLowerCase();
    return l == 'untitled' || l.startsWith('microsoft word - ') || l.endsWith('.doc') || l.endsWith('.docx') || l.endsWith('.pdf');
  }

  /// "o-alienista_de-machado.pdf" → "O Alienista de Machado".
  static String titleFromFile(String path) {
    final s = p.basenameWithoutExtension(path).replaceAll(RegExp(r'[_\-.]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return p.basename(path);
    const small = {'a', 'o', 'as', 'os', 'e', 'de', 'da', 'do', 'das', 'dos', 'em', 'na', 'no', 'nas', 'nos', 'para', 'por', 'com', 'um', 'uma'};
    final words = s.split(' ');
    return [
      for (var i = 0; i < words.length; i++)
        (i > 0 && small.contains(words[i].toLowerCase())) || words[i].isEmpty
            ? words[i].toLowerCase()
            : words[i][0].toUpperCase() + words[i].substring(1)
    ].join(' ');
  }

  /// Extrai /Title e /Author do objeto apontado por /Info no trailer.
  static ({String? title, String? author}) infoFrom(String text) {
    final refs = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text).toList();
    for (final r in refs.reversed) {
      final obj = RegExp('(?:^|[\\s>])${r.group(1)}\\s+${r.group(2)}\\s+obj').allMatches(text).lastOrNull;
      if (obj == null) continue;
      final end = text.indexOf('endobj', obj.end);
      final dict = text.substring(obj.end, end < 0 ? text.length : end);
      final t = _field(dict, 'Title'), a = _field(dict, 'Author');
      if (t != null || a != null) return (title: t, author: a);
    }
    // XMP (texto aberto em muitos PDFs)
    String? xmp(String tag) {
      final m = RegExp('<$tag>.*?<rdf:li[^>]*>(.*?)</rdf:li>', dotAll: true).firstMatch(text) ??
          RegExp('<$tag>([^<]+)</$tag>').firstMatch(text);
      if (m == null) return null;
      return utf8.decode(latin1.encode(m.group(1)!), allowMalformed: true)
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>');
    }

    return (title: xmp('dc:title'), author: xmp('dc:creator'));
  }

  static String? _field(String dict, String key) {
    final i = RegExp('/$key\\s*([(<])').firstMatch(dict);
    if (i == null) return null;
    if (i.group(1) == '<') {
      final end = dict.indexOf('>', i.end);
      if (end < 0) return null;
      final hex = dict.substring(i.end, end).replaceAll(RegExp(r'\s'), '');
      final bytes = <int>[];
      for (var k = 0; k + 1 < hex.length; k += 2) {
        bytes.add(int.tryParse(hex.substring(k, k + 2), radix: 16) ?? 0);
      }
      return decodePdfString(bytes);
    }
    // string literal com escapes e parênteses aninhados
    final out = <int>[];
    var depth = 1;
    var k = i.end;
    while (k < dict.length) {
      final c = dict.codeUnitAt(k);
      if (c == 0x5C && k + 1 < dict.length) {
        final n = dict[k + 1];
        k += 2;
        switch (n) {
          case 'n':
            out.add(10);
          case 'r':
            out.add(13);
          case 't':
            out.add(9);
          case 'b':
            out.add(8);
          case 'f':
            out.add(12);
          case '\r':
          case '\n':
            break;
          default:
            if (RegExp(r'[0-7]').hasMatch(n)) {
              var oct = n;
              while (oct.length < 3 && k < dict.length && RegExp(r'[0-7]').hasMatch(dict[k])) {
                oct += dict[k++];
              }
              out.add(int.parse(oct, radix: 8) & 0xFF);
            } else {
              out.add(n.codeUnitAt(0));
            }
        }
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29 && --depth == 0) break;
      out.add(c & 0xFF);
      k++;
    }
    return decodePdfString(out);
  }

  /// UTF-16BE (com BOM), UTF-8 (com BOM) ou PDFDocEncoding (≈ Latin-1).
  static String decodePdfString(List<int> b) {
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      final units = <int>[];
      for (var k = 2; k + 1 < b.length; k += 2) {
        units.add(b[k] << 8 | b[k + 1]);
      }
      return String.fromCharCodes(units);
    }
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return utf8.decode(b.sublist(3), allowMalformed: true);
    }
    return latin1.decode(b, allowInvalid: true);
  }
}

/// Capas dos PDFs: a primeira página vira um PNG pequeno guardado em cache.
class PdfCovers {
  PdfCovers(this.dir);
  final Directory dir;

  File fileFor(String id) => File(p.join(dir.path, '${id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.png'));

  /// Gera a capa (e devolve o número de páginas). Usa o PDFium do pdfrx.
  Future<({Uint8List? cover, int pages})> render(String path, String id, {double width = 300}) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final page = doc.pages.first;
      final h = width * page.height / page.width;
      final img = await page.render(fullWidth: width, fullHeight: h, backgroundColor: 0xFFFFFFFF);
      if (img == null) return (cover: null, pages: doc.pages.length);
      final ui.Image uiImg = await img.createImage();
      img.dispose();
      final bytes = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      uiImg.dispose();
      if (bytes == null) return (cover: null, pages: doc.pages.length);
      final png = bytes.buffer.asUint8List();
      await dir.create(recursive: true);
      await fileFor(id).writeAsBytes(png);
      return (cover: png, pages: doc.pages.length);
    } finally {
      await doc.dispose();
    }
  }
}
