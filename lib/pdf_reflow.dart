// Modo texto do PDF: transforma as linhas do PDF (com posição na página) em
// parágrafos e títulos, para o PDF ser lido no mesmo leitor dos EPUBs.
//
// Tudo aqui é Dart puro (sem PDFium), para rodar fora da thread de interface e
// ser testado com linhas sintéticas.
import 'dart:math' as math;

import 'epub.dart';

/// Uma linha de texto na página. Coordenadas em pontos, com y para baixo
/// (0 = topo da página). [size] é a altura típica das letras.
class PdfTextLine {
  const PdfTextLine(this.text, {required this.left, required this.right, required this.top, required this.bottom, required this.size});
  final String text;
  final double left, right, top, bottom, size;
  double get baseline => bottom;

  /// Linha de teste a partir do topo e da altura da letra.
  factory PdfTextLine.at(String text, {required double left, required double right, required double top, double size = 10}) =>
      PdfTextLine(text, left: left, right: right, top: top, bottom: top + size, size: size);
}

class PdfTextPage {
  const PdfTextPage(this.number, this.width, this.height, this.lines);
  final int number; // 1 = primeira
  final double width, height;
  final List<PdfTextLine> lines;
  int get chars => lines.fold(0, (n, l) => n + l.text.replaceAll(RegExp(r'\s'), '').length);
}

class ReflowResult {
  ReflowResult(this.blocks, this.blockPage, this.toc, {required this.hasText, this.pageBlock = const []});
  final List<Block> blocks;

  /// Página (1 = primeira) em que cada bloco começa.
  final List<int> blockPage;
  final List<TocEntry> toc;
  final bool hasText;

  /// Para cada página, o bloco onde está a primeira linha dela (-1: página
  /// sem texto). Um parágrafo que vem da página anterior conta para as duas.
  final List<int> pageBlock;

  /// Bloco a mostrar ao abrir uma página: o que contém o topo dela.
  int blockForPage(int page) {
    for (var q = math.min(page, pageBlock.length); q >= 1; q--) {
      final b = pageBlock[q - 1];
      if (b >= 0 && b < blocks.length) return b;
    }
    var r = 0;
    for (var i = 0; i < blockPage.length; i++) {
      if (blockPage[i] <= page) {
        r = i;
      } else {
        break;
      }
    }
    return r;
  }
}

/// Constrói as linhas de uma página a partir do texto bruto do PDFium
/// (`fullText` + um retângulo por caractere, em coordenadas do PDF com y para cima).
List<PdfTextLine> linesFromRaw(String text, List<({double l, double t, double r, double b})> rects, double pageHeight) {
  final out = <PdfTextLine>[];
  var start = 0;
  void flush(int end) {
    final buf = StringBuffer();
    final ls = <double>[], rs = <double>[], tops = <double>[], bottoms = <double>[], hs = <double>[];
    for (var i = start; i < end && i < rects.length; i++) {
      final ch = text[i];
      if (ch == '\r') continue;
      // o PDFium marca o hífen de fim de linha como \u0002
      buf.write(ch == '\u0002' ? '-' : ch);
      if (ch.trim().isEmpty) continue;
      final r = rects[i];
      ls.add(r.l);
      rs.add(r.r);
      final h = r.t - r.b;
      if (h >= 2 && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch)) {
        hs.add(h);
        bottoms.add(pageHeight - r.b);
        tops.add(pageHeight - r.t);
      }
    }
    final s = buf.toString().trim();
    if (s.isEmpty || ls.isEmpty) return;
    if (hs.isEmpty) {
      // só pontuação/símbolos: usa o que houver
      for (var i = start; i < end && i < rects.length; i++) {
        if (text[i].trim().isEmpty) continue;
        bottoms.add(pageHeight - rects[i].b);
        tops.add(pageHeight - rects[i].t);
        hs.add(math.max(rects[i].t - rects[i].b, 1));
      }
    }
    out.add(PdfTextLine(s,
        left: ls.reduce(math.min), right: rs.reduce(math.max), top: _median(tops), bottom: _median(bottoms), size: _pct(hs, .3)));
  }

  // Quebra em "\n" e também quando o texto volta para a esquerda numa linha
  // mais abaixo (o PDFium às vezes junta duas linhas visuais, como em "verme-
  // lho-" + "sangue").
  ({double l, double t, double r, double b})? last;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') {
      flush(i);
      start = i + 1;
      last = null;
      continue;
    }
    if (i >= rects.length || text[i].trim().isEmpty) continue;
    final r = rects[i];
    final h = math.max(r.t - r.b, 4.0);
    if (last != null && r.l < last.l - 3 * h && (last.b - r.b) > .6 * h) {
      flush(i);
      start = i;
    }
    last = r;
  }
  flush(text.length);
  return _mergeSameBaseline(out);
}

