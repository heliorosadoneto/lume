import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';

/// Ajustes de leitura: tema da página, fonte, tamanho, entrelinha, margens,
/// alinhamento e modo (rolagem ou virar página).
class AppearancePanel extends StatelessWidget {
  const AppearancePanel({super.key, required this.settings, required this.onChanged});
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  ReaderSettings get s => settings;
  void _set(void Function(ReaderSettings) f) {
    f(s);
    onChanged(s);
  }

  Widget _label(String t, [String? value]) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(children: [
          Text(t, style: Lume.s(15, w: 650)),
          const Spacer(),
          if (value != null) Text(value, style: Lume.s(14, color: Lume.muted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _label('Tema da página'),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final t in PageTheme.values)
          GestureDetector(
            key: ValueKey('theme-${t.name}'),
            onTap: () => _set((s) => s.theme = t),
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: s.theme == t ? Lume.accent : Lume.line, width: s.theme == t ? 3 : 1.5),
                ),
                child: Text('Aa', style: TextStyle(fontFamily: 'Literata', fontSize: 20, color: t.ink)),
              ),
              const SizedBox(height: 6),
              Text(t.label, style: Lume.s(13, w: s.theme == t ? 650 : 400, color: s.theme == t ? Lume.accent : Lume.muted)),
            ]),
          ),
      ]),
      _label('Fonte'),
      SegmentedButton<BookFont>(
        showSelectedIcon: false,
        segments: [
          for (final f in BookFont.values)
            ButtonSegment(value: f, label: Text(f.label, style: TextStyle(fontFamily: f.family, fontSize: 15))),
        ],
        selected: {s.font},
        onSelectionChanged: (v) => _set((s) => s.font = v.first),
      ),
      _label('Tamanho do texto', '${s.size.round()} pt'),
      Row(children: [
        Text('A', style: Lume.s(14, color: Lume.muted, family: Lume.serif)),
        Expanded(
          child: Slider(value: s.size, min: 14, max: 28, divisions: 14, onChanged: (v) => _set((s) => s.size = v)),
        ),
        Text('A', style: Lume.s(24, color: Lume.muted, family: Lume.serif)),
      ]),
      _label('Espaçamento entre linhas', s.lineHeight.toStringAsFixed(1).replaceAll('.', ',')),
      Slider(value: s.lineHeight, min: 1.3, max: 2.0, divisions: 7, onChanged: (v) => _set((s) => s.lineHeight = v)),
      _label('Margens'),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: Text('Estreitas')),
          ButtonSegment(value: 1, label: Text('Médias')),
          ButtonSegment(value: 2, label: Text('Largas')),
        ],
        selected: {s.margin},
        onSelectionChanged: (v) => _set((s) => s.margin = v.first),
      ),
      _label('Alinhamento'),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, icon: Icon(Icons.format_align_justify_rounded), label: Text('Justificado')),
          ButtonSegment(value: false, icon: Icon(Icons.format_align_left_rounded), label: Text('À esquerda')),
        ],
        selected: {s.justify},
        onSelectionChanged: (v) => _set((s) => s.justify = v.first),
      ),
      _label('Modo de leitura'),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.swap_vert_rounded), label: Text('Rolagem')),
          ButtonSegment(value: true, icon: Icon(Icons.auto_stories_outlined), label: Text('Virar página')),
        ],
        selected: {s.pageMode},
        onSelectionChanged: (v) => _set((s) => s.pageMode = v.first),
      ),
      if (s.pageMode)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Toque na borda direita ou esquerda da tela para avançar ou voltar.',
              style: Lume.s(13.5, color: Lume.muted)),
        ),
    ]);
  }
}

class AppearanceSheet extends StatefulWidget {
  const AppearanceSheet({super.key, required this.settings, required this.onChanged});
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  @override
  State<AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<AppearanceSheet> {
  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Aparência', style: Lume.s(22, w: 650, family: Lume.serif)),
            AppearancePanel(
              settings: widget.settings,
              onChanged: (s) {
                setState(() {});
                widget.onChanged(s);
              },
            ),
          ]),
        ),
      );
}
