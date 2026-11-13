// Modo texto do PDF: refazer parágrafos a partir das linhas do PDFium.
// Só dados sintéticos e PDFs de domínio público.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';
import 'package:lume/pdf.dart';
import 'package:lume/pdf_analysis.dart';
import 'package:lume/pdf_reflow.dart';

import 'support/pdfium.dart';

/// Página 400x600 com cabeçalho corrido, número de página no rodapé e linhas
/// de corpo (justificadas, recuo de 15 na primeira linha do parágrafo).
PdfTextPage page(int n, List<String> body, {String? heading, int numberOffset = 0, bool header = true}) {
  final lines = <PdfTextLine>[];
  if (header) lines.add(PdfTextLine.at(n.isEven ? 'MACHADO DE ASSIS' : 'A Mão e a Luva', left: 150, right: 250, top: 22, size: 8));
  var y = 80.0;
  if (heading != null) {
    lines.add(PdfTextLine.at(heading, left: 140, right: 260, top: y, size: 16));
    y += 50;
  }
  for (final raw in body) {
    final indent = raw.startsWith('>');
    final short = raw.endsWith('|');
    final text = raw.replaceAll('>', '').replaceAll('|', '');
    lines.add(PdfTextLine.at(text, left: indent ? 55 : 40, right: short ? 40 + text.length * 4.5 : 360, top: y));
    y += 14;
  }
  lines.add(PdfTextLine.at('${n + numberOffset}', left: 196, right: 204, top: 570, size: 8));
  return PdfTextPage(n, 400, 600, lines);
}

const filler = 'era uma vez uma linha de corpo comprida para ocupar a largura';

