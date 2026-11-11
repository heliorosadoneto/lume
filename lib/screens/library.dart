
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../library.dart';
import '../theme.dart';
import '../widgets.dart';
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
    final f = await FilePicker.pickFile(dialogTitle: 'Importar EPUB', type: FileType.custom, allowedExtensions: ['epub']);
    if (f?.path == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final m = await lib.importFile(f!.path!);
      messenger.showSnackBar(SnackBar(content: Text('“${m.title}” foi adicionado à biblioteca')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível importar: $e')));
    }
  }

  void _settings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(library: lib)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final cont = lib.continueReading;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(children: [
              const LumeMark(size: 30),
              const SizedBox(width: 12),
              Text('Lume', style: Lume.s(26, w: 650, family: Lume.serif)),
            ]),
            actions: [
              IconButton(tooltip: 'Importar EPUB', onPressed: _import, icon: const Icon(Icons.add_rounded)),
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
              SliverToBoxAdapter(child: _FolderBanner(library: lib, onTap: _settings)),
              if (lib.loaded && lib.books.isEmpty)
                SliverToBoxAdapter(child: _EmptyLibrary(onFolder: _settings, onImport: _import))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  sliver: SliverList.separated(
                    itemCount: lib.books.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _BookTile(book: lib.books[i], onTap: () => _open(lib.books[i])),
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
                        ? 'O Lume mostra aqui os EPUBs que estiverem nela'
                        : '$inFolder EPUB${inFolder == 1 ? '' : 's'} na pasta${library.watching ? ' · atualiza sozinho' : ''}',
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
                  Text(book.meta.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(14, color: Lume.muted)),
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
              Text(book.meta.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(14.5, color: Lume.muted)),
              const SizedBox(height: 10),
              Row(children: [
                Icon(book.source == BookSource.folder ? Icons.folder_outlined : Icons.download_done_rounded,
                    size: 15, color: Lume.muted),
                const SizedBox(width: 4),
                Text(book.source == BookSource.folder ? 'Pasta' : 'Importado', style: Lume.s(13, color: Lume.muted)),
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
          Text('Escolha a pasta onde ficam seus EPUBs ou importe um arquivo.',
              textAlign: TextAlign.center, style: Lume.s(15.5, color: Lume.muted)),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onFolder, icon: const Icon(Icons.folder_open_rounded), label: const Text('Escolher pasta')),
          TextButton(onPressed: onImport, child: const Text('Importar EPUB')),
        ]),
      );
}

