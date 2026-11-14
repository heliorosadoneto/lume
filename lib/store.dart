// Persistência local (SharedPreferences): posição de leitura, destaques,
// marcadores, preferências de leitura, as pastas e os livros ocultos.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

class ReadingPos {
  const ReadingPos(this.block, this.align, this.percent, this.opened);
  final int block;
  final double align, percent;
  final DateTime opened;
  Map<String, dynamic> toJson() => {'b': block, 'a': align, 'p': percent, 'o': opened.millisecondsSinceEpoch};
  static ReadingPos fromJson(Map<String, dynamic> j) =>
      ReadingPos(j['b'] as int, (j['a'] as num).toDouble(), (j['p'] as num).toDouble(), DateTime.fromMillisecondsSinceEpoch(j['o'] as int));
}

class Highlight {
  Highlight({
    required this.id,
    required this.block,
    required this.start,
    required this.end,
    required this.color,
    required this.text,
    this.note = '',
    required this.created,
  });
  final String id;
  final int block, start, end;
  HighlightColor color;
  final String text;
  String note;
  final DateTime created;
  Map<String, dynamic> toJson() => {
    'id': id, 'b': block, 's': start, 'e': end, 'c': color.name, 't': text, 'n': note, //
    'd': created.millisecondsSinceEpoch,
  };
  static Highlight fromJson(Map<String, dynamic> j) => Highlight(
    id: j['id'] as String,
    block: j['b'] as int,
    start: j['s'] as int,
    end: j['e'] as int,
    color: HighlightColor.values.byName(j['c'] as String),
    text: j['t'] as String,
    note: (j['n'] as String?) ?? '',
    created: DateTime.fromMillisecondsSinceEpoch(j['d'] as int),
  );
}

class Bookmark {
  Bookmark(this.block, this.excerpt, this.created);
  final int block;
  final String excerpt;
  final DateTime created;
  Map<String, dynamic> toJson() => {'b': block, 'x': excerpt, 'd': created.millisecondsSinceEpoch};
  static Bookmark fromJson(Map<String, dynamic> j) => Bookmark(j['b'] as int, j['x'] as String, DateTime.fromMillisecondsSinceEpoch(j['d'] as int));
}

class ReaderSettings {
  ReaderSettings({
    this.theme = PageTheme.sepia,
    this.font = BookFont.literata,
    this.size = 19,
    this.lineHeight = 1.6,
    this.margin = 1,
    this.justify = true,
    this.pageMode = false,
  });
  PageTheme theme;
  BookFont font;
  double size, lineHeight;
  int margin; // 0 estreita, 1 média, 2 larga
  bool justify, pageMode;
  double get hPad => const [16.0, 26.0, 40.0][margin];
  Map<String, dynamic> toJson() => {'t': theme.name, 'f': font.name, 's': size, 'l': lineHeight, 'm': margin, 'j': justify, 'p': pageMode};
  static ReaderSettings fromJson(Map<String, dynamic> j) => ReaderSettings(
    theme: PageTheme.values.byName(j['t'] as String),
    font: BookFont.values.byName(j['f'] as String),
    size: (j['s'] as num).toDouble(),
    lineHeight: (j['l'] as num).toDouble(),
    margin: j['m'] as int,
    justify: j['j'] as bool,
    pageMode: j['p'] as bool,
  );
}

class HiddenBook {
  const HiddenBook(this.id, this.title, this.path, this.format);
  final String id, title, path, format;
  Map<String, dynamic> toJson() => {'id': id, 't': title, 'p': path, 'f': format};
  static HiddenBook fromJson(Map<String, dynamic> j) => HiddenBook(j['id'] as String, j['t'] as String, j['p'] as String, (j['f'] as String?) ?? 'epub');
}

