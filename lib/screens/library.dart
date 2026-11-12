
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../epub.dart';
import '../library.dart';
import '../theme.dart';
import '../widgets.dart';
import 'folder_import.dart';
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

  Future<void> _import() async {
    final f = await FilePicker.pickFile(
        dialogTitle: 'Importar livro (EPUB ou PDF)', type: FileType.custom, allowedExtensions: Library.extensions);
    if (f?.path == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final m = await lib.importFile(f!.path!);
      messenger.showSnackBar(SnackBar(content: Text('“${m.title}” foi adicionado à biblioteca')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível importar: $e')));
    }
  }

  Future<void> _add() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => AddBooksSheet(folder: lib.folder),
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
        final shown = filter == null ? lib.books : lib.books.where((b) => b.meta.format == filter).toList();
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(children: [
              const LumeMark(size: 30),
              const SizedBox(width: 12),
              Text('Lume', style: Lume.s(26, w: 650, family: Lume.serif)),
            ]),
            actions: [
              if (lib.folder != null)
                IconButton(
                    tooltip: 'Atualizar pasta', onPressed: () => rescanFolder(context, lib), icon: const Icon(Icons.sync_rounded)),
              IconButton(tooltip: 'Adicionar livros', onPressed: _add, icon: const Icon(Icons.add_rounded)),
              IconButton(tooltip: 'Ajustes', onPressed: _settings, icon: const Icon(Icons.tune_rounded)),
              const SizedBox(width: 8),
            ],
          ),
          body: RefreshIndicator(
            color: Lume.accent,
            onRefresh: lib.load,
            child: CustomScrollView(slivers: [
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
                      : Text('${lib.books.length} ${lib.books.length == 1 ? 'livro' : 'livros'}',
                          style: Lume.s(14, color: Lume.muted)),
                ),
              ),
              SliverToBoxAdapter(child: _FolderBanner(library: lib, onTap: () => lib.folder == null ? chooseFolder(context, lib) : _settings())),
              if (pdfs > 0 && pdfs < lib.books.length)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Wrap(spacing: 8, children: [
                      for (final (f, label, n) in [
                        (null, 'Todos', lib.books.length),
                        (BookFormat.pdf, 'PDF', pdfs),
                        (BookFormat.epub, 'EPUB', lib.books.length - pdfs),
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
                    ]),
                  ),
                ),
              if (lib.loaded && lib.books.isEmpty)
                SliverToBoxAdapter(child: _EmptyLibrary(onFolder: () => chooseFolder(context, lib), onImport: _import))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _BookTile(book: shown[i], onTap: () => _open(shown[i])),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _FolderBanner extends StatelessWidget {
  const _FolderBanner({required this.library, required this.onTap});
  final Library library;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final f = library.folder;
    final inFolder = library.books.where((b) => b.source == BookSource.folder).length;
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
            child: Row(children: [
              Icon(f == null ? Icons.create_new_folder_outlined : Icons.folder_rounded, color: Lume.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f == null ? 'Escolha uma pasta de livros' : 'Pasta: ${p.basename(f)}',
                      style: Lume.s(14.5, w: 650), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    f == null
                        ? 'O Lume mostra os PDFs e EPUBs dela e das subpastas'
                        : '$inFolder ${inFolder == 1 ? 'livro' : 'livros'} na pasta e subpastas${library.watching ? ' · atualiza sozinho' : ''}',
                    style: Lume.s(13, color: Lume.muted),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Lume.muted),
            ]),
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
            child: Row(children: [
              BookCover(cover: book.meta.cover, title: book.meta.title, width: 96),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(book.meta.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: Lume.s(17, w: 650, family: Lume.serif, h: 1.2)),
                  const SizedBox(height: 4),
                  Text(book.meta.author.isEmpty ? 'PDF' : book.meta.author,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(14, color: Lume.muted)),
                  const Spacer(),
                  Text('${pct(pos.percent)} lido', style: Lume.s(13.5, w: 650, color: Lume.accent)),
                  const SizedBox(height: 6),
                  ThinProgress(pos.percent),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.play_arrow_rounded, size: 18, color: Lume.ink),
                    const SizedBox(width: 2),
                    Text('Continuar', style: Lume.s(14, w: 650)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap});
  final LibraryBook book;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final pos = book.pos;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          BookCover(cover: book.meta.cover, title: book.meta.title, width: 58, radius: 6),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book.meta.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: Lume.s(17, w: 650, family: Lume.serif, h: 1.25)),
              const SizedBox(height: 3),
              Text(
                  [
                    if (book.meta.author.isNotEmpty) book.meta.author,
                    if (book.meta.isPdf && book.pages != null) '${book.pages} páginas',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Lume.s(14.5, color: Lume.muted)),
              const SizedBox(height: 10),
              Row(children: [
                FormatBadge(book.meta.format),
                const SizedBox(width: 8),
                Icon(book.source == BookSource.folder ? Icons.folder_outlined : Icons.download_done_rounded,
                    size: 15, color: Lume.muted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    book.source == BookSource.folder ? (book.subfolder == null ? 'Pasta' : p.basename(book.subfolder!)) : 'Importado',
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
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Lume.line),
        ]),
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
        child: Column(children: [
          const LumeMark(size: 64),
          const SizedBox(height: 18),
          Text('Sua estante está vazia', style: Lume.s(21, w: 650, family: Lume.serif)),
          const SizedBox(height: 8),
          Text('Escolha a pasta onde ficam seus PDFs e EPUBs (o Lume olha as subpastas também) ou importe um arquivo.',
              textAlign: TextAlign.center, style: Lume.s(15.5, color: Lume.muted)),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onFolder, icon: const Icon(Icons.folder_open_rounded), label: const Text('Escolher pasta')),
          TextButton(onPressed: onImport, child: const Text('Importar arquivo')),
        ]),
      );
}


/// Etiqueta pequena com o formato do livro.
class FormatBadge extends StatelessWidget {
  const FormatBadge(this.format, {super.key});
  final BookFormat format;
  @override
  Widget build(BuildContext context) {
    final pdf = format == BookFormat.pdf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: pdf ? const Color(0xFFC9A78F) : Lume.line),
        color: pdf ? const Color(0xFFF6E9DF) : null,
      ),
      child: Text(pdf ? 'PDF' : 'EPUB', style: Lume.s(11, w: 700, ls: .6, color: pdf ? const Color(0xFF8F4A2C) : Lume.muted)),
    );
  }
}

/// Opções do botão +: um arquivo, uma pasta inteira ou atualizar a pasta.
class AddBooksSheet extends StatelessWidget {
  const AddBooksSheet({super.key, this.folder});
  final String? folder;
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
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Adicionar livros', style: Lume.s(22, w: 650, family: Lume.serif)),
        ),
        opt('folder', Icons.create_new_folder_outlined, folder == null ? 'Escolher pasta' : 'Trocar pasta',
            'Todos os PDFs e EPUBs da pasta e das subpastas'),
        if (folder != null) opt('rescan', Icons.sync_rounded, 'Atualizar pasta', 'Procura livros novos em ${p.basename(folder!)}'),
        opt('file', Icons.upload_file_rounded, 'Importar arquivo', 'Um PDF ou EPUB, copiado para o Lume'),
        const SizedBox(height: 12),
      ]),
    );
  }
}
