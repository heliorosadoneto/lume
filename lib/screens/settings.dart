import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../library.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'appearance.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.library});
  final Library library;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Library get lib => widget.library;
  ReaderSettings rs = Store.settings;

  /// No Android 11+ ler EPUBs de uma pasta qualquer exige "Acesso a todos os arquivos".
  Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted) return true;
    final r = await Permission.manageExternalStorage.request();
    if (r.isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }

  Future<void> _chooseFolder() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _ensurePermission()) {
      messenger.showSnackBar(const SnackBar(content: Text('Sem permissão para ler a pasta. Libere o acesso aos arquivos.')));
      return;
    }
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Pasta de livros', initialDirectory: lib.folder);
    if (dir == null) return;
    await lib.setFolder(dir);
    messenger.showSnackBar(SnackBar(content: Text('${lib.books.where((b) => b.source == BookSource.folder).length} livros encontrados na pasta')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final f = lib.folder;
        final inFolder = lib.books.where((b) => b.source == BookSource.folder).length;
        return Scaffold(
          appBar: AppBar(titleSpacing: 4, title: Text('Ajustes', style: Lume.s(22, w: 650, family: Lume.serif))),
          body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
            _label('Biblioteca'),
            Card(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: Lume.accentSoft, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.folder_rounded, color: Lume.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Pasta de livros', style: Lume.s(16.5, w: 650)),
                        const SizedBox(height: 3),
                        Text(f ?? 'Nenhuma pasta escolhida', style: Lume.s(14, color: f == null ? Lume.muted : Lume.ink, h: 1.3)),
                        if (f != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            lib.scanning
                                ? 'Procurando livros…'
                                : '$inFolder ${inFolder == 1 ? 'livro EPUB encontrado' : 'livros EPUB encontrados'}'
                                    '${lib.failed.isEmpty ? '' : ' · ${lib.failed.length} com erro'}',
                            style: Lume.s(13.5, color: Lume.accent, w: 600),
                          ),
                        ],
                      ]),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(74, 6, 12, 12),
                  child: Row(children: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('choose-folder'),
                      onPressed: _chooseFolder,
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: Text(f == null ? 'Escolher pasta' : 'Trocar pasta'),
                    ),
                    const SizedBox(width: 8),
                    if (f != null) TextButton(onPressed: () => lib.setFolder(null), child: const Text('Remover')),
                  ]),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                  secondary: const Icon(Icons.autorenew_rounded, color: Lume.ink),
                  title: const Text('Atualizar automaticamente'),
                  subtitle: const Text('Livros novos colocados na pasta aparecem sozinhos na biblioteca'),
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
                  title: const Text('Procurar livros agora'),
                  subtitle: const Text('Lê a pasta e as subpastas de novo'),
                  onTap: lib.load,
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text('Nesta versão o Lume lê arquivos EPUB. PDF chega numa próxima versão.',
                  style: Lume.s(13.5, color: Lume.muted)),
            ),
            _label('Leitura'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: EdgeInsets.symmetric(horizontal: rs.hPad * .6, vertical: 14),
                    decoration: BoxDecoration(
                        color: rs.theme.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: Lume.line)),
                    child: Text(
                      'Uma noite destas, vindo da cidade para o Engenho Novo, encontrei no trem da Central um rapaz aqui do bairro…',
                      textAlign: rs.justify ? TextAlign.justify : TextAlign.start,
                      style: TextStyle(fontFamily: rs.font.family, fontSize: rs.size * .85, height: rs.lineHeight, color: rs.theme.ink),
                    ),
                  ),
                  AppearancePanel(settings: rs, onChanged: (n) => setState(() => Store.settings = rs = n)),
                ]),
              ),
            ),
            _label('Sobre'),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const LumeMark(size: 34),
                  title: const Text('Lume 0.1 · protótipo'),
                  subtitle: const Text('Leitura offline, sem conta e sem anúncios'),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.menu_book_outlined, color: Lume.ink),
                  title: Text('Livros de exemplo'),
                  subtitle: Text('Machado de Assis e José de Alencar, em domínio público, via Project Gutenberg (gutenberg.org)'),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.font_download_outlined, color: Lume.ink),
                  title: Text('Fontes'),
                  subtitle: Text('Literata, Lora e Source Sans 3 · SIL Open Font License'),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Text(t, style: Lume.s(19, w: 650, family: Lume.serif)),
      );
}
