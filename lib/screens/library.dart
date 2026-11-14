import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../epub.dart';
import '../library.dart';
import '../theme.dart';
import '../widgets.dart';
import 'delete_books.dart';
import 'folder_import.dart';
import 'import_books.dart';
import 'reader.dart';
import 'settings.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.library});
  final Library library;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Library get lib => widget.library;
  BookFormat? filter; // null = todos

  /// Livros marcados no modo de seleção (toque longo), por id.
  final selected = <String>{};
  bool get selecting => selected.isNotEmpty;

  void _toggle(LibraryBook b) => setState(() => selected.contains(b.meta.id) ? selected.remove(b.meta.id) : selected.add(b.meta.id));

  Future<void> _deleteSelected() async {
    final list = [
      for (final b in lib.books)
        if (selected.contains(b.meta.id)) b,
    ];
    if (await deleteBooks(context, lib, list) && mounted) setState(selected.clear);
  }

  Future<void> _bookMenu(LibraryBook b, String action) async {
    switch (action) {
      case 'open':
        await _open(b);
      case 'select':
        _toggle(b);
      case 'delete':
        await deleteBooks(context, lib, [b]);
    }
  }

  late final AppLifecycleListener _life = AppLifecycleListener(onResume: () => lib.load());

  @override
  void initState() {
    super.initState();
    _life;
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _open(LibraryBook b) async {
    await openBook(context, b.meta);
    if (mounted) setState(() {}); // atualiza progresso e "Continuar leitura"
  }

  Future<void> _import() => importBooks(context, lib);

  Future<void> _add() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => AddBooksSheet(folders: lib.folders),
    );
    if (!mounted) return;
    switch (r) {
      case 'file':
        await _import();
      case 'folder':
        await chooseFolder(context, lib);
      case 'rescan':
        await rescanFolder(context, lib);
    }
  }

  void _settings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(library: lib)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final cont = lib.continueReading;
        final pdfs = lib.books.where((b) => b.meta.isPdf).length;
        final txts = lib.books.where((b) => b.meta.format == BookFormat.txt).length;
        final mds = lib.books.where((b) => b.meta.format == BookFormat.md).length;
        final epubs = lib.books.length - pdfs - txts - mds;
        final shown = filter == null ? lib.books : lib.books.where((b) => b.meta.format == filter).toList();
        selected.removeWhere((id) => !lib.books.any((b) => b.meta.id == id));
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(selected.clear);
          },
          child: Scaffold(
            floatingActionButton: selecting
                ? null
                : FloatingActionButton.extended(
                    key: const ValueKey('import-fab'),
                    onPressed: _import,
                    backgroundColor: Lume.accent,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shape: const StadiumBorder(),
                    icon: const Icon(Icons.file_download_outlined),
                    label: Text('Importar', style: Lume.s(16, w: 650, color: Colors.white)),
                  ),
            appBar: selecting
                ? _selectionBar(shown)
                : AppBar(
                    titleSpacing: 20,
                    title: Row(
                      children: [
                        const LumeMark(size: 30),
                        const SizedBox(width: 12),
                        Text('Lume', style: Lume.s(26, w: 650, family: Lume.serif)),
                      ],
                    ),
                    actions: [
                      if (lib.folders.isNotEmpty)
                        IconButton(tooltip: 'Atualizar pastas', onPressed: () => rescanFolder(context, lib), icon: const Icon(Icons.sync_rounded)),
                      IconButton(tooltip: 'Adicionar livros', onPressed: _add, icon: const Icon(Icons.add_rounded)),
                      IconButton(tooltip: 'Ajustes', onPressed: _settings, icon: const Icon(Icons.tune_rounded)),
                      const SizedBox(width: 8),
                    ],
                  ),
            body: RefreshIndicator(
              color: Lume.accent,
              onRefresh: lib.load,
              child: CustomScrollView(
                slivers: [
                  if (cont.isNotEmpty) ...[
                    const SliverToBoxAdapter(child: SectionLabel('Continuar leitura', padding: EdgeInsets.fromLTRB(20, 8, 20, 12))),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 176,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: cont.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (context, i) => _ContinueCard(book: cont[i], onTap: () => _open(cont[i])),
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: SectionLabel(
                      'Biblioteca',
                      trailing: lib.scanning
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Lume.accent))
                          : Text('${lib.books.length} ${lib.books.length == 1 ? 'livro' : 'livros'}', style: Lume.s(14, color: Lume.muted)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _FolderBanner(library: lib, onTap: _settings),
                  ),
                  if ([pdfs, txts, mds, epubs].where((n) => n > 0).length > 1)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final (f, label, n) in [
                              (null, 'Todos', lib.books.length),
                              if (pdfs > 0) (BookFormat.pdf, 'PDF', pdfs),
                              if (epubs > 0) (BookFormat.epub, 'EPUB', epubs),
                              if (txts > 0) (BookFormat.txt, 'TXT', txts),
                              if (mds > 0) (BookFormat.md, 'MD', mds),
                            ])
                              ChoiceChip(
                                key: ValueKey('filter-${f?.name ?? 'todos'}'),
                                label: Text('$label · $n'),
                                selected: filter == f,
                                showCheckmark: false,
                                labelStyle: Lume.s(14, w: 600, color: filter == f ? Lume.accent : Lume.ink),
                                selectedColor: Lume.accentSoft,
                                backgroundColor: Lume.card,
                                side: BorderSide(color: filter == f ? Lume.accent.withValues(alpha: .4) : Lume.line),
                                shape: const StadiumBorder(),
                                onSelected: (_) => setState(() => filter = f),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (lib.loaded && lib.books.isEmpty)
                    SliverToBoxAdapter(
                      child: _EmptyLibrary(onFolder: () => chooseFolder(context, lib), onImport: _import),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                      sliver: SliverList.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _BookTile(
                          book: shown[i],
                          selecting: selecting,
                          selected: selected.contains(shown[i].meta.id),
                          onTap: () => selecting ? _toggle(shown[i]) : _open(shown[i]),
                          onLongPress: () => _toggle(shown[i]),
                          onMenu: (a) => _bookMenu(shown[i], a),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _selectionBar(List<LibraryBook> shown) {
    final all = shown.isNotEmpty && shown.every((b) => selected.contains(b.meta.id));
    return AppBar(
      key: const ValueKey('selection-bar'),
      backgroundColor: Lume.accentSoft,
      leading: IconButton(
        key: const ValueKey('select-cancel'),
        tooltip: 'Cancelar',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(selected.clear),
      ),
      titleSpacing: 0,
      title: Text(selected.length == 1 ? '1 selecionado' : '${selected.length} selecionados', style: Lume.s(20, w: 650)),
      actions: [
        IconButton(
          key: const ValueKey('select-all'),
          tooltip: all ? 'Desmarcar todos' : 'Selecionar todos',
          icon: Icon(all ? Icons.deselect_rounded : Icons.select_all_rounded),
          onPressed: () => setState(() => all ? selected.clear() : selected.addAll(shown.map((b) => b.meta.id))),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: FilledButton.icon(
            key: const ValueKey('select-delete'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3412E)),
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            label: const Text('Apagar'),
          ),
        ),
      ],
    );
  }
}

class _FolderBanner extends StatelessWidget {
  const _FolderBanner({required this.library, required this.onTap});
  final Library library;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final fs = library.folders;
    final f = fs.isEmpty ? null : (fs.length == 1 ? p.basename(fs.single) : '${fs.length} outras pastas');
    final inFolder = library.books.where((b) => b.source == BookSource.folder).length;
    final inLume = library.books.length - inFolder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: const Color(0xFFF1E8D8),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, color: Lume.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f == null ? 'Pasta do Lume: ${lumeFolderLabel(library)}' : 'Pastas: Lume e $f',
                        style: Lume.s(14.5, w: 650),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        f == null
                            ? '$inLume ${inLume == 1 ? 'livro' : 'livros'} · importe ou coloque arquivos nela'
                            : '$inLume na pasta do Lume · $inFolder em ${fs.length == 1 ? '$f e subpastas' : 'outras pastas'}',
                        style: Lume.s(13, color: Lume.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Lume.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book, required this.onTap});
  final LibraryBook book;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final pos = book.pos!;
    return SizedBox(
      width: 300,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                BookCover(cover: book.meta.cover, title: book.meta.title, width: 96),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.meta.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Lume.s(17, w: 650, family: Lume.serif, h: 1.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        book.meta.author.isEmpty ? 'PDF' : book.meta.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Lume.s(14, color: Lume.muted),
                      ),
                      const Spacer(),
                      Text('${pct(pos.percent)} lido', style: Lume.s(13.5, w: 650, color: Lume.accent)),
                      const SizedBox(height: 6),
                      ThinProgress(pos.percent),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 18, color: Lume.ink),
                          const SizedBox(width: 2),
                          Text('Continuar', style: Lume.s(14, w: 650)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap, required this.onLongPress, required this.onMenu, this.selecting = false, this.selected = false});
  final LibraryBook book;
  final VoidCallback onTap, onLongPress;
  final ValueChanged<String> onMenu;
  final bool selecting, selected;
  @override
  Widget build(BuildContext context) {
    final pos = book.pos;
    return InkWell(
      key: ValueKey('book-${book.meta.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(color: selected ? Lume.accentSoft : null, borderRadius: BorderRadius.circular(12)),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: selecting ? 8 : 0),
        child: Row(
          children: [
            if (selecting) ...[
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                key: ValueKey('check-${book.meta.id}'),
                color: selected ? Lume.accent : Lume.line,
                size: 26,
              ),
              const SizedBox(width: 10),
            ],
            BookCover(cover: book.meta.cover, title: book.meta.title, width: 58, radius: 6),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.meta.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Lume.s(17, w: 650, family: Lume.serif, h: 1.25),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [if (book.meta.author.isNotEmpty) book.meta.author, if (book.meta.isPdf && book.pages != null) '${book.pages} páginas'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Lume.s(14.5, color: Lume.muted),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FormatBadge(book.meta.format),
                      const SizedBox(width: 8),
                      Icon(book.source == BookSource.folder ? Icons.folder_outlined : Icons.bookmarks_outlined, size: 15, color: Lume.muted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          book.place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Lume.s(13, color: Lume.muted),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (pos == null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Lume.accentSoft, borderRadius: BorderRadius.circular(20)),
                          child: Text('Novo', style: Lume.s(12.5, w: 650, color: Lume.accent)),
                        )
                      else ...[
                        SizedBox(width: 70, child: ThinProgress(pos.percent, height: 3)),
                        const SizedBox(width: 8),
                        Text(pct(pos.percent), style: Lume.s(13, color: Lume.muted)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!selecting)
              PopupMenuButton<String>(
                key: ValueKey('menu-${book.meta.id}'),
                tooltip: 'Mais opções',
                icon: const Icon(Icons.more_vert_rounded, color: Lume.muted),
                color: Lume.card,
                onSelected: onMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: ListTile(leading: Icon(Icons.menu_book_rounded), title: Text('Abrir')),
                  ),
                  const PopupMenuItem(
                    value: 'select',
                    child: ListTile(leading: Icon(Icons.check_circle_outline_rounded), title: Text('Selecionar')),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded, color: Color(0xFFB3412E)),
                      title: Text('Apagar…'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onFolder, required this.onImport});
  final VoidCallback onFolder, onImport;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
    child: Column(
      children: [
        const LumeMark(size: 64),
        const SizedBox(height: 18),
        Text('Sua estante está vazia', style: Lume.s(21, w: 650, family: Lume.serif)),
        const SizedBox(height: 8),
        Text(
          'Importe seus PDFs, EPUBs, TXTs e Markdown para a pasta do Lume ou escolha uma pasta onde eles já estão (o Lume olha as subpastas também).',
          textAlign: TextAlign.center,
          style: Lume.s(15.5, color: Lume.muted),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.file_download_outlined), label: const Text('Importar livros')),
        TextButton(onPressed: onFolder, child: const Text('Escolher outra pasta')),
      ],
    ),
  );
}

/// Etiqueta pequena com o formato do livro.
class FormatBadge extends StatelessWidget {
  const FormatBadge(this.format, {super.key});
  final BookFormat format;
  @override
  Widget build(BuildContext context) {
    final pdf = format == BookFormat.pdf;
    final label = switch (format) {
      BookFormat.pdf => 'PDF',
      BookFormat.epub => 'EPUB',
      BookFormat.txt => 'TXT',
      BookFormat.md => 'MD',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: pdf ? const Color(0xFFC9A78F) : Lume.line),
        color: pdf ? const Color(0xFFF6E9DF) : null,
      ),
      child: Text(label, style: Lume.s(11, w: 700, ls: .6, color: pdf ? const Color(0xFF8F4A2C) : Lume.muted)),
    );
  }
}

/// Opções do botão +: um arquivo, uma pasta inteira ou atualizar a pasta.
class AddBooksSheet extends StatelessWidget {
  const AddBooksSheet({super.key, this.folders = const []});
  final List<String> folders;
  @override
  Widget build(BuildContext context) {
    Widget opt(String key, IconData i, String title, String sub) => ListTile(
      key: ValueKey('add-$key'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: Lume.accentSoft, borderRadius: BorderRadius.circular(12)),
        child: Icon(i, color: Lume.accent),
      ),
      title: Text(title),
      subtitle: Text(sub),
      onTap: () => Navigator.pop(context, key),
    );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Adicionar livros', style: Lume.s(22, w: 650, family: Lume.serif)),
          ),
          opt('file', Icons.file_download_outlined, 'Importar livros', 'PDF, EPUB, TXT ou Markdown (vários de uma vez), copiados para a pasta do Lume'),
          opt(
            'folder',
            Icons.create_new_folder_outlined,
            folders.isEmpty ? 'Usar outra pasta' : 'Adicionar outra pasta',
            'Lê os livros onde já estão, sem copiar (com subpastas)',
          ),
          if (folders.isNotEmpty)
            opt(
              'rescan',
              Icons.sync_rounded,
              folders.length == 1 ? 'Atualizar pasta' : 'Atualizar pastas',
              'Procura livros novos em ${folders.length == 1 ? p.basename(folders.single) : 'todas as pastas'}',
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
