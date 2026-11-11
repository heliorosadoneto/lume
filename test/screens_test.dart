// Testes de tela do Lume. Renderizam os widgets reais com as fontes do app e
// livros de verdade (Project Gutenberg) e gravam os prints em docs/screenshots/
// (rode com --update-goldens para regravar).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';
import 'package:lume/library.dart';
import 'package:lume/screens/library.dart';
import 'package:lume/screens/notes.dart';
import 'package:lume/screens/reader.dart';
import 'package:lume/screens/settings.dart';
import 'package:lume/store.dart';
import 'package:lume/theme.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Widget wrap(Widget w) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Lume.theme(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: w,
    );

final now = DateTime(2026, 11, 11, 8, 30);
late Book dom;
late Directory folder, importDir;
late int chapterStart;
final ids = <String, String>{};

(int, int) sentence(String t, int n) {
  final ends = RegExp(r'[.!?](?=\s|$)').allMatches(t).map((m) => m.end).toList();
  final start = n == 0 ? 0 : ends[n - 1] + 1;
  return (start, ends[n]);
}

Map<String, Object> seedPrefs() {
  final hls = <Highlight>[];
  void hl(int block, int n, HighlightColor c, [String note = '']) {
    final (s, e) = sentence(dom.blocks[block].text, n);
    hls.add(Highlight(
        id: '$block-$n', block: block, start: s, end: e, color: c, text: dom.blocks[block].text.substring(s, e), note: note,
        created: now.subtract(Duration(days: block % 5))));
  }

  final paras = [for (var i = chapterStart; i < dom.blocks.length; i++) if (dom.blocks[i].kind == BlockKind.paragraph && dom.blocks[i].text.length > 260) i];
  hl(paras[0], 0, HighlightColor.amarelo);
  hl(paras[1], 1, HighlightColor.rosa, 'Bentinho já desconfia de tudo aqui. Voltar a este trecho no fim do livro.');
  hl(paras[2], 0, HighlightColor.azul);
  hl(paras[3], 0, HighlightColor.laranja);
  hl(23 + 1, 0, HighlightColor.amarelo, 'Origem do apelido Dom Casmurro.');
  return {
    'seeded': true,
    'folder': folder.path,
    'settings': '{"t":"sepia","f":"literata","s":19,"l":1.6,"m":1,"j":true,"p":false}',
    'pos:${dom.meta.id}': '{"b":$chapterStart,"a":0.0,"p":${dom.progressAt(chapterStart)},"o":${now.millisecondsSinceEpoch}}',
    'pos:${ids['memorias-postumas-bras-cubas']}':
        '{"b":900,"a":0.0,"p":0.61,"o":${now.subtract(const Duration(days: 1)).millisecondsSinceEpoch}}',
    'hl:${dom.meta.id}': '[${hls.map((h) => '{"id":"${h.id}","b":${h.block},"s":${h.start},"e":${h.end},"c":"${h.color.name}","t":"","n":"${h.note}","d":${h.created.millisecondsSinceEpoch}}').join(',')}]',
    'bm:${dom.meta.id}': '[{"b":$chapterStart,"x":"${dom.blocks[chapterStart + 2].text.substring(0, 90)}…","d":${now.millisecondsSinceEpoch}},{"b":42,"x":"Ia a entrar na sala de visitas, quando ouvi proferir o meu nome e escondi-me atrás da porta.","d":${now.millisecondsSinceEpoch}}]',
  };
}

Future<void> resetPrefs() async {
  final m = seedPrefs();
  // o texto dos destaques vem do livro
  SharedPreferences.setMockInitialValues(m);
  await Store.init();
  final h = Store.highlights(dom.meta.id);
  Store.saveHighlights(dom.meta.id, [
    for (final x in h)
      Highlight(id: x.id, block: x.block, start: x.start, end: x.end, color: x.color, text: dom.blocks[x.block].text.substring(x.start, x.end), note: x.note, created: x.created)
  ]);
}

Future<void> settle(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pumpAndSettle();
}

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  t.view.padding = const FakeViewPadding(top: 66);
  addTearDown(t.view.reset);
}

