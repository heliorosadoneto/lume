import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';

void main() {
  test('Dom Casmurro: metadados, capa, blocos e sumário', () {
    final b = Epub.parseFile('assets/books/dom-casmurro.epub');
    expect(b.meta.title, 'Dom Casmurro');
    expect(b.meta.author, 'Machado de Assis');
    expect(b.meta.cover, isNotNull);
    expect(b.blocks.length, greaterThan(500));
    expect(b.toc.length, greaterThan(100));
    final i = b.toc.indexWhere((t) => t.title == 'Do livro.');
    expect(b.blocks[b.toc[i].block].text, contains('Do livro'));
    expect(b.minutesLeftInChapter(b.toc[i].block), greaterThan(0));
  });
  test('Metadados: título de uma linha e autor "Sobrenome, Nome" invertido', () {
    final m = Epub.readMeta('demo_folder/iracema.epub');
    expect(m.title, 'Iracema');
    expect(m.author, 'José Martiniano de Alencar');
  });
  test('Todos os EPUBs de exemplo abrem', () {
    for (final f in ['dom-casmurro', 'quincas-borba', 'memorias-postumas-bras-cubas', 'iracema']) {
      final b = Epub.parseFile('demo_folder/$f.epub');
      expect(b.blocks, isNotEmpty);
      expect(b.toc, isNotEmpty, reason: f);
    }
  });
}
