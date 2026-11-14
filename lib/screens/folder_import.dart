// Escolher uma pasta de livros: explica a permissão do Android, abre o seletor
// de pastas e mostra o progresso enquanto o Lume procura EPUBs e PDFs na pasta e
// em todas as subpastas.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../library.dart';
import '../theme.dart';
import '../widgets.dart';

/// No Android 11+ ler arquivos de uma pasta qualquer (e das subpastas) exige
/// "Acesso a todos os arquivos". Antes de pedir, o Lume explica o motivo.
Future<bool> ensureStorageAccess(BuildContext context) async {
  if (!Platform.isAndroid) return true;
  if (await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(context: context, builder: (_) => const StorageAccessDialog());
  if (ok != true) return false;
  final r = await Permission.manageExternalStorage.request();
  if (r.isGranted) return true;
  return (await Permission.storage.request()).isGranted;
}

class StorageAccessDialog extends StatelessWidget {
  const StorageAccessDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Lume.card,
    icon: const Icon(Icons.folder_special_rounded, color: Lume.accent, size: 34),
    title: Text('Ler a sua pasta de livros', style: Lume.s(21, w: 650, family: Lume.serif)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Para encontrar os PDFs e EPUBs da pasta que você escolher, inclusive nas subpastas, '
          'o Android pede a permissão “Acesso a todos os arquivos”.',
          style: Lume.s(15.5, h: 1.4),
        ),
        const SizedBox(height: 12),
        for (final t in [
          'O Lume só abre arquivos .pdf, .epub, .txt e .md.',
          'Nada sai do celular: o app não usa internet.',
          'Você pode tirar a permissão nos ajustes do Android.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_rounded, size: 18, color: Lume.accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t, style: Lume.s(14.5, color: Lume.muted, h: 1.3)),
                ),
              ],
            ),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Agora não')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
    ],
  );
}

/// Fluxo completo: permissão → seletor de pasta → leitura com progresso.
Future<void> chooseFolder(BuildContext context, Library lib) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await ensureStorageAccess(context)) {
    messenger.showSnackBar(const SnackBar(content: Text('Sem permissão para ler a pasta. Libere o acesso aos arquivos.')));
    return;
  }
  final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Pasta de livros', initialDirectory: lib.folder);
  if (dir == null || !context.mounted) return;
  await showFolderScan(context, lib, () => lib.setFolder(dir));
}

/// Lê a pasta de novo (pega arquivos novos e tira os que sumiram).
Future<void> rescanFolder(BuildContext context, Library lib) => showFolderScan(context, lib, lib.load);

Future<void> showFolderScan(BuildContext context, Library lib, Future<void> Function() run) => showModalBottomSheet<void>(
  context: context,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => FolderScanSheet(library: lib, run: run),
);

class FolderScanSheet extends StatefulWidget {
  const FolderScanSheet({super.key, required this.library, this.run});
  final Library library;
  final Future<void> Function()? run;
  @override
  State<FolderScanSheet> createState() => _FolderScanSheetState();
}

class _FolderScanSheetState extends State<FolderScanSheet> {
  Library get lib => widget.library;
  bool started = false;

  @override
  void initState() {
    super.initState();
    if (widget.run != null) {
      started = true;
      widget.run!();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: AnimatedSize(duration: const Duration(milliseconds: 220), alignment: Alignment.topCenter, child: lib.scanning ? _progress() : _result(context)),
    ),
  );

  Widget _folderLine() => Row(
    children: [
      const Icon(Icons.folder_rounded, color: Lume.accent, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          friendlyPath(lib.folder ?? ''),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Lume.s(14, color: Lume.muted),
        ),
      ),
    ],
  );

  Widget _progress() {
    final total = lib.scanTotal, done = lib.scanDone;
    return Column(
      key: const ValueKey('scan-progress'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LumeMark(size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total == 0 ? 'Procurando livros…' : 'Encontrados $total ${total == 1 ? 'livro' : 'livros'}…',
                    style: Lume.s(21, w: 650, family: Lume.serif),
                  ),
                  const SizedBox(height: 2),
                  Text('Na pasta e em todas as subpastas', style: Lume.s(14, color: Lume.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _folderLine(),
        const SizedBox(height: 14),
        ThinProgress(total == 0 ? 0 : done / total, height: 6),
        const SizedBox(height: 8),
        Text(total == 0 ? 'Olhando as subpastas…' : 'Lendo título e capa · $done de $total', style: Lume.s(13.5, color: Lume.muted)),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final inFolder = lib.books.where((b) => b.source == BookSource.folder).toList();
    final pdf = inFolder.where((b) => b.meta.isPdf).length;
    final epub = inFolder.length - pdf;
    final subs = inFolder.map((b) => b.subfolder).whereType<String>().toSet().length;
    final r = lib.report;
    Widget row(IconData i, String label, String value, {Color color = Lume.ink}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(i, size: 20, color: Lume.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Lume.s(15.5))),
          Text(value, style: Lume.s(15.5, w: 650, color: color)),
        ],
      ),
    );
    return Column(
      key: const ValueKey('scan-result'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: Lume.accentSoft, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Lume.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${inFolder.length} ${inFolder.length == 1 ? 'livro' : 'livros'} na pasta', style: Lume.s(21, w: 650, family: Lume.serif)),
                  const SizedBox(height: 2),
                  Text(lib.watching ? 'Pasta lembrada · atualiza sozinha' : 'Pasta lembrada · use “Atualizar pasta”', style: Lume.s(14, color: Lume.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _folderLine(),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 4),
        row(Icons.picture_as_pdf_outlined, 'PDF', '$pdf'),
        row(Icons.menu_book_outlined, 'EPUB', '$epub'),
        row(Icons.account_tree_outlined, 'Subpastas com livros', '$subs'),
        if (r.duplicates > 0) row(Icons.copy_all_outlined, 'Repetidos (ignorados)', '${r.duplicates}', color: Lume.muted),
        if (r.failed > 0) row(Icons.error_outline_rounded, 'Não abriram', '${r.failed}', color: Lume.accent),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(key: const ValueKey('scan-done'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Ver biblioteca')),
        ),
      ],
    );
  }
}
