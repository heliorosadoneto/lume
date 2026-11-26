import 'package:flutter/material.dart';

/// Cores do aplicativo: o normal (papel creme e terracota) ou preto e branco.
enum AppColors {
  normal('Normal'),
  bwLight('P&B claro'),
  bwDark('P&B escuro');

  const AppColors(this.label);
  final String label;
  bool get mono => this != normal;
}

class _Pal {
  const _Pal({
    required this.paper,
    required this.card,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.amber,
    required this.sheet,
    required this.chip,
    required this.danger,
    required this.tint,
    required this.tintLine,
    required this.tintInk,
    required this.cover,
    required this.coverInk,
    required this.high,
    required this.outline,
    required this.onAccent,
    this.dark = false,
  });
  final Color paper, card, ink, muted, line, accent, accentSoft, amber, sheet, chip, danger, tint, tintLine, tintInk, cover, coverInk, high, outline, onAccent;
  final bool dark;
}

const _normal = _Pal(
  paper: Color(0xFFF6F0E4), card: Color(0xFFFBF7EF), ink: Color(0xFF2B2622), muted: Color(0xFF7D7166), line: Color(0xFFE6DCCB), //
  accent: Color(0xFFB85C38), accentSoft: Color(0xFFF2DFD3), amber: Color(0xFFD9932F), sheet: Color(0xFFFBF6EC), chip: Color(0xFFF1E8D8),
  danger: Color(0xFFB3412E), tint: Color(0xFFF6E9DF), tintLine: Color(0xFFC9A78F), tintInk: Color(0xFF8F4A2C), cover: Color(0xFF6E4A35),
  coverInk: Color(0xFFF6E7CF), high: Color(0xFFEDE3D1), outline: Color(0xFFCBBBA4), onAccent: Colors.white,
);

const _bwLight = _Pal(
  paper: Color(0xFFF4F4F4), card: Color(0xFFFFFFFF), ink: Color(0xFF111111), muted: Color(0xFF6B6B6B), line: Color(0xFFD9D9D9), //
  accent: Color(0xFF111111), accentSoft: Color(0xFFE3E3E3), amber: Color(0xFF555555), sheet: Color(0xFFFFFFFF), chip: Color(0xFFEAEAEA),
  danger: Color(0xFF111111), tint: Color(0xFFECECEC), tintLine: Color(0xFFB0B0B0), tintInk: Color(0xFF333333), cover: Color(0xFF3A3A3A),
  coverInk: Color(0xFFF2F2F2), high: Color(0xFFE6E6E6), outline: Color(0xFFB5B5B5), onAccent: Colors.white,
);

const _bwDark = _Pal(
  paper: Color(0xFF0C0C0C), card: Color(0xFF1A1A1A), ink: Color(0xFFEDEDED), muted: Color(0xFF9B9B9B), line: Color(0xFF2E2E2E), //
  accent: Color(0xFFEDEDED), accentSoft: Color(0xFF2A2A2A), amber: Color(0xFFBDBDBD), sheet: Color(0xFF1A1A1A), chip: Color(0xFF262626),
  danger: Color(0xFFEDEDED), tint: Color(0xFF242424), tintLine: Color(0xFF555555), tintInk: Color(0xFFDDDDDD), cover: Color(0xFF2E2E2E),
  coverInk: Color(0xFFEEEEEE), high: Color(0xFF2A2A2A), outline: Color(0xFF4A4A4A), onAccent: Color(0xFF0C0C0C), dark: true,
);

/// Design system do Lume: papel creme, tinta carvão-marrom, acento terracota
/// (ou, em Ajustes, preto e branco). As cores seguem [colors].
class Lume {
  /// Cores atuais do aplicativo; ao mudar, a interface se refaz.
  static final ValueNotifier<AppColors> colors = ValueNotifier(AppColors.normal);
  static _Pal get _p => switch (colors.value) {
    AppColors.normal => _normal,
    AppColors.bwLight => _bwLight,
    AppColors.bwDark => _bwDark,
  };
  static bool get mono => colors.value.mono;
  static bool get darkUi => _p.dark;

