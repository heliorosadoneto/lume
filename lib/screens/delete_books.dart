// Apagar livros: confirmação com duas escolhas (tirar só da biblioteca ou
// apagar o arquivo também), desfazer, aviso quando o Android não deixa apagar
// e a lista de "Livros ocultos" dos Ajustes.
import 'package:flutter/material.dart';

import '../epub.dart';
import '../library.dart';
import '../theme.dart';
import '../widgets.dart';

enum DeleteChoice { hide, file }

class DeleteBooksDialog extends StatefulWidget {
  const DeleteBooksDialog({super.key, required this.books, required this.library});
  final List<LibraryBook> books;
  final Library library;
  @override
  State<DeleteBooksDialog> createState() => DeleteBooksDialogState();
}

class DeleteBooksDialogState extends State<DeleteBooksDialog> {
  DeleteChoice choice = DeleteChoice.hide;

  @override
  Widget build(BuildContext context) {
    final n = widget.books.length;
    final outside = widget.books.where((b) => !widget.library.inLume(b)).length;
    final what = n == 1 ? '“${widget.books.single.meta.title}”' : '$n livros';
    Widget option(DeleteChoice c, IconData icon, String title, String sub, {Color? color}) {
      final on = choice == c;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: on ? (color ?? Lume.accent).withValues(alpha: .08) : Lume.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: on ? (color ?? Lume.accent).withValues(alpha: .6) : Lume.line, width: on ? 1.6 : 1),
          ),
          child: InkWell(
            key: ValueKey('delete-${c.name}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => choice = c),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: on ? (color ?? Lume.accent) : Lume.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 18, color: color ?? Lume.ink),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(title, style: Lume.s(15.5, w: 650, color: color ?? Lume.ink)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(sub, style: Lume.s(13.5, color: Lume.muted, h: 1.35)),
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

    return AlertDialog(
      key: const ValueKey('delete-dialog'),
      backgroundColor: Lume.sheet,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: Text('Apagar $what?', style: Lume.s(20, w: 650, family: Lume.serif, h: 1.25)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            option(
              DeleteChoice.hide,
              Icons.visibility_off_outlined,
              'Tirar só da biblioteca',
              'O arquivo continua no celular e não volta sozinho. Dá para mostrar de novo em Ajustes → Livros ocultos.',
            ),
            option(
              DeleteChoice.file,
              Icons.delete_outline_rounded,
              'Apagar o arquivo também',
              'Some do celular, junto com o progresso, os destaques e as notas. Não dá para desfazer.',
              color: Lume.danger,
            ),
            if (outside > 0)
              Container(
                key: const ValueKey('delete-note'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Lume.chip, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: Lume.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${outside == n ? (n == 1 ? 'Este livro está' : 'Estes livros estão') : '$outside deles estão'} fora da pasta do Lume. '
                        'Para apagar o arquivo lá, o Android precisa do “Acesso a todos os arquivos”; os da pasta do Lume sempre podem ser apagados.',
                        style: Lume.s(13, color: Lume.muted, h: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const ValueKey('delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: choice == DeleteChoice.file ? Lume.danger : Lume.accent),
          onPressed: () => Navigator.pop(context, choice),
          child: Text(choice == DeleteChoice.file ? 'Apagar arquivo${n == 1 ? '' : 's'}' : 'Tirar da biblioteca'),
        ),
      ],
    );
  }
}

/// Pergunta, faz o que foi escolhido e avisa (com "Desfazer" quando é só tirar da biblioteca).
Future<bool> deleteBooks(BuildContext context, Library lib, List<LibraryBook> books) async {
  if (books.isEmpty) return false;
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showDialog<DeleteChoice>(
    context: context,
    builder: (_) => DeleteBooksDialog(books: books, library: lib),
  );
  if (choice == null || !context.mounted) return false;
  final n = books.length;
  if (choice == DeleteChoice.hide) {
    lib.hide(books);
    final ids = [for (final b in books) b.meta.id];
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('undo-snack'),
        content: Text(n == 1 ? '“${books.single.meta.title}” saiu da biblioteca' : '$n livros saíram da biblioteca'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Desfazer', onPressed: () => lib.unhide(ids)),
      ),
    );
    return true;
  }
  final r = await lib.deleteFiles(books);
  if (!context.mounted) return true;
  final ok = r.deleted.length;
  messenger.hideCurrentSnackBar();
  if (ok > 0) {
    final copies = r.otherCopies.isEmpty ? '' : ' (${r.otherCopies.length} ainda tem outra cópia em outra pasta)';
    messenger.showSnackBar(SnackBar(content: Text('${ok == 1 ? '1 arquivo apagado' : '$ok arquivos apagados'}$copies')));
  }
  if (r.failed.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-failed'),
        backgroundColor: Lume.sheet,
        title: Text(
          r.failed.length == 1 ? 'Não foi possível apagar 1 arquivo' : 'Não foi possível apagar ${r.failed.length} arquivos',
          style: Lume.s(19, w: 650, family: Lume.serif),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (b, why) in r.failed.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• ${b.meta.title}: $why', style: Lume.s(14.5, h: 1.35)),
              ),
            const SizedBox(height: 4),
            Text(
              'Fora da pasta do Lume, o Android só deixa apagar com o “Acesso a todos os arquivos” liberado. '
              'Libere em Ajustes → Pasta do Lume → Liberar acesso, apague pelo gerenciador de arquivos ou tire o livro só da biblioteca.',
              style: Lume.s(13.5, color: Lume.muted, h: 1.4),
            ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
      ),
    );
  }
  return true;
}

/// Ajustes → Livros ocultos: os que foram tirados só da biblioteca.
class HiddenBooksScreen extends StatefulWidget {
  const HiddenBooksScreen({super.key, required this.library});
  final Library library;
  @override
  State<HiddenBooksScreen> createState() => _HiddenBooksScreenState();
}

class _HiddenBooksScreenState extends State<HiddenBooksScreen> {
  Library get lib => widget.library;

  Future<void> _show(Iterable<String> ids) async {
    await lib.unhide(ids);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = lib.hidden;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Text('Livros ocultos', style: Lume.s(22, w: 650, family: Lume.serif)),
        actions: [
          if (list.length > 1) TextButton(key: const ValueKey('unhide-all'), onPressed: () => _show(list.map((h) => h.id)), child: const Text('Mostrar todos')),
          const SizedBox(width: 8),
        ],
      ),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Nenhum livro oculto.', style: Lume.s(16, color: Lume.muted)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Text(
                  'Estes livros foram tirados só da biblioteca: os arquivos continuam no celular e o Lume não os mostra ao ler as pastas.',
                  style: Lume.s(14, color: Lume.muted, h: 1.4),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (final (i, h) in list.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          key: ValueKey('hidden-${h.id}'),
                          contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                          leading: Icon(Icons.visibility_off_outlined, color: Lume.muted),
                          title: Text(
                            h.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Lume.s(16, w: 600, family: Lume.serif),
                          ),
                          subtitle: Text(
                            '${_format(h.format)} · ${friendlyPath(h.path)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Lume.s(13, color: Lume.muted),
                          ),
                          trailing: TextButton(onPressed: () => _show([h.id]), child: const Text('Mostrar')),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _format(String name) => BookFormat.values.where((f) => f.name == name).firstOrNull?.name.toUpperCase() ?? name.toUpperCase();
}