void main() {
  group('joinLines', () {
    test('linhas comuns se juntam com espaço', () {
      expect(PdfReflow.joinLines('A noite caía', 'sobre a cidade.', hyphenated: true), 'A noite caía sobre a cidade.');
    });
    test('livro hifenizado: a palavra partida volta inteira', () {
      expect(PdfReflow.joinLines('ele conti-', 'nuou andando', hyphenated: true), 'ele continuou andando');
    });
    test('livro sem hifenização: o hífen da palavra composta fica', () {
      expect(PdfReflow.joinLines('um céu vermelho-', 'sangue', hyphenated: false), 'um céu vermelho-sangue');
    });
    test('pronome depois do hífen (ênclise) mantém o hífen', () {
      expect(PdfReflow.joinLines('apressavam-', 'se para casa', hyphenated: true), 'apressavam-se para casa');
      expect(PdfReflow.joinLines('disse-', 'lhe tudo', hyphenated: true), 'disse-lhe tudo');
    });
    test('hífen invisível (U+00AD) some', () {
      expect(PdfReflow.joinLines('pala\u00AD', 'vra', hyphenated: false), 'palavra');
    });
    test('travessão de diálogo não é hifenização', () {
      expect(PdfReflow.joinLines('Ele disse —', 'vamos', hyphenated: true), 'Ele disse — vamos');
    });
  });

  group('cabeçalhos, rodapés e números de página', () {
    final pages = [for (var i = 1; i <= 8; i++) page(i, [filler, filler, filler], numberOffset: 10)];
    final out = PdfReflow.stripRunning(pages);

    test('cabeçalho corrido e número de página saem', () {
      for (final p in out) {
        final texts = p.lines.map((l) => l.text).toList();
        expect(texts, isNot(contains('MACHADO DE ASSIS')));
        expect(texts, isNot(contains('A Mão e a Luva')));
        expect(texts.where((t) => RegExp(r'^\d+$').hasMatch(t)), isEmpty);
        expect(texts, [filler, filler, filler]);
      }
    });

    test('um número solto no meio do texto fica', () {
      final p = PdfTextPage(1, 400, 600, [
        PdfTextLine.at(filler, left: 40, right: 360, top: 80),
        PdfTextLine.at('1889', left: 190, right: 210, top: 300),
        PdfTextLine.at(filler, left: 40, right: 360, top: 320),
      ]);
      final r = PdfReflow.stripRunning([p, ...pages]);
      expect(r.first.lines.map((l) => l.text), contains('1889'));
    });
  });

  group('run', () {
    final pages = [
      page(1, [
        '>Estela tinha dezessete anos quando entrou naquela casa, e trazia',
        'consigo uma certa gravidade que espantava a todos que a conhe-',
        'ciam desde menina; ninguém sabia dizer de onde lhe viera aquilo|',
        '>Guiomar, ao contrário, era a alegria da casa e da vizinhança in-',
        'teira, e não havia festa em que não estivesse presente.|',
      ], heading: 'CAPÍTULO I'),
      page(2, [
        '>Passaram-se os meses sem novidade. A baronesa envelhecia de-',
        'vagar, cercada de cuidados, e a afilhada lia-lhe os jornais to-',
        'das as tardes, depois do café, na varanda que dava para o mar,',
        'enquanto o sol descia por trás dos morros da cidade antiga.|',
      ]),
      page(3, [
        'continuação do parágrafo que veio da página anterior sem recuo',
        'e termina aqui.|',
      ], heading: 'CAPÍTULO II'),
      page(4, [filler, '$filler.|']),
      // mais páginas para o cabeçalho corrido se repetir o bastante
      for (var i = 5; i <= 10; i++) page(i, ['>$filler', filler, filler, filler, filler, '$filler.|']),
    ];
    final r = PdfReflow.run(pages);

    test('tem texto e acha os capítulos', () {
      expect(r.hasText, isTrue);
      expect(r.toc.map((e) => e.title), ['CAPÍTULO I', 'CAPÍTULO II']);
      expect(r.blocks[r.toc.first.block].kind, BlockKind.heading);
    });

    test('parágrafos refeitos, hifenização desfeita, sem cabeçalho nem número', () {
      final paras = r.blocks.where((b) => b.kind != BlockKind.heading).map((b) => b.text).toList();
      expect(paras[0], startsWith('Estela tinha dezessete anos'));
      expect(paras[0], contains('a conheciam desde menina'));
      expect(paras[0], endsWith('aquilo'));
      expect(paras[1], contains('vizinhança inteira'));
      expect(paras[2], contains('envelhecia devagar'));
      expect(paras[2], contains('lia-lhe os jornais todas as tardes'));
      expect(paras.any((p) => p.contains('MACHADO') || p.contains('Mão e a Luva')), isFalse);
      expect(paras.any((p) => RegExp(r'^\d+$').hasMatch(p)), isFalse);
    });

    test('parágrafo que atravessa a página conta para as duas', () {
      final two = [
        page(1, ['>$filler', filler, filler]),
        page(2, [filler, '$filler.|', '>$filler', '$filler.|']),
        for (var i = 3; i <= 8; i++) page(i, ['>$filler', filler, filler, filler, '$filler.|']),
      ];
      final rr = PdfReflow.run(two);
      expect(rr.blockForPage(2), rr.blockForPage(1));
      expect(rr.blocks[rr.blockForPage(1)].text.split(filler).length - 1, 5);
    });

    test('cada bloco sabe a página de onde veio', () {
      expect(r.blockPage.length, r.blocks.length);
      expect(r.blockPage.first, 1);
      final ch2 = r.toc[1].block;
      expect(r.blockPage[ch2], 3);
      // página que começa com capítulo: o título
      expect(r.blockForPage(3), ch2);
      // página 2 começa um parágrafo novo
      expect(r.blocks[r.blockForPage(2)].text, startsWith('Passaram-se'));
      // fim curto na página 3 → a página 4 começa outro parágrafo
      expect(r.blockPage[r.blockForPage(4)], 4);
      expect(r.blocks[r.blockForPage(3) + 1].text, endsWith('termina aqui.'));
    });

    test('PDF sem texto (escaneado) não tem modo texto', () {
      final empty = [for (var i = 1; i <= 5; i++) PdfTextPage(i, 400, 600, const [])];
      expect(PdfReflow.run(empty).hasText, isFalse);
      // só uma linha perdida em meio a páginas-imagem também não conta
      final almost = [...empty, page(6, ['Digitalizado por fulano'], header: false)];
      expect(PdfReflow.run(almost).hasText, isFalse);
    });
  });

  group('linesFromRaw', () {
    ({double l, double t, double r, double b}) box(double x, double base) => (l: x, t: base + 10, r: x + 5, b: base);

    test('hífen de fim de linha do PDFium (\\u0002) e linhas coladas', () {
      // PDF: y para cima. "ab\u0002" na linha de cima, "cd" logo abaixo, sem \n entre elas.
      const text = 'ab\u0002cd';
      final rects = [box(300, 500), box(305, 500), box(310, 500), box(10, 480), box(15, 480)];
      final lines = linesFromRaw(text, rects, 600);
      expect(lines.map((l) => l.text), ['ab-', 'cd']);
      expect(lines.first.top, lessThan(lines.last.top)); // y para baixo
    });

    test('quebra de linha normal', () {
      const text = 'ab\r\ncd';
      final rects = [box(10, 500), box(15, 500), box(20, 500), box(25, 500), box(10, 480), box(15, 480)];
      expect(linesFromRaw(text, rects, 600).map((l) => l.text), ['ab', 'cd']);
    });
  });

  test('inkBounds: caixa dos pixels escuros', () {
    const w = 10, h = 20;
    final px = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
    for (var y = 5; y <= 14; y++) {
      for (var x = 3; x <= 6; x++) {
        final o = (y * w + x) * 4;
        px[o] = px[o + 1] = px[o + 2] = 0;
      }
    }
    final c = PdfAnalyzer.inkBounds(px, w, h)!;
    expect(c.left, closeTo(.2, 1e-9));
    expect(c.right, closeTo(.8, 1e-9));
    expect(c.top, closeTo(.2, 1e-9));
    expect(c.bottom, closeTo(.8, 1e-9));
    expect(PdfAnalyzer.inkBounds(Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255), w, h), isNull);
  });

  group('PDF de verdade (domínio público)', () {
    setUpAll(initPdfiumForTests);

    test('Helena: modo texto, cache e corte de margens', () async {
      final dir = Directory.systemTemp.createTempSync('lume-texto');
      final meta = PdfMeta.read('test/fixtures/helena-amostra.pdf');
      final analyzer = PdfAnalyzer(dir);
      final steps = <int>[];
      final a = await analyzer.analyze(meta.path, meta.id, progress: (d, t) => steps.add(d));
      expect(a.hasText, isTrue);
      expect(steps.last, a.pages);
      expect(a.crops.length, a.pages);
      final book = a.bookFor(meta);
      expect(book.meta.id, '${meta.id}#texto');
      final paras = book.blocks.where((b) => b.kind != BlockKind.heading).toList();
      expect(paras.length, greaterThan(5));
      expect(paras.any((b) => RegExp(r'^\d+$').hasMatch(b.text.trim())), isFalse);
      expect(paras.where((b) => b.text.length > 300), isNotEmpty); // parágrafos, não linhas
      // a amostra tem margens: a área de texto é mais estreita que a página
      final mid = a.crops[a.pages ~/ 2];
      expect(mid.left, greaterThan(.05));
      expect(mid.right, lessThan(.95));
      // segunda vez vem do cache, sem progresso
      expect(analyzer.fileFor(meta.id).existsSync(), isTrue);
      final steps2 = <int>[];
      final b = await analyzer.analyze(meta.path, meta.id, progress: (d, t) => steps2.add(d));
      expect(steps2, isEmpty);
      expect(b.reflow.blocks.length, a.reflow.blocks.length);
      expect(b.reflow.blocks.last.text, a.reflow.blocks.last.text);
      expect(b.reflow.blockPage, a.reflow.blockPage);
      expect(b.reflow.pageBlock, a.reflow.pageBlock);
      expect(a.reflow.pageBlock.length, a.pages);
    });
  });
}
