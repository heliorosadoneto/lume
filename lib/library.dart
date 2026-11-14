// Biblioteca: livros da pasta do Lume (Documentos/Lume, para onde o "Importar"
// copia) + livros encontrados na pasta escolhida pelo usuário (e em todas as
// subpastas), com atualização automática. Aceita EPUB, PDF e TXT.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'epub.dart';
import 'importer.dart';
import 'lume_folder.dart';
import 'pdf.dart';
import 'store.dart';
import 'txt.dart';

enum BookSource { folder, imported }

class LibraryBook {
  LibraryBook(this.meta, this.source, {this.subfolder});
  final BookMeta meta;
  final BookSource source;

  /// Subpasta (relativa à pasta escolhida ou à do Lume) onde o arquivo está.
  final String? subfolder;
  ReadingPos? get pos => Store.pos(meta.id);
  int? get pages => Store.pages(meta.id);
}

/// Resumo da última leitura da pasta.
class ScanReport {
  const ScanReport({this.epub = 0, this.pdf = 0, this.txt = 0, this.failed = 0, this.duplicates = 0});
  final int epub, pdf, txt, failed, duplicates;
  int get total => epub + pdf + txt;
}

typedef _MetaResult = ({List<BookMeta> metas, List<String> failed});

class Library extends ChangeNotifier {
  Library(this.importDir, {Directory? coversDir, this.renderPdfCovers = true, this.lumeKind = LumeFolderKind.internal, this.legacyDirs = const []})
    : covers = PdfCovers(coversDir ?? Directory(p.join(importDir.parent.path, 'capas')));

  /// Pasta do Lume: onde o "Importar" copia os livros (lida com subpastas).
  Directory importDir;
  LumeFolderKind lumeKind;

  /// Pastas antigas de importados (versões até a 1.2), lidas sem subpastas.
  final List<Directory> legacyDirs;
  final PdfCovers covers;

  /// Gera as capas dos PDFs com o PDFium depois de ler a pasta.
  final bool renderPdfCovers;
  List<LibraryBook> books = [];
  List<String> failed = [];
  bool scanning = false;
  bool loaded = false;

  /// Progresso da leitura: arquivos encontrados e já lidos.
  int scanTotal = 0, scanDone = 0;
  ScanReport report = const ScanReport();
  StreamSubscription<FileSystemEvent>? _watch, _watchLume;
  Timer? _debounce;
  Future<void>? _coversJob;

  String? get folder => Store.folder;
  bool get watching => _watch != null;

  static const seedAssets = ['assets/books/dom-casmurro.epub', 'assets/books/quincas-borba.epub'];
  static const extensions = bookExtensions;

  static bool isBook(String path) => isBookPath(path);

  static bool looksLikeCopy(String path) =>
      RegExp(r'(\(\d+\)|[ _-]c[oó]pia|[ _-]copy)( \d+)?$', caseSensitive: false).hasMatch(p.basenameWithoutExtension(path));

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

  static List<String> _booksIn(String dir, bool recursive) {
    final d = Directory(dir);
    if (!d.existsSync()) return [];
    final out = <String>[];
    void walk(Directory d, bool deep) {
      List<FileSystemEntity> items;
      try {
        items = d.listSync(followLinks: false);
      } on FileSystemException {
        return; // subpasta sem permissão: segue com as outras
      }
      for (final e in items) {
        if (e is File && isBook(e.path)) {
          out.add(e.path);
        } else if (deep && e is Directory && !p.basename(e.path).startsWith('.')) {
          walk(e, true);
        }
      }
    }

    walk(d, recursive);
    return out..sort();
  }

  /// Lista os arquivos: pasta escolhida e pasta do Lume (com subpastas) e as
  /// pastas antigas de importados.
  static List<String> _list((String, String?, List<String>) dirs) => [
    if (dirs.$2 != null) ..._booksIn(dirs.$2!, true),
    ..._booksIn(dirs.$1, true),
    for (final d in dirs.$3) ..._booksIn(d, false),
  ];

  static _MetaResult _metas((List<String>, String) args) {
    final metas = <BookMeta>[];
    final failed = <String>[];
    final covers = PdfCovers(Directory(args.$2));
    for (final path in args.$1) {
      try {
        if (TxtBook.isTxt(path)) {
          metas.add(TxtBook.readMeta(path));
        } else if (path.toLowerCase().endsWith('.pdf')) {
          final m = PdfMeta.read(path);
          final c = covers.fileFor(m.id);
          if (c.existsSync()) m.cover = c.readAsBytesSync();
          metas.add(m);
        } else {
          metas.add(Epub.readMeta(path));
        }
      } catch (_) {
        failed.add(path);
      }
    }
    return (metas: metas, failed: failed);
  }

  static BookMeta readMeta(String path) => _metas(([path], '')).metas.firstOrNull ?? (throw EpubException('Arquivo inválido'));

