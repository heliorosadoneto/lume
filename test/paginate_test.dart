// A divisão em páginas do modo "Virar página", sem Flutter: blocos de mentira
// com linhas de altura fixa.
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/paginate.dart';

/// Texto de [lines] linhas de 20 px, [perLine] caracteres por linha.
class Fake implements Measured {
  Fake(this.lines, {this.padTop = 0, this.padBottom = 0, this.perLine = 10});
  final int lines, perLine;
  @override
  final double padTop, padBottom;
  @override
  bool get splittable => true;
  @override
  int get length => lines * perLine;
  int linesFrom(int from) => ((length - from) / perLine).ceil();
  @override
  double heightFrom(int from) => linesFrom(from) * 20.0;
  @override
  int cutFor(int from, double avail, {int minLines = 2}) {
    final n = linesFrom(from);
    var k = (avail / 20).floor();
    if (k >= n) return length;
    if (k < minLines) return from;
    if (n - k == 1 && k > minLines) k--;
    return from + k * perLine;
  }

  @override
  int firstLineEnd(int from) => from + perLine;
}

class Box implements Measured {
  Box(this.h);
  final double h;
  @override
  double get padTop => 0;
  @override
  double get padBottom => 0;
  @override
  bool get splittable => false;
  @override
  int get length => 0;
  @override
  double heightFrom(int from) => h;
  @override
  int cutFor(int from, double avail, {int minLines = 2}) => from;
  @override
  int firstLineEnd(int from) => from;
}

void main() {
  test('Parágrafos longos passam de uma página para a outra sem perder nem repetir texto', () async {
    final blocks = [Fake(7), Fake(30), Fake(4), Fake(55), Fake(1)];
    final pages = await paginate(count: blocks.length, measure: (i) => blocks[i], height: 200);
    // cada bloco: os pedaços são contíguos, do 0 até o fim
    for (var b = 0; b < blocks.length; b++) {
      var at = 0;
      for (final p in pages) {
        for (final s in p.slices.where((s) => s.block == b)) {
          expect(s.from, at, reason: 'bloco $b: pedaço seguinte começa onde o anterior terminou');
          at = s.to;
        }
      }
      expect(at, blocks[b].length, reason: 'bloco $b inteiro');
    }
    // nenhuma página passa da altura (10 linhas de 20 px)
    for (final p in pages) {
      var h = 0.0;
      for (final s in p.slices) {
        h += blocks[s.block].heightFrom(s.from) - (s.to < blocks[s.block].length ? blocks[s.block].heightFrom(s.to) : 0);
      }
      expect(h, lessThanOrEqualTo(200.0), reason: 'página ${pages.indexOf(p)}');
    }
    // páginas cheias: 97 linhas em páginas de 10 → 10 páginas
    expect(pages.length, inInclusiveRange(10, 11));
  });

  test('Não deixa uma linha sozinha no começo nem no fim da página', () async {
    final blocks = [Fake(9), Fake(12)]; // altura: 10 linhas; sobra 1 linha depois do primeiro bloco
    final pages = await paginate(count: 2, measure: (i) => blocks[i], height: 200);
    final first = pages.first.slices.where((s) => s.block == 1);
    expect(first, isEmpty, reason: 'sobra 1 linha: o parágrafo seguinte vai inteiro para a próxima página');
    final lastOfPage = pages.expand((p) => p.slices).where((s) => s.block == 1).toList();
    for (final s in lastOfPage) {
      expect(s.to - s.from, greaterThanOrEqualTo(20), reason: 'pelo menos 2 linhas por pedaço');
    }
  });

  test('Blocos que não se dividem (imagem) vão para a página seguinte se não cabem; maiores que a tela rolam', () async {
    final blocks = <Measured>[Fake(6), Box(120), Box(500), Fake(2)];
    final pages = await paginate(count: 4, measure: (i) => blocks[i], height: 200);
    expect(pages[0].slices.map((s) => s.block), [0], reason: '120 px não cabem depois de 120 px de texto');
    expect(pages[1].slices.map((s) => s.block), [1]);
    final big = pages.firstWhere((p) => p.slices.any((s) => s.block == 2));
    expect(big.oversize, isTrue);
    expect(big.slices.length, 1);
    expect(pages.last.slices.single.block, 3);
  });

  test('Uma linha mais alta que a página não trava', () async {
    final pages = await paginate(count: 1, measure: (i) => Fake(3), height: 10);
    expect(pages.expand((p) => p.slices).last.to, 30);
    expect(pages.length, greaterThanOrEqualTo(1));
  });

  test('pageOf acha a página do ponto', () async {
    final blocks = [Fake(30), Fake(30)];
    final pages = await paginate(count: 2, measure: (i) => blocks[i], height: 200);
    expect(pageOf(pages, 0, 0), 0);
    expect(pageOf(pages, 1, 0), greaterThan(0));
    for (var i = 0; i < pages.length; i++) {
      expect(pageOf(pages, pages[i].first.block, pages[i].first.from), i);
    }
    expect(pageOf(pages, 99, 0), pages.length - 1);
  });

  test('Cancelar interrompe a divisão', () async {
    var n = 0;
    final pages = await paginate(
      count: 100000,
      measure: (i) => Fake(3),
      height: 200,
      slice: Duration.zero,
      cancelled: () => ++n > 3,
    );
    expect(pages.length, lessThan(2000));
  });
}