/// O PDFium às vezes quebra uma linha visual em pedaços (itálico, outra fonte).
List<PdfTextLine> _mergeSameBaseline(List<PdfTextLine> l) {
  final out = <PdfTextLine>[];
  for (final x in l) {
    final p = out.isEmpty ? null : out.last;
    if (p != null && (x.baseline - p.baseline).abs() < 0.35 * math.max(p.size, x.size) && x.left >= p.right - 1) {
      final gap = x.left - p.right;
      out[out.length - 1] = PdfTextLine('${p.text}${gap > 0.15 * p.size ? ' ' : ''}${x.text}',
          left: p.left, right: x.right, top: math.min(p.top, x.top), bottom: p.bottom, size: math.max(p.size, x.size));
    } else {
      out.add(x);
    }
  }
  return out;
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

double _pct(List<double> v, double p) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[((s.length - 1) * p).round()];
}

class PdfReflow {
  static const _clitics = {
    'se', 'me', 'te', 'lhe', 'lhes', 'nos', 'vos', 'o', 'a', 'os', 'as', 'lo', 'la', 'los', 'las', 'no', 'na', 'nas', //
    'mo', 'ma', 'to', 'ta', 'lho', 'lha', 'lhos', 'lhas', 'ei', 'ia', 'emos', 'ás', 'á', 'ão', 'íamos',
  };

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\d+'), '#').replaceAll(RegExp(r'\s+'), ' ').trim();
  static final _pageNum = RegExp(r'^(?:p[áa]g(?:ina)?\.?\s*)?[-–—\s]*(\d{1,4})[-–—\s]*(?:de\s+\d+)?$', caseSensitive: false);

