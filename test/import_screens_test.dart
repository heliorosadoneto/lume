// Telas da pasta do Lume, do "Importar", do TXT e da tela Sobre, com livros de
// domínio público. Grava em docs/screenshots/ (rode com --update-goldens).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/importer.dart';
import 'package:lume/library.dart';
import 'package:lume/lume_folder.dart';
import 'package:lume/screens/import_books.dart';
import 'package:lume/screens/library.dart';
import 'package:lume/screens/reader.dart';
import 'package:lume/screens/settings.dart';
import 'package:lume/store.dart';
import 'package:lume/txt.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pdfium.dart';

import 'package:lume/theme.dart';

import 'support/shots.dart';

Widget wrap(Widget w) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: Lume.theme(),
  locale: const Locale('pt', 'BR'),
  supportedLocales: const [Locale('pt', 'BR')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: w,
);

final now = DateTime(2026, 11, 13, 21, 0);
late Directory root, storage, download;
late List<String> picked;

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  t.view.padding = const FakeViewPadding(top: 66);
  addTearDown(t.view.reset);
}

Future<void> snap(WidgetTester t, String name) => snapShot(name);

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

/// Armazenamento como no celular: Documents/Lume com os dois livros de
/// exemplo da primeira abertura e uma pasta Download com o que vai ser importado.
Future<Library> freshLibrary(WidgetTester t, {LumeFolderKind kind = LumeFolderKind.documents}) async {
  SharedPreferences.setMockInitialValues({'seeded': true});
  await Store.init();
  final base = Directory.systemTemp.createTempSync('lumev3');
  final s = Directory(p.join(base.path, 'storage', 'emulated', '0'));
  final dir = kind == LumeFolderKind.documents
      ? Directory(p.join(s.path, 'Documents', 'Lume'))
      : Directory(p.join(s.path, 'Android', 'data', 'com.helio.lume', 'files', 'Livros'));
  dir.createSync(recursive: true);
  for (final b in ['dom-casmurro.epub', 'quincas-borba.epub']) {
    File('assets/books/$b').copySync(p.join(dir.path, b));
  }
  final lib = Library(dir, coversDir: Directory(p.join(base.path, 'capas')), lumeKind: kind);
  await t.runAsync(() async {
    await lib.load(useIsolate: false);
    await lib.coversReady;
  });
  return lib;
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
    root = Directory.systemTemp.createTempSync('lumev3src');
    download = Directory(p.join(root.path, 'Download'))..createSync();
    picked = [
      for (final (from, name) in [
        ('demo_folder/pdf/helena.pdf', 'Helena - Machado de Assis.pdf'),
        ('demo_folder/txt/iracema-trecho.txt', 'iracema-trecho.txt'),
        ('demo_folder/memorias-postumas-bras-cubas.epub', 'memorias-postumas-bras-cubas.epub'),
        ('demo_folder/pdf/esau-e-jaco.pdf', 'Esaú e Jacó.pdf'),
        ('assets/books/dom-casmurro.epub', 'Dom Casmurro (1).epub'), // já está na pasta
      ])
        File(from).copySync(p.join(download.path, name)).path,
    ];
  });

  testWidgets('Biblioteca com o botão Importar e a pasta do Lume', (t) async {
    phone(t);
    final lib = await freshLibrary(t);
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    expect(find.byKey(const ValueKey('import-fab')), findsOneWidget);
    expect(find.text('Pasta do Lume: Documentos/Lume'), findsOneWidget);
    await snap(t, '29_biblioteca_importar');
    await t.tap(find.byTooltip('Adicionar livros'));
    await settle(t);
    expect(find.text('Importar livros'), findsOneWidget);
    await snap(t, '30_adicionar_livros');
  });

  testWidgets('Importando vários arquivos: progresso, resultado e biblioteca', (t) async {
    phone(t);
    final lib = await freshLibrary(t);
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    final ctx = t.element(find.byType(LibraryScreen));
    // progresso: 2º de 5 arquivos, no meio da cópia
    showModalBottomSheet<void>(
      context: ctx,
      isDismissible: false,
      isScrollControlled: true,
      builder: (_) => ImportSheet(library: lib, paths: picked, autoStart: false),
    );
    await settle(t, rounds: 1);
    final st = t.state<ImportSheetState>(find.byType(ImportSheet));
    final total = picked.fold<int>(0, (a, f) => a + File(f).lengthSync());
    st.show(progress: ImportProgress(1, 5, p.basename(picked[1]), (total * .38).round(), total));
    await settle(t, rounds: 1);
    expect(find.text('Importando 2 de 5…'), findsOneWidget);
    await snap(t, '31_importando');
    Navigator.of(t.element(find.byType(ImportSheet))).pop();
    await settle(t, rounds: 1);

    // import de verdade (no teste, a cópia roda fora do relógio falso)
    final items = await t.runAsync(() => lib.importFiles(picked));
    showModalBottomSheet<void>(
      context: ctx,
      isDismissible: false,
      isScrollControlled: true,
      builder: (_) => ImportSheet(library: lib, paths: picked, autoStart: false),
    );
    await settle(t, rounds: 1);
    final st2 = t.state<ImportSheetState>(find.byType(ImportSheet));
    st2.show(items: items);
    await settle(t, rounds: 2);
    expect(find.text('4 livros importados'), findsOneWidget);
    expect(find.text('Já estava na pasta'), findsOneWidget);
    await snap(t, '32_importado');
    await t.tap(find.byKey(const ValueKey('import-done')));
    await t.runAsync(() => lib.coversReady);
    await settle(t);
    expect(lib.books.length, 6);
    expect(File(p.join(lib.importDir.path, 'iracema-trecho.txt')).existsSync(), isTrue);
    expect(find.text('TXT · 1'), findsOneWidget);
    await snap(t, '33_biblioteca_depois');
  });

  testWidgets('Ajustes: pasta do Lume em Documentos e as outras pastas', (t) async {
    phone(t);
    final lib = await freshLibrary(t);
    await t.pumpWidget(wrap(SettingsScreen(library: lib, allFilesAccess: false)));
    await settle(t);
    expect(find.text('Armazenamento interno/Documents/Lume'), findsOneWidget);
    expect(find.text('Outras pastas'), findsOneWidget);
    expect(find.byKey(const ValueKey('lume-fixed')), findsOneWidget);
    await snap(t, '34_ajustes_pasta_lume');
    // Sobre, no fim dos ajustes
    await t.scrollUntilVisible(find.byKey(const ValueKey('about')), 400, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(ListView).first, const Offset(0, -600));
    await settle(t);
    await snap(t, '36_sobre');
  });

  testWidgets('Ajustes: sem Documentos, a pasta fica em Android/data e o Lume explica', (t) async {
    phone(t);
    final lib = await freshLibrary(t, kind: LumeFolderKind.appExternal);
    await t.pumpWidget(wrap(SettingsScreen(library: lib, allFilesAccess: false)));
    await settle(t);
    expect(find.byKey(const ValueKey('lume-note-appExternal')), findsOneWidget);
    expect(find.text('Usar Documentos/Lume'), findsOneWidget);
    await snap(t, '35_ajustes_pasta_app');
  });

  testWidgets('TXT no leitor de texto', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({'seeded': true, 'settings': '{"t":"sepia","f":"literata","s":19,"l":1.6,"m":1,"j":true,"p":false}'});
    await Store.init();
    final book = TxtBook.parseFile('demo_folder/txt/iracema-trecho.txt');
    expect(isBookPath(book.meta.path), isTrue);
    await t.pumpWidget(wrap(ReaderScreen(book: book, now: () => now)));
    await settle(t);
    expect(find.textContaining('Verdes mares bravios'), findsOneWidget);
    await snap(t, '37_txt_leitor');
  });
}