  Future<void> load({bool useIsolate = true}) async {
    scanning = true;
    scanTotal = 0;
    scanDone = 0;
    notifyListeners();
    final args = (importDir.path, folder, [for (final d in legacyDirs) d.path]);
    final paths = useIsolate ? await compute(_list, args) : _list(args);
    scanTotal = paths.length;
    notifyListeners();

    final metas = <BookMeta>[];
    final fails = <String>[];
    const chunk = 8;
    for (var i = 0; i < paths.length; i += chunk) {
      final part = paths.sublist(i, (i + chunk).clamp(0, paths.length));
      final a = (part, covers.dir.path);
      final r = useIsolate ? await compute(_metas, a) : _metas(a);
      metas.addAll(r.metas);
      fails.addAll(r.failed);
      scanDone = i + part.length;
      notifyListeners();
    }

    // Mesmo livro em dois lugares conta uma vez só. Vale o da pasta (antes dos
    // importados) e, entre cópias, o arquivo que não parece cópia ("x (1).pdf").
    final byId = <String, BookMeta>{};
    var dups = 0;
    for (final m in metas) {
      final prev = byId[m.id];
      if (prev == null) {
        byId[m.id] = m;
        continue;
      }
      dups++;
      final f = folder;
      final sameSource = f == null || p.isWithin(f, prev.path) == p.isWithin(f, m.path);
      if (sameSource && looksLikeCopy(prev.path) && !looksLikeCopy(m.path)) byId[m.id] = m;
    }
    final list = <LibraryBook>[];
    for (final m in byId.values) {
      final f = folder;
      final fromFolder = f != null && p.isWithin(f, m.path);
      String? sub;
      final base = fromFolder ? f : (p.isWithin(importDir.path, m.path) ? importDir.path : null);
      if (base != null) {
        final rel = p.dirname(p.relative(m.path, from: base));
        sub = rel == '.' ? null : rel;
      }
      list.add(LibraryBook(m, fromFolder ? BookSource.folder : BookSource.imported, subfolder: sub));
    }
    list.sort((a, b) => a.meta.title.toLowerCase().compareTo(b.meta.title.toLowerCase()));
    books = list;
    failed = fails;
    report = ScanReport(
      epub: list.where((b) => b.meta.format == BookFormat.epub).length,
      pdf: list.where((b) => b.meta.isPdf).length,
      txt: list.where((b) => b.meta.format == BookFormat.txt).length,
      failed: fails.length,
      duplicates: dups,
    );
    scanning = false;
    loaded = true;
    notifyListeners();
    if (renderPdfCovers) _coversJob = _renderMissingCovers();
  }

  /// Espera as capas de PDF que ainda estão sendo geradas.
  Future<void> get coversReady => _coversJob ?? Future.value();

  Future<void> _renderMissingCovers() async {
    for (final b in [...books]) {
      if (!b.meta.isPdf || (b.meta.cover != null && b.pages != null)) continue;
      try {
        final r = await covers.render(b.meta.path, b.meta.id);
        b.meta.cover = r.cover;
        Store.setPages(b.meta.id, r.pages);
        notifyListeners();
      } catch (_) {
        // PDF protegido ou danificado: fica a capa tipográfica
      }
    }
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

  /// Observa as pastas (a escolhida e a do Lume) e recarrega quando um livro
  /// é adicionado ou removido, inclusive pelo gerenciador de arquivos.
  void watch() {
    _watch?.cancel();
    _watchLume?.cancel();
    _watch = _watchLume = null;
    if (Store.watchFolder) {
      final f = folder;
      if (f != null) _watch = _watchDir(f);
      _watchLume = _watchDir(importDir.path);
    }
    notifyListeners();
  }

  /// Se a escolhida está sendo observada (a do Lume é sempre que der).
  bool get watchingLume => _watchLume != null;

  StreamSubscription<FileSystemEvent>? _watchDir(String path) {
    if (!Directory(path).existsSync()) return null;
    try {
      return Directory(path).watch(events: FileSystemEvent.create | FileSystemEvent.delete | FileSystemEvent.move, recursive: true).listen((e) {
        if (!isBook(e.path) && e is! FileSystemMoveEvent) return;
        if (importing) return; // o import recarrega no fim
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 900), load);
      }, onError: (_) {});
    } catch (_) {
      // Sistema de arquivos sem suporte a observação: fica o "Atualizar pasta".
      return null;
    }
  }

  /// Import em andamento (o observador da pasta espera ele terminar).
  bool importing = false;

  /// Copia os arquivos para a pasta do Lume e recarrega a biblioteca.
  Future<List<ImportItem>> importFiles(List<String> paths, {void Function(ImportProgress)? onProgress}) async {
    importing = true;
    try {
      final items = await BookImporter(importDir).importAll(paths, onProgress: onProgress);
      await load();
      return items;
    } finally {
      importing = false;
    }
  }

  /// Um arquivo só (mesmo caminho do "Importar"): devolve o livro na biblioteca.
  Future<BookMeta> importFile(String path) async {
    final r = (await importFiles([path])).single;
    if (r.outcome == ImportOutcome.unsupported) throw EpubException('Formato não suportado');
    if (r.outcome == ImportOutcome.failed) throw EpubException(r.error ?? 'Erro ao copiar');
    final dest = r.dest!;
    return books.firstWhere((b) => b.meta.path == dest, orElse: () => LibraryBook(readMeta(dest), BookSource.imported)).meta;
  }

  /// Troca a pasta do Lume (ex.: depois de liberar o acesso, de
  /// Android/data/… para Documentos/Lume) levando os livros junto.
  Future<int> setLumeFolder(LumeFolder f, {bool useIsolate = true}) async {
    if (p.canonicalize(f.path) == p.canonicalize(importDir.path)) {
      lumeKind = f.kind;
      notifyListeners();
      return 0;
    }
    final moved = LumeFolder.migrate(importDir, f.dir, isBook);
    importDir = f.dir;
    lumeKind = f.kind;
    Store.lumeFolder = f.path;
    await load(useIsolate: useIsolate);
    watch();
    return moved;
  }

  @override
  void dispose() {
    _watch?.cancel();
    _watchLume?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
