import 'package:flutter/material.dart';

import '../epub.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'reader.dart' show editNoteDialog;

/// Caderno do livro: destaques (com notas) e marcadores. Tocar leva ao trecho.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.book, this.initialTab = 0});
  final Book book;
  final int initialTab;
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  Book get book => widget.book;
  late List<Highlight> hls = Store.highlights(book.meta.id);
  late List<Bookmark> bms = Store.bookmarks(book.meta.id);
  HighlightColor? filter;

  String _chapter(int block) {
    final i = book.tocIndexFor(block);
    return i < 0 ? 'Início' : book.toc[i].title;
  }

  void _saveH() => Store.saveHighlights(book.meta.id, hls);

  @override
  Widget build(BuildContext context) {
    final sortedH = [...hls]..sort((a, b) => a.block != b.block ? a.block.compareTo(b.block) : a.start.compareTo(b.start));
    final shown = sortedH.where((h) => filter == null || h.color == filter).toList();
    final sortedB = [...bms]..sort((a, b) => a.block.compareTo(b.block));
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Caderno', style: Lume.s(21, w: 650, family: Lume.serif)),
            Text(book.meta.title, style: Lume.s(13.5, color: Lume.muted)),
          ]),
          bottom: TabBar(
            labelStyle: Lume.s(15.5, w: 650),
            unselectedLabelStyle: Lume.s(15.5),
            labelColor: Lume.accent,
            unselectedLabelColor: Lume.muted,
            indicatorColor: Lume.accent,
            dividerColor: Lume.line,
            tabs: [Tab(text: 'Destaques (${hls.length})'), Tab(text: 'Marcadores (${bms.length})')],
          ),
        ),
        body: TabBarView(children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip(null, 'Todas'),
                  for (final c in HighlightColor.values) _chip(c, c.label),
                ]),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty) _empty('Nenhum destaque ainda', 'Selecione um trecho no livro e escolha uma cor.'),
              for (final h in shown) _highlightCard(h),
            ],
          ),
          sortedB.isEmpty
              ? ListView(padding: const EdgeInsets.all(16), children: [
                  _empty('Nenhum marcador', 'Toque no ícone de marcador no topo do leitor para guardar a página.'),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: sortedB.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final b = sortedB[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        leading: const Icon(Icons.bookmark_rounded, color: Lume.accent),
                        title: Text(_chapter(b.block)),
                        subtitle: Text(b.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(pct(book.progressAt(b.block)), style: Lume.s(13, color: Lume.muted)),
                        onTap: () => Navigator.pop(context, b.block),
                        onLongPress: () {
                          setState(() => bms.remove(b));
                          Store.saveBookmarks(book.meta.id, bms);
                        },
                      ),
                    );
                  },
                ),
        ]),
      ),
    );
  }

  Widget _chip(HighlightColor? c, String label) {
    final sel = filter == c;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: sel,
        showCheckmark: false,
        avatar: c == null ? null : CircleAvatar(backgroundColor: c.color, radius: 7),
        label: Text(label),
        labelStyle: Lume.s(14, w: sel ? 650 : 450, color: sel ? Lume.accent : Lume.ink),
        selectedColor: Lume.accentSoft,
        backgroundColor: Lume.card,
        side: BorderSide(color: sel ? Lume.accent.withValues(alpha: .4) : Lume.line),
        shape: const StadiumBorder(),
        onSelected: (_) => setState(() => filter = c),
      ),
    );
  }

  Widget _empty(String t, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(children: [
          const Icon(Icons.format_quote_rounded, size: 44, color: Lume.line),
          const SizedBox(height: 10),
          Text(t, style: Lume.s(18, w: 650, family: Lume.serif)),
          const SizedBox(height: 6),
          Text(sub, textAlign: TextAlign.center, style: Lume.s(15, color: Lume.muted)),
        ]),
      );

  Widget _highlightCard(Highlight h) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.pop(context, h.block),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 6, color: h.color.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 4, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_chapter(h.block).toUpperCase(),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(12, w: 650, color: Lume.muted, ls: .8)),
                      const SizedBox(height: 8),
                      Text('“${h.text}”', style: Lume.s(16.5, family: Lume.serif, h: 1.5)),
                      if (h.note.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(color: const Color(0xFFF1E8D8), borderRadius: BorderRadius.circular(10)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.sticky_note_2_outlined, size: 18, color: Lume.accent),
                            const SizedBox(width: 8),
                            Expanded(child: Text(h.note, style: Lume.s(14.5, h: 1.35))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(children: [
                        Text('${fmtDate(h.created)} · ${pct(book.progressAt(h.block))}', style: Lume.s(13, color: Lume.muted)),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz_rounded, color: Lume.muted),
                          color: Lume.card,
                          onSelected: (v) async {
                            if (v == 'note') {
                              final n = await editNoteDialog(context, h.note);
                              if (n == null) return;
                              setState(() => h.note = n);
                            } else if (v == 'del') {
                              setState(() => hls.remove(h));
                            } else {
                              setState(() => h.color = HighlightColor.values.byName(v));
                            }
                            _saveH();
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'note', child: Text(h.note.isEmpty ? 'Adicionar nota' : 'Editar nota')),
                            for (final c in HighlightColor.values)
                              if (c != h.color)
                                PopupMenuItem(
                                  value: c.name,
                                  child: Row(children: [
                                    CircleAvatar(radius: 7, backgroundColor: c.color),
                                    const SizedBox(width: 10),
                                    Text('Mudar para ${c.label.toLowerCase()}'),
                                  ]),
                                ),
                            const PopupMenuItem(value: 'del', child: Text('Excluir destaque')),
                          ],
                        ),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}
