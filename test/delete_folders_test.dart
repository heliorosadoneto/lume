// Apagar livros (só da biblioteca ou o arquivo) e várias pastas: migração da
// pasta antiga, adicionar/remover, repetidos entre pastas e lista de ocultos.
// Só livros de domínio público.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/library.dart';
import 'package:lume/pdf_analysis.dart';
import 'package:lume/store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

late Directory base, lume, a, b, covers, texto;

Future<void> fresh([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'seeded': true, ...prefs});
  await Store.init();
  Store.settings = Store.settings..fullscreen = false;
}

void put(Directory d, String from, [String? name]) {
  d.createSync(recursive: true);
  File(from).copySync(p.join(d.path, name ?? p.basename(from)));
}

Library make() => Library(lume, coversDir: covers, textCacheDir: texto, renderPdfCovers: false);

Future<Library> loaded() async {
  final l = make();
  await l.load(useIsolate: false);
  return l;
}

List<String> titles(Library l) => [for (final x in l.books) x.meta.title];

void main() {
  setUp(() async {
    base = Directory.systemTemp.createTempSync('lumedel');
    lume = Directory(p.join(base.path, 'Documents', 'Lume'));
    a = Directory(p.join(base.path, 'Download', 'Livros'));
    b = Directory(p.join(base.path, 'Estudos'));
    covers = Directory(p.join(base.path, 'capas'));
    texto = Directory(p.join(base.path, 'texto'));
    put(lume, 'assets/books/dom-casmurro.epub');
    put(a, 'demo_folder/iracema.epub');
    put(Directory(p.join(a.path, 'pdf')), 'demo_folder/pdf/helena.pdf');
    put(b, 'demo_folder/txt/iracema-trecho.txt');
    put(b, 'demo_folder/quincas-borba.epub');
    await fresh();
  });
  tearDown(() {
    for (final d in [a, b, lume]) {
      if (d.existsSync()) Process.runSync('chmod', ['-R', 'u+w', d.path]);
    }
    base.deleteSync(recursive: true);
  });

  group('Várias pastas', () {
    test('a pasta antiga (uma só) vira a lista, uma vez', () async {
      await fresh({'folder': a.path});
      expect(Store.folders, [a.path]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('folder'), isNull);
      expect(jsonDecode(prefs.getString('folders')!), [a.path]);
      expect(Store.folders, [a.path]); // de novo, já migrado
      final l = await loaded();
      expect(titles(l), containsAll(['Dom Casmurro', 'Iracema', 'Helena']));
    });

    test('sem pasta antiga a lista começa vazia', () async {
      expect(Store.folders, isEmpty);
      final l = await loaded();
      expect(titles(l), ['Dom Casmurro']);
    });

    test('adicionar várias, contar livros de cada e remover sem apagar arquivos', () async {
      final l = await loaded();
      await l.addFolder(a.path, useIsolate: false, watchIt: false);
      await l.addFolder(b.path, useIsolate: false, watchIt: false);
      await l.addFolder(a.path, useIsolate: false, watchIt: false); // repetida: não entra de novo
      await l.addFolder(lume.path, useIsolate: false, watchIt: false); // a do Lume já é fixa
      expect(l.folders, [a.path, b.path]);
      expect(l.lastAdded, lume.path);
      expect(l.books.length, 5);
      expect(l.countIn(a.path), 2);
      expect(l.countIn(b.path), 2);
      expect(l.countInLume, 1);
      final helena = l.books.firstWhere((x) => x.meta.title == 'Helena');
      expect(helena.root, a.path);
      expect(helena.place, 'pdf'); // subpasta
      expect(l.books.firstWhere((x) => x.meta.title == 'Quincas Borba').place, 'Estudos');
      expect(l.books.firstWhere((x) => x.meta.title == 'Dom Casmurro').place, 'Lume');

      await l.removeFolder(a.path, useIsolate: false, watchIt: false);
      expect(l.folders, [b.path]);
      expect(titles(l), isNot(contains('Helena')));
      expect(File(p.join(a.path, 'pdf', 'helena.pdf')).existsSync(), isTrue);
      expect(File(p.join(a.path, 'iracema.epub')).existsSync(), isTrue);
    });

    test('o mesmo livro em duas pastas conta uma vez (vale a primeira pasta)', () async {
      put(b, 'demo_folder/iracema.epub', 'Iracema (cópia).epub');
      put(b, 'assets/books/dom-casmurro.epub');
      final l = await loaded();
      await l.addFolder(a.path, useIsolate: false, watchIt: false);
      await l.addFolder(b.path, useIsolate: false, watchIt: false);
      expect(titles(l).where((t) => t == 'Iracema').length, 1);
      expect(titles(l).where((t) => t == 'Dom Casmurro').length, 1);
      expect(l.books.firstWhere((x) => x.meta.title == 'Iracema').root, a.path);
      expect(l.books.firstWhere((x) => x.meta.title == 'Dom Casmurro').root, b.path); // outras pastas antes da do Lume
      expect(l.report.duplicates, 2);
    });

    test('pasta dentro de outra: cada arquivo aparece uma vez, na pasta mais funda', () async {
      final l = await loaded();
      final sub = p.join(a.path, 'pdf');
      await l.addFolder(a.path, useIsolate: false, watchIt: false);
      await l.addFolder(sub, useIsolate: false, watchIt: false);
      expect(l.books.length, 3);
      expect(l.report.duplicates, 0);
      expect(l.books.firstWhere((x) => x.meta.title == 'Helena').root, sub);
      expect(l.countIn(a.path), 1);
      expect(l.countIn(sub), 1);
    });
  });

  group('Tirar só da biblioteca', () {
    test('some da lista, não volta ao ler as pastas de novo e dá para mostrar', () async {
      final l = await loaded();
      await l.addFolder(a.path, useIsolate: false, watchIt: false);
      final iracema = l.books.firstWhere((x) => x.meta.title == 'Iracema');
      l.hide([iracema]);
      expect(titles(l), isNot(contains('Iracema')));
      expect(File(iracema.meta.path).existsSync(), isTrue);
      expect(l.hidden.single.title, 'Iracema');
      expect(l.hidden.single.path, iracema.meta.path);

      await l.load(useIsolate: false);
      expect(titles(l), isNot(contains('Iracema')));
      // mesmo movido para outra pasta (o id é do conteúdo)
      File(iracema.meta.path).renameSync(p.join(a.path, 'pdf', 'iracema-movido.epub'));
      await l.load(useIsolate: false);
      expect(titles(l), isNot(contains('Iracema')));
      // ocultos ficam guardados
      expect(HiddenBook.fromJson(l.hidden.single.toJson()).id, iracema.meta.id);

      await l.unhide([iracema.meta.id], useIsolate: false);
      expect(titles(l), contains('Iracema'));
      expect(l.hidden, isEmpty);
    });

    test('ocultar o mesmo livro duas vezes guarda um só', () async {
      final l = await loaded();
      final dom = l.books.single;
      l.hide([dom]);
      l.hide([dom]);
      expect(Store.hidden.length, 1);
    });
  });

  group('Apagar o arquivo também', () {
    test('apaga o arquivo e tudo o que o Lume guardou dele', () async {
      final l = await loaded();
      await l.addFolder(a.path, useIsolate: false, watchIt: false);
      final helena = l.books.firstWhere((x) => x.meta.title == 'Helena');
      final id = helena.meta.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pos:$id', '{"c":0,"o":0,"p":0.4}');
      Store.saveHighlights(id, []);
      await prefs.setString('hl:$id', '[{"x":1}]');
      await prefs.setString('bm:$id', '[{"x":1}]');
      Store.setPages(id, 20);
      Store.setPdfMode(id, 'text');
      covers.createSync(recursive: true);
      final cover = l.covers.fileFor(id)..writeAsBytesSync([1, 2, 3]);
      final cache = PdfAnalyzer(texto).fileFor(id);
      cache.parent.createSync(recursive: true);
      cache.writeAsStringSync('{}');
      // outro livro não é afetado
      final dom = l.books.firstWhere((x) => x.meta.title == 'Dom Casmurro');
      Store.setPages(dom.meta.id, 99);

      final r = await l.deleteFiles([helena], useIsolate: false);
      expect(r.deleted.single.meta.title, 'Helena');
      expect(r.failed, isEmpty);
      expect(File(helena.meta.path).existsSync(), isFalse);
      expect(titles(l), isNot(contains('Helena')));
      for (final k in ['pos', 'hl', 'bm', 'pages', 'pdfmode']) {
        expect(prefs.containsKey('$k:$id'), isFalse, reason: k);
      }
      expect(cover.existsSync(), isFalse);
      expect(cache.existsSync(), isFalse);
      expect(Store.pages(dom.meta.id), 99);
    });

    test('vários de uma vez, inclusive da pasta do Lume', () async {
      final l = await loaded();
      await l.addFolder(b.path, useIsolate: false, watchIt: false);
      final all = [...l.books];
      expect(all.length, 3);
      expect(l.inLume(all.firstWhere((x) => x.meta.title == 'Dom Casmurro')), isTrue);
      final r = await l.deleteFiles(all, useIsolate: false);
      expect(r.deleted.length, 3);
      expect(l.books, isEmpty);
      expect(lume.listSync(), isEmpty);
      expect(b.listSync(), isEmpty);
    });

    test('com cópia igual em outra pasta: apaga só o arquivo mostrado e guarda a leitura', () async {
      put(b, 'demo_folder/iracema.epub', 'iracema.epub');
      final l = await loaded();
      await l.addFolder(a.path, useIsolate: false, watchIt: false);
      await l.addFolder(b.path, useIsolate: false, watchIt: false);
      final ira = l.books.firstWhere((x) => x.meta.title == 'Iracema');
      expect(ira.root, a.path);
      Store.setPages(ira.meta.id, 7);
      final r = await l.deleteFiles([ira], useIsolate: false);
      expect(r.otherCopies.single.meta.title, 'Iracema');
      expect(Store.pages(ira.meta.id), 7);
      final again = l.books.firstWhere((x) => x.meta.title == 'Iracema');
      expect(again.root, b.path);
    });

    test('pasta sem permissão: não apaga, explica e mantém o livro', () async {
      final l = await loaded();
      await l.addFolder(b.path, useIsolate: false, watchIt: false);
      final q = l.books.firstWhere((x) => x.meta.title == 'Quincas Borba');
      Store.setPages(q.meta.id, 3);
      Process.runSync('chmod', ['a-w', b.path]);
      final r = await l.deleteFiles([q], useIsolate: false);
      expect(r.deleted, isEmpty);
      expect(r.failed.single.$2, contains('permissão'));
      expect(File(q.meta.path).existsSync(), isTrue);
      expect(titles(l), contains('Quincas Borba'));
      expect(Store.pages(q.meta.id), 3);
      expect(l.importing, isFalse);
    });

    test('apagar um livro oculto também o tira da lista de ocultos', () async {
      final l = await loaded();
      await l.addFolder(b.path, useIsolate: false, watchIt: false);
      final q = l.books.firstWhere((x) => x.meta.title == 'Quincas Borba');
      l.hide([q]);
      await l.deleteFiles([q], useIsolate: false);
      expect(Store.hidden, isEmpty);
      expect(File(q.meta.path).existsSync(), isFalse);
    });
  });
}
