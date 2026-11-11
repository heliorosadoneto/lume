import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'screens/library.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  final docs = await getApplicationDocumentsDirectory();
  final library = Library(Directory(p.join(docs.path, 'Lume', 'livros')));
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