  /// Tira cabeçalhos e rodapés que se repetem e números de página.
  static List<PdfTextPage> stripRunning(List<PdfTextPage> pages) {
    final textPages = pages.where((p) => p.lines.isNotEmpty).toList();
    final minRepeat = math.max(3, (textPages.length * .25).round());
    bool inTop(PdfTextPage p, PdfTextLine l) => l.top < p.height * .1;
    bool inBottom(PdfTextPage p, PdfTextLine l) => l.bottom > p.height * .9;

    // Linhas repetidas no topo/rodapé (com os números trocados por #).
    final counts = <String, int>{};
    Iterable<PdfTextLine> edges(PdfTextPage p) sync* {
      final n = p.lines.length;
      for (var i = 0; i < n; i++) {
        if (i < 2 || i >= n - 2) yield p.lines[i];
      }
    }

    for (final p in textPages) {
      for (final k in {for (final l in edges(p)) if (inTop(p, l) || inBottom(p, l)) _norm(l.text)}) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final repeated = {
      for (final e in counts.entries)
        if (e.value >= minRepeat && e.key.length > 1 && e.key != '#') e.key
    };

    // Números de página: o número acompanha a página (deslocamento constante).
    final offsets = <int, int>{};
    for (final p in textPages) {
      for (final l in edges(p)) {
        final m = _pageNum.firstMatch(l.text.trim());
        if (m != null && (inTop(p, l) || inBottom(p, l))) {
          final o = int.parse(m.group(1)!) - p.number;
          offsets[o] = (offsets[o] ?? 0) + 1;
        }
      }
    }
    final pageOffsets = {
      for (final e in offsets.entries)
        if (e.value >= math.max(3, (textPages.length * .2).round())) e.key
    };

    return [
      for (final p in pages)
        PdfTextPage(p.number, p.width, p.height, [
          for (var i = 0; i < p.lines.length; i++)
            if (!_isRunning(p, i, repeated, pageOffsets, inTop, inBottom)) p.lines[i]
        ])
    ];
  }

  static bool _isRunning(PdfTextPage p, int i, Set<String> repeated, Set<int> pageOffsets,
      bool Function(PdfTextPage, PdfTextLine) inTop, bool Function(PdfTextPage, PdfTextLine) inBottom) {
    final n = p.lines.length;
    if (i >= 2 && i < n - 2) return false;
    final l = p.lines[i];
    if (!inTop(p, l) && !inBottom(p, l)) return false;
    if (repeated.contains(_norm(l.text))) return true;
    final m = _pageNum.firstMatch(l.text.trim());
    return m != null && pageOffsets.contains(int.parse(m.group(1)!) - p.number);
  }

  /// Junta duas linhas do mesmo parágrafo, tratando hifenização no fim da linha.
  static String joinLines(String a, String b, {required bool hyphenated}) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    final last = a[a.length - 1];
    if (last == '\u00AD') return a.substring(0, a.length - 1) + b;
    final m = RegExp(r'(\p{L})-$', unicode: true).firstMatch(a);
    final next = RegExp(r'^(\p{Ll}+)', unicode: true).firstMatch(b);
    if (m != null && next != null) {
      final word = next.group(1)!;
      // "apressavam-|se", "vermelho-|sangue" (não hifenizado): mantém o hífen
      if (!hyphenated || _clitics.contains(word)) return a + b;
      // livro hifenizado: "conti-|nuou" → "continuou"
      return a.substring(0, a.length - 1) + b;
    }
    return '$a $b';
  }

