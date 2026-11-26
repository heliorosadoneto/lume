// Telas do suporte a PDF e da importação por pasta. Como em screens_test.dart,
// renderizam os widgets reais com as fontes do app e PDFs de domínio público
// (gerados de textos do Project Gutenberg, veja tool/make_sample_pdfs.py) e
// gravam os prints em docs/screenshots/ (rode com --update-goldens).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';
import 'package:lume/library.dart';
import 'package:lume/lume_folder.dart';
import 'package:lume/pdf.dart';
import 'package:lume/screens/folder_import.dart';
import 'package:lume/screens/library.dart';
import 'package:lume/pdf_analysis.dart';
import 'package:lume/screens/pdf_book.dart';
import 'package:lume/screens/pdf_reader.dart';
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

final now = DateTime(2026, 11, 11, 21, 40);
late Directory root, folder, importDir, coversDir;
late BookMeta helena, esau;

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  t.view.padding = const FakeViewPadding(top: 66);
  addTearDown(t.view.reset);
}

Future<void> snap(String name) => snapShot(name);

/// Deixa o PDFium (que roda em outro isolate) terminar de desenhar.
Future<void> render(WidgetTester t, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> resetPrefs() async {
  SharedPreferences.setMockInitialValues({
    'seeded': true,
    'folder': folder.path,
    'settings': '{"t":"sepia","f":"literata","s":19,"l":1.6,"m":1,"j":true,"p":false}',
    'pos:${helena.id}': '{"b":41,"a":0.0,"p":${42 / 228},"o":${now.millisecondsSinceEpoch}}',
    'pos:${esau.id}': '{"b":120,"a":0.0,"p":${121 / 329},"o":${now.subtract(const Duration(days: 2)).millisecondsSinceEpoch}}',
    'bm:${helena.id}':
        '[{"b":1,"x":"O conselheiro Vale morreu ás 7 horas da noite de 25 de abril de 1859.","d":${now.millisecondsSinceEpoch}},{"b":41,"x":"","d":${now.millisecondsSinceEpoch}}]',
  });
  await Store.init();
  Store.settings = Store.settings..fullscreen = false;
}

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
    await initPdfiumForTests();

    // Pasta "Livros" como no celular: EPUBs soltos, PDFs em subpastas e um PDF repetido.
    root = Directory.systemTemp.createTempSync('lumepdf');
    folder = Directory(p.join(root.path, 'storage', 'emulated', '0', 'Livros'))..createSync(recursive: true);
    importDir = Directory(p.join(root.path, 'storage', 'emulated', '0', 'Documents', 'Lume'))..createSync(recursive: true);
    coversDir = Directory(p.join(root.path, 'capas'));
    for (final f in Directory('demo_folder').listSync().whereType<File>()) {
      f.copySync(p.join(folder.path, p.basename(f.path)));
    }
    final rom = Directory(p.join(folder.path, 'Machado de Assis', 'Romances'))..createSync(recursive: true);
    final diario = Directory(p.join(folder.path, 'Machado de Assis', 'Diários'))..createSync(recursive: true);
    final down = Directory(p.join(folder.path, 'Download'))..createSync();
    File('demo_folder/pdf/helena.pdf').copySync(p.join(rom.path, 'helena.pdf'));
    File('demo_folder/pdf/esau-e-jaco.pdf').copySync(p.join(rom.path, 'esau-e-jaco.pdf'));
    File('demo_folder/pdf/sem-metadados/memorial-de-aires.pdf').copySync(p.join(diario.path, 'memorial-de-aires.pdf'));
    File('demo_folder/pdf/helena.pdf').copySync(p.join(down.path, 'Helena (1).pdf')); // repetido
    helena = PdfMeta.read(p.join(rom.path, 'helena.pdf'));
    esau = PdfMeta.read(p.join(rom.path, 'esau-e-jaco.pdf'));
    PdfBookScreen.cacheDir = Directory(p.join(root.path, 'texto'));
    await resetPrefs();
  });

  setUp(resetPrefs);

  Future<Library> library(WidgetTester t) async {
    final lib = Library(importDir, coversDir: coversDir, lumeKind: LumeFolderKind.documents);
    await t.runAsync(() async {
      await lib.load(useIsolate: false);
      await lib.coversReady;
    });
    return lib;
  }

  testWidgets('Pasta com subpastas: PDFs e EPUBs, sem repetidos, capa da 1ª página', (t) async {
    phone(t);
    final lib = await library(t);
    expect(lib.books.length, 7); // 4 EPUB + 3 PDF; "Helena (1).pdf" é o mesmo livro
    expect(lib.report.duplicates, 1);
    expect(lib.report.pdf, 3);
    final h = lib.books.firstWhere((b) => b.meta.id == helena.id);
    expect(h.subfolder, p.join('Machado de Assis', 'Romances'));
    expect(h.meta.cover, isNotNull);
    expect(h.pages, 228);
    expect(lib.books.map((b) => b.meta.title), contains('Memorial de Aires'));
    expect(lib.continueReading.first.meta.title, 'Helena');
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await render(t, rounds: 2);
    expect(find.text('PDF · 3'), findsOneWidget);
    await snap('12_biblioteca_pdf');
    await t.tap(find.byKey(const ValueKey('filter-pdf')));
    await render(t, rounds: 2);
    expect(find.text('Iracema'), findsNothing);
    await snap('13_biblioteca_filtro_pdf');
  });

  testWidgets('Botão +: arquivo, pasta ou atualizar pasta', (t) async {
    phone(t);
    final lib = await library(t);
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await render(t, rounds: 1);
    await t.tap(find.byTooltip('Adicionar livros'));
    await render(t, rounds: 2);
    expect(find.text('Atualizar pasta'), findsOneWidget);
    await snap('14_adicionar_livros');
  });

  testWidgets('Explicação da permissão de pasta (Android 11+)', (t) async {
    phone(t);
    final lib = await library(t);
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await render(t, rounds: 1);
    showDialog<bool>(context: t.element(find.byType(LibraryScreen)), builder: (_) => const StorageAccessDialog());
    await render(t, rounds: 2);
    await snap('15_permissao_pasta');
  });

  testWidgets('Lendo a pasta: progresso e resultado', (t) async {
    phone(t);
    final lib = await library(t);
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await render(t, rounds: 1);
    // progresso no meio da leitura de uma pasta grande
    lib
      ..scanning = true
      ..scanTotal = 34
      ..scanDone = 13;
    showModalBottomSheet<void>(
      context: t.element(find.byType(LibraryScreen)),
      builder: (_) => FolderScanSheet(library: lib),
    );
    await render(t, rounds: 2);
    expect(find.text('Encontrados 34 livros…'), findsOneWidget);
    await snap('16_pasta_progresso');
    // agora a leitura de verdade
    await t.runAsync(() => lib.load(useIsolate: false));
    await render(t, rounds: 2);
    expect(find.text('7 livros na pasta'), findsOneWidget);
    expect(find.text('Repetidos (ignorados)'), findsOneWidget);
    await snap('17_pasta_resultado');
  });

  testWidgets('Leitor de PDF sépia (rolagem contínua) retoma a página', (t) async {
    phone(t);
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    final st = t.state<PdfReaderScreenState>(find.byType(PdfReaderScreen));
    expect(st.page, 42);
    expect(find.text('Página 42 de 228'), findsOneWidget);
    await snap('18_pdf_leitor_sepia');
  });

  testWidgets('Leitor de PDF no tema preto', (t) async {
    phone(t);
    Store.settings = ReaderSettings(fullscreen: false, theme: PageTheme.preto);
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    await snap('19_pdf_leitor_preto');
  });

  testWidgets('Página a página (branco), deslizar avança e salva', (t) async {
    phone(t);
    Store.settings = ReaderSettings(fullscreen: false, theme: PageTheme.branco);
    Store.pdfPaged = true;
    Store.savePos(helena.id, ReadingPos(1, 0, 0, now));
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    final st = t.state<PdfReaderScreenState>(find.byType(PdfReaderScreen));
    expect(st.page, 2);
    await snap('20_pdf_pagina_a_pagina');
    await t.fling(find.byKey(const ValueKey('pdf-paged')), const Offset(-220, 0), 1200);
    await render(t, rounds: 4);
    expect(st.page, 3);
    expect(Store.pos(helena.id)!.block, 2);
    await t.tap(find.byKey(const ValueKey('pdfpage1')));
    await render(t, rounds: 4);
    expect(st.page, 4);
  });

  testWidgets('PDF em tela cheia: botões escondidos, centro mostra, borda vira a página', (t) async {
    phone(t);
    final ui = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'SystemChrome.setEnabledSystemUIMode') ui.add(c.arguments as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    Store.settings = ReaderSettings(fullscreen: true, theme: PageTheme.branco);
    Store.pdfPaged = true;
    Store.savePos(helena.id, ReadingPos(1, 0, 0, now));
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    final st = t.state<PdfReaderScreenState>(find.byType(PdfReaderScreen));
    expect(find.byTooltip('Aparência'), findsNothing);
    expect(ui.last, 'SystemUiMode.immersiveSticky');
    await t.tap(find.byKey(const ValueKey('pdfpage1')));
    await render(t, rounds: 4);
    expect(st.page, 3, reason: 'a borda direita vira a página');
    expect(find.byTooltip('Aparência'), findsNothing, reason: 'e não mostra os botões');
    final size = t.getSize(find.byType(Scaffold));
    await t.tapAt(Offset(size.width / 2, size.height / 2));
    await t.pump(const Duration(milliseconds: 400));
    await render(t, rounds: 2);
    expect(find.byTooltip('Aparência'), findsOneWidget);
    expect(ui.last, 'SystemUiMode.edgeToEdge');
    await snap('64_pdf_tela_cheia_botoes');
    await t.pumpWidget(const SizedBox());
    expect(ui.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('Zoom com pinça na página', (t) async {
    phone(t);
    Store.pdfPaged = true;
    Store.savePos(helena.id, ReadingPos(1, 0, 0, now));
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    final center = t.getCenter(find.byKey(const ValueKey('zoom2')));
    final a = await t.startGesture(center - const Offset(40, 120));
    final b = await t.startGesture(center + const Offset(40, -40));
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(center - Offset(40 + i * 10.0, 120 + i * 12.0));
      await b.moveTo(center + Offset(40 + i * 10.0, -40 + i * 12.0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await render(t, rounds: 8);
    final st = t.state<PdfReaderScreenState>(find.byType(PdfReaderScreen));
    expect(st.zoom, greaterThan(1.5));
    expect(find.byKey(const ValueKey('zoom-pill')), findsOneWidget);
    await snap('21_pdf_zoom');
    await t.tap(find.byKey(const ValueKey('zoom-pill')));
    await render(t, rounds: 2);
    expect(st.zoom, lessThan(1.05));
  });

  testWidgets('Barra de páginas e "Ir para a página"', (t) async {
    phone(t);
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    // arrastando a barra mostra a página de destino
    final slider = find.byKey(const ValueKey('pdf-slider'));
    final g = await t.startGesture(t.getCenter(slider));
    await g.moveBy(const Offset(110, 0));
    await t.pump(const Duration(milliseconds: 100));
    await snap('22_pdf_barra_paginas');
    await g.up();
    await render(t);
    final st = t.state<PdfReaderScreenState>(find.byType(PdfReaderScreen));
    expect(st.page, greaterThan(120));
    await t.tap(find.byTooltip('Ir para a página'));
    await render(t, rounds: 2);
    await snap('23_pdf_ir_para_pagina');
    await t.enterText(find.byKey(const ValueKey('goto-field')), '150');
    await render(t, rounds: 1);
    await t.tap(find.byKey(const ValueKey('goto-ok')));
    await render(t);
    expect(st.page, 150);
    expect(Store.pos(helena.id)!.block, 149);
  });

  testWidgets('Sumário do PDF e marcadores', (t) async {
    phone(t);
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    final st = t.state<PdfReaderScreenState>(find.byType(PdfReaderScreen));
    expect(st.bookmarked, isTrue); // página 42 tem marcador
    await t.tap(find.byTooltip('Sumário e marcadores'));
    await render(t, rounds: 3);
    expect(find.text('Capítulos (28)'), findsOneWidget);
    await snap('24_pdf_sumario');
    await t.tap(find.text('Marcadores (2)'));
    await render(t, rounds: 2);
    await snap('25_pdf_marcadores');
    await t.tap(find.text('Página 2'));
    await render(t);
    expect(st.page, 2);
  });

  testWidgets('Aparência do PDF', (t) async {
    phone(t);
    await t.pumpWidget(wrap(PdfReaderScreen(meta: helena, now: () => now)));
    await render(t);
    await t.tap(find.byTooltip('Aparência'));
    await render(t, rounds: 3);
    await snap('26_pdf_aparencia');
    await t.tap(find.byKey(const ValueKey('pdftheme-preto')));
    await render(t, rounds: 1);
    expect(Store.settings.theme, PageTheme.preto);
  });

  testWidgets('Modo texto: padrão para PDF com texto, página sincronizada nos dois modos', (t) async {
    phone(t);
    await t.pumpWidget(wrap(PdfBookScreen(meta: helena, now: () => now)));
    // primeira vez: extrai o texto (fora da thread da interface) com progresso
    expect(find.text('Preparando o modo texto…'), findsOneWidget);
    for (var i = 0; i < 20 && find.textContaining(' de 228').evaluate().isEmpty; i++) {
      await render(t, rounds: 1);
    }
    expect(find.textContaining(RegExp(r'^Página \d+ de 228$')), findsOneWidget);
    // (no teste, o PDFium só anda entre um pump e outro; a extração de verdade
    // roda aqui e o leitor reabre lendo do cache)
    await t.runAsync(() => PdfBookScreen.defaultAnalyzer.analyze(helena.path, helena.id));
    await t.pumpWidget(wrap(PdfBookScreen(key: const ValueKey('again'), meta: helena, now: () => now)));
    await render(t, rounds: 6);
    expect(find.byType(ReaderScreen), findsOneWidget);
    final a = await t.runAsync(() => PdfBookScreen.defaultAnalyzer.analyze(helena.path, helena.id));
    final tid = PdfAnalysis.textId(helena.id);
    // abriu no bloco do topo da página 42, onde a leitura estava
    final blk = Store.pos(tid)!.block;
    expect(blk, a!.reflow.blockForPage(42));
    expect(find.textContaining('p. ${a.reflow.blockPage[blk]} de 228'), findsOneWidget);
    await snap('27_pdf_modo_texto');

    // lendo no modo texto: a posição do PDF acompanha
    final st = t.state<ReaderScreenState>(find.byType(ReaderScreen));
    final target = a.reflow.blockForPage(120);
    st.jumpTo(target);
    await render(t, rounds: 4);
    expect(Store.pos(helena.id)!.block, a.reflow.blockPage[Store.pos(tid)!.block] - 1);
    expect(Store.pos(helena.id)!.block, inInclusiveRange(118, 120));

    // troca para a página original pela folha de aparência
    await t.tap(find.byTooltip('Aparência'));
    await render(t, rounds: 3);
    expect(find.text('Modo texto'), findsOneWidget);
    await snap('28_pdf_modo_texto_aparencia');
    await t.tap(find.text('Página original'));
    await render(t);
    expect(Store.pdfMode(helena.id), 'pagina');
    final pr = t.state<PdfReaderScreenState>(find.byType(PdfReaderScreen));
    final page = Store.pos(helena.id)!.block + 1;
    expect(pr.page, page);

    // avança no modo página e volta para o modo texto: continua da página nova
    await pr.goTo(150, animate: false);
    await render(t, rounds: 4);
    await t.tap(find.byTooltip('Aparência'));
    await render(t, rounds: 3);
    await t.tap(find.text('Modo texto'));
    await render(t, rounds: 8);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(Store.pdfMode(helena.id), 'texto');
    expect(Store.pos(tid)!.block, a.reflow.blockForPage(150));
  });

  testWidgets('PDF escaneado (sem texto): abre na página original e explica', (t) async {
    phone(t);
    final scan = PdfMeta.read('test/fixtures/escaneado.pdf');
    await t.pumpWidget(wrap(PdfBookScreen(meta: scan, now: () => now)));
    for (var i = 0; i < 40 && find.byType(PdfReaderScreen).evaluate().isEmpty; i++) {
      await render(t, rounds: 1);
    }
    await render(t, rounds: 4);
    expect(find.byType(PdfReaderScreen), findsOneWidget);
    expect(find.textContaining('escaneado'), findsOneWidget);
    await t.pump(const Duration(seconds: 8));
    await t.tap(find.byTooltip('Aparência'));
    await render(t, rounds: 3);
    expect(find.textContaining('Este PDF é escaneado'), findsOneWidget);
    // o botão do modo texto fica desligado
    await t.tap(find.text('Modo texto'));
    await render(t, rounds: 2);
    expect(find.byType(PdfReaderScreen), findsOneWidget);
  });
}
