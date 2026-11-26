// Divide o livro em páginas do tamanho da tela (modo "Virar página").
//
// O algoritmo não sabe desenhar: recebe de cada bloco a altura e onde cortar
// (veja [Measured]), então dá para testá-lo sem Flutter. O leitor mede com
// TextPainter, com o mesmo estilo e a mesma largura que usa para desenhar.
import 'dart:async';

/// Um pedaço de bloco numa página: do caractere [from] ao [to] (exclusivo).
/// Blocos que não se dividem (imagem, tabela, código) ocupam uma página inteira
/// ou o que sobrar dela: [from] 0 e [to] -1.
class Slice {
  const Slice(this.block, this.from, this.to, {this.showTop = true, this.showBottom = true});
  final int block, from, to;

  /// Espaço acima/abaixo do bloco: só no primeiro/último pedaço dele.
  final bool showTop, showBottom;
  bool get whole => to < 0;
  @override
  String toString() => 'Slice($block, $from–$to)';
}

class PageSpec {
  const PageSpec(this.slices, {this.oversize = false});
  final List<Slice> slices;

  /// Um bloco que não se divide é maior que a tela: a página rola na vertical.
  final bool oversize;
  Slice get first => slices.first;
}

/// Medidas de um bloco, dadas pelo leitor.
abstract class Measured {
  /// Espaço acima e abaixo do bloco.
  double get padTop;
  double get padBottom;

  /// Blocos de texto se dividem entre páginas; os demais não.
  bool get splittable;

  /// Número de caracteres do bloco (só para os que se dividem).
  int get length;

  /// Altura do texto de [from] até o fim do bloco, sem o espaço acima/abaixo.
  double heightFrom(int from);

  /// Onde cortar o texto que começa em [from] para caber em [avail] pixels:
  /// o início da primeira linha que não cabe. Devolve [from] se nem uma linha
  /// couber. [minLines] evita deixar uma linha sozinha no fim ou no começo da página.
  int cutFor(int from, double avail, {int minLines = 2});

  /// Fim da primeira linha (corte forçado quando uma linha só já não cabe).
  int firstLineEnd(int from);
}

/// Pagina [count] blocos em páginas de [height] pixels. Passa o controle ao
/// laço de eventos a cada [slice] de tempo para a tela não travar.
Future<List<PageSpec>> paginate({
  required int count,
  required Measured Function(int block) measure,
  required double height,
  bool Function()? cancelled,
  void Function(double progress)? onProgress,
  Duration slice = const Duration(milliseconds: 8),
}) async {
  final pages = <PageSpec>[];
  var cur = <Slice>[];
  var used = 0.0;
  var oversize = false;
  final clock = Stopwatch()..start();

  void flush() {
    if (cur.isEmpty) return;
    pages.add(PageSpec(cur, oversize: oversize));
    cur = [];
    used = 0;
    oversize = false;
  }

  for (var i = 0; i < count; i++) {
    if (clock.elapsed > slice) {
      onProgress?.call(i / count);
      await Future<void>.delayed(Duration.zero);
      if (cancelled?.call() ?? false) return pages;
      clock.reset();
    }
    final m = measure(i);
    if (!m.splittable) {
      final top = cur.isEmpty ? 0.0 : m.padTop;
      final h = m.heightFrom(0);
      if (cur.isNotEmpty && used + top + h > height) flush();
      final t = cur.isEmpty ? 0.0 : m.padTop;
      if (h > height) oversize = true;
      cur.add(Slice(i, 0, -1, showTop: t > 0));
      used += t + h + m.padBottom;
      if (h > height) flush();
      continue;
    }
    var from = 0;
    while (true) {
      final first = from == 0;
      // no alto da página o espaço acima do bloco não é desenhado
      final top = cur.isEmpty ? 0.0 : (first ? m.padTop : 0.0);
      final h = m.heightFrom(from);
      if (used + top + h <= height) {
        cur.add(Slice(i, from, m.length, showTop: top > 0));
        used += top + h + m.padBottom;
        break;
      }
      final avail = height - used - top;
      var end = m.cutFor(from, avail);
      if (end <= from) {
        if (cur.isNotEmpty) {
          flush();
          continue;
        }
        end = m.firstLineEnd(from);
        if (end <= from || end >= m.length) {
          cur.add(Slice(i, from, m.length, showTop: false, showBottom: true));
          oversize = true;
          flush();
          break;
        }
      }
      cur.add(Slice(i, from, end, showTop: top > 0, showBottom: false));
      flush();
      from = end;
    }
  }
  flush();
  onProgress?.call(1);
  return pages;
}

/// Índice da página que contém o ponto ([block], [char]).
int pageOf(List<PageSpec> pages, int block, int char) {
  var r = 0;
  for (var i = 0; i < pages.length; i++) {
    final f = pages[i].first;
    if (f.block < block || (f.block == block && f.from <= char)) {
      r = i;
    } else {
      break;
    }
  }
  return r;
}