  static Color get paper => _p.paper;
  static Color get card => _p.card;
  static Color get ink => _p.ink;
  static Color get muted => _p.muted;
  static Color get line => _p.line;
  static Color get accent => _p.accent; // terracota
  static Color get accentSoft => _p.accentSoft;
  static Color get amber => _p.amber;
  static Color get sheet => _p.sheet;
  static Color get chip => _p.chip;
  static Color get danger => _p.danger;
  static Color get tint => _p.tint;
  static Color get tintLine => _p.tintLine;
  static Color get tintInk => _p.tintInk;
  static Color get coverBg => _p.cover;
  static Color get coverInk => _p.coverInk;
  static Color get onAccent => _p.onAccent;
  static const ui = 'SourceSans3';
  static const serif = 'Literata';

  static TextStyle s(double size,
          {int w = 400, Color? color, double? h, double? ls, String family = ui, bool italic = false}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color ?? ink,
        height: h,
        letterSpacing: ls,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontWeight: FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)],
        fontVariations: [FontVariation.weight(w.toDouble())],
      );

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: accent, surface: paper, brightness: darkUi ? Brightness.dark : Brightness.light).copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: amber,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: card,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: chip,
      surfaceContainerHighest: _p.high,
      secondaryContainer: accentSoft,
      onSecondaryContainer: ink,
      outline: _p.outline,
      outlineVariant: line,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      fontFamily: ui,
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: s(20, w: 600),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: line)),
      ),
      dividerTheme: DividerThemeData(color: line, space: 1),
      sliderTheme: SliderThemeData(activeTrackColor: accent, thumbColor: accent, inactiveTrackColor: line),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: card, surfaceTintColor: Colors.transparent, showDragHandle: true, dragHandleColor: line),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: ink, contentTextStyle: s(15, color: paper), behavior: SnackBarBehavior.floating),
      listTileTheme: ListTileThemeData(titleTextStyle: s(16.5, w: 600), subtitleTextStyle: s(14.5, color: muted)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onAccent : muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : line),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}

/// Temas de página do leitor.
enum PageTheme {
  branco('Branco', Color(0xFFFCFBF8), Color(0xFF26231F), Color(0xFF8A8178)),
  sepia('Sépia', Color(0xFFF3E6CC), Color(0xFF4A3826), Color(0xFF8C735A)),
  verde('Verde claro', Color(0xFFE3EDDA), Color(0xFF2C3A2A), Color(0xFF6E7F68)),
  preto('Preto', Color(0xFF141311), Color(0xFFD8D0C2), Color(0xFF8E857A));

  const PageTheme(this.label, this._bg, this._ink, this._muted);
  final String label;
  final Color _bg, _ink, _muted;

  /// Em preto e branco, as páginas também ficam em tons de cinza.
  static Color _gray(Color c) {
    final y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    return Color.from(alpha: c.a, red: y, green: y, blue: y);
  }

  Color get bg => Lume.mono ? _gray(_bg) : _bg;
  Color get ink => Lume.mono ? _gray(_ink) : _ink;
  Color get muted => Lume.mono ? _gray(_muted) : _muted;
  bool get dark => this == preto;
}

/// Cores do marca-texto, como no Kindle.
enum HighlightColor {
  amarelo('Amarelo', Color(0xFFF6D86B)),
  laranja('Laranja', Color(0xFFF4B06A)),
  rosa('Rosa', Color(0xFFF1A6C2)),
  azul('Azul', Color(0xFF9DC7EC));

  const HighlightColor(this.label, this.color);
  final String label;
  final Color color;
  Color on(PageTheme t) => t.dark ? color.withValues(alpha: 0.55) : color.withValues(alpha: 0.75);
}

enum BookFont {
  literata('Literata', 'Literata'),
  lora('Lora', 'Lora'),
  sans('Source Sans', 'SourceSans3');

  const BookFont(this.label, this.family);
  final String label, family;
}

/// Filtro de cor para páginas de PDF: o branco do papel vira o fundo do tema e
/// o preto da tinta vira a cor do texto do tema (no Preto, a página se inverte).
ColorFilter? pdfPageFilter(PageTheme t) {
  if (t == PageTheme.branco) return null;
  double ch(Color c, int i) => [c.r, c.g, c.b][i] * 255;
  final m = <double>[];
  for (var i = 0; i < 3; i++) {
    final ink = ch(t.ink, i), bg = ch(t.bg, i);
    final row = [0.0, 0.0, 0.0, 0.0, ink];
    row[i] = (bg - ink) / 255;
    m.addAll(row);
  }
  m.addAll([0, 0, 0, 1, 0]);
  return ColorFilter.matrix(m);
}

/// Refaz toda a interface (as cores do [Lume] são lidas na hora de desenhar).
void rebuildAllElements() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
