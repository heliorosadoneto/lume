// Markdown (.md, .markdown) no leitor de texto do Lume. O texto é lido pelo
// pacote `markdown` (do time do Dart, licença BSD) com as extensões do GitHub
// e convertido nos mesmos blocos do EPUB: títulos (com âncoras e sumário),
// parágrafos com negrito, itálico, código e links, listas, citações, blocos de
// código, linhas horizontais, tabelas e imagens locais.
import 'dart:io';
import 'dart:typed_data';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import 'epub.dart';
import 'pdf.dart';
import 'txt.dart';

class MarkdownBook {
  static const extensions = ['md', 'markdown'];
  static bool isMarkdown(String path) => extensions.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));

  static String idFor(Uint8List bytes) => 'md:${TxtBook.idFor(bytes).substring(4)}';

  static final _front = RegExp(r'^\uFEFF?---[ \t]*\r?\n([\s\S]*?)\r?\n(---|\.\.\.)[ \t]*(\r?\n|$)');
  static final _frontKey = RegExp(r'^(title|t[íi]tulo|author|autor)\s*:\s*(.+)$', caseSensitive: false, multiLine: true);

  /// Separa o cabeçalho YAML (--- title: … ---), se houver.
  static ({String body, String? title, String? author}) frontMatter(String text) {
    final m = _front.firstMatch(text);
    if (m == null) return (body: text, title: null, author: null);
    String? title, author;
    for (final k in _frontKey.allMatches(m.group(1)!)) {
      final v = k.group(2)!.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
      if (k.group(1)!.toLowerCase().startsWith('t')) {
        title ??= v;
      } else {
        author ??= v;
      }
    }
    return (body: text.substring(m.end), title: title, author: author);
  }

  static final _h1 = RegExp(r'^ {0,3}#[ \t]+(.+?)[ \t#]*$', multiLine: true);
  static final _setext = RegExp(r'^(\S.*)\r?\n=+[ \t]*$', multiLine: true);

  /// Título: do cabeçalho YAML, do primeiro título de nível 1 ou do nome do arquivo.
  static BookMeta metaFromBytes(Uint8List bytes, String path) {
    final fm = frontMatter(TxtBook.decode(bytes.length > 64 * 1024 ? bytes.sublist(0, 64 * 1024) : bytes));
    var title = fm.title;
    if (title == null) {
      final noCode = fm.body.replaceAll(RegExp(r'^(```|~~~)[\s\S]*?^\1', multiLine: true), '');
      final a = _h1.firstMatch(noCode), b = _setext.firstMatch(noCode);
      final m = (a != null && (b == null || a.start <= b.start)) ? a : b;
      if (m != null) title = _plain(m.group(1)!);
    }
    return BookMeta(
      id: idFor(bytes),
      title: (title == null || title.isEmpty) ? PdfMeta.titleFromFile(path) : title,
      author: fm.author ?? '',
      path: path,
      format: BookFormat.md,
    );
  }

  /// Texto do título sem marcação (**, `, [link](…)).
  static String _plain(String s) => s
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'[*_`~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static BookMeta readMeta(String path) => metaFromBytes(File(path).readAsBytesSync(), path);

  static Book parseFile(String path) => parse(File(path).readAsBytesSync(), path);

  static Book parse(Uint8List bytes, String path) {
    final meta = metaFromBytes(bytes, path);
    final body = frontMatter(TxtBook.decode(bytes)).body;
    final r = convert(body, baseDir: p.dirname(path));
    return Book(meta, r.blocks, r.toc);
  }

  /// Converte o texto Markdown em blocos do leitor e no sumário.
  static ({List<Block> blocks, List<TocEntry> toc}) convert(String text, {required String baseDir}) {
    final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false).parse(text.replaceAll('\r\n', '\n'));
    final c = _Converter(baseDir);
    for (final n in nodes) {
      c.block(n, 0);
    }
    if (c.blocks.isEmpty) c.blocks.add(Block(BlockKind.paragraph, const [Run('(arquivo vazio)')]));
    // Sumário: títulos de nível 1 a 3, com o recuo relativo ao menor nível usado.
    final heads = [for (var i = 0; i < c.blocks.length; i++) if (c.blocks[i].kind == BlockKind.heading && c.blocks[i].level <= 3) i];
    final minLevel = heads.isEmpty ? 1 : heads.map((i) => c.blocks[i].level).reduce((a, b) => a < b ? a : b);
    final toc = [for (final i in heads) TocEntry(c.blocks[i].text, i, c.blocks[i].level - minLevel)];
    return (blocks: c.blocks, toc: toc);
  }

  /// Âncora no estilo do GitHub: minúsculas, sem pontuação, espaços viram "-".
  static String slug(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '').replaceAll(RegExp(r'\s'), '-');

  static bool isRemote(String src) => RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(src) && !src.toLowerCase().startsWith('file:');
}