  static ReflowResult run(List<PdfTextPage> rawPages) {
    final total = rawPages.length;
    final withText = rawPages.where((p) => p.chars >= 40).length;
    final hasText = total > 0 && withText >= math.max(1, total * .5) && rawPages.fold<int>(0, (n, p) => n + p.chars) >= 200;
    if (!hasText) return ReflowResult([], [], [], hasText: false);

    final pages = stripRunning(rawPages);
    final all = [for (final p in pages) ...p.lines];
    if (all.isEmpty) return ReflowResult([], [], [], hasText: false);

    // Medidas do corpo do texto.
    final sizes = <double>[for (final l in all) for (var k = 0; k < math.min(l.text.length ~/ 10 + 1, 8); k++) l.size];
    final body = _median(sizes);
    final leftCounts = <int, int>{};
    for (final l in all) {
      if (l.text.length > 20) leftCounts[l.left.round()] = (leftCounts[l.left.round()] ?? 0) + 1;
    }
    final bodyLeft = leftCounts.isEmpty
        ? _median([for (final l in all) l.left])
        : leftCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key.toDouble();
    final bodyRight = _pct([for (final l in all) if (l.text.length > 20) l.right], .9);
    final width = math.max(bodyRight - bodyLeft, 1.0);
    final gaps = <double>[];
    for (final p in pages) {
      for (var i = 1; i < p.lines.length; i++) {
        final d = p.lines[i].baseline - p.lines[i - 1].baseline;
        if (d > 0 && d < body * 3) gaps.add(d);
      }
    }
    final lineGap = gaps.isEmpty ? body * 1.4 : _median(gaps);

    bool isShort(PdfTextLine l) => l.right < bodyRight - .12 * width;
    bool indented(PdfTextLine l) => l.left > bodyLeft + .8 * body && l.left < bodyLeft + .25 * width;
    bool centered(PdfTextLine l) =>
        ((l.left - bodyLeft) - (bodyRight - l.right)).abs() < .08 * width && l.left > bodyLeft + .12 * width;

    // Texto alinhado à esquerda (sem justificar): linha curta não indica fim de parágrafo.
    final shortRatio = all.where(isShort).length / all.length;
    final ragged = shortRatio > .35;

    // Livro hifenizado? (muitas linhas terminam em "letra-" seguidas de minúscula)
    var hy = 0, pairs = 0;
    for (final p in pages) {
      for (var i = 1; i < p.lines.length; i++) {
        pairs++;
        if (RegExp(r'\p{L}-$', unicode: true).hasMatch(p.lines[i - 1].text) &&
            RegExp(r'^\p{Ll}', unicode: true).hasMatch(p.lines[i].text)) {
          hy++;
        }
      }
    }
    final hyphenated = pairs > 0 && hy / pairs > .03;

    final blocks = <Block>[];
    final blockPage = <int>[];
    final toc = <TocEntry>[];
    final pageBlock = List.filled(pages.length, -1);
    String? cur;
    var curPage = 0;
    PdfTextLine? prev;
    var prevWasHeading = false;

    void close() {
      if (cur != null && cur!.trim().isNotEmpty) {
        blocks.add(Block(BlockKind.paragraph, [Run(cur!.trim())]));
        blockPage.add(curPage);
      }
      cur = null;
    }

    for (final p in pages) {
      for (var i = 0; i < p.lines.length; i++) {
        final l = p.lines[i];
        final gapBefore = i == 0 ? double.infinity : l.baseline - p.lines[i - 1].baseline;
        final gapAfter = i == p.lines.length - 1 ? double.infinity : p.lines[i + 1].baseline - l.baseline;
        final big = l.size >= body * 1.3 && l.text.length < 120;
        final isolated = gapBefore > lineGap * 1.8 && gapAfter > lineGap * 1.8;
        final looksLikeText = RegExp(r'^[—–\-«"“]|^\p{Ll}', unicode: true).hasMatch(l.text) || RegExp(r'[,;]$').hasMatch(l.text);
        final endsSentence = RegExp(r'[.!?…]$').hasMatch(l.text);
        final continuesHeading = prevWasHeading && big && i > 0 && gapBefore < lineGap * 2.2 && l.text.length < 90;
        final heading = continuesHeading ||
            (!looksLikeText &&
                l.text.length < 90 &&
                (big || (centered(l) && isolated && l.text.length < 60)) &&
                (!endsSentence || (centered(l) && big)));
        if (heading) {
          close();
          if (i == 0 && p.number <= pageBlock.length) pageBlock[p.number - 1] = blocks.length;
          // títulos de várias linhas (grandes e seguidos) viram um só
          if (continuesHeading && blocks.isNotEmpty && blocks.last.kind == BlockKind.heading) {
            final last = blocks.removeLast();
            blocks.add(Block(BlockKind.heading, [Run('${last.text} ${l.text}')], level: last.level));
            final t = toc.removeLast();
            toc.add(TocEntry(_tocTitle('${last.text} ${l.text}'), t.block, 0));
          } else {
            blocks.add(Block(BlockKind.heading, [Run(l.text)], level: big ? 2 : 3));
            blockPage.add(p.number);
            toc.add(TocEntry(_tocTitle(l.text), blocks.length - 1, 0));
          }
          prev = l;
          prevWasHeading = true;
          continue;
        }
        final newPage = i == 0;
        bool breakHere;
        if (cur == null || prev == null) {
          breakHere = true;
        } else if (newPage) {
          breakHere = (!ragged && isShort(prev)) || indented(l);
        } else {
          breakHere = gapBefore > lineGap * 1.55 || indented(l) || (!ragged && isShort(prev)) || (centered(l) && centered(prev));
        }
        if (breakHere) close();
        if (newPage && p.number <= pageBlock.length) pageBlock[p.number - 1] = blocks.length;
        if (breakHere) {
          cur = l.text;
          curPage = p.number;
        } else {
          cur = joinLines(cur!, l.text, hyphenated: hyphenated);
        }
        prev = l;
        prevWasHeading = false;
      }
    }
    close();
    return ReflowResult(blocks, blockPage, toc, hasText: blocks.isNotEmpty, pageBlock: pageBlock);
  }

  static String _tocTitle(String t) {
    final s = t.trim();
    if (RegExp(r'^\d{1,3}$').hasMatch(s)) return 'Capítulo $s';
    return s;
  }
}
