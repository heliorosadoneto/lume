// Persistência local (SharedPreferences): posição de leitura, destaques,
// marcadores, preferências de leitura e a pasta escolhida.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

class ReadingPos {
  const ReadingPos(this.block, this.align, this.percent, this.opened);
  final int block;
  final double align, percent;
  final DateTime opened;
  Map<String, dynamic> toJson() => {'b': block, 'a': align, 'p': percent, 'o': opened.millisecondsSinceEpoch};
  static ReadingPos fromJson(Map<String, dynamic> j) => ReadingPos(j['b'] as int, (j['a'] as num).toDouble(),
      (j['p'] as num).toDouble(), DateTime.fromMillisecondsSinceEpoch(j['o'] as int));
}

class Highlight {
  Highlight(
      {required this.id,
      required this.block,
      required this.start,
      required this.end,
      required this.color,
      required this.text,
      this.note = '',
      required this.created});
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
  static Bookmark fromJson(Map<String, dynamic> j) =>
      Bookmark(j['b'] as int, j['x'] as String, DateTime.fromMillisecondsSinceEpoch(j['d'] as int));
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
  Map<String, dynamic> toJson() =>
      {'t': theme.name, 'f': font.name, 's': size, 'l': lineHeight, 'm': margin, 'j': justify, 'p': pageMode};
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

class Store {
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static ReadingPos? pos(String book) {
    final s = _p.getString('pos:$book');
    return s == null ? null : ReadingPos.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  static void savePos(String book, ReadingPos p) => _p.setString('pos:$book', jsonEncode(p.toJson()));

  static List<Highlight> highlights(String book) => [
        for (final j in jsonDecode(_p.getString('hl:$book') ?? '[]') as List) Highlight.fromJson(j as Map<String, dynamic>)
      ];
  static void saveHighlights(String book, List<Highlight> h) =>
      _p.setString('hl:$book', jsonEncode([for (final x in h) x.toJson()]));

  static List<Bookmark> bookmarks(String book) => [
        for (final j in jsonDecode(_p.getString('bm:$book') ?? '[]') as List) Bookmark.fromJson(j as Map<String, dynamic>)
      ];
  static void saveBookmarks(String book, List<Bookmark> b) =>
      _p.setString('bm:$book', jsonEncode([for (final x in b) x.toJson()]));

  static ReaderSettings get settings {
    final s = _p.getString('settings');
    return s == null ? ReaderSettings() : ReaderSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  static set settings(ReaderSettings s) => _p.setString('settings', jsonEncode(s.toJson()));

  static String? get folder => _p.getString('folder');
  static set folder(String? f) => f == null ? _p.remove('folder') : _p.setString('folder', f);

  static bool get watchFolder => _p.getBool('watch') ?? true;
  static set watchFolder(bool v) => _p.setBool('watch', v);

  static bool get seeded => _p.getBool('seeded') ?? false;
  static set seeded(bool v) => _p.setBool('seeded', v);
}
