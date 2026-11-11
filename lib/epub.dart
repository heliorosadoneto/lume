// Leitor de EPUB próprio do Lume: abre o ZIP, lê o OPF, o sumário (NCX ou nav)
// e transforma o XHTML em blocos de texto simples (títulos e parágrafos).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as hp;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class Run {
  const Run(this.text, {this.italic = false, this.bold = false});
  final String text;
  final bool italic, bold;
}

enum BlockKind { heading, paragraph, separator }

class Block {
  Block(this.kind, this.runs, {this.level = 0});
  final BlockKind kind;
  final List<Run> runs;
  final int level;
  late final String text = runs.map((r) => r.text).join();
}

class TocEntry {
  const TocEntry(this.title, this.block, this.depth);
  final String title;
  final int block, depth;
}

class BookMeta {
  BookMeta({required this.id, required this.title, required this.author, required this.path, this.cover});
  final String id, title, author, path;
  final Uint8List? cover;
}

class Book {
  Book(this.meta, this.blocks, this.toc) {
    var acc = 0;
    final starts = <int>[];
    for (final b in blocks) {
      starts.add(acc);
      acc += b.text.length + 1;
    }
    charStart = starts;
    totalChars = acc;
  }
  final BookMeta meta;
  final List<Block> blocks;
  final List<TocEntry> toc;
  late final List<int> charStart;
  late final int totalChars;

  double progressAt(int block) => totalChars == 0 ? 0 : charStart[block.clamp(0, blocks.length - 1)] / totalChars;

  /// Índice da entrada do sumário que contém o bloco.
  int tocIndexFor(int block) {
    var r = -1;
    for (var i = 0; i < toc.length; i++) {
      if (toc[i].block <= block) r = i;
    }
    return r;
  }

  /// Fim (exclusivo) do capítulo em que o bloco está.
  int chapterEnd(int block) {
    final i = tocIndexFor(block);
    for (var j = i + 1; j < toc.length; j++) {
      if (toc[j].block > block) return toc[j].block;
    }
    return blocks.length;
  }

  /// Minutos restantes no capítulo (~1000 caracteres por minuto).
  int minutesLeftInChapter(int block) {
    final end = chapterEnd(block);
    final endChar = end >= blocks.length ? totalChars : charStart[end];
    return ((endChar - charStart[block]) / 1000).ceil();
  }
}

