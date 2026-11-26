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
import 'package:lume/lume_folder.dart';
import 'package:lume/main.dart' show LumeApp;
import 'package:lume/screens/library.dart';
import 'package:lume/screens/notes.dart';
import 'package:lume/screens/reader.dart';
import 'package:lume/screens/settings.dart';
import 'package:lume/store.dart';
import 'package:lume/theme.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shots.dart';

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
    hls.add(
      Highlight(
        id: '$block-$n',
        block: block,
        start: s,
        end: e,
        color: c,
        text: dom.blocks[block].text.substring(s, e),
        note: note,
        created: now.subtract(Duration(days: block % 5)),
      ),
    );
  }

  final paras = [
    for (var i = chapterStart; i < dom.blocks.length; i++)
      if (dom.blocks[i].kind == BlockKind.paragraph && dom.blocks[i].text.length > 260) i,
  ];
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
    'pos:${ids['memorias-postumas-bras-cubas']}': '{"b":900,"a":0.0,"p":0.61,"o":${now.subtract(const Duration(days: 1)).millisecondsSinceEpoch}}',
    'hl:${dom.meta.id}':
        '[${hls.map((h) => '{"id":"${h.id}","b":${h.block},"s":${h.start},"e":${h.end},"c":"${h.color.name}","t":"","n":"${h.note}","d":${h.created.millisecondsSinceEpoch}}').join(',')}]',
    'bm:${dom.meta.id}':
        '[{"b":$chapterStart,"x":"${dom.blocks[chapterStart + 2].text.substring(0, 90)}…","d":${now.millisecondsSinceEpoch}},{"b":42,"x":"Ia a entrar na sala de visitas, quando ouvi proferir o meu nome e escondi-me atrás da porta.","d":${now.millisecondsSinceEpoch}}]',
  };
}