class _Style {
  const _Style({this.italic = false, this.bold = false, this.code = false, this.strike = false, this.link});
  final bool italic, bold, code, strike;
  final String? link;
  _Style copy({bool? italic, bool? bold, bool? code, bool? strike, String? link}) =>
      _Style(italic: italic ?? this.italic, bold: bold ?? this.bold, code: code ?? this.code, strike: strike ?? this.strike, link: link ?? this.link);
}

class _Converter {
  _Converter(this.baseDir);
  final String baseDir;
  final blocks = <Block>[];
  final _anchors = <String, int>{};

  static final _tag = RegExp(r'</?[a-zA-Z][a-zA-Z0-9-]*(\s[^<>]*)?/?>');
  static final _br = RegExp(r'<br\s*/?>', caseSensitive: false);

  String _anchor(String text) {
    final base = MarkdownBook.slug(text);
    final n = _anchors.update(base, (v) => v + 1, ifAbsent: () => 0);
    return n == 0 ? base : '$base-$n';
  }

  // ---------- trechos em linha ----------
  void _inline(md.Node n, _Style st, List<Run> out, List<md.Element> images) {
    if (n is md.Text) {
      final t = n.text.replaceAll(_br, '\n').replaceAll(_tag, '');
      if (t.isNotEmpty) out.add(Run(t, italic: st.italic, bold: st.bold, code: st.code, strike: st.strike, link: st.link));
      return;
    }
    if (n is! md.Element) {
      if (n.textContent.isNotEmpty) out.add(Run(n.textContent));
      return;
    }
    switch (n.tag) {
      case 'em':
        _children(n, st.copy(italic: true), out, images);
      case 'strong':
        _children(n, st.copy(bold: true), out, images);
      case 'del':
        _children(n, st.copy(strike: true), out, images);
      case 'code':
        out.add(Run(n.textContent, italic: st.italic, bold: st.bold, code: true, link: st.link));
      case 'a':
        _children(n, st.copy(link: n.attributes['href'] ?? ''), out, images);
      case 'br':
        out.add(const Run('\n'));
      case 'img':
        images.add(n);
      case 'input': // caixa de tarefa (- [x]) tratada no item da lista
        break;
      default:
        _children(n, st, out, images);
    }
  }

  void _children(md.Element e, _Style st, List<Run> out, List<md.Element> images) {
    for (final c in e.children ?? const <md.Node>[]) {
      _inline(c, st, out, images);
    }
  }

  /// Junta trechos vizinhos com o mesmo estilo e tira espaços nas pontas.
  List<Run> _tidy(List<Run> runs) {
    final out = <Run>[];
    for (final r in runs) {
      final last = out.isEmpty ? null : out.last;
      if (last != null && last.italic == r.italic && last.bold == r.bold && last.code == r.code && last.strike == r.strike && last.link == r.link) {
        out[out.length - 1] = Run(last.text + r.text, italic: r.italic, bold: r.bold, code: r.code, strike: r.strike, link: r.link);
      } else {
        out.add(r);
      }
    }
    if (out.isEmpty) return out;
    Run trim(Run r, String t) => Run(t, italic: r.italic, bold: r.bold, code: r.code, strike: r.strike, link: r.link);
    out[0] = trim(out[0], out[0].text.trimLeft());
    out[out.length - 1] = trim(out.last, out.last.text.trimRight());
    return out.where((r) => r.text.isNotEmpty).toList();
  }

  void _image(md.Element img, int quote) {
    final raw = img.attributes['src'] ?? '';
    final src = Uri.decodeFull(raw);
    final path = MarkdownBook.isRemote(src)
        ? src
        : p.normalize(p.isAbsolute(src) ? src : p.join(baseDir, src.startsWith('file:') ? Uri.parse(src).toFilePath() : src));
    final alt = img.attributes['alt'] ?? img.attributes['title'] ?? '';
    blocks.add(Block(BlockKind.image, [Run(alt)], src: path, quote: quote));
  }

