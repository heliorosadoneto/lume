// Biblioteca: livros importados (copiados para a pasta do app) + livros
// encontrados na pasta escolhida pelo usuário, com atualização automática.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'epub.dart';
import 'store.dart';

enum BookSource { folder, imported }

class LibraryBook {
  LibraryBook(this.meta, this.source);
  final BookMeta meta;
  final BookSource source;
  ReadingPos? get pos => Store.pos(meta.id);
}

typedef _ScanResult = ({List<BookMeta> metas, List<String> failed});

class Library extends ChangeNotifier {
  Library(this.importDir);
  final Directory importDir;
  List<LibraryBook> books = [];
  List<String> failed = [];
  bool scanning = false;
  bool loaded = false;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;

  String? get folder => Store.folder;
  bool get watching => _watch != null;

  static const seedAssets = ['assets/books/dom-casmurro.epub', 'assets/books/quincas-borba.epub'];

  /// Na primeira abertura copia os livros de domínio público de exemplo.
  Future<void> seedIfNeeded(AssetBundle bundle) async {
    if (Store.seeded) return;
    await importDir.create(recursive: true);
    for (final a in seedAssets) {
      final data = await bundle.load(a);
      await File(p.join(importDir.path, p.basename(a))).writeAsBytes(data.buffer.asUint8List());
    }
    Store.seeded = true;
  }

  static List<String> _epubsIn(String dir, bool recursive) {
    final d = Directory(dir);
    if (!d.existsSync()) return [];
    try {
      return d
          .listSync(recursive: recursive, followLinks: false)
          .whereType<File>()
          .map((f) => f.path)
          .where((x) => x.toLowerCase().endsWith('.epub'))
          .toList()
        ..sort();
    } on FileSystemException {
      return [];
    }
  }

  static _ScanResult _scan((String, String?) dirs) {
    final metas = <BookMeta>[];
    final failed = <String>[];
    for (final path in [if (dirs.$2 != null) ..._epubsIn(dirs.$2!, true), ..._epubsIn(dirs.$1, false)]) {
      try {
        metas.add(Epub.readMeta(path));
      } catch (_) {
        failed.add(path);
      }
    }
    return (metas: metas, failed: failed);
  }

  Future<void> load({bool useIsolate = true}) async {
    scanning = true;
    notifyListeners();
    final args = (importDir.path, folder);
    final r = useIsolate ? await compute(_scan, args) : _scan(args);
    final seen = <String>{};
    final list = <LibraryBook>[];
    for (final m in r.metas) {
      if (!seen.add(m.id)) continue; // mesmo livro na pasta e importado: vale o da pasta
      final fromFolder = folder != null && p.isWithin(folder!, m.path);
      list.add(LibraryBook(m, fromFolder ? BookSource.folder : BookSource.imported));
    }
    list.sort((a, b) => a.meta.title.toLowerCase().compareTo(b.meta.title.toLowerCase()));
    books = list;
    failed = r.failed;
    scanning = false;
    loaded = true;
    notifyListeners();
  }

  /// Livros com leitura em andamento, do mais recente para o mais antigo.
  List<LibraryBook> get continueReading {
    final l = books.where((b) => b.pos != null && b.pos!.percent < 0.995).toList();
    l.sort((a, b) => b.pos!.opened.compareTo(a.pos!.opened));
    return l;
  }

  Future<void> setFolder(String? path, {bool useIsolate = true, bool watchIt = true}) async {
    Store.folder = path;
    await load(useIsolate: useIsolate);
    if (watchIt) watch();
  }

  /// Observa a pasta e recarrega quando um arquivo é adicionado ou removido.
  void watch() {
    _watch?.cancel();
    _watch = null;
    final f = folder;
    if (f == null || !Store.watchFolder || !Directory(f).existsSync()) {
      notifyListeners();
      return;
    }
    try {
      _watch = Directory(f)
          .watch(events: FileSystemEvent.create | FileSystemEvent.delete | FileSystemEvent.move)
          .listen((e) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 900), load);
      }, onError: (_) {});
    } catch (_) {
      // Sistema de arquivos sem suporte a observação: fica o "puxar para atualizar".
    }
    notifyListeners();
  }

  Future<BookMeta> importFile(String path) async {
    final meta = await compute(Epub.readMeta, path);
    await importDir.create(recursive: true);
    final dest = p.join(importDir.path, p.basename(path));
    if (p.canonicalize(dest) != p.canonicalize(path)) await File(path).copy(dest);
    await load();
    return meta;
  }

  @override
  void dispose() {
    _watch?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