class EpubException implements Exception {
  EpubException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Epub {
  static Iterable<XmlElement> _els(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static String? _readText(Archive a, String name) {
    final f = a.findFile(name);
    if (f == null) return null;
    return utf8.decode(f.content, allowMalformed: true);
  }

  static String _join(String base, String href) {
    final clean = Uri.decodeComponent(href.split('#').first);
    return p.posix.normalize(p.posix.join(base, clean));
  }

  static String _flipName(String n) {
    final m = RegExp(r'^([^,]+),\s*([^,(]+)').firstMatch(n);
    if (m == null) return n.trim();
    return '${m.group(2)!.trim()} ${m.group(1)!.trim()}';
  }

  static ({Archive archive, XmlDocument opf, String opfDir, BookMeta meta}) _open(Uint8List bytes, String path) {
    final Archive a;
    try {
      a = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw EpubException('Arquivo EPUB inválido');
    }
    final container = _readText(a, 'META-INF/container.xml');
    if (container == null) throw EpubException('EPUB sem container.xml');
    final opfPath = _els(XmlDocument.parse(container), 'rootfile').first.getAttribute('full-path')!;
    final opfText = _readText(a, opfPath);
    if (opfText == null) throw EpubException('EPUB sem OPF');
    final opf = XmlDocument.parse(opfText);
    final opfDir = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);

    String first(String local) =>
        _els(opf, local).map((e) => e.innerText.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => '');
    final title = first('title').split(RegExp(r'\r?\n| / |: ')).first.trim();
    final authors = _els(opf, 'creator').map((e) => _flipName(e.innerText)).where((t) => t.isNotEmpty).toList();
    final ident = first('identifier');

    // Capa: EPUB3 (properties=cover-image) ou EPUB2 (<meta name="cover">).
    final items = _els(opf, 'item').toList();
    XmlElement? coverItem = items.where((e) => (e.getAttribute('properties') ?? '').contains('cover-image')).firstOrNull;
    if (coverItem == null) {
      final coverId = _els(opf, 'meta').where((e) => e.getAttribute('name') == 'cover').firstOrNull?.getAttribute('content');
      if (coverId != null) coverItem = items.where((e) => e.getAttribute('id') == coverId).firstOrNull;
    }
    Uint8List? cover;
    if (coverItem != null) {
      cover = a.findFile(_join(opfDir, coverItem.getAttribute('href')!))?.content;
    }
    final meta = BookMeta(
      id: ident.isNotEmpty ? ident : p.basename(path),
      title: title.isNotEmpty ? title : p.basenameWithoutExtension(path),
      author: authors.isNotEmpty ? authors.join(', ') : 'Autor desconhecido',
      path: path,
      cover: cover,
    );
    return (archive: a, opf: opf, opfDir: opfDir, meta: meta);
  }

  static BookMeta readMeta(String path) => _open(File(path).readAsBytesSync(), path).meta;

  static Book parseFile(String path) => parseBytes(File(path).readAsBytesSync(), path);

  static Book parseBytes(Uint8List bytes, String path) {
    final o = _open(bytes, path);
    final a = o.archive;
    final manifest = {for (final e in _els(o.opf, 'item')) e.getAttribute('id')!: e};
    final blocks = <Block>[];
    final anchors = <String, int>{};

    for (final ref in _els(o.opf, 'itemref')) {
      final item = manifest[ref.getAttribute('idref')];
      if (item == null) continue;
      if (!(item.getAttribute('media-type') ?? '').contains('html')) continue;
      final full = _join(o.opfDir, item.getAttribute('href')!);
      final text = _readText(a, full);
      if (text == null) continue;
      anchors[full] = blocks.length;
      final body = hp.parse(text).body;
      if (body != null) _walk(body, full, blocks, anchors);
    }
    if (blocks.isEmpty) throw EpubException('O livro não tem texto legível');

    // Sumário: NCX (EPUB2) ou nav (EPUB3).
    final toc = <TocEntry>[];
    void add(String title, String src, String base, int depth) {
      final parts = src.split('#');
      final file = _join(base, parts.first);
      final key = parts.length > 1 ? '$file#${parts[1]}' : file;
      final idx = anchors[key] ?? anchors[file];
      final t = title.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (idx != null && t.isNotEmpty) toc.add(TocEntry(t, idx.clamp(0, blocks.length - 1), depth));
    }

    String dirOf(String path) => p.posix.dirname(path) == '.' ? '' : p.posix.dirname(path);
    final ncxItem = manifest.values.where((e) => e.getAttribute('media-type') == 'application/x-dtbncx+xml').firstOrNull;
    final navItem =
        manifest.values.where((e) => (e.getAttribute('properties') ?? '').split(' ').contains('nav')).firstOrNull;
    if (ncxItem != null) {
      final ncxPath = _join(o.opfDir, ncxItem.getAttribute('href')!);
      final ncxText = _readText(a, ncxPath);
      if (ncxText != null) {
        void walkNav(XmlElement parent, int depth) {
          for (final np in parent.childElements.where((e) => e.name.local == 'navPoint')) {
            final label = _els(np, 'text').firstOrNull?.innerText ?? '';
            final src = np.childElements.where((e) => e.name.local == 'content').firstOrNull?.getAttribute('src');
            if (src != null) add(label, src, dirOf(ncxPath), depth);
            walkNav(np, depth + 1);
          }
        }

        final navMap = _els(XmlDocument.parse(ncxText), 'navMap').firstOrNull;
        if (navMap != null) walkNav(navMap, 0);
      }
    }
    if (toc.isEmpty && navItem != null) {
      final navPath = _join(o.opfDir, navItem.getAttribute('href')!);
      final navText = _readText(a, navPath);
      if (navText != null) {
        final doc = hp.parse(navText);
        final nav = doc.querySelectorAll('nav').where((n) => (n.attributes['epub:type'] ?? 'toc') == 'toc').firstOrNull;
        for (final link in nav?.querySelectorAll('a[href]') ?? <dom.Element>[]) {
          var depth = 0;
          for (var e = link.parent; e != null && e != nav; e = e.parent) {
            if (e.localName == 'ol') depth++;
          }
          add(link.text, link.attributes['href']!, dirOf(navPath), (depth - 1).clamp(0, 6));
        }
      }
    }
    toc.sort((x, y) => x.block.compareTo(y.block));
    return Book(o.meta, blocks, toc);
  }

  static const _blockTags = {
    'p', 'div', 'section', 'article', 'blockquote', 'li', 'ul', 'ol', 'dl', 'dd', 'dt', 'table', 'tbody', 'thead', //
    'tr', 'td', 'th', 'pre', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'header', 'footer', 'aside', 'figure', 'nav',
    'main', 'body',
  };

  static void _walk(dom.Element el, String file, List<Block> out, Map<String, int> anchors) {
    for (final node in el.nodes) {
      if (node is dom.Text) {
        if (node.text.trim().isNotEmpty) _emit(node, file, out, anchors);
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName ?? '';
      if (node.id.isNotEmpty) anchors['$file#${node.id}'] = out.length;
      if (tag == 'script' || tag == 'style' || tag == 'svg' || tag == 'img') continue;
      if (tag == 'hr') {
        if (out.isNotEmpty && out.last.kind != BlockKind.separator) out.add(Block(BlockKind.separator, const []));
        continue;
      }
      final h = RegExp(r'^h([1-6])$').firstMatch(tag);
      if (h != null) {
        _registerIds(node, file, out.length, anchors);
        final runs = _inline(node);
        if (runs.isNotEmpty) out.add(Block(BlockKind.heading, runs, level: int.parse(h.group(1)!)));
        continue;
      }
      final hasBlockChild = node.children.any((c) => _blockTags.contains(c.localName));
      if (hasBlockChild) {
        _walk(node, file, out, anchors);
      } else {
        _emit(node, file, out, anchors);
      }
    }
  }

  static void _registerIds(dom.Element e, String file, int idx, Map<String, int> anchors) {
    for (final d in e.querySelectorAll('[id]')) {
      anchors['$file#${d.id}'] = idx;
    }
  }

  static void _emit(dom.Node n, String file, List<Block> out, Map<String, int> anchors) {
    List<Run> runs;
    if (n is dom.Element) {
      _registerIds(n, file, out.length, anchors);
      final t = n.localName;
      runs = _inline(n, italic: t == 'i' || t == 'em', bold: t == 'b' || t == 'strong');
    } else {
      runs = _clean([Run(n.text ?? '')]);
    }
    if (runs.isNotEmpty) out.add(Block(BlockKind.paragraph, runs));
  }

  static List<Run> _inline(dom.Element e, {bool italic = false, bool bold = false}) {
    final runs = <Run>[];
    void go(dom.Node n, bool i, bool b) {
      if (n is dom.Text) {
        runs.add(Run(n.text, italic: i, bold: b));
      } else if (n is dom.Element) {
        final t = n.localName;
        if (t == 'br') {
          runs.add(Run('\n', italic: i, bold: b));
          return;
        }
        if (t == 'script' || t == 'style' || t == 'img' || t == 'svg') return;
        for (final c in n.nodes) {
          go(c, i || t == 'i' || t == 'em' || t == 'cite', b || t == 'b' || t == 'strong');
        }
      }
    }

    for (final c in e.nodes) {
      go(c, italic, bold);
    }
    return _clean(runs);
  }

  /// Junta espaços e quebras de linha do HTML e apara as pontas.
  static List<Run> _clean(List<Run> runs) {
    final out = <Run>[];
    var lastSpace = true;
    for (final r in runs) {
      final sb = StringBuffer();
      if (r.text == '\n') {
        sb.write('\n');
        lastSpace = true;
      } else {
        for (final ch in r.text.split('')) {
          if (ch.trim().isEmpty && ch != '\u00a0') {
            if (!lastSpace) sb.write(' ');
            lastSpace = true;
          } else {
            sb.write(ch);
            lastSpace = false;
          }
        }
      }
      final s = sb.toString();
      if (s.isEmpty) continue;
      if (out.isNotEmpty && out.last.italic == r.italic && out.last.bold == r.bold) {
        out[out.length - 1] = Run(out.last.text + s, italic: r.italic, bold: r.bold);
      } else {
        out.add(Run(s, italic: r.italic, bold: r.bold));
      }
    }
    while (out.isNotEmpty && out.first.text.trim().isEmpty) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.text.trim().isEmpty) {
      out.removeLast();
    }
    if (out.isEmpty) return out;
    out[0] = Run(out.first.text.trimLeft(), italic: out.first.italic, bold: out.first.bold);
    final l = out.length - 1;
    out[l] = Run(out[l].text.trimRight(), italic: out[l].italic, bold: out[l].bold);
    return out;
  }
}
