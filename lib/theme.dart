import 'package:flutter/material.dart';

/// Design system do Lume: papel creme, tinta carvão-marrom, acento terracota.
class Lume {
  static const paper = Color(0xFFF6F0E4);
  static const card = Color(0xFFFBF7EF);
  static const ink = Color(0xFF2B2622);
  static const muted = Color(0xFF7D7166);
  static const line = Color(0xFFE6DCCB);
  static const accent = Color(0xFFB85C38); // terracota
  static const accentSoft = Color(0xFFF2DFD3);
  static const amber = Color(0xFFD9932F);
  static const ui = 'SourceSans3';
  static const serif = 'Literata';

  static TextStyle s(double size,
          {int w = 400, Color color = ink, double? h, double? ls, String family = ui, bool italic = false}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color,
        height: h,
        letterSpacing: ls,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontWeight: FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)],
        fontVariations: [FontVariation.weight(w.toDouble())],
      );

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: accent, surface: paper).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: amber,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: card,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: const Color(0xFFF1E8D8),
      surfaceContainerHighest: const Color(0xFFEDE3D1),
      secondaryContainer: accentSoft,
      onSecondaryContainer: ink,
      outline: const Color(0xFFCBBBA4),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: line)),
      ),
      dividerTheme: const DividerThemeData(color: line, space: 1),
      sliderTheme: const SliderThemeData(activeTrackColor: accent, thumbColor: accent, inactiveTrackColor: line),
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: card, surfaceTintColor: Colors.transparent, showDragHandle: true, dragHandleColor: line),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: ink, contentTextStyle: s(15, color: paper), behavior: SnackBarBehavior.floating),
      listTileTheme: ListTileThemeData(titleTextStyle: s(16.5, w: 600), subtitleTextStyle: s(14.5, color: muted)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : muted),
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

  const PageTheme(this.label, this.bg, this.ink, this.muted);
  final String label;
  final Color bg, ink, muted;
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