class Store {
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static ReadingPos? pos(String book) {
    final s = _p.getString('pos:$book');
    return s == null ? null : ReadingPos.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  static void savePos(String book, ReadingPos p) => _p.setString('pos:$book', jsonEncode(p.toJson()));

  static List<Highlight> highlights(String book) => [
    for (final j in jsonDecode(_p.getString('hl:$book') ?? '[]') as List) Highlight.fromJson(j as Map<String, dynamic>),
  ];
  static void saveHighlights(String book, List<Highlight> h) => _p.setString('hl:$book', jsonEncode([for (final x in h) x.toJson()]));

  static List<Bookmark> bookmarks(String book) => [
    for (final j in jsonDecode(_p.getString('bm:$book') ?? '[]') as List) Bookmark.fromJson(j as Map<String, dynamic>),
  ];
  static void saveBookmarks(String book, List<Bookmark> b) => _p.setString('bm:$book', jsonEncode([for (final x in b) x.toJson()]));

  static ReaderSettings get settings {
    final s = _p.getString('settings');
    return s == null ? ReaderSettings() : ReaderSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  static set settings(ReaderSettings s) => _p.setString('settings', jsonEncode(s.toJson()));

  /// Número de páginas de um PDF (conhecido depois de gerar a capa ou abrir).
  static int? pages(String book) => _p.getInt('pages:$book');
  static void setPages(String book, int n) => _p.setInt('pages:$book', n);

  /// Leitor de PDF: rolagem contínua (false) ou página a página (true).
  static bool get pdfPaged => _p.getBool('pdfPaged') ?? false;
  static set pdfPaged(bool v) => _p.setBool('pdfPaged', v);

  /// Leitor de PDF: mostra as cores originais da página, sem o tom do tema.
  static bool get pdfOriginal => _p.getBool('pdfOriginal') ?? false;
  static set pdfOriginal(bool v) => _p.setBool('pdfOriginal', v);

  /// Leitor de PDF: corta as margens brancas das páginas.
  static bool get pdfCrop => _p.getBool('pdfCrop') ?? true;
  static set pdfCrop(bool v) => _p.setBool('pdfCrop', v);

  /// Modo do PDF: 'texto' (refeito em parágrafos) ou 'pagina' (original).
  /// Sem escolha salva, PDFs com texto abrem no modo texto.
  static String? pdfMode(String book) => _p.getString('pdfmode:$book');
  static void setPdfMode(String book, String mode) => _p.setString('pdfmode:$book', mode);

  /// Última pasta do Lume usada (para avisar se ela mudou de lugar).
  static String? get lumeFolder => _p.getString('lumeFolder');
  static set lumeFolder(String? v) => v == null ? _p.remove('lumeFolder') : _p.setString('lumeFolder', v);

  /// Outras pastas (além da do Lume), lidas onde estão, com subpastas.
  /// Até a 1.2 havia uma só ('folder'); ela entra na lista na primeira leitura.
  static List<String> get folders {
    final raw = _p.getString('folders');
    if (raw != null) return [for (final f in jsonDecode(raw) as List) f as String];
    final old = _p.getString('folder');
    final list = [?old];
    folders = list;
    _p.remove('folder');
    return list;
  }

  static set folders(List<String> l) => _p.setString('folders', jsonEncode(l));

  /// Livros tirados só da biblioteca (o arquivo continua no lugar): por id,
  /// com título, caminho e formato para a lista "Livros ocultos".
  static List<HiddenBook> get hidden => [for (final j in jsonDecode(_p.getString('hidden') ?? '[]') as List) HiddenBook.fromJson(j as Map<String, dynamic>)];
  static set hidden(List<HiddenBook> l) => _p.setString('hidden', jsonEncode([for (final h in l) h.toJson()]));

  /// Apaga tudo o que o Lume guardou sobre um livro (posição, destaques,
  /// notas, marcadores, páginas e modo do PDF).
  static void forget(String book) {
    for (final k in ['pos', 'hl', 'bm', 'pages', 'pdfmode']) {
      _p.remove('$k:$book');
    }
  }

  static bool get watchFolder => _p.getBool('watch') ?? true;
  static set watchFolder(bool v) => _p.setBool('watch', v);

  static bool get seeded => _p.getBool('seeded') ?? false;
  static set seeded(bool v) => _p.setBool('seeded', v);
}
