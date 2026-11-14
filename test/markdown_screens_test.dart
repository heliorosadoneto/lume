// Telas do Markdown: biblioteca com um .md, o .md aberto (títulos, listas,
// citação, código, tabela e imagem), tema preto, destaques e sumário.
// O texto e a imagem de exemplo foram feitos para o Lume (demo_folder/md/).
// Grava em docs/screenshots/ (rode com --update-goldens).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';
import 'package:lume/library.dart';
import 'package:lume/lume_folder.dart';
import 'package:lume/markdown_book.dart';
import 'package:lume/screens/library.dart';
import 'package:lume/screens/reader.dart';
import 'package:lume/store.dart';
import 'package:lume/theme.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pdfium.dart';
import 'support/shots.dart';

Widget wrap(Widget w) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: Lume.theme(),
  locale: const Locale('pt', 'BR'),
  supportedLocales: const [Locale('pt', 'BR')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: w,
);

final now = DateTime(2026, 11, 13, 22, 30);
const sample = 'demo_folder/md/caderno-de-leitura.md';

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  t.view.padding = const FakeViewPadding(top: 66);
  addTearDown(t.view.reset);
}

Future<void> settle(WidgetTester t, {int rounds = 3}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 300));
  }
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> prefs({String theme = 'sepia', double size = 18}) async {
  SharedPreferences.setMockInitialValues({'seeded': true, 'settings': '{"t":"$theme","f":"literata","s":$size,"l":1.55,"m":1,"j":false,"p":false}'});
  await Store.init();
}

/// Abre o .md no leitor já rolado até o bloco [at].
Future<ReaderScreenState> openAt(WidgetTester t, Book book, {int at = 0}) async {
  Store.savePos(book.meta.id, ReadingPos(at, 0, book.progressAt(at), now));
  await t.pumpWidget(wrap(ReaderScreen(book: book, now: () => now)));
  await settle(t);
  return t.state<ReaderScreenState>(find.byType(ReaderScreen));
}

int blockWith(Book b, String text) => b.blocks.indexWhere((x) => x.text.contains(text));

