// Markdown: título, cabeçalho YAML, conversão para os blocos do leitor,
// âncoras, imagens relativas e entrada na biblioteca e no Importar.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';
import 'package:lume/importer.dart';
import 'package:lume/library.dart';
import 'package:lume/markdown_book.dart';
import 'package:lume/store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  const sample = 'demo_folder/md/caderno-de-leitura.md';

  group('título e metadados', () {
    test('primeiro título de nível 1', () {
      final m = MarkdownBook.metaFromBytes(b('Intro\n\n## Antes\n\n# Meu **livro** de `notas`\n\ntexto'), '/x/arquivo.md');
      expect(m.title, 'Meu livro de notas');
      expect(m.format, BookFormat.md);
      expect(m.id, startsWith('md:'));
    });

    test('título sublinhado (=====) e # dentro de bloco de código não conta', () {
      expect(MarkdownBook.metaFromBytes(b('```\n# não é título\n```\n\nO Título\n========\n'), '/x/a.md').title, 'O Título');
    });

    test('cabeçalho YAML tem prioridade e some do texto', () {
      final m = MarkdownBook.metaFromBytes(b('---\ntitle: "Diário"\nauthor: Ana\n---\n# Outro\n'), '/x/a.md');
      expect(m.title, 'Diário');
      expect(m.author, 'Ana');
      final book = MarkdownBook.parse(b('---\ntitle: Diário\n---\n# Outro\n'), '/x/a.md');
      expect(book.blocks.first.text, 'Outro');
    });

    test('sem título usa o nome do arquivo', () {
      expect(MarkdownBook.metaFromBytes(b('só texto'), '/x/minhas-notas_2026.markdown').title, isNot(isEmpty));
      expect(MarkdownBook.metaFromBytes(b('só texto'), '/x/minhas-notas_2026.markdown').title.toLowerCase(), contains('minhas'));
    });

    test('Latin-1 também é lido', () {
      final latin = Uint8List.fromList([...latin1.encode('# Cora'), 0xE7, 0xE3, ...latin1.encode('o\n')]);
      expect(MarkdownBook.metaFromBytes(latin, '/x/a.md').title, 'Coração');
    });
  });

  group('conversão', () {
    test('títulos, âncoras e sumário', () {
      final r = MarkdownBook.convert('# Guia\n\n## Como usar\n\ntexto\n\n### Detalhe\n\n#### Fora do sumário\n\n## Como usar\n', baseDir: '/x');
      final heads = r.blocks.where((b) => b.kind == BlockKind.heading).toList();
      expect(heads.map((h) => h.level), [1, 2, 3, 4, 2]);
      expect(heads.map((h) => h.anchor), ['guia', 'como-usar', 'detalhe', 'fora-do-sumário', 'como-usar-1']);
      expect(heads.every((h) => !h.center), isTrue);
      expect(r.toc.map((e) => (e.title, e.depth)), [('Guia', 0), ('Como usar', 1), ('Detalhe', 2), ('Como usar', 1)]);
    });

    test('negrito, itálico, código, riscado e links', () {
      final r = MarkdownBook.convert('Um **forte** e *leve*, `x = 1`, ~~não~~ e [site](https://a.b) ou [aqui](#guia).', baseDir: '/x');
      final runs = r.blocks.single.runs;
      expect(r.blocks.single.text, 'Um forte e leve, x = 1, não e site ou aqui.');
      expect(runs.firstWhere((x) => x.text == 'forte').bold, isTrue);
      expect(runs.firstWhere((x) => x.text == 'leve').italic, isTrue);
      expect(runs.firstWhere((x) => x.text == 'x = 1').code, isTrue);
      expect(runs.firstWhere((x) => x.text == 'não').strike, isTrue);
      expect(runs.firstWhere((x) => x.text == 'site').link, 'https://a.b');
      expect(runs.firstWhere((x) => x.text == 'aqui').link, '#guia');
    });

    test('listas com níveis, numeradas e de tarefas', () {
      final r = MarkdownBook.convert('- um\n- dois\n  1. a\n  2. b\n- [x] feito\n- [ ] falta\n\n3. três\n4. quatro\n', baseDir: '/x');
      final items = r.blocks.where((b) => b.kind == BlockKind.listItem).toList();
      expect(items.map((i) => (i.marker, i.indent, i.text)), [
        ('•', 0, 'um'),
        ('•', 0, 'dois'),
        ('1.', 1, 'a'),
        ('2.', 1, 'b'),
        ('☑', 0, 'feito'),
        ('☐', 0, 'falta'),
        ('3.', 0, 'três'),
        ('4.', 0, 'quatro'),
      ]);
    });

    test('citações (inclusive dentro de citação)', () {
      final r = MarkdownBook.convert('> primeira\n>\n> > dentro\n\nfora', baseDir: '/x');
      expect(r.blocks.map((b) => (b.text, b.quote)), [('primeira', 1), ('dentro', 2), ('fora', 0)]);
    });

    test('bloco de código, linha horizontal e tabela', () {
      final r = MarkdownBook.convert('```dart\nvoid main() {\n  print(1);\n}\n```\n\n---\n\n| a | b |\n|:-:|--:|\n| 1 | 2 |\n', baseDir: '/x');
      expect(r.blocks[0].kind, BlockKind.code);
      expect(r.blocks[0].text, 'void main() {\n  print(1);\n}');
      expect(r.blocks[1].kind, BlockKind.separator);
      expect(r.blocks[2].kind, BlockKind.table);
      expect(r.blocks[2].rows, [
        ['a', 'b'],
        ['1', '2'],
      ]);
      expect(r.blocks[2].aligns, ['center', 'right']);
    });

    test('imagens: relativas à pasta do .md, da internet e com espaço no nome', () {
      final r = MarkdownBook.convert('Texto ![gato](img/gato.png)\n\n![](../capa%20nova.jpg)\n\n![web](https://x.y/z.png)', baseDir: '/livros/notas');
      final imgs = r.blocks.where((b) => b.kind == BlockKind.image).toList();
      expect(r.blocks.first.text, 'Texto');
      expect(imgs.map((i) => i.src), ['/livros/notas/img/gato.png', '/livros/capa nova.jpg', 'https://x.y/z.png']);
      expect(imgs.first.text, 'gato');
    });

    test('HTML solto vira texto e entidades são decodificadas', () {
      final r = MarkdownBook.convert('Um <b>teste</b> &amp; outro<br>linha', baseDir: '/x');
      expect(r.blocks.single.text, 'Um teste & outro\nlinha');
    });

    test('arquivo vazio não quebra o leitor', () {
      expect(MarkdownBook.convert('', baseDir: '/x').blocks, hasLength(1));
    });

    test('exemplo do repositório', () {
      final book = MarkdownBook.parseFile(sample);
      expect(book.meta.title, 'Caderno de leitura');
      expect(book.meta.author, 'Lume');
      expect(book.toc.map((e) => e.title), ['Caderno de leitura', 'Antes de começar', 'Como marcar trechos', 'Para quem gosta de código', 'Lista de tarefas']);
      final kinds = book.blocks.map((b) => b.kind).toSet();
      expect(kinds, containsAll(BlockKind.values));
      final img = book.blocks.firstWhere((b) => b.kind == BlockKind.image);
      expect(File(img.src!).existsSync(), isTrue);
      expect(book.blocks.where((b) => b.quote > 0), isNotEmpty);
    });
  });

  group('biblioteca e importar', () {
    test('.md e .markdown são livros', () {
      expect(isBookPath('/a/notas.md'), isTrue);
      expect(isBookPath('/a/NOTAS.MARKDOWN'), isTrue);
      expect(Library.isBook('/a/notas.mdx'), isFalse);
    });

    test('a pasta do Lume lista o .md e Importar copia', () async {
      SharedPreferences.setMockInitialValues({'seeded': true});
      await Store.init();
      Store.settings = Store.settings..fullscreen = false;
      final tmp = Directory.systemTemp.createTempSync('lumemd');
      final dir = Directory(p.join(tmp.path, 'Lume'))..createSync();
      Directory(p.join(dir.path, 'notas')).createSync();
      File(sample).copySync(p.join(dir.path, 'notas', 'caderno.md'));
      final lib = Library(dir, coversDir: Directory(p.join(tmp.path, 'capas')));
      await lib.load(useIsolate: false);
      expect(lib.books.single.meta.format, BookFormat.md);
      expect(lib.books.single.meta.title, 'Caderno de leitura');
      expect(lib.report.md, 1);

      final src = File(p.join(tmp.path, 'outro.markdown'))..writeAsStringSync('# Outro texto\n\nOlá.');
      final items = await lib.importFiles([src.path]);
      expect(items.single.outcome, ImportOutcome.added);
      expect(lib.books.map((b) => b.meta.title), containsAll(['Caderno de leitura', 'Outro texto']));
    });
  });
}
