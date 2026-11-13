// Análise de um PDF para leitura confortável no celular: texto refeito em
// parágrafos (modo texto) e a área com conteúdo de cada página (para cortar as
// margens brancas no modo página). O resultado fica em cache no aparelho.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'epub.dart';
import 'pdf_reflow.dart';

/// Área com conteúdo da página, em frações (0 a 1) da largura e da altura,
/// com y para baixo.
class PageCrop {
  const PageCrop(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  static const full = PageCrop(0, 0, 1, 1);
  double get width => right - left;
  double get height => bottom - top;
  List<double> toJson() => [left, top, right, bottom].map((v) => (v * 10000).round() / 10000).toList();
  static PageCrop fromJson(List<dynamic> j) =>
      PageCrop((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), (j[3] as num).toDouble());
}

class PdfAnalysis {
  PdfAnalysis({required this.pages, required this.reflow, required this.crops});
  final int pages;
  final ReflowResult reflow;

  /// Uma por página (o leitor alinha as páginas pela largura mais comum).
  final List<PageCrop> crops;
  bool get hasText => reflow.hasText;

  /// Livro para o leitor de texto (o mesmo dos EPUBs).
  Book bookFor(BookMeta pdf) => Book(
        BookMeta(id: textId(pdf.id), title: pdf.title, author: pdf.author, path: pdf.path, cover: pdf.cover, format: BookFormat.pdf),
        reflow.blocks,
        reflow.toc,
      );

  static String textId(String pdfId) => '$pdfId#texto';

  Map<String, dynamic> toJson() => {
        'v': PdfAnalyzer.version,
        'n': pages,
        't': reflow.hasText,
        'c': [for (final c in crops) c.toJson()],
        'b': [
          for (var i = 0; i < reflow.blocks.length; i++)
            [reflow.blocks[i].kind == BlockKind.heading ? reflow.blocks[i].level : 0, reflow.blockPage[i], reflow.blocks[i].text]
        ],
        'toc': [for (final e in reflow.toc) [e.title, e.block]],
        'pb': reflow.pageBlock,
      };

  static PdfAnalysis fromJson(Map<String, dynamic> j) {
    final blocks = <Block>[], pages = <int>[];
    for (final b in j['b'] as List) {
      final l = (b as List)[0] as int;
      blocks.add(l == 0 ? Block(BlockKind.paragraph, [Run(b[2] as String)]) : Block(BlockKind.heading, [Run(b[2] as String)], level: l));
      pages.add(b[1] as int);
    }
    return PdfAnalysis(
      pages: j['n'] as int,
      reflow: ReflowResult(blocks, pages, [for (final e in j['toc'] as List) TocEntry((e as List)[0] as String, e[1] as int, 0)],
          hasText: j['t'] as bool, pageBlock: [for (final b in (j['pb'] as List? ?? const [])) b as int]),
      crops: [for (final c in j['c'] as List) PageCrop.fromJson(c as List)],
    );
  }
}

class PdfAnalyzer {
  PdfAnalyzer(this.dir);
  final Directory dir;

  /// Sobe quando a forma de refazer o texto muda (refaz o cache).
  static const version = 2;

  File fileFor(String id) => File(p.join(dir.path, '${id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.json'));

  /// Lê do cache (rápido) ou analisa o PDF. [progress] recebe (feitas, total).
  Future<PdfAnalysis> analyze(String path, String id, {void Function(int done, int total)? progress}) async {
    final f = fileFor(id);
    if (await f.exists()) {
      try {
        final text = await f.readAsString();
        final a = await compute(_decode, text);
        if (a != null) return a;
      } catch (_) {}
    }
    final doc = await PdfDocument.openFile(path);
    try {
      final n = doc.pages.length;
      final pages = <PdfTextPage>[];
      final crops = <PageCrop>[];
      final renderCrop = n <= 1500;
      for (var i = 0; i < n; i++) {
        final page = doc.pages[i];
        var lines = <PdfTextLine>[];
        try {
          final raw = await page.loadText();
          if (raw != null && raw.fullText.trim().isNotEmpty) {
            final rects = [for (final r in raw.charRects) (l: r.left, t: r.top, r: r.right, b: r.bottom)];
            lines = linesFromRaw(raw.fullText, rects, page.height);
          }
        } catch (_) {}
        pages.add(PdfTextPage(i + 1, page.width, page.height, lines));
        PageCrop? c = renderCrop ? await _inkCrop(page) : null;
        c = _union(c, _textCrop(page.width, page.height, lines));
        crops.add(c ?? PageCrop.full);
        progress?.call(i + 1, n);
      }
      final reflow = await compute(PdfReflow.run, pages);
      final a = PdfAnalysis(pages: n, reflow: reflow, crops: _padded(crops));
      try {
        await dir.create(recursive: true);
        await f.writeAsString(jsonEncode(a.toJson()));
      } catch (_) {}
      return a;
    } finally {
      await doc.dispose();
    }
  }

  static PdfAnalysis? _decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    if (j['v'] != version) return null;
    return PdfAnalysis.fromJson(j);
  }

  /// Área com tinta, numa miniatura da página (pega imagens também).
  static Future<PageCrop?> _inkCrop(PdfPage page) async {
    const w = 72;
    final h = math.max(1, (w * page.height / page.width).round());
    final img = await page.render(fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xFFFFFFFF);
    if (img == null) return null;
    try {
      return inkBounds(img.pixels, img.width, img.height);
    } finally {
      img.dispose();
    }
  }

  /// Caixa dos pixels não brancos (BGRA ou RGBA) em frações da imagem.
  static PageCrop? inkBounds(Uint8List px, int w, int h, {int threshold = 235}) {
    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        if (px[o] < threshold || px[o + 1] < threshold || px[o + 2] < threshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return null;
    // um pixel de folga de cada lado
    return PageCrop(math.max(0, minX - 1) / w, math.max(0, minY - 1) / h, math.min(w, maxX + 2) / w, math.min(h, maxY + 2) / h);
  }

  static PageCrop? _textCrop(double pw, double ph, List<PdfTextLine> lines) {
    if (lines.isEmpty) return null;
    var l = double.infinity, t = double.infinity, r = 0.0, b = 0.0;
    for (final x in lines) {
      l = math.min(l, x.left);
      r = math.max(r, x.right);
      t = math.min(t, x.top - x.size * .4);
      b = math.max(b, x.bottom + x.size * .4);
    }
    return PageCrop((l / pw).clamp(0, 1), (t / ph).clamp(0, 1), (r / pw).clamp(0, 1), (b / ph).clamp(0, 1));
  }

  static PageCrop? _union(PageCrop? a, PageCrop? b) {
    if (a == null) return b;
    if (b == null) return a;
    return PageCrop(math.min(a.left, b.left), math.min(a.top, b.top), math.max(a.right, b.right), math.max(a.bottom, b.bottom));
  }

  /// Uma pequena folga em volta do conteúdo de cada página. Página vazia
  /// (ou quase sem margem) fica inteira.
  static List<PageCrop> _padded(List<PageCrop> crops) {
    const pad = .015;
    return [
      for (final c in crops)
        PageCrop(math.max(0, c.left - pad), math.max(0, c.top - pad * .7), math.min(1, c.right + pad), math.min(1, c.bottom + pad * .7)),
    ];
  }
}
