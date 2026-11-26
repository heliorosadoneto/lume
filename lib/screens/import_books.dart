// "Importar": escolhe vários arquivos no seletor do Android e copia para a
// pasta do Lume, com progresso e um resumo no fim.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../importer.dart';
import '../library.dart';
import '../lume_folder.dart';
import '../theme.dart';
import '../widgets.dart';

/// Nome curto da pasta do Lume para mostrar na interface.
String lumeFolderLabel(Library lib) => switch (lib.lumeKind) {
  LumeFolderKind.documents => 'Documentos/Lume',
  LumeFolderKind.appExternal => 'Android/data/com.helio.lume/files/Livros',
  LumeFolderKind.internal => 'pasta interna do app',
};

/// Depois de liberar o acesso: passa a pasta do Lume para Documentos/Lume
/// (levando os livros), se ainda não estiver lá.
Future<void> moveToDocuments(BuildContext context, Library lib) async {
  if (!Platform.isAndroid || lib.lumeKind == LumeFolderKind.documents) return;
  final messenger = ScaffoldMessenger.of(context);
  final ext = (await getExternalStorageDirectory())?.path;
  final f = LumeFolder.resolve(appExternal: ext, internal: lib.importDir.path);
  if (f.kind != LumeFolderKind.documents) {
    messenger.showSnackBar(const SnackBar(content: Text('O Android ainda não deixou criar Documentos/Lume.')));
    return;
  }
  final moved = await lib.setLumeFolder(f);
  messenger.showSnackBar(SnackBar(content: Text('Pasta do Lume agora em Documentos/Lume${moved > 0 ? ' ($moved livros movidos)' : ''}')));
}

Future<void> importBooks(BuildContext context, Library lib) async {
  // No Android, .md e .markdown não têm tipo MIME conhecido e o filtro do
  // seletor os esconderia; lá ele mostra tudo e o Lume ignora o que não lê.
  final files = Platform.isAndroid
      ? await FilePicker.pickFiles(dialogTitle: 'Importar livros (PDF, EPUB, TXT ou Markdown)', type: FileType.any)
      : await FilePicker.pickFiles(dialogTitle: 'Importar livros (PDF, EPUB, TXT ou Markdown)', type: FileType.custom, allowedExtensions: bookExtensions);
  final paths = files.map((f) => f.path).whereType<String>().toList();
  if (paths.isEmpty || !context.mounted) return;
  await showImport(context, lib, paths);
}

Future<void> showImport(BuildContext context, Library lib, List<String> paths) => showModalBottomSheet<void>(
  context: context,
  isDismissible: false,
  enableDrag: false,
  isScrollControlled: true,
  builder: (_) => ImportSheet(library: lib, paths: paths),
);

class ImportSheet extends StatefulWidget {
  const ImportSheet({super.key, required this.library, required this.paths, this.autoStart = true});
  final Library library;
  final List<String> paths;
  final bool autoStart;
  @override
  State<ImportSheet> createState() => ImportSheetState();
}

class ImportSheetState extends State<ImportSheet> {
  ImportProgress? progress;
  List<ImportItem>? items;

  /// Mostra um estado pronto (usado nos prints de teste).
  @visibleForTesting
  void show({ImportProgress? progress, List<ImportItem>? items}) => setState(() {
    this.progress = progress ?? this.progress;
    this.items = items ?? this.items;
  });

  @override
  void initState() {
    super.initState();
    progress = ImportProgress(0, widget.paths.length, widget.paths.isEmpty ? '' : widget.paths.first.split('/').last, 0, 0);
    if (widget.autoStart) _run();
  }

  Future<void> _run() async {
    final r = await widget.library.importFiles(
      widget.paths,
      onProgress: (p) {
        if (mounted) setState(() => progress = p);
      },
    );
    if (mounted) setState(() => items = r);
  }

  static String mb(int b) => b < 1024 * 1024 ? '${(b / 1024).ceil()} KB' : '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: AnimatedSize(duration: const Duration(milliseconds: 220), alignment: Alignment.topCenter, child: items == null ? _progress() : _result(context)),
    ),
  );

  Widget _dest() => Row(
    children: [
      Icon(Icons.folder_rounded, color: Lume.accent, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Para ${lumeFolderLabel(widget.library)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Lume.s(14, color: Lume.muted),
        ),
      ),
    ],
  );

  Widget _progress() {
    final pr = progress!;
    final n = pr.total, i = (pr.index + 1).clamp(1, n == 0 ? 1 : n);
    return Column(
      key: const ValueKey('import-progress'),
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
                  Text(n == 1 ? 'Importando 1 livro…' : 'Importando $i de $n…', style: Lume.s(21, w: 650, family: Lume.serif)),
                  const SizedBox(height: 2),
                  Text(
                    pr.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Lume.s(14, color: Lume.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _dest(),
        const SizedBox(height: 14),
        ThinProgress(pr.fraction, height: 6),
        const SizedBox(height: 8),
        Text(pr.bytesTotal == 0 ? 'Preparando…' : '${mb(pr.bytesDone)} de ${mb(pr.bytesTotal)} copiados', style: Lume.s(13.5, color: Lume.muted)),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final r = items!;
    final added = r.where((x) => x.outcome == ImportOutcome.added).length;
    final dup = r.where((x) => x.outcome == ImportOutcome.duplicate).length;
    String title;
    if (added > 0) {
      title = added == 1 ? '1 livro importado' : '$added livros importados';
    } else if (dup > 0) {
      title = 'Já estavam na pasta';
    } else {
      title = 'Nada foi importado';
    }
    (IconData, Color, String) status(ImportItem x) => switch (x.outcome) {
      ImportOutcome.added => (Icons.check_circle_rounded, Lume.accent, 'Importado'),
      ImportOutcome.duplicate => (Icons.copy_all_outlined, Lume.muted, 'Já estava na pasta'),
      ImportOutcome.unsupported => (Icons.block_rounded, Lume.muted, 'Formato não suportado'),
      ImportOutcome.failed => (Icons.error_outline_rounded, Lume.accent, 'Não foi possível copiar'),
    };
    return Column(
      key: const ValueKey('import-result'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Lume.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: Lume.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Lume.s(21, w: 650, family: Lume.serif)),
                  const SizedBox(height: 2),
                  Text(
                    dup > 0 && added > 0 ? '$dup ${dup == 1 ? 'já estava' : 'já estavam'} na pasta (ignorados)' : 'Já aparecem na biblioteca',
                    style: Lume.s(14, color: Lume.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _dest(),
        const SizedBox(height: 8),
        const Divider(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final x in r)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(status(x).$1, size: 20, color: status(x).$2),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(x.dest == null ? x.name : x.dest!.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(15)),
                            Text(status(x).$3, style: Lume.s(13, color: Lume.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(key: const ValueKey('import-done'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Ver biblioteca')),
        ),
      ],
    );
  }
}
