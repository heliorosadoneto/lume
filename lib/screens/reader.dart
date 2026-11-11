import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../epub.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'appearance.dart';
import 'notes.dart';

/// Abre o livro (o EPUB é processado fora da thread de interface).
Future<void> openBook(BuildContext context, BookMeta meta) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final book = await compute(Epub.parseFile, meta.path);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Não foi possível abrir "${meta.title}": $e')));
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, this.now});
  final Book book;
  final DateTime Function()? now;
  @override
  State<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends State<ReaderScreen> {
  Book get book => widget.book;
  late ReaderSettings s = Store.settings;
  late List<Highlight> hls = Store.highlights(book.meta.id);
  late List<Bookmark> bms = Store.bookmarks(book.meta.id);
  final items = ItemScrollController();
  final offsets = ScrollOffsetController();
  final positions = ItemPositionsListener.create();
  late int current;
  late double initialAlign;
  double _viewport = 600;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final pos = Store.pos(book.meta.id);
    current = (pos?.block ?? 0).clamp(0, book.blocks.length - 1);
    initialAlign = (pos?.align ?? 0).clamp(-3.0, 0.9);
    positions.itemPositions.addListener(_onScroll);
    _save(initialAlign);
  }

  @override
  void dispose() {
    positions.itemPositions.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final vis = positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0.001).toList();
    if (vis.isEmpty) return;
    vis.sort((a, b) => a.index.compareTo(b.index));
    final top = vis.first;
    _save(top.itemLeadingEdge);
    if (top.index != current) setState(() => current = top.index);
  }

  void _save(double align) {
    final bottom = positions.itemPositions.value.fold<int>(current, (m, p) => p.index > m ? p.index : m);
    final percent = bottom >= book.blocks.length - 1 ? 1.0 : book.progressAt(current);
    Store.savePos(book.meta.id, ReadingPos(current, align, percent, _now()));
  }

  String get chapterTitle {
    final i = book.tocIndexFor(current);
    return i < 0 ? book.meta.title : book.toc[i].title;
  }

  void jumpTo(int block) {
    current = block;
    items.jumpTo(index: block, alignment: 0);
    setState(() {});
  }

  Future<void> _page(int dir) =>
      offsets.animateScroll(offset: dir * (_viewport - s.size * s.lineHeight * 1.5), duration: const Duration(milliseconds: 320), curve: Curves.easeInOutCubic);

  // ---------- destaques ----------
  List<Highlight> _hlsFor(int block) => hls.where((h) => h.block == block).toList();

  void _addHighlight(int block, TextSelection sel, HighlightColor color, {String note = ''}) {
    final text = book.blocks[block].text;
    final start = sel.start.clamp(0, text.length), end = sel.end.clamp(0, text.length);
    if (end <= start) return;
    final overlapping = hls.where((h) => h.block == block && h.start < end && h.end > start).toList();
    final keepNote = note.isNotEmpty ? note : overlapping.map((h) => h.note).where((n) => n.isNotEmpty).join(' ');
    setState(() {
      hls.removeWhere(overlapping.contains);
      hls.add(Highlight(
        id: '${_now().microsecondsSinceEpoch}',
        block: block,
        start: start,
        end: end,
        color: color,
        text: text.substring(start, end).trim(),
        note: keepNote,
        created: _now(),
      ));
    });
    Store.saveHighlights(book.meta.id, hls);
  }

  void _removeHighlights(int block, TextSelection sel) {
    setState(() => hls.removeWhere((h) => h.block == block && h.start < sel.end && h.end > sel.start));
    Store.saveHighlights(book.meta.id, hls);
  }

  Future<void> _noteFor(int block, TextSelection sel) async {
    final existing = hls.where((h) => h.block == block && h.start < sel.end && h.end > sel.start).firstOrNull;
    final note = await editNoteDialog(context, existing?.note ?? '');
    if (note == null) return;
    _addHighlight(block, sel, existing?.color ?? HighlightColor.amarelo, note: note);
  }

  bool get _bookmarked => bms.any((b) => b.block == current);

  void _toggleBookmark() {
    setState(() {
      if (_bookmarked) {
        bms.removeWhere((b) => b.block == current);
      } else {
        final t = book.blocks[current].text;
        bms.add(Bookmark(current, t.length > 140 ? '${t.substring(0, 140)}…' : t, _now()));
      }
    });
    Store.saveBookmarks(book.meta.id, bms);
  }

  // ---------- painéis ----------
  Future<void> openToc() async {
    final idx = book.tocIndexFor(current);
    final r = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TocSheet(book: book, currentIndex: idx),
    );
    if (r != null) jumpTo(r);
  }

  Future<void> openAppearance() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black12,
      builder: (_) => AppearanceSheet(
        settings: s,
        onChanged: (n) {
          setState(() => s = n);
          Store.settings = n;
        },
      ),
    );
  }

  Future<void> openNotes() async {
    final r = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => NotesScreen(book: book)));
    setState(() {
      hls = Store.highlights(book.meta.id);
      bms = Store.bookmarks(book.meta.id);
    });
    if (r != null) jumpTo(r);
  }

  // ---------- interface ----------
  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final progress = book.progressAt(current);
    final mins = book.minutesLeftInChapter(current);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Column(children: [
            _topBar(t),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                _viewport = c.maxHeight;
                return Stack(children: [
                  Positioned.fill(
                    child: ScrollablePositionedList.builder(
                      itemCount: book.blocks.length,
                      itemScrollController: items,
                      scrollOffsetController: offsets,
                      itemPositionsListener: positions,
                      initialScrollIndex: current,
                      initialAlignment: initialAlign,
                      padding: const EdgeInsets.only(top: 12, bottom: 48),
                      itemBuilder: (context, i) => _block(i, t),
                    ),
                  ),
                  if (s.pageMode) ...[
                    Positioned(left: 0, top: 0, bottom: 0, width: c.maxWidth * .16, child: _tapZone(-1)),
                    Positioned(right: 0, top: 0, bottom: 0, width: c.maxWidth * .16, child: _tapZone(1)),
                  ],
                ]);
              }),
            ),
            _bottomBar(t, progress, mins),
          ]),
        ),
      ),
    );
  }

  Widget _tapZone(int dir) => GestureDetector(
        key: ValueKey('page$dir'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _page(dir),
      );

  Widget _topBar(PageTheme t) {
    Widget btn(IconData i, String tip, VoidCallback f, {Color? color}) =>
        IconButton(icon: Icon(i, color: color ?? t.ink.withValues(alpha: .78)), tooltip: tip, onPressed: f);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(children: [
        btn(Icons.arrow_back_rounded, 'Biblioteca', () => Navigator.of(context).maybePop()),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(book.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(15.5, w: 650, color: t.ink)),
            Text(chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(13, color: t.muted)),
          ]),
        ),
        btn(Icons.toc_rounded, 'Sumário', openToc),
        btn(Icons.edit_note_rounded, 'Caderno', openNotes),
        btn(Icons.text_fields_rounded, 'Aparência', openAppearance),
        btn(_bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, 'Marcador', _toggleBookmark,
            color: _bookmarked ? Lume.accent : null),
      ]),
    );
  }

  Widget _bottomBar(PageTheme t, double progress, int mins) => Padding(
        padding: EdgeInsets.fromLTRB(s.hPad, 6, s.hPad, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ThinProgress(progress, height: 3, color: t.dark ? Lume.amber : Lume.accent, track: t.muted.withValues(alpha: .25)),
          const SizedBox(height: 8),
          Row(children: [
            Text('${pct(progress)} do livro', style: Lume.s(13, color: t.muted, w: 500)),
            const Spacer(),
            Text(mins <= 1 ? 'Menos de 1 min no capítulo' : '$mins min restantes no capítulo',
                style: Lume.s(13, color: t.muted)),
          ]),
        ]),
      );

  TextStyle get _bodyStyle => TextStyle(
        fontFamily: s.font.family,
        fontSize: s.size,
        height: s.lineHeight,
        color: s.theme.ink,
        fontVariations: const [FontVariation.weight(400)],
      );

  Widget _block(int i, PageTheme t) {
    final b = book.blocks[i];
    final pad = EdgeInsets.symmetric(horizontal: s.hPad);
    switch (b.kind) {
      case BlockKind.separator:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(child: Text('·  ·  ·', style: Lume.s(16, color: t.muted, ls: 2))),
        );
      case BlockKind.heading:
        final scale = b.level <= 2 ? 1.4 : (b.level <= 4 ? 1.18 : 0.95);
        return Padding(
          padding: pad.add(EdgeInsets.only(top: b.level <= 4 ? 10 : 18, bottom: 14)),
          child: _selectable(
            i,
            b,
            _bodyStyle.copyWith(
              fontSize: s.size * scale,
              height: 1.3,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation.weight(600)],
              letterSpacing: b.level >= 5 ? 1.5 : 0,
              color: b.level >= 5 ? t.muted : t.ink,
            ),
            TextAlign.center,
          ),
        );
      case BlockKind.paragraph:
        return Padding(
          padding: pad.add(EdgeInsets.only(bottom: s.size * 0.75)),
          child: _selectable(i, b, _bodyStyle, s.justify ? TextAlign.justify : TextAlign.start),
        );
    }
  }

  Widget _selectable(int i, Block b, TextStyle style, TextAlign align) {
    final spans = _spans(b, _hlsFor(i), style);
    return SelectableText.rich(
      TextSpan(children: spans, style: style),
      key: ValueKey('block$i'),
      textAlign: align,
      cursorColor: Lume.accent,
      selectionColor: s.theme.dark ? const Color(0x664A7FB0) : const Color(0x553C7DC4),
      contextMenuBuilder: (context, st) {
        final sel = st.textEditingValue.selection;
        if (!sel.isValid || sel.isCollapsed) return const SizedBox.shrink();
        final hasHl = hls.any((h) => h.block == i && h.start < sel.end && h.end > sel.start);
        void done() {
          st.hideToolbar();
          st.userUpdateTextEditingValue(
              st.textEditingValue.copyWith(selection: TextSelection.collapsed(offset: sel.end)), SelectionChangedCause.toolbar);
        }

        return HighlightToolbar(
          anchors: st.contextMenuAnchors,
          dark: s.theme.dark,
          canRemove: hasHl,
          onColor: (c) {
            done();
            _addHighlight(i, sel, c);
          },
          onNote: () {
            done();
            _noteFor(i, sel);
          },
          onCopy: () {
            Clipboard.setData(ClipboardData(text: b.text.substring(sel.start, sel.end)));
            done();
          },
          onRemove: () {
            done();
            _removeHighlights(i, sel);
          },
        );
      },
    );
  }

  List<InlineSpan> _spans(Block b, List<Highlight> hs, TextStyle base) {
    final len = b.text.length;
    final cuts = <int>{0, len};
    var o = 0;
    final runStarts = <int>[];
    for (final r in b.runs) {
      runStarts.add(o);
      o += r.text.length;
      cuts.add(o);
    }
    for (final h in hs) {
      cuts
        ..add(h.start.clamp(0, len))
        ..add(h.end.clamp(0, len));
    }
    final sorted = cuts.toList()..sort();
    final out = <InlineSpan>[];
    var ri = 0;
    for (var k = 0; k < sorted.length - 1; k++) {
      final a = sorted[k], z = sorted[k + 1];
      if (z <= a) continue;
      while (ri < b.runs.length - 1 && runStarts[ri + 1] <= a) {
        ri++;
      }
      final run = b.runs[ri];
      final h = hs.lastWhere((h) => h.start <= a && h.end >= z, orElse: () => _none);
      out.add(TextSpan(
        text: b.text.substring(a, z),
        style: TextStyle(
          fontStyle: run.italic ? FontStyle.italic : null,
          fontWeight: run.bold ? FontWeight.w700 : null,
          backgroundColor: identical(h, _none) ? null : h.color.on(s.theme),
          decoration: !identical(h, _none) && h.note.isNotEmpty ? TextDecoration.underline : null,
          decorationColor: Lume.accent,
          decorationThickness: 1.5,
        ),
      ));
    }
    return out;
  }

  static final _none =
      Highlight(id: '', block: -1, start: 0, end: 0, color: HighlightColor.amarelo, text: '', created: DateTime(2000));
}

