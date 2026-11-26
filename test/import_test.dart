// Pasta do Lume, "Importar" (cópia, nomes repetidos, repetidos por conteúdo)
// e leitura de TXT (codificação e parágrafos). Só arquivos de domínio público.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';
import 'package:lume/importer.dart';
import 'package:lume/library.dart';
import 'package:lume/lume_folder.dart';
import 'package:lume/store.dart';
import 'package:lume/txt.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Directory tmp() => Directory.systemTemp.createTempSync('lumeimp');

void main() {
  group('Importar: cópia para a pasta do Lume', () {
    late Directory src, dest;
    setUp(() {
      src = tmp();
      dest = Directory(p.join(tmp().path, 'Lume'));
    });

    File put(String name, List<int> bytes) => File(p.join(src.path, name))..writeAsBytesSync(bytes);

    test('copia com progresso e cria a pasta', () async {
      final a = put('helena.pdf', File('demo_folder/pdf/helena.pdf').readAsBytesSync());
      final b = put('iracema.epub', File('demo_folder/iracema.epub').readAsBytesSync());
      final steps = <ImportProgress>[];
      final r = await BookImporter(dest).importAll([a.path, b.path], onProgress: steps.add);
      expect(r.map((x) => x.outcome), [ImportOutcome.added, ImportOutcome.added]);
      expect(File(p.join(dest.path, 'helena.pdf')).readAsBytesSync(), a.readAsBytesSync());
      expect(File(p.join(dest.path, 'iracema.epub')).existsSync(), isTrue);
      expect(steps.last.fraction, 1);
      expect(steps.map((s) => s.bytesDone), orderedEquals([...steps.map((s) => s.bytesDone)]..sort()));
      expect(steps.any((s) => s.index == 1 && s.name == 'iracema.epub'), isTrue);
      expect(dest.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    });

    test('nome repetido com conteúdo diferente vira "nome (2)", "nome (3)"', () async {
      dest.createSync(recursive: true);
      File(p.join(dest.path, 'livro.txt')).writeAsStringSync('primeiro');
      final x = put('livro.txt', utf8.encode('segundo'));
      final r1 = await BookImporter(dest).importAll([x.path]);
      expect(p.basename(r1.single.dest!), 'livro (2).txt');
      x.writeAsStringSync('terceiro');
      final r2 = await BookImporter(dest).importAll([x.path]);
      expect(p.basename(r2.single.dest!), 'livro (3).txt');
      expect(BookImporter.freeName(dest, 'outro.pdf'), 'outro.pdf');
      expect(BookImporter.freeName(dest, 'livro.txt'), 'livro (4).txt');
    });

    test('mesmo conteúdo (mesmo com outro nome) não é copiado de novo', () async {
      final a = put('helena.pdf', File('demo_folder/pdf/helena.pdf').readAsBytesSync());
      await BookImporter(dest).importAll([a.path]);
      final b = put('Helena (cópia).pdf', a.readAsBytesSync());
      final c = put('esau.pdf', File('demo_folder/pdf/esau-e-jaco.pdf').readAsBytesSync());
      final r = await BookImporter(dest).importAll([b.path, c.path, a.path]);
      expect(r.map((x) => x.outcome), [ImportOutcome.duplicate, ImportOutcome.added, ImportOutcome.duplicate]);
      expect(p.basename(r.first.dest!), 'helena.pdf');
      expect(dest.listSync().whereType<File>().length, 2);
    });

    test('dois arquivos iguais no mesmo import: entra um só', () async {
      final a = put('a.txt', utf8.encode('mesmo texto'));
      final b = put('b.txt', utf8.encode('mesmo texto'));
      final r = await BookImporter(dest).importAll([a.path, b.path]);
      expect(r.map((x) => x.outcome), [ImportOutcome.added, ImportOutcome.duplicate]);
    });

    test('formato não suportado e arquivo sumido não quebram o resto', () async {
      final a = put('foto.jpg', [1, 2, 3]);
      final ok = put('ok.txt', utf8.encode('olá'));
      final r = await BookImporter(dest).importAll([a.path, p.join(src.path, 'sumiu.pdf'), ok.path]);
      expect(r.map((x) => x.outcome), [ImportOutcome.unsupported, ImportOutcome.failed, ImportOutcome.added]);
    });

    test('Library.importFiles: os livros aparecem na biblioteca na hora', () async {
      SharedPreferences.setMockInitialValues({'seeded': true});
      await Store.init();
      Store.settings = Store.settings..fullscreen = false;
      final lib = Library(dest, coversDir: Directory(p.join(tmp().path, 'capas')), renderPdfCovers: false);
      await lib.load(useIsolate: false);
      expect(lib.books, isEmpty);
      final t = File('demo_folder/txt/iracema-trecho.txt');
      final e = put('dom.epub', File('demo_folder/dom-casmurro.epub').readAsBytesSync());
      await lib.importFiles([t.path, e.path]);
      expect(lib.books.map((b) => b.meta.format).toSet(), {BookFormat.txt, BookFormat.epub});
      expect(lib.books.every((b) => b.source == BookSource.imported), isTrue);
      expect(lib.report.txt, 1);
      // arquivo colocado direto na pasta (gerenciador de arquivos), até em subpasta
      final sub = Directory(p.join(dest.path, 'Machado'))..createSync();
      File('demo_folder/quincas-borba.epub').copySync(p.join(sub.path, 'quincas.epub'));
      await lib.load(useIsolate: false);
      expect(lib.books.length, 3);
      expect(lib.books.firstWhere((b) => b.meta.path.endsWith('quincas.epub')).subfolder, 'Machado');
      final m = await lib.importFile(e.path); // de novo: já estava
      expect(m.title, 'Dom Casmurro');
      expect(lib.books.length, 3);
    });
  });

  group('Pasta do Lume', () {
    test('Documentos/Lume quando dá para gravar', () {
      final root = tmp();
      final ext = p.join(root.path, 'storage', 'emulated', '0', 'Android', 'data', 'com.helio.lume', 'files');
      final f = LumeFolder.resolve(appExternal: ext, internal: p.join(root.path, 'interna'));
      expect(f.kind, LumeFolderKind.documents);
      expect(f.path, p.join(root.path, 'storage', 'emulated', '0', 'Documents', 'Lume'));
      expect(Directory(f.path).existsSync(), isTrue);
      expect(Directory(f.path).listSync(), isEmpty); // o teste de escrita não fica lá
    });

    test('sem permissão: Android/data/…/files/Livros; sem armazenamento: interna', () {
      final root = tmp();
      final ext = p.join(root.path, 'storage', 'emulated', '0', 'Android', 'data', 'com.helio.lume', 'files');
      final f = LumeFolder.resolve(appExternal: ext, internal: p.join(root.path, 'interna'), canUse: (d) => !d.path.contains('Documents'));
      expect(f.kind, LumeFolderKind.appExternal);
      expect(f.path, p.join(ext, 'Livros'));
      final g = LumeFolder.resolve(appExternal: null, internal: p.join(root.path, 'interna'));
      expect(g.kind, LumeFolderKind.internal);
    });

    test('livros da pasta antiga vão para a nova (sem duplicar)', () {
      final old = tmp(), neu = Directory(p.join(tmp().path, 'Lume'));
      File('demo_folder/iracema.epub').copySync(p.join(old.path, 'iracema.epub'));
      File(p.join(old.path, 'notas.docx')).writeAsStringSync('x');
      neu.createSync();
      File('demo_folder/iracema.epub').copySync(p.join(neu.path, 'iracema.epub'));
      File('demo_folder/pdf/helena.pdf').copySync(p.join(old.path, 'helena.pdf'));
      final moved = LumeFolder.migrate(old, neu, Library.isBook);
      expect(moved, 1);
      expect(neu.listSync().map((e) => p.basename(e.path)).toSet(), {'iracema.epub', 'helena.pdf'});
      expect(old.listSync().map((e) => p.basename(e.path)), ['notas.docx']);
    });
  });

  group('TXT', () {
    test('UTF-8, com e sem BOM', () {
      final s = 'Coração — “aspas” e ç';
      expect(TxtBook.decode(Uint8List.fromList(utf8.encode(s))), s);
      expect(TxtBook.decode(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(s)])), s);
    });

    test('Latin-1 / Windows-1252 (aspas curvas e travessão)', () {
      expect(TxtBook.decode(Uint8List.fromList(latin1.encode('Coração, ação'))), 'Coração, ação');
      expect(TxtBook.decode(Uint8List.fromList([0x93, 0x4F, 0x69, 0x94, 0x20, 0x97, 0x20, 0x85])), '“Oi” — …');
    });

    test('UTF-16 com BOM', () {
      final le = [
        0xFF,
        0xFE,
        for (final c in 'Ação'.codeUnits) ...[c & 0xFF, c >> 8],
      ];
      final be = [
        0xFE,
        0xFF,
        for (final c in 'Ação'.codeUnits) ...[c >> 8, c & 0xFF],
      ];
      expect(TxtBook.decode(Uint8List.fromList(le)), 'Ação');
      expect(TxtBook.decode(Uint8List.fromList(be)), 'Ação');
    });

    test('parágrafos separados por linha em branco; linhas quebradas se juntam', () {
      final r = TxtBook.paragraphs([
        'CAPÍTULO I', '', 'Era uma vez uma linha', 'quebrada no meio.', '', '* * *', '', 'Outro parágrafo.', //
        '', 'II', '', 'Fim.',
      ]);
      expect(r.blocks.map((b) => b.kind), [
        BlockKind.heading,
        BlockKind.paragraph,
        BlockKind.separator,
        BlockKind.paragraph,
        BlockKind.heading,
        BlockKind.paragraph,
      ]);
      expect(r.blocks[1].text, 'Era uma vez uma linha quebrada no meio.');
      expect(r.toc.map((e) => e.title), ['CAPÍTULO I', 'II']);
    });

    test('sem linhas em branco: cada linha é um parágrafo', () {
      final r = TxtBook.paragraphs(['Primeira frase.', 'Segunda frase.', 'Terceira frase.']);
      expect(r.blocks.length, 3);
    });

    test('Iracema (Latin-1, Project Gutenberg): título, autor, capítulos e texto', () {
      const path = 'demo_folder/txt/iracema-trecho.txt';
      final m = TxtBook.readMeta(path);
      expect(m.format, BookFormat.txt);
      expect(m.title, 'Iracema (capítulos I a IV)');
      expect(m.author, 'José de Alencar');
      expect(m.id, startsWith('txt:'));
      final b = TxtBook.parseFile(path);
      expect(b.toc.map((e) => e.title), ['CAPÍTULO I', 'CAPÍTULO II', 'CAPÍTULO III', 'CAPÍTULO IV']);
      expect(b.blocks[1].text, 'Verdes mares bravios de minha terra natal, onde canta a jandaia nas frondes da carnaúba:');
      expect(b.blocks.any((x) => x.text.contains('Gutenberg') || x.text.contains('Title:')), isFalse);
      expect(b.blocks.any((x) => x.text.contains('\uFFFD')), isFalse);
    });
  });
}
