// Biblioteca: livros da pasta do Lume (Documentos/Lume, para onde o "Importar"
// copia) + livros das outras pastas escolhidas pelo usuário (e de todas as
// subpastas), com atualização automática. Aceita EPUB, PDF, TXT e Markdown.
// Livros podem ser tirados só da biblioteca (lista de ocultos) ou apagados.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'epub.dart';
import 'importer.dart';
import 'lume_folder.dart';
import 'pdf.dart';
import 'pdf_analysis.dart';
import 'store.dart';
import 'markdown_book.dart';
import 'txt.dart';

enum BookSource { folder, imported }

class LibraryBook {
  LibraryBook(this.meta, this.source, {this.subfolder, this.root});
  final BookMeta meta;
  final BookSource source;

  /// Subpasta (relativa à pasta escolhida ou à do Lume) onde o arquivo está.
  final String? subfolder;

  /// Pasta da lista de onde o livro veio (null = pasta do Lume).
  final String? root;

  /// Etiqueta curta na lista: subpasta, nome da pasta ou "Lume".
  String get place => subfolder != null ? p.basename(subfolder!) : (root != null ? p.basename(root!) : 'Lume');
  ReadingPos? get pos => Store.pos(meta.id);
  int? get pages => Store.pages(meta.id);
}

/// Resumo da última leitura da pasta.
class ScanReport {
  const ScanReport({this.epub = 0, this.pdf = 0, this.txt = 0, this.md = 0, this.failed = 0, this.duplicates = 0});
  final int epub, pdf, txt, md, failed, duplicates;
  int get total => epub + pdf + txt + md;
}

typedef _MetaResult = ({List<BookMeta> metas, List<String> failed});

/// Resultado de "Apagar o arquivo também".
class DeleteResult {
  DeleteResult(this.deleted, this.failed, this.otherCopies);
  final List<LibraryBook> deleted;

  /// Livros cujo arquivo o Android não deixou apagar, com o motivo.
  final List<(LibraryBook, String)> failed;

  /// Apagados que ainda têm outra cópia idêntica em alguma pasta (continuam na lista).
  final List<LibraryBook> otherCopies;
}

class Library extends ChangeNotifier {
  Library(
    this.importDir, {
    Directory? coversDir,
    this.textCacheDir,
    this.renderPdfCovers = true,
    this.lumeKind = LumeFolderKind.internal,
    this.legacyDirs = const [],
  }) : covers = PdfCovers(coversDir ?? Directory(p.join(importDir.parent.path, 'capas')));

  /// Cache do texto dos PDFs (modo texto), limpo quando o arquivo é apagado.
  final Directory? textCacheDir;

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
  final _watches = <StreamSubscription<FileSystemEvent>>[];
  StreamSubscription<FileSystemEvent>? _watchLume;
  Timer? _debounce;
  Future<void>? _coversJob;

  /// Todos os caminhos encontrados de cada livro (cópias idênticas incluídas).
  Map<String, List<String>> _paths = {};

  /// Outras pastas (além da do Lume), na ordem em que foram adicionadas.
  List<String> get folders => Store.folders;

  /// A primeira das outras pastas (compatibilidade com telas de uma pasta só).
  String? get folder => folders.firstOrNull;

  /// Pasta que acabou de ser adicionada (mostrada na leitura com progresso).
  String? lastAdded;
  bool get watching => _watches.isNotEmpty;

  /// Livros tirados só da biblioteca.
  List<HiddenBook> get hidden => Store.hidden;

  /// Quantos livros (já sem repetidos e ocultos) vieram de uma pasta da lista.
  int countIn(String folder) => books.where((b) => b.root == folder).length;
  int get countInLume => books.where((b) => b.root == null).length;

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

