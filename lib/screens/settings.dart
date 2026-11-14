import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../library.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'appearance.dart';
import 'delete_books.dart';
import 'folder_import.dart';
import 'import_books.dart';
import '../lume_folder.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.library, this.allFilesAccess});
  final Library library;

  /// Para os testes: se o acesso a todos os arquivos está liberado.
  final bool? allFilesAccess;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Library get lib => widget.library;
  ReaderSettings rs = Store.settings;

  Future<void> _chooseFolder() => chooseFolder(context, lib);
  late bool allFiles = widget.allFilesAccess ?? !Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (widget.allFilesAccess == null && Platform.isAndroid) {
      Permission.manageExternalStorage.isGranted.then((v) {
        if (mounted) setState(() => allFiles = v);
      });
    }
  }

  Future<void> _grant() async {
    final ok = await ensureStorageAccess(context);
    if (!mounted) return;
    setState(() => allFiles = ok);
    if (ok) await moveToDocuments(context, lib);
  }

  Widget _lumeFolderCard() {
    final kind = lib.lumeKind;
    final inLume = lib.books.where((b) => b.source == BookSource.imported).length;
    final note = switch (kind) {
      LumeFolderKind.documents =>
        allFiles ? 'Fica em Documentos/Lume, à vista no gerenciador de arquivos. O que você colocar nela (ou importar) aparece na biblioteca.' : 'Fica em Documentos/Lume, à vista no gerenciador de arquivos. Os livros importados aparecem na hora; para o Lume ver os que você copiar para lá pelo gerenciador, libere o “Acesso a todos os arquivos”.',
      LumeFolderKind.appExternal =>
        'O Android não deixou criar a pasta em Documentos, então ela fica na pasta do app: Android/data/com.helio.lume/files/Livros. '
            'Alguns gerenciadores de arquivos escondem essa pasta, e o Android a apaga se você desinstalar o Lume. '
            'Libere o “Acesso a todos os arquivos” para usar Documentos/Lume.',
      LumeFolderKind.internal => 'Fica dentro do app (este aparelho não tem armazenamento compartilhado).',
    };
    return Card(
      key: const ValueKey('lume-folder-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LumeMark(size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Pasta do Lume', style: Lume.s(16.5, w: 650)),
                          const SizedBox(width: 8),
                          Container(
                            key: const ValueKey('lume-fixed'),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(color: Lume.line),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline_rounded, size: 12, color: Lume.muted),
                                const SizedBox(width: 3),
                                Text('fixa', style: Lume.s(11.5, w: 600, color: Lume.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(friendlyPath(lib.importDir.path), style: Lume.s(14, h: 1.3)),
                      const SizedBox(height: 4),
                      Text('$inLume ${inLume == 1 ? 'livro' : 'livros'} (PDF, EPUB, TXT e MD)', style: Lume.s(13.5, color: Lume.accent, w: 600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              key: ValueKey('lume-note-${kind.name}'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kind == LumeFolderKind.appExternal ? const Color(0xFFF6E9DF) : const Color(0xFFF1E8D8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(kind == LumeFolderKind.appExternal ? Icons.info_outline_rounded : Icons.lightbulb_outline_rounded, size: 19, color: Lume.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(note, style: Lume.s(13.5, color: Lume.ink, h: 1.35)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  key: const ValueKey('settings-import'),
                  onPressed: () => importBooks(context, lib),
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  label: const Text('Importar livros'),
                ),
                if (!allFiles && kind != LumeFolderKind.internal)
                  TextButton(
                    key: const ValueKey('grant-access'),
                    onPressed: _grant,
                    child: Text(kind == LumeFolderKind.appExternal ? 'Usar Documentos/Lume' : 'Liberar acesso'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFolder(String f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('remove-folder-dialog'),
        backgroundColor: const Color(0xFFFBF6EC),
        title: Text('Remover a pasta ${p.basename(f)}?', style: Lume.s(20, w: 650, family: Lume.serif)),
        content: Text(
          'Os livros dela saem da biblioteca, mas nenhum arquivo é apagado. Dá para adicionar a pasta de novo quando quiser.',
          style: Lume.s(15, h: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(key: const ValueKey('remove-folder-ok'), onPressed: () => Navigator.pop(context, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) await lib.removeFolder(f);
  }

  Widget _foldersCard() {
    final fs = lib.folders;
    Widget row(String f) {
      final n = lib.countIn(f);
      final exists = Directory(f).existsSync();
      return Padding(
        key: ValueKey('folder-$f'),
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Lume.accentSoft, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.folder_rounded, color: Lume.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.basename(f), style: Lume.s(16.5, w: 650)),
                  const SizedBox(height: 2),
                  Text(friendlyPath(f), style: Lume.s(13.5, color: Lume.muted, h: 1.3)),
                  const SizedBox(height: 3),
                  Text(
                    lib.scanning ? 'Procurando livros…' : (exists ? '$n ${n == 1 ? 'livro' : 'livros'} (com subpastas)' : 'Pasta não encontrada ou sem acesso'),
                    style: Lume.s(13.5, color: exists ? Lume.accent : const Color(0xFFB3412E), w: 600),
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('remove-$f'),
              tooltip: 'Remover pasta',
              onPressed: () => _removeFolder(f),
              icon: const Icon(Icons.remove_circle_outline_rounded, color: Lume.muted),
            ),
          ],
        ),
      );
    }

    return Card(
      key: const ValueKey('folders-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(child: Text('Outras pastas', style: Lume.s(16.5, w: 650))),
                Text(fs.isEmpty ? 'nenhuma' : '${fs.length}', style: Lume.s(14, color: Lume.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('Lidas onde estão, sem copiar. Os livros de todas aparecem juntos na biblioteca.', style: Lume.s(13.5, color: Lume.muted, h: 1.35)),
          ),
          for (final f in fs) ...[const Divider(height: 1), row(f)],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton.tonalIcon(
              key: const ValueKey('choose-folder'),
              onPressed: _chooseFolder,
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              label: const Text('Adicionar pasta'),
            ),
          ),
          Container(
            key: const ValueKey('folders-note'),
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF1E8D8), borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: Lume.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${allFiles ? '' : 'Para ler pastas fora da do Lume, o Android pede o “Acesso a todos os arquivos”. '}'
                    'No Android 11 ou mais novo, o seletor não deixa escolher algumas pastas, como Android/data e a raiz de Downloads: '
                    'escolha uma subpasta (por exemplo Download/Livros). Remover uma pasta só tira os livros dela da biblioteca; nenhum arquivo é apagado.',
                    style: Lume.s(13, color: Lume.muted, h: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final hidden = lib.hidden.length;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 4,
            title: Text('Ajustes', style: Lume.s(22, w: 650, family: Lume.serif)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              _label('Pastas'),
              _lumeFolderCard(),
              const SizedBox(height: 12),
              _foldersCard(),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                      secondary: const Icon(Icons.autorenew_rounded, color: Lume.ink),
                      title: const Text('Atualizar automaticamente'),
                      subtitle: const Text('Livros novos colocados nas pastas aparecem sozinhos na biblioteca'),
                      value: Store.watchFolder,
                      onChanged: (v) {
                        Store.watchFolder = v;
                        lib.watch();
                      },
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      leading: const Icon(Icons.manage_search_rounded, color: Lume.ink),
                      title: const Text('Atualizar pastas'),
                      subtitle: const Text('Lê todas as pastas e subpastas de novo e pega os livros novos'),
                      onTap: () => rescanFolder(context, lib),
                    ),
                    const Divider(),
                    ListTile(
                      key: const ValueKey('hidden-books'),
                      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      leading: const Icon(Icons.visibility_off_outlined, color: Lume.ink),
                      title: const Text('Livros ocultos'),
                      subtitle: Text(
                        hidden == 0
                            ? 'Nenhum livro tirado da biblioteca'
                            : '$hidden ${hidden == 1 ? 'livro tirado' : 'livros tirados'} só da biblioteca · toque para mostrar de novo',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Lume.muted),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HiddenBooksScreen(library: lib)));
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(
                  'O Lume lê EPUB, TXT e Markdown (texto que se ajusta à tela) e PDF (modo texto ou páginas como no original). '
                  '“Importar” copia para a pasta do Lume; os livros das outras pastas não são copiados, ficam onde estão.',
                  style: Lume.s(13.5, color: Lume.muted),
                ),
              ),
              _label('Leitura'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: EdgeInsets.symmetric(horizontal: rs.hPad * .6, vertical: 14),
                        decoration: BoxDecoration(
                          color: rs.theme.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Lume.line),
                        ),
                        child: Text(
                          'Uma noite destas, vindo da cidade para o Engenho Novo, encontrei no trem da Central um rapaz aqui do bairro…',
                          textAlign: rs.justify ? TextAlign.justify : TextAlign.start,
                          style: TextStyle(fontFamily: rs.font.family, fontSize: rs.size * .85, height: rs.lineHeight, color: rs.theme.ink),
                        ),
                      ),
                      AppearancePanel(settings: rs, onChanged: (n) => setState(() => Store.settings = rs = n)),
                    ],
                  ),
                ),
              ),
              _label('Sobre'),
              Card(
                child: Column(
                  children: [
                    Padding(
                      key: const ValueKey('about'),
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                      child: Column(
                        children: [
                          const LumeMark(size: 96),
                          const SizedBox(height: 12),
                          Text('Lume', style: Lume.s(24, w: 650, family: Lume.serif)),
                          const SizedBox(height: 2),
                          Text(
                            'Versão 1.3 · leitura offline, sem conta e sem anúncios',
                            textAlign: TextAlign.center,
                            style: Lume.s(14, color: Lume.muted),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.menu_book_outlined, color: Lume.ink),
                      title: Text('Livros de exemplo'),
                      subtitle: Text('Machado de Assis e José de Alencar, em domínio público, via Project Gutenberg (gutenberg.org)'),
                    ),
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.picture_as_pdf_outlined, color: Lume.ink),
                      title: Text('PDF'),
                      subtitle: Text('Páginas desenhadas pelo PDFium (pacote pdfrx, licença MIT), direto no celular'),
                    ),
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.font_download_outlined, color: Lume.ink),
                      title: Text('Fontes'),
                      subtitle: Text('Literata, Lora e Source Sans 3 · SIL Open Font License'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Text(t, style: Lume.s(19, w: 650, family: Lume.serif)),
  );
}
