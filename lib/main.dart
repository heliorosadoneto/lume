import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'library.dart';
import 'lume_folder.dart';
import 'screens/library.dart';
import 'screens/pdf_book.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await pdfrxFlutterInitialize(); // PDFium local (sem internet)
  final docs = await getApplicationDocumentsDirectory();
  final support = (await getApplicationSupportDirectory()).path;
  PdfBookScreen.cacheDir = Directory(p.join(support, 'texto'));
  // Pasta do Lume: Documentos/Lume (visível no gerenciador de arquivos) ou,
  // se o Android não deixar, a pasta do app no armazenamento.
  final legacy = Directory(p.join(docs.path, 'Lume', 'livros')); // até a 1.2
  final ext = Platform.isAndroid ? (await getExternalStorageDirectory())?.path : null;
  final lume = LumeFolder.resolve(appExternal: ext, internal: legacy.path);
  LumeFolder.migrate(legacy, lume.dir, Library.isBook);
  Store.lumeFolder = lume.path;
  final library = Library(lume.dir, coversDir: Directory(p.join(support, 'capas')), lumeKind: lume.kind, legacyDirs: [if (legacy.path != lume.path) legacy]);
  await library.seedIfNeeded(rootBundle);
  runApp(LumeApp(library: library));
  await library.load();
  library.watch();
}

class LumeApp extends StatelessWidget {
  const LumeApp({super.key, required this.library});
  final Library library;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lume',
    debugShowCheckedModeBanner: false,
    theme: Lume.theme(),
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: LibraryScreen(library: library),
  );
}