  /// Parágrafo (ou item de lista) com as imagens que estavam dentro dele logo depois.
  void _textBlock(Iterable<md.Node> nodes, int quote, Block Function(List<Run> runs) make) {
    final runs = <Run>[];
    final images = <md.Element>[];
    for (final n in nodes) {
      _inline(n, const _Style(), runs, images);
    }
    final tidy = _tidy(runs);
    if (tidy.isNotEmpty) blocks.add(make(tidy));
    for (final i in images) {
      _image(i, quote);
    }
  }

  // ---------- blocos ----------
  void block(md.Node n, int quote) {
    if (n is md.Text) {
      _textBlock([n], quote, (r) => Block(BlockKind.paragraph, r, quote: quote));
      return;
    }
    if (n is! md.Element) return;
    switch (n.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(n.tag.substring(1));
        _textBlock(n.children ?? const [], quote, (r) {
          final text = r.map((x) => x.text).join();
          return Block(BlockKind.heading, r, level: level, quote: quote, anchor: _anchor(text), center: false);
        });
      case 'p':
        _textBlock(n.children ?? const [], quote, (r) => Block(BlockKind.paragraph, r, quote: quote));
      case 'blockquote':
        for (final c in n.children ?? const <md.Node>[]) {
          block(c, quote + 1);
        }
      case 'ul' || 'ol':
        _list(n, quote, 0);
      case 'pre':
        var code = n.textContent;
        if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
        blocks.add(Block(BlockKind.code, [Run(code, code: true)], quote: quote));
      case 'hr':
        blocks.add(Block(BlockKind.separator, const [Run('* * *')], quote: quote));
      case 'table':
        _table(n, quote);
      default:
        // HTML em bloco ou algo desconhecido: fica o texto.
        final t = n.textContent.replaceAll(_br, '\n').replaceAll(_tag, '').trim();
        if (t.isNotEmpty) blocks.add(Block(BlockKind.paragraph, [Run(t)], quote: quote));
    }
  }

  static const _bullets = ['•', '◦', '▪'];

  void _list(md.Element list, int quote, int depth) {
    final ordered = list.tag == 'ol';
    var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    for (final li in (list.children ?? const <md.Node>[]).whereType<md.Element>()) {
      final box = li.children?.whereType<md.Element>().where((e) => e.tag == 'input').firstOrNull;
      var marker = box != null ? (box.attributes['checked'] == 'true' ? '☑' : '☐') : (ordered ? '$number.' : _bullets[depth % _bullets.length]);
      number++;
      final inline = <md.Node>[];
      void flush() {
        if (inline.isEmpty) return;
        final m = marker;
        _textBlock(List.of(inline), quote, (r) => Block(BlockKind.listItem, r, indent: depth, marker: m, quote: quote));
        inline.clear();
        marker = ''; // parágrafos seguintes do mesmo item ficam sem marcador
      }

      for (final c in li.children ?? const <md.Node>[]) {
        if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) {
          flush();
          _list(c, quote, depth + 1);
        } else if (c is md.Element && c.tag == 'p') {
          flush();
          inline.addAll(c.children ?? const []);
          flush();
        } else if (c is md.Element && const {'pre', 'blockquote', 'table', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(c.tag)) {
          flush();
          block(c, quote);
        } else {
          inline.add(c);
        }
      }
      if (marker.isNotEmpty && inline.isEmpty) inline.add(md.Text(''));
      flush();
    }
  }

  void _table(md.Element t, int quote) {
    final rows = <List<String>>[];
    List<String?>? aligns;
    for (final tr in _all(t, 'tr')) {
      final cells = (tr.children ?? const <md.Node>[]).whereType<md.Element>().toList();
      aligns ??= [for (final c in cells) c.attributes['align']];
      rows.add([for (final c in cells) c.textContent.replaceAll(_tag, '').trim()]);
    }
    if (rows.isEmpty) return;
    final text = rows.map((r) => r.join(' · ')).join('\n');
    blocks.add(Block(BlockKind.table, [Run(text)], rows: rows, aligns: aligns, quote: quote));
  }

  Iterable<md.Element> _all(md.Element e, String tag) sync* {
    for (final c in (e.children ?? const <md.Node>[]).whereType<md.Element>()) {
      if (c.tag == tag) {
        yield c;
      } else {
        yield* _all(c, tag);
      }
    }
  }
}