/// Barra que aparece sobre o texto selecionado: 4 cores, nota, copiar.
class HighlightToolbar extends StatelessWidget {
  const HighlightToolbar(
      {super.key,
      required this.anchors,
      required this.onColor,
      required this.onNote,
      required this.onCopy,
      required this.onRemove,
      this.canRemove = false,
      this.dark = false});
  final TextSelectionToolbarAnchors anchors;
  final ValueChanged<HighlightColor> onColor;
  final VoidCallback onNote, onCopy, onRemove;
  final bool canRemove, dark;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    final fg = dark ? Lume.ink : const Color(0xFFF6F0E4);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, top, 12, 0),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchors.primaryAnchor - Offset(12, top + 12),
          anchorBelow: (anchors.secondaryAnchor ?? anchors.primaryAnchor) - Offset(12, top - 24),
        ),
        child: Material(
          key: const ValueKey('hl-toolbar'),
          color: dark ? const Color(0xFFEDE3D1) : Lume.ink,
          elevation: 8,
          shadowColor: Colors.black38,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final c in HighlightColor.values)
                Tooltip(
                  message: c.label,
                  child: InkResponse(
                    key: ValueKey('hl-${c.name}'),
                    onTap: () => onColor(c),
                    radius: 22,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                          color: c.color, shape: BoxShape.circle, border: Border.all(color: fg.withValues(alpha: .5), width: 1.5)),
                    ),
                  ),
                ),
              Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 6), color: fg.withValues(alpha: .25)),
              IconButton(
                  key: const ValueKey('hl-note'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Nota',
                  onPressed: onNote,
                  icon: Icon(Icons.sticky_note_2_outlined, color: fg)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copiar',
                  onPressed: onCopy,
                  icon: Icon(Icons.content_copy_rounded, size: 20, color: fg)),
              if (canRemove)
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remover destaque',
                    onPressed: onRemove,
                    icon: Icon(Icons.format_color_reset_outlined, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

class TocSheet extends StatelessWidget {
  const TocSheet({super.key, required this.book, required this.currentIndex});
  final Book book;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      maxChildSize: .94,
      builder: (context, ctrl) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sumário', style: Lume.s(22, w: 650, family: Lume.serif)),
                const SizedBox(height: 2),
                Text('${book.meta.title} · ${book.toc.length} capítulos', style: Lume.s(14, color: Lume.muted)),
              ]),
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            controller: ScrollController(initialScrollOffset: (currentIndex - 3).clamp(0, 1 << 20) * 52.0),
            itemCount: book.toc.length,
            itemExtent: 52,
            itemBuilder: (context, i) {
              final e = book.toc[i];
              final here = i == currentIndex;
              return InkWell(
                onTap: () => Navigator.pop(context, e.block),
                child: Container(
                  color: here ? Lume.accentSoft : null,
                  padding: EdgeInsets.only(left: 24.0 + e.depth * 16, right: 20),
                  child: Row(children: [
                    if (here) const Padding(padding: EdgeInsets.only(right: 10), child: Icon(Icons.circle, size: 8, color: Lume.accent)),
                    Expanded(
                      child: Text(e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Lume.s(16, w: here ? 650 : 450, family: Lume.serif, color: here ? Lume.accent : Lume.ink)),
                    ),
                    Text(pct(book.progressAt(e.block)), style: Lume.s(13, color: Lume.muted)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

Future<String?> editNoteDialog(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Lume.card,
      title: Text('Nota', style: Lume.s(20, w: 650, family: Lume.serif)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        decoration: const InputDecoration(hintText: 'O que este trecho te fez pensar?', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Salvar')),
      ],
    ),
  );
}
