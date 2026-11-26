// Medidas dos blocos para o modo "Virar página": o texto é medido com o mesmo
// estilo e a mesma largura com que é desenhado (veja paginate.dart).
import 'package:flutter/painting.dart';

import 'paginate.dart';

/// Bloco de texto: altura e linhas medidas com TextPainter.
class TextMeasure implements Measured {
  TextMeasure({
    required this.span,
    required this.align,
    required this.width,
    required this.scaler,
    required this.length,
    this.locale,
    this.padTop = 0,
    this.padBottom = 0,
  });

  /// Texto do caractere `from` ao fim do bloco.
  final TextSpan Function(int from) span;
  final TextAlign align;
  final double width;
  final TextScaler scaler;

  /// Idioma do texto: o corte de linhas depende dele, como no campo de texto.
  final Locale? locale;
  @override
  final int length;
  @override
  final double padTop, padBottom;

  @override
  bool get splittable => true;

  TextPainter _layout(int from) => TextPainter(text: span(from), textAlign: align, textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)..layout(maxWidth: width);

  @override
  double heightFrom(int from) {
    final tp = _layout(from);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  /// Alturas das linhas, ajustadas para somar a altura total do texto.
  static List<double> _heights(TextPainter tp) {
    final lines = tp.computeLineMetrics();
    final sum = lines.fold<double>(0, (a, l) => a + l.height);
    final k = sum <= 0 ? 1.0 : tp.height / sum;
    return [for (final l in lines) l.height * k];
  }

  int _lineStart(TextPainter tp, List<double> h, int line, int from) {
    var y = 0.0;
    for (var i = 0; i < line; i++) {
      y += h[i];
    }
    return from + tp.getPositionForOffset(Offset(0, y + h[line] / 2)).offset;
  }

  @override
  int cutFor(int from, double avail, {int minLines = 2}) {
    final tp = _layout(from);
    final h = _heights(tp);
    final n = h.length;
    var k = 0;
    var y = 0.0;
    while (k < n && y + h[k] <= avail + 0.01) {
      y += h[k];
      k++;
    }
    if (k >= n) {
      tp.dispose();
      return length;
    }
    if (k < minLines) {
      tp.dispose();
      return from;
    }
    if (n - k == 1 && k > minLines) k--; // não deixa uma linha sozinha na próxima página
    final cut = _lineStart(tp, h, k, from);
    tp.dispose();
    return cut.clamp(from + 1, length - 1);
  }

  @override
  int firstLineEnd(int from) {
    final tp = _layout(from);
    final h = _heights(tp);
    final cut = h.length <= 1 ? length : _lineStart(tp, h, 1, from);
    tp.dispose();
    return cut.clamp(from + 1, length);
  }
}

/// Bloco que não se divide (imagem, tabela, código, separador): altura estimada.
class FixedMeasure implements Measured {
  FixedMeasure(this.height, {this.padBottom = 0});
  final double height;
  @override
  final double padBottom;
  @override
  double get padTop => 0;
  @override
  bool get splittable => false;
  @override
  int get length => 0;
  @override
  double heightFrom(int from) => height;
  @override
  int cutFor(int from, double avail, {int minLines = 2}) => from;
  @override
  int firstLineEnd(int from) => from;
}
