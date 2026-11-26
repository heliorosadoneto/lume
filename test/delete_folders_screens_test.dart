// Telas de apagar livros (seleção, diálogo, desfazer), das várias pastas nos
// Ajustes e dos livros ocultos, com livros de domínio público. Grava em
// docs/screenshots/ (rode com --update-goldens).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/library.dart';
import 'package:lume/lume_folder.dart';
import 'package:lume/screens/delete_books.dart';
import 'package:lume/screens/library.dart';
import 'package:lume/screens/settings.dart';
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

/// Espera algo que roda fora do teste (leitura das pastas em isolate).
Future<void> until(WidgetTester t, bool Function() ok) async {
  for (var i = 0; i < 100 && !ok(); i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(ok(), isTrue);
}

late Directory storage, lume, download, estudos;

/// Celular com Documents/Lume (dois livros) e duas outras pastas.
Future<Library> phoneLibrary(WidgetTester t, {bool folders = true}) async {
  SharedPreferences.setMockInitialValues({'seeded': true});
  await Store.init();
  Store.settings = Store.settings..fullscreen = false;
  final base = Directory.systemTemp.createTempSync('lumev5');
  storage = Directory(p.join(base.path, 'storage', 'emulated', '0'));
  lume = Directory(p.join(storage.path, 'Documents', 'Lume'))..createSync(recursive: true);
  download = Directory(p.join(storage.path, 'Download', 'Livros'));
  estudos = Directory(p.join(storage.path, 'Estudos'));
  void put(Directory d, String from, [String? name]) {
    d.createSync(recursive: true);
    File(from).copySync(p.join(d.path, name ?? p.basename(from)));
  }

  put(lume, 'assets/books/dom-casmurro.epub');
  put(lume, 'assets/books/quincas-borba.epub');
  put(download, 'demo_folder/iracema.epub');
  put(Directory(p.join(download.path, 'Machado')), 'demo_folder/pdf/helena.pdf');
  put(Directory(p.join(download.path, 'Machado')), 'demo_folder/pdf/esau-e-jaco.pdf');
  put(estudos, 'demo_folder/memorias-postumas-bras-cubas.epub');
  put(estudos, 'demo_folder/txt/iracema-trecho.txt');
  put(estudos, 'demo_folder/iracema.epub', 'Iracema (cópia).epub'); // repetido
  if (folders) Store.folders = [download.path, estudos.path];
  final lib = Library(
    lume,
    coversDir: Directory(p.join(base.path, 'capas')),
    textCacheDir: Directory(p.join(base.path, 'texto')),
    lumeKind: LumeFolderKind.documents,
  );
  await t.runAsync(() async {
    await lib.load(useIsolate: false);
    await lib.coversReady;
  });
  return lib;
}

LibraryBook byTitle(Library lib, String t) => lib.books.firstWhere((b) => b.meta.title == t);
Finder tile(Library lib, String t) => find.byKey(ValueKey('book-${byTitle(lib, t).meta.id}'));

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
  });

  testWidgets('Seleção: toque longo, marcar, selecionar todos, cancelar', (t) async {
    phone(t);
    final lib = await phoneLibrary(t);
    expect(lib.books.length, 7); // a cópia da Iracema não conta
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    await t.longPress(tile(lib, 'Dom Casmurro'));
    await settle(t, rounds: 1);
    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
    expect(find.text('1 selecionado'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-fab')), findsNothing);
    // no modo de seleção, tocar marca/desmarca (não abre o livro)
    await t.tap(tile(lib, 'Esaú e Jacó'));
    await t.tap(tile(lib, 'Helena'));
    await t.tap(tile(lib, 'Iracema'));
    await settle(t, rounds: 1);
    expect(find.text('4 selecionados'), findsOneWidget);
    await t.tap(tile(lib, 'Iracema'));
    await settle(t, rounds: 1);
    expect(find.text('3 selecionados'), findsOneWidget);
    expect(find.byKey(ValueKey('check-${byTitle(lib, 'Helena').meta.id}')), findsOneWidget);
    await snapShot('48_selecao');

    await t.tap(find.byKey(const ValueKey('select-all')));
    await settle(t, rounds: 1);
    expect(find.text('7 selecionados'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('select-all'))); // desmarcar todos
    await settle(t, rounds: 1);
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);

    await t.longPress(tile(lib, 'Helena'));
    await settle(t, rounds: 1);
    await t.tap(find.byKey(const ValueKey('select-cancel')));
    await settle(t, rounds: 1);
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    expect(find.byKey(const ValueKey('import-fab')), findsOneWidget);
  });

  testWidgets('Apagar: diálogo com as duas opções, tirar da biblioteca e desfazer', (t) async {
    phone(t);
    final lib = await phoneLibrary(t);
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    for (final b in ['Dom Casmurro', 'Esaú e Jacó', 'Helena']) {
      await t.longPress(tile(lib, b));
      await settle(t, rounds: 1);
    }
    expect(find.text('3 selecionados'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('select-delete')));
    await settle(t);
    expect(find.byKey(const ValueKey('delete-dialog')), findsOneWidget);
    expect(find.text('Apagar 3 livros?'), findsOneWidget);
    expect(find.text('Tirar só da biblioteca'), findsOneWidget);
    expect(find.text('Apagar o arquivo também'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-note')), findsOneWidget); // há livros fora da pasta do Lume
    expect(find.text('Tirar da biblioteca'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('delete-file')));
    await settle(t, rounds: 1);
    expect(find.text('Apagar arquivos'), findsOneWidget);
    await snapShot('49_apagar_dialogo');
    // volta para "só da biblioteca" e confirma
    await t.tap(find.byKey(const ValueKey('delete-hide')));
    await settle(t, rounds: 1);
    await t.tap(find.byKey(const ValueKey('delete-confirm')));
    await settle(t);
    expect(find.byKey(const ValueKey('undo-snack')), findsOneWidget);
    expect(find.text('3 livros saíram da biblioteca'), findsOneWidget);
    expect(lib.books.length, 4);
    expect(lib.hidden.length, 3);
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    expect(File(byTitleHidden(lib, 'Helena')).existsSync(), isTrue); // arquivo continua lá
    await snapShot('50_apagou_desfazer');

    await t.tap(find.text('Desfazer'));
    await until(t, () => lib.books.length == 7);
    expect(lib.hidden, isEmpty);
    await t.pump(const Duration(seconds: 7)); // o aviso some
    await settle(t, rounds: 1);
  });

  testWidgets('Apagar o arquivo pelo menu do livro (pasta do Lume)', (t) async {
    phone(t);
    final lib = await phoneLibrary(t);
    final q = byTitle(lib, 'Quincas Borba');
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    await t.scrollUntilVisible(find.byKey(ValueKey('menu-${q.meta.id}')), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(ValueKey('menu-${q.meta.id}')));
    await settle(t, rounds: 1);
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Selecionar'), findsOneWidget);
    await t.tap(find.text('Apagar…'));
    await settle(t);
    expect(find.text('Apagar “Quincas Borba”?'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-note')), findsNothing); // está na pasta do Lume
    await t.tap(find.byKey(const ValueKey('delete-file')));
    await settle(t, rounds: 1);
    expect(find.text('Apagar arquivo'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('delete-confirm')));
    await until(t, () => lib.books.length == 6 && !lib.scanning);
    await settle(t, rounds: 1);
    expect(File(q.meta.path).existsSync(), isFalse);
    expect(find.text('1 arquivo apagado'), findsOneWidget);
    expect(find.text('Quincas Borba'), findsNothing);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('Apagar o arquivo sem permissão: explica na tela', (t) async {
    phone(t);
    final lib = await phoneLibrary(t);
    final m = byTitle(lib, 'Memorias Posthumas de Braz Cubas');
    Process.runSync('chmod', ['a-w', estudos.path]);
    addTearDown(() => Process.runSync('chmod', ['u+w', estudos.path]));
    await t.pumpWidget(wrap(LibraryScreen(library: lib)));
    await settle(t);
    await t.scrollUntilVisible(find.byKey(ValueKey('book-${m.meta.id}')), 300, scrollable: find.byType(Scrollable).first);
    await settle(t, rounds: 1);
    await t.longPress(find.byKey(ValueKey('book-${m.meta.id}')));
    await settle(t, rounds: 1);
    await t.tap(find.byKey(const ValueKey('select-delete')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('delete-file')));
    await settle(t, rounds: 1);
    await t.tap(find.byKey(const ValueKey('delete-confirm')));
    await until(t, () => find.byKey(const ValueKey('delete-failed')).evaluate().isNotEmpty);
    await settle(t, rounds: 1);
    expect(find.textContaining('permissão'), findsWidgets);
    expect(File(m.meta.path).existsSync(), isTrue);
    expect(lib.books.length, 7);
    await t.tap(find.text('Entendi'));
    await settle(t, rounds: 1);
  });

  testWidgets('Ajustes > Pastas: a do Lume e mais duas, avisos e remover', (t) async {
    phone(t);
    final lib = await phoneLibrary(t);
    await t.pumpWidget(wrap(SettingsScreen(library: lib, allFilesAccess: false)));
    await settle(t);
    expect(find.text('Pastas'), findsOneWidget);
    expect(find.text('Livros'), findsOneWidget);
    expect(find.text('Armazenamento interno/Download/Livros'), findsOneWidget);
    expect(find.text('3 livros (com subpastas)'), findsOneWidget);
    expect(find.text('Estudos'), findsOneWidget);
    expect(find.text('2 livros (com subpastas)'), findsOneWidget); // a cópia da Iracema não conta
    await snapShot('51_ajustes_pastas');

    await t.drag(find.byType(ListView).first, const Offset(0, -330));
    await settle(t);
    expect(find.textContaining('Para ler pastas fora da do Lume'), findsOneWidget);
    expect(find.textContaining('Android/data'), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-folder')), findsOneWidget);
    expect(find.text('Adicionar pasta'), findsOneWidget);
    await snapShot('52_pastas_limites');

    // remover: só tira da biblioteca
    await t.scrollUntilVisible(find.byKey(ValueKey('remove-${download.path}')), -300, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(ListView).first, const Offset(0, 300));
    await settle(t, rounds: 1);
    await t.tap(find.byKey(ValueKey('remove-${download.path}')));
    await settle(t, rounds: 1);
    expect(find.byKey(const ValueKey('remove-folder-dialog')), findsOneWidget);
    expect(find.textContaining('nenhum arquivo é apagado'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('remove-folder-ok')));
    await until(t, () => lib.folders.length == 1 && !lib.scanning);
    await settle(t, rounds: 1);
    expect(lib.folders, [estudos.path]);
    expect(find.text('Armazenamento interno/Download/Livros'), findsNothing);
    expect(File(p.join(download.path, 'Machado', 'helena.pdf')).existsSync(), isTrue);
    expect(lib.books.length, 5); // agora vale a cópia da Iracema em Estudos
  });

  testWidgets('Livros ocultos: lista, mostrar um e mostrar todos', (t) async {
    phone(t);
    final lib = await phoneLibrary(t);
    lib.hide([byTitle(lib, 'Helena'), byTitle(lib, 'Iracema'), byTitle(lib, 'Quincas Borba')]);
    await t.pumpWidget(wrap(SettingsScreen(library: lib, allFilesAccess: false)));
    await settle(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('hidden-books')), 300, scrollable: find.byType(Scrollable).first);
    await settle(t, rounds: 1);
    expect(find.textContaining('3 livros tirados'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('hidden-books')));
    await settle(t);
    expect(find.byType(HiddenBooksScreen), findsOneWidget);
    expect(find.text('Helena'), findsOneWidget);
    expect(find.byKey(const ValueKey('unhide-all')), findsOneWidget);
    await snapShot('53_livros_ocultos');

    final helena = lib.hidden.firstWhere((h) => h.title == 'Helena');
    await t.tap(find.descendant(of: find.byKey(ValueKey('hidden-${helena.id}')), matching: find.text('Mostrar')));
    await until(t, () => lib.hidden.length == 2 && !lib.scanning);
    await settle(t, rounds: 1);
    expect(lib.books.any((b) => b.meta.title == 'Helena'), isTrue);
    expect(find.text('Helena'), findsNothing);
    await t.tap(find.byKey(const ValueKey('unhide-all')));
    await until(t, () => lib.hidden.isEmpty && !lib.scanning);
    await settle(t, rounds: 1);
    expect(find.text('Nenhum livro oculto.'), findsOneWidget);
    expect(lib.books.length, 7);
  });
}

String byTitleHidden(Library lib, String t) => lib.hidden.firstWhere((h) => h.title == t).path;