Future<void> snap(String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/screenshots/$name.png'));

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
    await load('MaterialIcons', ['${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);

    final tmp = Directory.systemTemp.createTempSync('lume');
    folder = Directory(p.join(tmp.path, 'Livros'))..createSync();
    importDir = Directory(p.join(tmp.path, 'importados'))..createSync();
    for (final f in Directory('demo_folder').listSync().whereType<File>()) {
      f.copySync(p.join(folder.path, p.basename(f.path)));
      ids[p.basenameWithoutExtension(f.path)] = Epub.readMeta(f.path).id;
    }
    dom = Epub.parseFile(p.join(folder.path, 'dom-casmurro.epub'));
    chapterStart = dom.toc.firstWhere((e) => dom.progressAt(e.block) >= 0.34).block;
    await resetPrefs();
  });

  setUp(resetPrefs);

  Future<Library> library() async {
    final lib = Library(importDir);
    await lib.load(useIsolate: false);
    return lib;
  }

  testWidgets('Biblioteca em lista a partir da pasta + Continuar leitura', (t) async {
    phone(t);
    final lib = await library();
    expect(lib.books.length, 4);
    expect(lib.books.every((b) => b.source == BookSource.folder), isTrue);
    expect(lib.continueReading.first.meta.title, 'Dom Casmurro');
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    expect(find.text('Continuar leitura'), findsOneWidget);
    expect(find.text('Iracema'), findsOneWidget);
    await snap('01_biblioteca');
  });

  testWidgets('Ajustes: pasta de livros', (t) async {
    phone(t);
    final lib = await library();
    await t.pumpWidget(wrap(SettingsScreen(library: lib)));
    await settle(t);
    expect(find.text(folder.path), findsOneWidget);
    expect(find.text('4 livros EPUB encontrados'), findsOneWidget);
    await snap('02_ajustes_pasta');
    await t.drag(find.byType(ListView).first, const Offset(0, -900));
    await settle(t);
    await snap('03_ajustes_leitura');
  });

  testWidgets('Novo livro na pasta (inclusive subpasta) aparece ao atualizar', (t) async {
    final lib = await library();
    expect(lib.books.length, 4);
    // cópia do mesmo livro não duplica (mesmo identificador)
    File(p.join(folder.path, 'iracema.epub')).copySync(p.join(folder.path, 'iracema-copia.epub'));
    await lib.load(useIsolate: false);
    expect(lib.books.length, 4);
    final sub = Directory(p.join(folder.path, 'poesia'))..createSync();
    File('test/fixtures/os-lusiadas.epub').copySync(p.join(sub.path, 'os-lusiadas.epub'));
    File(p.join(folder.path, 'notas.txt')).writeAsStringSync('não é livro');
    await lib.load(useIsolate: false);
    expect(lib.books.length, 5);
    expect(lib.books.map((b) => b.meta.title), contains('Os Lusíadas'));
    sub.deleteSync(recursive: true);
    File(p.join(folder.path, 'iracema-copia.epub')).deleteSync();
    File(p.join(folder.path, 'notas.txt')).deleteSync();
  });

  testWidgets('Leitor sépia retoma a posição e mostra destaques', (t) async {
    phone(t);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    final st = t.state<ReaderScreenState>(find.byType(ReaderScreen));
    expect(st.current, chapterStart);
    expect(find.textContaining('no capítulo'), findsOneWidget);
    await t.drag(find.byKey(ValueKey('block${chapterStart + 1}')), const Offset(0, -60));
    await settle(t);
    await snap('04_leitor_sepia');
  });

  testWidgets('Leitor no tema preto', (t) async {
    phone(t);
    Store.settings = ReaderSettings(theme: PageTheme.preto);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    await snap('05_leitor_preto');
  });

  testWidgets('Leitor verde claro, Lora, alinhado à esquerda', (t) async {
    phone(t);
    Store.settings = ReaderSettings(theme: PageTheme.verde, font: BookFont.lora, size: 18, justify: false, margin: 2);
    Store.savePos(dom.meta.id, ReadingPos(23, 0, 0, now));
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    await snap('06_leitor_verde_lora');
  });

  testWidgets('Selecionar texto e marcar com cor (persiste)', (t) async {
    phone(t);
    Store.savePos(dom.meta.id, ReadingPos(43, 0, 0, now));
    Store.saveHighlights(dom.meta.id, []);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    final target = find.byKey(const ValueKey('block46'));
    await t.longPress(target);
    await t.pumpAndSettle();
    final edit = t.state<EditableTextState>(find.descendant(of: target, matching: find.byType(EditableText)));
    final (s, e) = sentence(dom.blocks[46].text, 0);
    edit.userUpdateTextEditingValue(
        edit.textEditingValue.copyWith(selection: TextSelection(baseOffset: s, extentOffset: e)), SelectionChangedCause.drag);
    edit.showToolbar();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('hl-toolbar')), findsOneWidget);
    await snap('07_selecao_cores');
    await t.tap(find.byKey(const ValueKey('hl-rosa')));
    await t.pumpAndSettle();
    final saved = Store.highlights(dom.meta.id);
    expect(saved.single.color, HighlightColor.rosa);
    expect(saved.single.text, startsWith('Minha mãe quiz saber'));
  });

  testWidgets('Caderno com destaques e notas', (t) async {
    phone(t);
    await t.pumpWidget(wrap(NotesScreen(book: dom)));
    await settle(t);
    expect(find.text('Destaques (5)'), findsOneWidget);
    await snap('08_caderno_destaques');
    await t.tap(find.text('Marcadores (2)'));
    await settle(t);
    await snap('09_caderno_marcadores');
  });

  testWidgets('Aparência dentro do leitor', (t) async {
    phone(t);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    await t.tap(find.byTooltip('Aparência'));
    await settle(t);
    await snap('10_aparencia');
    await t.tap(find.byKey(const ValueKey('theme-preto')));
    await t.pumpAndSettle();
    expect(Store.settings.theme, PageTheme.preto);
  });

  testWidgets('Sumário', (t) async {
    phone(t);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    await t.tap(find.byTooltip('Sumário'));
    await settle(t);
    await snap('11_sumario');
    await t.tap(find.text('As pazes.'));
    await settle(t);
    expect(t.state<ReaderScreenState>(find.byType(ReaderScreen)).chapterTitle, 'As pazes.');
  });

  testWidgets('Posição salva ao rolar e restaurada ao reabrir', (t) async {
    phone(t);
    Store.savePos(dom.meta.id, ReadingPos(100, 0, 0, now));
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    await t.fling(find.byType(ReaderScreen), const Offset(0, -1500), 3000);
    await t.pumpAndSettle();
    final moved = t.state<ReaderScreenState>(find.byType(ReaderScreen)).current;
    expect(moved, greaterThan(100));
    await t.pumpWidget(const SizedBox());
    expect(Store.pos(dom.meta.id)!.block, moved);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    expect(t.state<ReaderScreenState>(find.byType(ReaderScreen)).current, moved);
  });

  testWidgets('Modo virar página: toque na borda avança', (t) async {
    phone(t);
    Store.settings = ReaderSettings(pageMode: true);
    Store.savePos(dom.meta.id, ReadingPos(100, 0, 0, now));
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('page1')));
    await t.pumpAndSettle();
    expect(t.state<ReaderScreenState>(find.byType(ReaderScreen)).current, greaterThan(100));
  });
}

