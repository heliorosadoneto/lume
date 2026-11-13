import 'dart:io';

import 'package:flutter/material.dart';

import '../epub.dart';
import '../pdf_analysis.dart';
import '../store.dart';
import '../theme.dart';
import 'pdf_reader.dart';
import 'reader.dart';

/// Abre um PDF no modo texto (o texto refeito em parágrafos, no mesmo leitor
/// dos EPUBs) ou na página original. A posição é uma só: o modo texto guarda a
/// página do bloco lido na posição do PDF, e ao voltar para o modo texto ele
/// continua da página em que a leitura parou.
class PdfBookScreen extends StatefulWidget {
  const PdfBookScreen({super.key, required this.meta, this.now, this.analyzer});
  final BookMeta meta;
  final DateTime Function()? now;
  final PdfAnalyzer? analyzer;

  /// Pasta do cache do texto extraído (definida no main; nos testes, uma pasta temporária).
  static Directory? cacheDir;

  static PdfAnalyzer get defaultAnalyzer => PdfAnalyzer(cacheDir ?? Directory('${Directory.systemTemp.path}/lume-texto'));

  @override
  State<PdfBookScreen> createState() => PdfBookScreenState();
}

class PdfBookScreenState extends State<PdfBookScreen> {
  BookMeta get meta => widget.meta;
  late bool textMode = Store.pdfMode(meta.id) != 'pagina';
  PdfAnalysis? analysis;
  Book? book;
  Object? error;
  int done = 0, total = 0;
  String? notice;
  int _session = 0;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      final a = await (widget.analyzer ?? PdfBookScreen.defaultAnalyzer).analyze(
        meta.path,
        meta.id,
        progress: (d, t) {
          if (!mounted) return;
          setState(() {
            done = d;
            total = t;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        analysis = a;
        if (a.hasText) {
          book = a.bookFor(meta);
          if (textMode) _syncTextFromPage();
        } else if (textMode) {
          textMode = false;
          notice =
              'Este PDF é escaneado (as páginas são imagens), por isso não há modo texto. '
              'Use o zoom com os dedos para aumentar a página.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e;
        if (textMode) {
          textMode = false;
          notice = 'Não foi possível preparar o modo texto deste PDF. Abrindo a página original.';
        }
      });
    }
  }

  /// Leva o modo texto para a página salva (se a leitura avançou no modo página).
  void _syncTextFromPage() {
    final a = analysis!, b = book!;
    final page = (Store.pos(meta.id)?.block ?? 0) + 1;
    final tpos = Store.pos(b.meta.id);
    final cur = tpos == null || tpos.block >= a.reflow.blockPage.length ? -1 : a.reflow.blockPage[tpos.block];
    if (cur == page) return;
    final blk = a.reflow.blockForPage(page);
    Store.savePos(b.meta.id, ReadingPos(blk, 0, b.progressAt(blk), _now()));
  }

  /// O modo texto avisa cada bloco lido: a página dele vira a posição do PDF.
  void _onTextPosition(int block, double percent) {
    final pages = analysis!.reflow.blockPage;
    if (block >= pages.length) return;
    Store.savePos(meta.id, ReadingPos(pages[block] - 1, 0, percent, _now()));
  }

  void setMode(bool text) {
    if (text == textMode) return;
    if (text && book == null) return;
    Store.setPdfMode(meta.id, text ? 'texto' : 'pagina');
    setState(() {
      textMode = text;
      notice = null;
      _session++;
      if (text) _syncTextFromPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!textMode) {
      return PdfReaderScreen(
        key: ValueKey('pagina$_session'),
        meta: meta,
        now: widget.now,
        crops: analysis?.crops,
        textMode: analysis != null ? analysis!.hasText : (error != null ? false : null),
        onTextMode: () => setMode(true),
        notice: notice,
      );
    }
    final b = book;
    if (b == null) return _preparing(context);
    final pages = analysis!.reflow.blockPage;
    return ReaderScreen(
      key: ValueKey('texto$_session'),
      book: b,
      now: widget.now,
      onPosition: _onTextPosition,
      locationLabel: (i) => i < pages.length ? 'p. ${pages[i]} de ${analysis!.pages}' : '',
      appearanceExtra: (sheet) => PdfModeSwitch(
        text: true,
        available: true,
        onChanged: (text) {
          if (text) return;
          Navigator.pop(sheet);
          setMode(false);
        },
      ),
    );
  }

  Widget _preparing(BuildContext context) {
    final t = Store.settings.theme;
    final frac = total == 0 ? null : done / total;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.ink,
        elevation: 0,
        title: Text(meta.title, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.subject_rounded, size: 40, color: t.dark ? Lume.amber : Lume.accent),
              const SizedBox(height: 16),
              Text(
                'Preparando o modo texto…',
                style: Lume.s(20, w: 650, color: t.ink, family: Lume.serif),
              ),
              const SizedBox(height: 8),
              Text(
                total == 0 ? 'Lendo o PDF' : 'Página $done de $total',
                key: const ValueKey('pdf-prep-progress'),
                style: Lume.s(15, color: t.muted),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 6,
                  color: t.dark ? Lume.amber : Lume.accent,
                  backgroundColor: t.muted.withValues(alpha: .2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Só na primeira vez: depois o texto fica guardado no aparelho.',
                textAlign: TextAlign.center,
                style: Lume.s(13.5, color: t.muted, h: 1.35),
              ),
              const SizedBox(height: 22),
              TextButton.icon(
                key: const ValueKey('pdf-open-pages'),
                onPressed: () {
                  Store.setPdfMode(meta.id, 'pagina');
                  setState(() {
                    textMode = false;
                    _session++;
                  });
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Abrir a página original'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