Future<void> resetPrefs() async {
  final m = seedPrefs();
  // o texto dos destaques vem do livro
  SharedPreferences.setMockInitialValues(m);
  await Store.init();
  Store.settings = Store.settings..fullscreen = false;
  final h = Store.highlights(dom.meta.id);
  Store.saveHighlights(dom.meta.id, [
    for (final x in h)
      Highlight(
        id: x.id,
        block: x.block,
        start: x.start,
        end: x.end,
        color: x.color,
        text: dom.blocks[x.block].text.substring(x.start, x.end),
        note: x.note,
        created: x.created,
      ),
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

Future<void> snap(String name) => snapShot(name);

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
    folder = Directory(p.join(tmp.path, 'storage', 'emulated', '0', 'Livros'))..createSync(recursive: true);
    importDir = Directory(p.join(tmp.path, 'storage', 'emulated', '0', 'Documents', 'Lume'))..createSync(recursive: true);
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
    final lib = Library(importDir, lumeKind: LumeFolderKind.documents);
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
    expect(find.text('Armazenamento interno/Livros'), findsOneWidget);
    expect(find.text('4 livros (com subpastas)'), findsOneWidget);
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
    File(p.join(folder.path, 'notas.docx')).writeAsStringSync('não é livro');
    await lib.load(useIsolate: false);
    expect(lib.books.length, 5);
    expect(lib.books.map((b) => b.meta.title), contains('Os Lusíadas'));
    sub.deleteSync(recursive: true);
    File(p.join(folder.path, 'iracema-copia.epub')).deleteSync();
    File(p.join(folder.path, 'notas.docx')).deleteSync();
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
    Store.settings = ReaderSettings(fullscreen: false, theme: PageTheme.preto);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    await snap('05_leitor_preto');
  });

  testWidgets('Leitor verde claro, Lora, alinhado à esquerda', (t) async {
    phone(t);
    Store.settings = ReaderSettings(fullscreen: false, theme: PageTheme.verde, font: BookFont.lora, size: 18, justify: false, widthPct: 80);
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
      edit.textEditingValue.copyWith(
        selection: TextSelection(baseOffset: s, extentOffset: e),
      ),
      SelectionChangedCause.drag,
    );
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

  // ---------- 1.4: virar página, largura do texto, tela cheia ----------
  List<MethodCall> systemUi(WidgetTester t) {
    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'SystemChrome.setEnabledSystemUIMode') calls.add(c);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  Future<ReaderScreenState> openPaged(WidgetTester t, {int block = 100, ReaderSettings? settings}) async {
    phone(t);
    Store.settings = settings ?? ReaderSettings(pageMode: true, fullscreen: false);
    Store.savePos(dom.meta.id, ReadingPos(block, 0, 0, now));
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    return t.state<ReaderScreenState>(find.byType(ReaderScreen));
  }

  testWidgets('Virar página: as páginas são feitas, o toque nos terços e o deslize viram a página', (t) async {
    final st = await openPaged(t);
    expect(find.byKey(const ValueKey('pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('paginating')), findsNothing);
    await snap('60_virar_pagina_1');
    final n = st.pageCount;
    expect(n, greaterThan(200), reason: 'o livro inteiro é dividido em páginas da altura da tela');
    final first = st.pageIndex;
    expect(st.current, lessThanOrEqualTo(100));
    expect(st.current, greaterThan(90), reason: 'abre perto de onde parou');
    final size = t.getSize(find.byType(Scaffold));
    // terço direito: avança
    await t.tapAt(Offset(size.width * .85, size.height / 2));
    await t.pumpAndSettle();
    expect(st.pageIndex, first + 1);
    expect(Store.pos(dom.meta.id)!.block, st.current);
    await snap('61_virar_pagina_2');
    final after = st.current;
    // terço esquerdo: volta
    await t.tapAt(Offset(size.width * .12, size.height / 2));
    await t.pumpAndSettle();
    expect(st.pageIndex, first);
    // deslizar para a esquerda avança, para a direita volta
    await t.fling(find.byKey(const ValueKey('pages')), const Offset(-500, 0), 2000);
    await t.pumpAndSettle();
    expect(st.pageIndex, first + 1);
    expect(st.current, after);
    await t.fling(find.byKey(const ValueKey('pages')), const Offset(500, 0), 2000);
    await t.pumpAndSettle();
    expect(st.pageIndex, first);
    // o centro não vira a página
    await t.tapAt(Offset(size.width / 2, size.height / 2));
    await t.pump(const Duration(milliseconds: 400));
    expect(st.pageIndex, first);
  });

  testWidgets('Virar página: o que foi medido cabe na página desenhada e a posição volta ao reabrir', (t) async {
    final st = await openPaged(t, block: 0);
    expect(st.pageIndex, 0);
    final scroll = find.descendant(of: find.byKey(const ValueKey('pages')), matching: find.byType(SingleChildScrollView)).first;
    final viewport = t.getSize(scroll).height;
    for (var i = 0; i < st.pageCount; i += 4) {
      await st.goToPageForTest(i);
      await t.pumpAndSettle();
      final column = find.descendant(of: scroll, matching: find.byType(Column)).first;
      final last = st.pagesForTest![i].slices.last;
      final tail = last.showBottom && !last.whole ? ReaderSettings().size * .75 : 0; // o respiro depois do último parágrafo pode passar
      expect(t.getSize(column).height - tail, lessThanOrEqualTo(viewport + 0.5), reason: 'página $i: o texto cabe sem cortar linha');
      if (i < st.pageCount - 1) expect(t.getSize(column).height, greaterThan(viewport * .5), reason: 'página $i: a página é preenchida');
    }
    final at = st.current;
    final idx = st.pageIndex;
    await t.pumpWidget(const SizedBox());
    expect(Store.pos(dom.meta.id)!.block, at);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    final again = t.state<ReaderScreenState>(find.byType(ReaderScreen));
    expect(again.pageIndex, idx);
  });

  testWidgets('Virar página: muda o tamanho da letra e refaz as páginas no mesmo ponto', (t) async {
    final st = await openPaged(t, block: 300);
    final before = st.pageCount;
    final at = st.current;
    await t.tap(find.byTooltip('Aparência'));
    await t.pumpAndSettle();
    final slider = t.widget<Slider>(find.byType(Slider).first);
    slider.onChanged!(26);
    await t.pumpAndSettle();
    expect(st.pageCount, greaterThan(before), reason: 'letra maior, mais páginas');
    expect((st.current - at).abs(), lessThan(6), reason: 'continua no mesmo trecho');
  });

  testWidgets('Largura do texto: 100% usa a tela toda; o ajuste estreita na hora e fica salvo', (t) async {
    phone(t);
    Store.settings = ReaderSettings(fullscreen: false);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    final w = t.getSize(find.byType(Scaffold)).width;
    final key = find.byKey(ValueKey('block${chapterStart + 1}'));
    expect(t.getSize(key).width, closeTo(w - 2 * ReaderSettings.minPad, 0.5), reason: '100% = tela toda menos 10 dp de cada lado');
    await t.tap(find.byTooltip('Aparência'));
    await t.pumpAndSettle();
    final slider = find.byKey(const ValueKey('width-slider'));
    expect(slider, findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    t.widget<Slider>(slider).onChanged!(80);
    await t.pumpAndSettle();
    expect(Store.settings.widthPct, 80);
    expect(find.text('80%'), findsOneWidget);
    await t.tapAt(const Offset(10, 100)); // fecha o painel
    await t.pumpAndSettle();
    expect(t.getSize(key).width, closeTo((w - 20) * .8, 0.5));
  });

  test('Configurações de leitura: largura, tela cheia e o formato antigo', () {
    final s = ReaderSettings(widthPct: 85, fullscreen: false, pageMode: true);
    final back = ReaderSettings.fromJson(s.toJson());
    expect(back.widthPct, 85);
    expect(back.fullscreen, isFalse);
    expect(back.pageMode, isTrue);
    // 1.3: margem em 3 níveis, sem tela cheia → agora texto na tela toda e tela cheia ligada
    final old = ReaderSettings.fromJson({'t': 'sepia', 'f': 'literata', 's': 19, 'l': 1.6, 'm': 2, 'j': true, 'p': false});
    expect(old.widthPct, 100);
    expect(old.fullscreen, isTrue);
    expect(ReaderSettings().hPadFor(400), ReaderSettings.minPad);
    expect(ReaderSettings(widthPct: 70).hPadFor(400), closeTo(10 + 380 * .15, 0.001));
  });

  testWidgets('Tela cheia: botões escondidos, toque no centro mostra e esconde, as barras do Android seguem', (t) async {
    final calls = systemUi(t);
    phone(t);
    Store.settings = ReaderSettings(fullscreen: true);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    expect(find.byTooltip('Sumário'), findsNothing, reason: 'começa sem os botões');
    expect(find.byKey(const ValueKey('footer')), findsOneWidget);
    expect(calls.last.arguments, 'SystemUiMode.immersiveSticky');
    expect(Store.fullscreenHint, isTrue);
    await snap('62_tela_cheia_lendo');
    final size = t.getSize(find.byType(Scaffold));
    final top = t.getTopLeft(find.byKey(ValueKey('block$chapterStart'))).dy;
    await t.tapAt(Offset(size.width / 2, size.height / 2));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.byTooltip('Sumário'), findsOneWidget);
    expect(calls.last.arguments, 'SystemUiMode.edgeToEdge');
    expect(t.getTopLeft(find.byKey(ValueKey('block$chapterStart'))).dy, top, reason: 'o texto não se mexe quando os botões aparecem');
    expect(find.byType(CompositedTransformFollower), findsNothing, reason: 'um toque não deixa a alça de seleção na tela');
    await snap('54_tela_cheia_botoes');
    await t.tapAt(Offset(size.width / 2, size.height * .55));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.byTooltip('Sumário'), findsNothing);
    expect(calls.last.arguments, 'SystemUiMode.immersiveSticky');
    // ao sair do leitor as barras do Android voltam
    await t.pumpWidget(const SizedBox());
    expect(calls.last.arguments, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('Tela cheia desligada: botões sempre à vista e o centro não faz nada', (t) async {
    final calls = systemUi(t);
    phone(t);
    Store.settings = ReaderSettings(fullscreen: false);
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await t.pumpAndSettle();
    expect(find.byTooltip('Sumário'), findsOneWidget);
    expect(calls.where((c) => c.arguments == 'SystemUiMode.immersiveSticky'), isEmpty);
    final size = t.getSize(find.byType(Scaffold));
    await t.tapAt(Offset(size.width / 2, size.height / 2));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Sumário'), findsOneWidget);
  });

  testWidgets('Tela cheia + virar página: o terço direito vira a página e só o centro mostra os botões', (t) async {
    systemUi(t);
    final st = await openPaged(t, settings: ReaderSettings(pageMode: true, fullscreen: true));
    expect(find.byTooltip('Sumário'), findsNothing);
    final first = st.pageIndex;
    final size = t.getSize(find.byType(Scaffold));
    await t.tapAt(Offset(size.width * .9, size.height * .5));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(st.pageIndex, first + 1);
    expect(find.byTooltip('Sumário'), findsNothing, reason: 'virar página não mostra os botões');
    await t.tapAt(Offset(size.width * .5, size.height * .5));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(st.pageIndex, first + 1, reason: 'o centro não vira a página');
    expect(find.byTooltip('Sumário'), findsOneWidget);
    await snap('55_virar_pagina_botoes');
  });

  testWidgets('Ajustes: largura do texto e tela cheia na tela de Ajustes', (t) async {
    phone(t);
    final lib = await library();
    await t.pumpWidget(wrap(SettingsScreen(library: lib)));
    await settle(t);
    await t.drag(find.byType(ListView).first, const Offset(0, -2400));
    await settle(t);
    expect(find.byKey(const ValueKey('width-slider')), findsOneWidget);
    expect(find.byKey(const ValueKey('fullscreen-switch')), findsOneWidget);
    t.widget<Slider>(find.byKey(const ValueKey('width-slider'))).onChanged!(85);
    t.widget<SwitchListTile>(find.byKey(const ValueKey('fullscreen-switch'))).onChanged!(false);
    await settle(t);
    expect(Store.settings.widthPct, 85);
    expect(Store.settings.fullscreen, isFalse);
    await snap('63_ajustes_largura_tela_cheia');
  });

  // ---------- 1.4: cores do aplicativo ----------
  Color? scaffoldColor(WidgetTester t, Finder under) =>
      t.widget<Scaffold>(find.ancestor(of: under, matching: find.byType(Scaffold)).first).backgroundColor ?? Theme.of(t.element(under)).scaffoldBackgroundColor;

  testWidgets('Cores do aplicativo: Normal, P&B claro e P&B escuro mudam a interface ao vivo e ficam salvas', (t) async {
    phone(t);
    addTearDown(() => Lume.colors.value = AppColors.normal);
    final lib = await library();
    await t.pumpWidget(LumeApp(library: lib));
    await settle(t);
    expect(find.text('Continuar leitura'), findsOneWidget);
    expect(scaffoldColor(t, find.text('Continuar leitura')), const Color(0xFFF6F0E4));
    await t.tap(find.byTooltip('Ajustes'));
    await settle(t);
    await t.drag(find.byType(ListView).first, const Offset(0, -700));
    await settle(t);
    final seg = find.byKey(const ValueKey('app-colors'));
    expect(seg, findsOneWidget);
    await snap('56_ajustes_cores_normal');
    // preto e branco, claro
    await t.tap(find.text('P&B claro'));
    await settle(t);
    expect(Store.appColors, AppColors.bwLight);
    expect(Lume.colors.value, AppColors.bwLight);
    expect(scaffoldColor(t, seg), const Color(0xFFF4F4F4), reason: 'a tela de Ajustes já aberta muda na hora');
    expect(Lume.accent, const Color(0xFF111111));
    // tudo em tons de cinza: o tema do Material e as páginas do leitor
    final theme = Theme.of(t.element(seg));
    for (final c in [theme.colorScheme.primary, theme.colorScheme.surface, theme.scaffoldBackgroundColor, theme.cardTheme.color!, Lume.muted, Lume.line, Lume.accentSoft]) {
      expect((c.r - c.g).abs() < .005 && (c.g - c.b).abs() < .005, isTrue, reason: '$c deveria ser cinza');
    }
    for (final pt in PageTheme.values) {
      for (final c in [pt.bg, pt.ink, pt.muted]) {
        expect((c.r - c.g).abs() < .005 && (c.g - c.b).abs() < .005, isTrue, reason: '${pt.label}: $c deveria ser cinza');
      }
    }
    await snap('57_ajustes_preto_branco_claro');
    // preto e branco, escuro
    await t.tap(find.text('P&B escuro'));
    await settle(t);
    expect(Lume.darkUi, isTrue);
    expect(scaffoldColor(t, seg), const Color(0xFF0C0C0C));
    expect(Theme.of(t.element(seg)).brightness, Brightness.dark);
    await snap('58_ajustes_preto_branco_escuro');
    // volta ao normal
    await t.tap(find.text('Normal'));
    await settle(t);
    expect(scaffoldColor(t, seg), const Color(0xFFF6F0E4));
    expect(Lume.accent, const Color(0xFFB85C38));
    expect(Store.appColors, AppColors.normal);
  });

  testWidgets('Cores do aplicativo: o leitor também fica em preto e branco e a escolha vale depois de reiniciar', (t) async {
    phone(t);
    addTearDown(() => Lume.colors.value = AppColors.normal);
    SharedPreferences.setMockInitialValues({...seedPrefs(), 'appcolors': 'bwLight'});
    await Store.init();
    expect(Lume.colors.value, AppColors.bwLight, reason: 'lida ao abrir o app');
    Store.settings = ReaderSettings(fullscreen: false); // sépia
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    final bg = scaffoldColor(t, find.byKey(ValueKey('block${chapterStart + 1}')))!;
    expect((bg.r - bg.g).abs() < .005 && (bg.g - bg.b).abs() < .005, isTrue, reason: 'a página sépia vira cinza claro');
    await snap('59_leitor_preto_branco');
    Lume.colors.value = AppColors.normal;
    await t.pumpWidget(wrap(ReaderScreen(book: dom, now: () => now)));
    await settle(t);
    expect(scaffoldColor(t, find.byKey(ValueKey('block${chapterStart + 1}'))), PageTheme.sepia.bg);
  });
}