void main() {
  setUpAll(() async {
    Future<void> load(String fam, List<String> paths) async {
      final l = FontLoader(fam);
      for (final f in paths) {
        l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
      }
      await l.load();
    }

    await load('Literata', ['assets/fonts/Literata.ttf', 'assets/fonts/Literata-Italic.ttf']);
    await load('Lora', ['assets/fonts/Lora.ttf', 'assets/fonts/Lora-Italic.ttf']);
    await load('SourceSans3', ['assets/fonts/SourceSans3.ttf']);
    await load('SourceCodePro', ['assets/fonts/SourceCodePro.ttf']);
    await load('MaterialIcons', ['${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    await initPdfiumForTests();
  });

  testWidgets('Biblioteca com um arquivo Markdown', (t) async {
    phone(t);
    await prefs();
    final base = Directory.systemTemp.createTempSync('lumemd');
    final dir = Directory(p.join(base.path, 'storage', 'emulated', '0', 'Documents', 'Lume'))..createSync(recursive: true);
    for (final b in ['dom-casmurro.epub', 'quincas-borba.epub']) {
      File('assets/books/$b').copySync(p.join(dir.path, b));
    }
    File('demo_folder/txt/iracema-trecho.txt').copySync(p.join(dir.path, 'iracema-trecho.txt'));
    final notas = Directory(p.join(dir.path, 'Notas', 'imagens'))..createSync(recursive: true);
    File(sample).copySync(p.join(notas.parent.path, 'caderno-de-leitura.md'));
    File('demo_folder/md/imagens/lua-e-livros.png').copySync(p.join(notas.path, 'lua-e-livros.png'));
    final lib = Library(dir, coversDir: Directory(p.join(base.path, 'capas')), lumeKind: LumeFolderKind.documents);
    await t.runAsync(() async {
      await lib.load(useIsolate: false);
      await lib.coversReady;
    });
    expect(lib.books.where((b) => b.meta.format == BookFormat.md).single.meta.title, 'Caderno de leitura');
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    expect(find.text('MD · 1'), findsOneWidget);
    expect(find.text('Caderno de leitura'), findsWidgets);
    await snapShot('40_biblioteca_md');
    await t.tap(find.byKey(const ValueKey('filter-md')));
    await settle(t, rounds: 1);
    expect(find.text('Dom Casmurro'), findsNothing);
  });

  testWidgets('Markdown aberto: títulos, listas, citação, código e imagem', (t) async {
    phone(t);
    await prefs();
    final book = MarkdownBook.parseFile(sample);
    await openAt(t, book);
    expect(find.text('Caderno de leitura'), findsWidgets);
    expect(find.byKey(const ValueKey('img-missing0')), findsNothing);
    await snapShot('41_md_leitor');
    // mais adiante: tabela, imagem e bloco de código
    final st = t.state<ReaderScreenState>(find.byType(ReaderScreen));
    st.jumpTo(blockWith(book, 'Como marcar trechos'));
    await settle(t);
    expect(find.byType(Image), findsOneWidget);
    await snapShot('42_md_tabela_imagem');
    st.jumpTo(book.blocks.length - 1); // fim: código e lista de tarefas
    await settle(t);
    expect(find.textContaining('HighlightColor.amarelo'), findsOneWidget);
    await snapShot('43_md_codigo');
  });

  testWidgets('Markdown no tema preto', (t) async {
    phone(t);
    await prefs(theme: 'preto');
    final book = MarkdownBook.parseFile(sample);
    await openAt(t, book, at: blockWith(book, 'Antes de começar'));
    await snapShot('44_md_preto');
    t.state<ReaderScreenState>(find.byType(ReaderScreen)).jumpTo(blockWith(book, 'Selecione o texto'));
    await settle(t);
    expect(find.byType(Image), findsOneWidget);
    await snapShot('47_md_preto_imagem');
  });

  testWidgets('Markdown com destaques e nota, sumário com os títulos', (t) async {
    phone(t);
    await prefs();
    final book = MarkdownBook.parseFile(sample);
    final quote = blockWith(book, 'Ler devagar não é ler menos');
    final list = blockWith(book, 'uma xícara de chá');
    final intro = blockWith(book, 'Um pequeno guia');
    final qt = book.blocks[quote].text;
    final it = book.blocks[intro].text;
    Store.saveHighlights(book.meta.id, [
      Highlight(id: '1', block: quote, start: 0, end: qt.indexOf('.') + 1, color: HighlightColor.amarelo, text: 'Ler devagar não é ler menos.', created: now),
      Highlight(id: '2', block: list, start: 0, end: book.blocks[list].text.length, color: HighlightColor.rosa, text: 'uma xícara de chá.', note: 'De preferência de camomila', created: now),
      Highlight(
        id: '3',
        block: intro,
        start: it.indexOf('guardar'),
        end: it.indexOf('importa') + 'importa'.length,
        color: HighlightColor.azul,
        text: 'guardar o que importa',
        created: now,
      ),
    ]);
    await openAt(t, book);
    await snapShot('45_md_destaque');

    // link interno salta para a seção
    final st = t.state<ReaderScreenState>(find.byType(ReaderScreen));
    await st.openLink('#como-marcar-trechos');
    await settle(t, rounds: 1);
    expect(st.current, blockWith(book, 'Como marcar trechos'));
    // link externo pede confirmação (e cancelar não abre nada)
    final open = st.openLink('https://www.gutenberg.org');
    await settle(t, rounds: 1);
    expect(find.byKey(const ValueKey('link-dialog')), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await settle(t, rounds: 1);
    await t.runAsync(() => open);
    expect(find.byKey(const ValueKey('link-dialog')), findsNothing);

    st.openToc();
    await settle(t);
    expect(find.text('Para quem gosta de código'), findsWidgets);
    await snapShot('46_md_sumario');
  });

  testWidgets('Imagem que não existe vira um aviso', (t) async {
    phone(t);
    await prefs();
    final tmp = Directory.systemTemp.createTempSync('lumemdimg');
    final f = File(p.join(tmp.path, 'falta.md'))..writeAsStringSync('# Sem imagem\n\n![Foto da viagem](fotos/praia.jpg)\n\n![web](https://exemplo.org/a.png)\n');
    final book = MarkdownBook.parseFile(f.path);
    await openAt(t, book);
    expect(find.text('Imagem não encontrada\nFoto da viagem'), findsOneWidget);
    expect(find.textContaining('o Lume não usa internet'), findsOneWidget);
  });
}