  /// Lista os arquivos: outras pastas e pasta do Lume (com subpastas) e as
  /// pastas antigas de importados. Um caminho aparece uma vez só, mesmo se
  /// uma pasta estiver dentro de outra.
  static List<String> _list((String, List<String>, List<String>) dirs) =>
      {for (final f in dirs.$2) ..._booksIn(f, true), ..._booksIn(dirs.$1, true), for (final d in dirs.$3) ..._booksIn(d, false)}.toList();

  /// Pasta da lista que contém o arquivo (a mais funda, se uma estiver dentro de outra).
  String? rootOf(String path) {
    String? best;
    for (final f in folders) {
      if (p.isWithin(f, path) && (best == null || f.length > best.length)) best = f;
    }
    if (best != null && p.isWithin(importDir.path, path) && importDir.path.length > best.length) return null;
    return best;
  }

  static _MetaResult _metas((List<String>, String) args) {
    final metas = <BookMeta>[];
    final failed = <String>[];
    final covers = PdfCovers(Directory(args.$2));
    for (final path in args.$1) {
      try {
        if (TxtBook.isTxt(path)) {
          metas.add(TxtBook.readMeta(path));
        } else if (MarkdownBook.isMarkdown(path)) {
          metas.add(MarkdownBook.readMeta(path));
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
    final args = (importDir.path, folders, [for (final d in legacyDirs) d.path]);
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

    // Mesmo livro em dois lugares (ou em duas pastas) conta uma vez só. Vale o
    // da primeira pasta da lista (antes dos importados) e, entre cópias na mesma
    // pasta, o arquivo que não parece cópia ("x (1).pdf").
    final byId = <String, BookMeta>{};
    final copies = <String, List<String>>{};
    var dups = 0;
    for (final m in metas) {
      (copies[m.id] ??= []).add(m.path);
      final prev = byId[m.id];
      if (prev == null) {
        byId[m.id] = m;
        continue;
      }
      dups++;
      final sameSource = rootOf(prev.path) == rootOf(m.path);
      if (sameSource && looksLikeCopy(prev.path) && !looksLikeCopy(m.path)) byId[m.id] = m;
    }
    _paths = copies;
    final hiddenIds = {for (final h in Store.hidden) h.id};
    final list = <LibraryBook>[];
    for (final m in byId.values) {
      if (hiddenIds.contains(m.id)) continue;
      final root = rootOf(m.path);
      String? sub;
      final base = root ?? (p.isWithin(importDir.path, m.path) ? importDir.path : null);
      if (base != null) {
        final rel = p.dirname(p.relative(m.path, from: base));
        sub = rel == '.' ? null : rel;
      }
      list.add(LibraryBook(m, root != null ? BookSource.folder : BookSource.imported, subfolder: sub, root: root));
    }
    list.sort((a, b) => a.meta.title.toLowerCase().compareTo(b.meta.title.toLowerCase()));
    books = list;
    failed = fails;
    report = ScanReport(
      epub: list.where((b) => b.meta.format == BookFormat.epub).length,
      pdf: list.where((b) => b.meta.isPdf).length,
      txt: list.where((b) => b.meta.format == BookFormat.txt).length,
      md: list.where((b) => b.meta.format == BookFormat.md).length,
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

  /// Troca todas as outras pastas por uma só (ou nenhuma).
  Future<void> setFolder(String? path, {bool useIsolate = true, bool watchIt = true}) async {
    Store.folders = [?path];
    lastAdded = path;
    await load(useIsolate: useIsolate);
    if (watchIt) watch();
  }

  /// Adiciona uma pasta à lista (se já estiver, só relê).
  Future<void> addFolder(String path, {bool useIsolate = true, bool watchIt = true}) async {
    final norm = p.normalize(path);
    final l = folders;
    if (!l.any((f) => p.equals(f, norm)) && !p.equals(norm, importDir.path)) Store.folders = [...l, norm];
    lastAdded = norm;
    await load(useIsolate: useIsolate);
    if (watchIt) watch();
  }

  /// Tira a pasta da lista: os livros dela saem da biblioteca, os arquivos ficam.
  Future<void> removeFolder(String path, {bool useIsolate = true, bool watchIt = true}) async {
    Store.folders = [
      for (final f in folders)
        if (!p.equals(f, path)) f,
    ];
    if (lastAdded != null && p.equals(lastAdded!, path)) lastAdded = null;
    await load(useIsolate: useIsolate);
    if (watchIt) watch();
  }

  // ---------- tirar da biblioteca e apagar ----------

  /// Tira os livros só da biblioteca: os arquivos ficam e não voltam ao ler a pasta.
  void hide(List<LibraryBook> list) {
    final ids = {for (final b in list) b.meta.id};
    final keep = [
      for (final h in Store.hidden)
        if (!ids.contains(h.id)) h,
    ];
    Store.hidden = [...keep, for (final b in list) HiddenBook(b.meta.id, b.meta.title, b.meta.path, b.meta.format.name)];
    books = [
      for (final b in books)
        if (!ids.contains(b.meta.id)) b,
    ];
    notifyListeners();
  }

  /// Volta a mostrar livros ocultos (desfazer ou "Livros ocultos" nos Ajustes).
  Future<void> unhide(Iterable<String> ids, {bool useIsolate = true}) async {
    final set = ids.toSet();
    Store.hidden = [
      for (final h in Store.hidden)
        if (!set.contains(h.id)) h,
    ];
    await load(useIsolate: useIsolate);
  }

  /// Se o arquivo está na pasta do Lume (que o app sempre pode apagar).
  bool inLume(LibraryBook b) => p.isWithin(importDir.path, b.meta.path);

  /// Apaga os arquivos do celular e o que o Lume guardou deles (posição,
  /// destaques, notas, marcadores, capa e texto do PDF).
  Future<DeleteResult> deleteFiles(List<LibraryBook> list, {bool useIsolate = true}) async {
    final deleted = <LibraryBook>[];
    final failed = <(LibraryBook, String)>[];
    final copies = <LibraryBook>[];
    importing = true; // o observador da pasta espera
    try {
      for (final b in list) {
        try {
          final f = File(b.meta.path);
          if (f.existsSync()) await f.delete();
          deleted.add(b);
        } on FileSystemException catch (e) {
          failed.add((b, _why(e)));
          continue;
        }
        final others = [
          for (final x in _paths[b.meta.id] ?? const <String>[])
            if (x != b.meta.path && File(x).existsSync()) x,
        ];
        if (others.isNotEmpty) {
          copies.add(b);
          continue;
        }
        Store.forget(b.meta.id);
        Store.hidden = [
          for (final h in Store.hidden)
            if (h.id != b.meta.id) h,
        ];
        for (final c in [covers.fileFor(b.meta.id), if (textCacheDir != null) PdfAnalyzer(textCacheDir!).fileFor(b.meta.id)]) {
          try {
            if (c.existsSync()) c.deleteSync();
          } catch (_) {}
        }
      }
      await load(useIsolate: useIsolate);
    } finally {
      importing = false;
    }
    return DeleteResult(deleted, failed, copies);
  }

  static String _why(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (code == 1 || code == 13 || code == 30) {
      return 'o Android não deu permissão para apagar nesta pasta';
    }
    return e.osError?.message ?? e.message;
  }

  /// Observa as pastas (as da lista e a do Lume) e recarrega quando um livro
  /// é adicionado ou removido, inclusive pelo gerenciador de arquivos.
  void watch() {
    for (final w in _watches) {
      w.cancel();
    }
    _watches.clear();
    _watchLume?.cancel();
    _watchLume = null;
    if (Store.watchFolder) {
      for (final f in folders) {
        final w = _watchDir(f);
        if (w != null) _watches.add(w);
      }
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
    for (final w in _watches) {
      w.cancel();
    }
    _watchLume?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
