import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../epub.dart';
import '../fullscreen.dart';
import '../markdown_book.dart';
import '../page_measure.dart';
import '../paginate.dart';
import '../store.dart';
import '../txt.dart';
import '../theme.dart';
import '../widgets.dart';
import 'appearance.dart';
import 'notes.dart';
import 'pdf_book.dart';

/// Abre o livro: PDF no modo texto ou de páginas; TXT, Markdown e EPUB processados fora da thread de interface.
Future<void> openBook(BuildContext context, BookMeta meta) async {
  final messenger = ScaffoldMessenger.of(context);
  if (meta.isPdf) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfBookScreen(meta: meta)));
    return;
  }
  try {
    final parse = switch (meta.format) {
      BookFormat.txt => TxtBook.parseFile,
      BookFormat.md => MarkdownBook.parseFile,
      _ => Epub.parseFile,
    };
    final book = await compute(parse, meta.path);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Não foi possível abrir "${meta.title}": $e')));
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, this.now, this.onPosition, this.appearanceExtra, this.locationLabel});
  final Book book;
  final DateTime Function()? now;

  /// Avisado a cada mudança de bloco (o modo texto do PDF sincroniza a página).
  final void Function(int block, double percent)? onPosition;

  /// Conteúdo extra no topo do painel de aparência (troca de modo do PDF).
  final Widget Function(BuildContext sheetContext)? appearanceExtra;

  /// Texto extra na barra de baixo, como "p. 42 de 273" no modo texto do PDF.
  final String Function(int block)? locationLabel;
  @override
  State<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends State<ReaderScreen> {
  Book get book => widget.book;
  late ReaderSettings s = Store.settings;
  late List<Highlight> hls = Store.highlights(book.meta.id);
  late List<Bookmark> bms = Store.bookmarks(book.meta.id);
  final items = ItemScrollController();
  final offsets = ScrollOffsetController();
  final positions = ItemPositionsListener.create();
  late int current;
  late double initialAlign;

  // ---------- tela cheia ----------
  /// Botões do leitor (e barras do Android) à vista. Com "Tela cheia ao ler"
  /// ligada, começam escondidos; um toque no centro da tela os mostra.
  late bool _chrome = !s.fullscreen;
  double _safeTop = 0, _safeBottom = 0;
  double _hPad = 10;
  final _toggle = TapDebounce();

  bool get _showBars => !s.fullscreen || _chrome;

  void _applySystemUi() => applySystemUi(immersive: !_showBars);

  void _setChrome(bool v) {
    if (!s.fullscreen) return;
    setState(() => _chrome = v);
    _applySystemUi();
  }

  // ---------- modo "Virar página" ----------
  List<PageSpec>? _pages;
  PageController? _pager;
  int _pageIdx = 0;
  String? _pageKey;
  int _pageToken = 0;
  int _hlSig = 0;
  final _progress = ValueNotifier<double>(0);
  late int _anchorBlock;
  int _anchorChar = 0;
  double? _imgH;

  /// Há texto selecionado: arrastar as alças não pode virar a página.
  bool _selecting = false;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final pos = Store.pos(book.meta.id);
    current = (pos?.block ?? 0).clamp(0, book.blocks.length - 1);
    initialAlign = (pos?.align ?? 0).clamp(-3.0, 0.9);
    _anchorBlock = current;
    _anchorChar = Store.pageChar(book.meta.id, current);
    positions.itemPositions.addListener(_onScroll);
    if (!s.pageMode) _save(initialAlign);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applySystemUi();
      if (s.fullscreen && !Store.fullscreenHint) {
        Store.fullscreenHint = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tela cheia: toque no centro da tela para mostrar os botões.'), duration: Duration(seconds: 4)),
        );
      }
    });
  }

  @override
  void dispose() {
    _pageToken++;
    _toggle.dispose();
    _pager?.dispose();
    _progress.dispose();
    applySystemUi(immersive: false); // devolve as barras do Android
    positions.itemPositions.removeListener(_onScroll);
    for (final r in _links.values) {
      r.dispose();
    }
    super.dispose();
  }

  // ---------- links (Markdown) ----------
  final _links = <String, TapGestureRecognizer>{};

  TapGestureRecognizer _linkRecognizer(int block, int run, String href) =>
      _links.putIfAbsent('$block:$run', () => TapGestureRecognizer()..onTap = () => openLink(href));

  /// Link interno (#âncora) salta para o título; externo abre no navegador depois de confirmar.
  Future<void> openLink(String href) async {
    final messenger = ScaffoldMessenger.of(context);
    if (href.startsWith('#')) {
      final want = Uri.decodeComponent(href.substring(1)).toLowerCase();
      final i = book.blocks.indexWhere((b) => b.anchor == want);
      if (i >= 0) {
        jumpTo(i);
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Não achei a seção "$want" neste arquivo.')));
      }
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null || !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
      messenger.showSnackBar(SnackBar(content: Text('O Lume ainda não abre este link: $href')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('link-dialog'),
        backgroundColor: Lume.card,
        title: Text('Abrir link?', style: Lume.s(20, w: 650, family: Lume.serif)),
        content: Text('O link abre fora do Lume:\n$href', style: Lume.s(15, h: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(key: const ValueKey('link-open'), onPressed: () => Navigator.pop(context, true), child: const Text('Abrir')),
        ],
      ),
    );
    if (ok != true) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!launched) messenger.showSnackBar(SnackBar(content: Text('Não foi possível abrir $href')));
  }

  void _onScroll() {
    final vis = positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0.001).toList();
    if (vis.isEmpty) return;
    vis.sort((a, b) => a.index.compareTo(b.index));
    final top = vis.first;
    _save(top.itemLeadingEdge);
    if (top.index != current) {
      _anchorBlock = top.index;
      _anchorChar = 0;
      setState(() => current = top.index);
    }
  }

  void _save(double align) {
    final bottom = positions.itemPositions.value.fold<int>(current, (m, p) => p.index > m ? p.index : m);
    final percent = bottom >= book.blocks.length - 1 ? 1.0 : book.progressAt(current);
    Store.savePos(book.meta.id, ReadingPos(current, align, percent, _now()));
    widget.onPosition?.call(current, percent);
  }

  String get chapterTitle {
    final i = book.tocIndexFor(current);
    return i < 0 ? book.meta.title : book.toc[i].title;
  }

  void jumpTo(int block) {
    current = block;
    _anchorBlock = block;
    _anchorChar = 0;
    if (s.pageMode) {
      final pages = _pages;
      if (pages != null) _goToPage(pageOf(pages, block, 0), animate: false);
      setState(() {});
      return;
    }
    items.jumpTo(index: block, alignment: 0);
    setState(() {});
  }

  /// Vira para a página [n] do modo "Virar página".
  Future<void> _goToPage(int n, {bool animate = true}) async {
    final pages = _pages, c = _pager;
    if (pages == null || c == null || !c.hasClients) return;
    n = n.clamp(0, pages.length - 1);
    if (animate && (c.page ?? n).round() != n) {
      await c.animateToPage(n, duration: const Duration(milliseconds: 260), curve: Curves.easeInOutCubic);
    } else {
      c.jumpToPage(n);
      _onPageChanged(n);
    }
  }

  /// Para os testes: quantas páginas, qual está aberta e ir direto a uma.
  int get pageCount => _pages?.length ?? 0;
  int get pageIndex => _pageIdx;
  List<PageSpec>? get pagesForTest => _pages;
  Future<void> goToPageForTest(int n) => _goToPage(n, animate: false);

  /// Página seguinte (1) ou anterior (-1).
  Future<void> turnPage(int dir) => _goToPage(_pageIdx + dir);

  void _onPageChanged(int i) {
    final pages = _pages;
    if (pages == null || i < 0 || i >= pages.length) return;
    final f = pages[i].first;
    setState(() {
      _pageIdx = i;
      current = f.block;
      _anchorBlock = f.block;
      _anchorChar = f.from;
    });
    final last = i >= pages.length - 1;
    final percent = last ? 1.0 : (book.charStart[f.block] + f.from) / (book.totalChars == 0 ? 1 : book.totalChars);
    Store.savePos(book.meta.id, ReadingPos(f.block, 0, percent, _now()));
    Store.savePageChar(book.meta.id, f.block, f.from);
    widget.onPosition?.call(f.block, percent);
  }

  /// Toque curto na área de leitura: no modo página, o terço esquerdo volta e o
  /// direito avança; o centro (e qualquer toque na rolagem) mostra ou esconde os botões.
  void _tapped(double fx) {
    if (s.pageMode && fx < .3) {
      turnPage(-1);
    } else if (s.pageMode && fx > .7) {
      turnPage(1);
    } else if (s.fullscreen) {
      _toggle(() {
        if (mounted) _setChrome(!_chrome);
      });
    }
  }

  // ---------- destaques ----------
  List<Highlight> _hlsFor(int block) => hls.where((h) => h.block == block).toList();

  void _addHighlight(int block, TextSelection sel, HighlightColor color, {String note = ''}) {
    final text = book.blocks[block].text;
    final start = sel.start.clamp(0, text.length), end = sel.end.clamp(0, text.length);
    if (end <= start) return;
    final overlapping = hls.where((h) => h.block == block && h.start < end && h.end > start).toList();
    final keepNote = note.isNotEmpty ? note : overlapping.map((h) => h.note).where((n) => n.isNotEmpty).join(' ');
    setState(() {
      hls.removeWhere(overlapping.contains);
      hls.add(
        Highlight(
          id: '${_now().microsecondsSinceEpoch}',
          block: block,
          start: start,
          end: end,
          color: color,
          text: text.substring(start, end).trim(),
          note: keepNote,
          created: _now(),
        ),
      );
    });
    Store.saveHighlights(book.meta.id, hls);
  }

  void _removeHighlights(int block, TextSelection sel) {
    setState(() => hls.removeWhere((h) => h.block == block && h.start < sel.end && h.end > sel.start));
    Store.saveHighlights(book.meta.id, hls);
  }

  Future<void> _noteFor(int block, TextSelection sel) async {
    final existing = hls.where((h) => h.block == block && h.start < sel.end && h.end > sel.start).firstOrNull;
    final note = await editNoteDialog(context, existing?.note ?? '');
    if (note == null) return;
    _addHighlight(block, sel, existing?.color ?? HighlightColor.amarelo, note: note);
  }

  bool get _bookmarked => bms.any((b) => b.block == current);

  void _toggleBookmark() {
    setState(() {
      if (_bookmarked) {
        bms.removeWhere((b) => b.block == current);
      } else {
        final t = book.blocks[current].text;
        bms.add(Bookmark(current, t.length > 140 ? '${t.substring(0, 140)}…' : t, _now()));
      }
    });
    Store.saveBookmarks(book.meta.id, bms);
  }

  // ---------- painéis ----------
  Future<void> openToc() async {
    final idx = book.tocIndexFor(current);
    final r = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TocSheet(book: book, currentIndex: idx),
    );
    if (r != null) jumpTo(r);
  }

  Future<void> openAppearance() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black12,
      builder: (sheet) => AppearanceSheet(
        extra: widget.appearanceExtra?.call(sheet),
        settings: s,
        onChanged: (n) {
          setState(() {
            s = n;
            if (!n.fullscreen) _chrome = true;
          });
          Store.settings = n;
        },
      ),
    );
    // com tela cheia ligada, fecha o painel e volta a ler sem os botões
    if (mounted && s.fullscreen) _setChrome(false);
  }

  Future<void> openNotes() async {
    final r = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => NotesScreen(book: book)));
    setState(() {
      hls = Store.highlights(book.meta.id);
      bms = Store.bookmarks(book.meta.id);
    });
    if (r != null) jumpTo(r);
  }

  // ---------- interface ----------
  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final progress = book.progressAt(current);
    final mins = book.minutesLeftInChapter(current);
    final mq = MediaQuery.of(context);
    _safeTop = _safeTop < mq.viewPadding.top ? mq.viewPadding.top : _safeTop;
    _safeBottom = _safeBottom < mq.viewPadding.bottom ? mq.viewPadding.bottom : _safeBottom;
    final Widget body;
    if (!s.fullscreen) {
      body = SafeArea(
        child: Column(
          children: [
            _topBar(t),
            Expanded(child: LayoutBuilder(builder: (context, c) => _reading(c, t, 12, s.pageMode ? 14 : 48))),
            _bottomBar(t, progress, mins),
          ],
        ),
      );
    } else {
      // tela cheia: o texto ocupa a tela toda; os botões aparecem por cima
      body = Stack(
        children: [
          Positioned.fill(child: LayoutBuilder(builder: (context, c) => _reading(c, t, _safeTop + 10, _safeBottom + 30))),
          if (!_chrome)
            Positioned(
              left: 0,
              right: 0,
              bottom: _safeBottom + 6,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    s.pageMode && _pages != null ? 'Página ${_pageIdx + 1} de ${_pages!.length}  ·  ${pct(progress)}' : pct(progress),
                    key: const ValueKey('footer'),
                    style: Lume.s(12, color: t.muted.withValues(alpha: .85), w: 500),
                  ),
                ),
              ),
            ),
          if (_chrome) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Material(
                key: const ValueKey('chrome-top'),
                color: t.bg,
                elevation: 2,
                child: Padding(padding: EdgeInsets.only(top: _safeTop), child: _topBar(t)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                key: const ValueKey('chrome-bottom'),
                color: t.bg,
                elevation: 2,
                child: Padding(padding: EdgeInsets.only(bottom: _safeBottom), child: _bottomBar(t, progress, mins)),
              ),
            ),
          ],
        ],
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(backgroundColor: t.bg, body: body),
    );
  }

  /// A área do texto: lista rolável ou páginas, com o toque curto reconhecido por cima.
  Widget _reading(BoxConstraints c, PageTheme t, double top, double bottom) {
    _hPad = s.hPadFor(c.maxWidth);
    final Widget area;
    if (s.pageMode) {
      area = _pagedArea(c, t, top, bottom);
    } else {
      _imgH = null;
      area = ScrollablePositionedList.builder(
        key: const ValueKey('scroll-list'),
        itemCount: book.blocks.length,
        itemScrollController: items,
        scrollOffsetController: offsets,
        itemPositionsListener: positions,
        initialScrollIndex: current,
        initialAlignment: initialAlign,
        padding: EdgeInsets.only(top: top, bottom: bottom),
        itemBuilder: (context, i) => _block(i, t),
      );
    }
    return TapSpot(onTap: _tapped, onSwipe: s.pageMode && !_selecting ? turnPage : null, child: area);
  }

  // ---------- virar página ----------
  Widget _pagedArea(BoxConstraints c, PageTheme t, double top, double bottom) {
    final pageH = (c.maxHeight - top - bottom).clamp(50.0, double.infinity);
    _imgH = pageH * .62;
    final scale = MediaQuery.textScalerOf(context).scale(100);
    final key = '${c.maxWidth.round()}x${pageH.round()}|${s.font.name}|${s.size}|${s.lineHeight}|${s.widthPct}|${s.justify}|$scale';
    // os destaques entram na medida (o texto em pedaços pode quebrar uma linha diferente)
    final hlSig = Object.hashAll([for (final h in hls) '${h.block}:${h.start}-${h.end}']);
    if (key != _pageKey) {
      _pageKey = key;
      _hlSig = hlSig;
      final token = ++_pageToken;
      _pages = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && token == _pageToken) _startPagination(token, c.maxWidth, pageH);
      });
    } else if (hlSig != _hlSig) {
      // só os destaques mudaram: refaz as páginas por trás, sem tirar a página da tela
      _hlSig = hlSig;
      final token = ++_pageToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && token == _pageToken) _startPagination(token, c.maxWidth, pageH);
      });
    }
    final pages = _pages;
    if (pages == null) {
      return Center(
        key: const ValueKey('paginating'),
        child: ValueListenableBuilder<double>(
          valueListenable: _progress,
          builder: (context, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, value: v > 0 && v < 1 ? v : null, color: Lume.accent)),
              const SizedBox(height: 14),
              Text('Preparando as páginas…', style: Lume.s(14, color: t.muted)),
            ],
          ),
        ),
      );
    }
    return PageView.builder(
      key: const ValueKey('pages'),
      controller: _pager,
      physics: const NeverScrollableScrollPhysics(), // o deslize é lido pelo TapSpot (veja fullscreen.dart)
      itemCount: pages.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        child: _pageWidget(pages[i], t),
      ),
    );
  }

  Future<void> _startPagination(int token, double width, double pageH) async {
    _progress.value = 0;
    final w = width - 2 * _hPad;
    final scaler = MediaQuery.textScalerOf(context);
    final t = s.theme;
    final pages = await paginate(
      count: book.blocks.length,
      measure: (i) => _measure(i, w, pageH, scaler, t),
      height: pageH - 6,
      cancelled: () => !mounted || token != _pageToken,
      onProgress: (v) => _progress.value = v,
    );
    if (!mounted || token != _pageToken) return;
    final idx = pageOf(pages, _anchorBlock, _anchorChar);
    final old = _pager;
    _pager = PageController(initialPage: idx);
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    setState(() {
      _pages = pages;
      _pageIdx = idx;
    });
    if (pages.isNotEmpty) {
      final f = pages[idx].first;
      current = f.block;
      final last = idx >= pages.length - 1;
      final percent = last ? 1.0 : (book.charStart[f.block] + f.from) / (book.totalChars == 0 ? 1 : book.totalChars);
      Store.savePos(book.meta.id, ReadingPos(f.block, 0, percent, _now()));
      widget.onPosition?.call(f.block, percent);
    }
  }

  /// Medidas do bloco [i] para a paginação (mesmos estilos e larguras do desenho).
  Measured _measure(int i, double w, double pageH, TextScaler scaler, PageTheme t) {
    final b = book.blocks[i];
    final sp = _specFor(i, b, t);
    if (sp != null) {
      // o campo de texto reserva 3 px (cursor 2 + folga 1) e quebra as linhas nessa largura
      var width = w - sp.left - 3;
      if (b.quote > 0) width -= 14.0 + 14 * (b.quote - 1) + 3;
      return TextMeasure(
        span: (from) => TextSpan(style: sp.style, children: _spans(i, b, _hlsFor(i), sp.style, from: from)),
        align: sp.align,
        width: width < 20 ? 20 : width,
        scaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
        length: b.text.length,
        padTop: sp.top,
        padBottom: sp.bottom,
      );
    }
    switch (b.kind) {
      case BlockKind.separator:
        return FixedMeasure(56);
      case BlockKind.image:
        final cap = b.text.trim();
        var capH = 0.0;
        if (cap.isNotEmpty) {
          final tp = TextPainter(text: TextSpan(text: cap, style: Lume.s(13.5, h: 1.3)), textDirection: TextDirection.ltr, textAlign: TextAlign.center, textScaler: scaler)
            ..layout(maxWidth: w);
          capH = tp.height + 8;
          tp.dispose();
        }
        return FixedMeasure(_imgH! + capH, padBottom: s.size * .9);
      case BlockKind.table:
        final rows = b.rows?.length ?? 1;
        return FixedMeasure(rows * (s.size * .85 * 1.35 + 17) + 2, padBottom: s.size * .9);
      case BlockKind.code:
        final lines = '\n'.allMatches(b.text).length + 1;
        return FixedMeasure(lines * s.size * .8 * 1.45 + 24, padBottom: s.size * .9);
      default:
        return FixedMeasure(s.size * s.lineHeight);
    }
  }

  Widget _pageWidget(PageSpec p, PageTheme t) => SingleChildScrollView(
    physics: p.oversize ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final sl in p.slices) _sliceWidget(sl, t)],
    ),
  );

  Widget _sliceWidget(Slice sl, PageTheme t) {
    final b = book.blocks[sl.block];
    final sp = _specFor(sl.block, b, t);
    if (sp == null || sl.whole) return _block(sl.block, t);
    final text = _selectable(sl.block, b, sp.style, sp.align, from: sl.from, to: sl.to);
    final pad = EdgeInsets.only(top: sl.showTop ? sp.top : 0, bottom: sl.showBottom ? sp.bottom : 0);
    final Widget inner = b.kind == BlockKind.listItem ? _listRow(sl.block, b, t, text, marker: sl.from == 0) : text;
    return _quoted(b, t, Padding(padding: b.quote > 0 ? pad : pad.add(EdgeInsets.symmetric(horizontal: _hPad)), child: inner));
  }

  Widget _topBar(PageTheme t) {
    Widget btn(IconData i, String tip, VoidCallback f, {Color? color}) => IconButton(
      icon: Icon(i, color: color ?? t.ink.withValues(alpha: .78)),
      tooltip: tip,
      onPressed: f,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          btn(Icons.arrow_back_rounded, 'Biblioteca', () => Navigator.of(context).maybePop()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.meta.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Lume.s(15.5, w: 650, color: t.ink),
                ),
                Text(
                  chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Lume.s(13, color: t.muted),
                ),
              ],
            ),
          ),
          btn(Icons.toc_rounded, 'Sumário', openToc),
          btn(Icons.edit_note_rounded, 'Caderno', openNotes),
          btn(Icons.text_fields_rounded, 'Aparência', openAppearance),
          btn(_bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, 'Marcador', _toggleBookmark, color: _bookmarked ? Lume.accent : null),
        ],
      ),
    );
  }

  Widget _bottomBar(PageTheme t, double progress, int mins) => Padding(
    padding: EdgeInsets.fromLTRB(_hPad, 6, _hPad, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ThinProgress(progress, height: 3, color: t.dark ? Lume.amber : Lume.accent, track: t.muted.withValues(alpha: .25)),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${pct(progress)} do livro${widget.locationLabel == null ? '' : ' · ${widget.locationLabel!(current)}'}',
              style: Lume.s(13, color: t.muted, w: 500),
            ),
            const Spacer(),
            Text(
              s.pageMode && _pages != null
                  ? '${widget.locationLabel == null ? 'Página' : 'Tela'} ${_pageIdx + 1} de ${_pages!.length}'
                  : (mins <= 1 ? 'Menos de 1 min no capítulo' : '$mins min restantes no capítulo'),
              style: Lume.s(13, color: t.muted),
            ),
          ],
        ),
      ],
    ),
  );

  TextStyle get _bodyStyle =>
      TextStyle(
        fontFamily: s.font.family,
        fontSize: s.size,
        height: s.lineHeight,
        color: s.theme.ink,
        // o mesmo espaçamento do tema do Material, dito aqui para a medida das páginas bater com o desenho
        letterSpacing: 0.25,
        fontVariations: const [FontVariation.weight(400)],
      );

  /// Barra das citações (> no Markdown) à esquerda do bloco.
  Widget _quoted(Block b, PageTheme t, Widget child) {
    if (b.quote == 0) return child;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _hPad),
      child: Container(
        padding: EdgeInsets.only(left: 14.0 + 14 * (b.quote - 1)),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: (t.dark ? Lume.amber : Lume.accent).withValues(alpha: .55), width: 3)),
        ),
        child: child,
      ),
    );
  }

  static const mono = 'SourceCodePro';
  Color _codeBg(PageTheme t) => t.ink.withValues(alpha: t.dark ? .10 : .06);

  /// Estilo, alinhamento e espaços de um bloco de texto (os que se dividem entre páginas).
  _TextSpec? _specFor(int i, Block b, PageTheme t) {
    switch (b.kind) {
      case BlockKind.heading when !b.center:
        // Markdown: títulos à esquerda, do maior (#) ao menor (######).
        const scales = [1.55, 1.32, 1.16, 1.05, 1.0, .92];
        return _TextSpec(
          _bodyStyle.copyWith(
            fontSize: s.size * scales[(b.level - 1).clamp(0, 5)],
            height: 1.28,
            fontWeight: FontWeight.w700,
            fontVariations: const [FontVariation.weight(650)],
            color: b.level >= 6 ? t.muted : t.ink,
          ),
          TextAlign.start,
          top: b.level <= 2 ? 18 : 12,
          bottom: b.level <= 2 ? 12 : 8,
        );
      case BlockKind.heading:
        final scale = b.level <= 2 ? 1.4 : (b.level <= 4 ? 1.18 : 0.95);
        return _TextSpec(
          _bodyStyle.copyWith(
            fontSize: s.size * scale,
            height: 1.3,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation.weight(600)],
            letterSpacing: b.level >= 5 ? 1.5 : 0,
            color: b.level >= 5 ? t.muted : t.ink,
          ),
          TextAlign.center,
          top: b.level <= 4 ? 10 : 18,
          bottom: 14,
        );
      case BlockKind.paragraph:
        return _TextSpec(
          b.quote > 0 ? _bodyStyle.copyWith(fontStyle: FontStyle.italic) : _bodyStyle,
          s.justify ? TextAlign.justify : TextAlign.start,
          bottom: s.size * 0.75,
        );
      case BlockKind.listItem:
        final next = i + 1 < book.blocks.length ? book.blocks[i + 1] : null;
        final tight = next != null && next.kind == BlockKind.listItem;
        return _TextSpec(_bodyStyle, TextAlign.start, bottom: tight ? s.size * .3 : s.size * .75, left: 6.0 + b.indent * s.size * 1.4 + s.size * 1.6);
      default:
        return null;
    }
  }

  Widget _block(int i, PageTheme t) {
    final b = book.blocks[i];
    final inner = _blockBody(i, b, t, EdgeInsets.symmetric(horizontal: b.quote > 0 ? 0 : _hPad));
    return _quoted(b, t, inner);
  }

  Widget _blockBody(int i, Block b, PageTheme t, EdgeInsets pad) {
    switch (b.kind) {
      case BlockKind.separator:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Text('·  ·  ·', style: Lume.s(16, color: t.muted, ls: 2)),
          ),
        );
      case BlockKind.heading || BlockKind.paragraph:
        final sp = _specFor(i, b, t)!;
        return Padding(
          padding: pad.add(EdgeInsets.only(top: sp.top, bottom: sp.bottom)),
          child: _selectable(i, b, sp.style, sp.align),
        );
      case BlockKind.listItem:
        final sp = _specFor(i, b, t)!;
        return Padding(
          padding: pad.add(EdgeInsets.only(bottom: sp.bottom)),
          child: _listRow(i, b, t, _selectable(i, b, sp.style, sp.align)),
        );
      case BlockKind.code:
        return Padding(
          padding: pad.add(EdgeInsets.only(bottom: s.size * .9)),
          child: Container(
            key: ValueKey('code$i'),
            decoration: BoxDecoration(color: _codeBg(t), borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: _selectable(
                i,
                b,
                TextStyle(fontFamily: mono, fontSize: s.size * .8, height: 1.45, color: t.ink, fontVariations: const [FontVariation.weight(450)]),
                TextAlign.start,
              ),
            ),
          ),
        );
      case BlockKind.image:
        return Padding(padding: pad.add(EdgeInsets.only(bottom: s.size * .9)), child: _image(i, b, t));
      case BlockKind.table:
        return Padding(padding: pad.add(EdgeInsets.only(bottom: s.size * .9)), child: _table(b, t));
    }
  }

  /// Item de lista: marcador (•, 1., caixa de tarefa) e o texto à direita.
  Widget _listRow(int i, Block b, PageTheme t, Widget text, {bool marker = true}) => Padding(
    padding: EdgeInsets.only(left: 6.0 + b.indent * s.size * 1.4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: s.size * 1.6,
          child: !marker
              ? null
              : switch (b.marker) {
                  // tarefas (- [x] / - [ ]): caixa marcada ou vazia
                  '☑' || '☐' => Padding(
                    padding: EdgeInsets.only(top: s.size * (s.lineHeight - 1.05) / 2),
                    child: Icon(
                      b.marker == '☑' ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: s.size * 1.05,
                      color: b.marker == '☑' ? (t.dark ? Lume.amber : Lume.accent) : t.muted,
                    ),
                  ),
                  _ => Text(b.marker, style: _bodyStyle.copyWith(color: b.marker.length == 1 ? (t.dark ? Lume.amber : Lume.accent) : t.ink)),
                },
        ),
        Expanded(child: text),
      ],
    ),
  );

  Widget _image(int i, Block b, PageTheme t) {
    final src = b.src ?? '';
    final caption = b.text.trim();
    Widget missing(String why) => Container(
      key: ValueKey('img-missing$i'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _codeBg(t),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.muted.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Icon(Icons.image_not_supported_outlined, color: t.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text('$why\n${caption.isEmpty ? src.split('/').last : caption}', style: Lume.s(14, color: t.muted, h: 1.35)),
          ),
        ],
      ),
    );
    final remote = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(src);
    if (remote) return missing('Imagem da internet (o Lume não usa internet)');
    final f = File(src);
    if (!f.existsSync()) return missing('Imagem não encontrada');
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            f,
            key: ValueKey('img$i'),
            height: _imgH, // no modo página a imagem ocupa uma altura fixa
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => missing('Não foi possível abrir a imagem'),
          ),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(caption, textAlign: TextAlign.center, style: Lume.s(13.5, color: t.muted, h: 1.3)),
          ),
      ],
    );
  }

  Widget _table(Block b, PageTheme t) {
    final rows = b.rows ?? const [];
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final line = t.muted.withValues(alpha: .35);
    TextAlign align(int c) => switch (b.aligns != null && c < b.aligns!.length ? b.aligns![c] : null) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(horizontalInside: BorderSide(color: line), bottom: BorderSide(color: line), top: BorderSide(color: line)),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: r == 0 ? BoxDecoration(color: _codeBg(t)) : null,
              children: [
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      c < rows[r].length ? rows[r][c] : '',
                      textAlign: align(c),
                      style: _bodyStyle.copyWith(fontSize: s.size * .85, height: 1.35, fontWeight: r == 0 ? FontWeight.w700 : null),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Texto selecionável do bloco [i]; no modo página, só o pedaço [from]–[to].
  Widget _selectable(int i, Block b, TextStyle style, TextAlign align, {int from = 0, int? to}) {
    final spans = _spans(i, b, _hlsFor(i), style, from: from, to: to);
    return SelectableText.rich(
      TextSpan(children: spans, style: style),
      key: ValueKey(from == 0 ? 'block$i' : 'block$i@$from'),
      textAlign: align,
      cursorColor: Lume.accent,
      onSelectionChanged: (sel, cause) {
        _selecting = !sel.isCollapsed;
        // um toque simples não deve deixar a alça do cursor na tela (o toque vira página ou mostra os botões)
        if (sel.isCollapsed && cause == SelectionChangedCause.tap) {
          WidgetsBinding.instance.addPostFrameCallback((_) => FocusManager.instance.primaryFocus?.unfocus());
        }
      },
      selectionColor: s.theme.dark ? const Color(0x664A7FB0) : const Color(0x553C7DC4),
      contextMenuBuilder: (context, st) {
        final local = st.textEditingValue.selection;
        if (!local.isValid || local.isCollapsed) return const SizedBox.shrink();
        final sel = TextSelection(baseOffset: local.start + from, extentOffset: local.end + from); // posição no bloco todo
        final hasHl = hls.any((h) => h.block == i && h.start < sel.end && h.end > sel.start);
        void done() {
          st.hideToolbar();
          st.userUpdateTextEditingValue(st.textEditingValue.copyWith(selection: TextSelection.collapsed(offset: local.end)), SelectionChangedCause.toolbar);
        }

        return HighlightToolbar(
          anchors: st.contextMenuAnchors,
          dark: s.theme.dark,
          canRemove: hasHl,
          onColor: (c) {
            done();
            _addHighlight(i, sel, c);
          },
          onNote: () {
            done();
            _noteFor(i, sel);
          },
          onCopy: () {
            Clipboard.setData(ClipboardData(text: b.text.substring(sel.start, sel.end)));
            done();
          },
          onRemove: () {
            done();
            _removeHighlights(i, sel);
          },
        );
      },
    );
  }

  List<InlineSpan> _spans(int index, Block b, List<Highlight> hs, TextStyle base, {int from = 0, int? to}) {
    final len = b.text.length;
    final end = to ?? len;
    final cuts = <int>{from, end};
    var o = 0;
    final runStarts = <int>[];
    for (final r in b.runs) {
      runStarts.add(o);
      o += r.text.length;
      cuts.add(o);
    }
    for (final h in hs) {
      cuts
        ..add(h.start.clamp(0, len))
        ..add(h.end.clamp(0, len));
    }
    final sorted = cuts.where((x) => x >= from && x <= end).toList()..sort();
    final out = <InlineSpan>[];
    var ri = 0;
    for (var k = 0; k < sorted.length - 1; k++) {
      final a = sorted[k], z = sorted[k + 1];
      if (z <= a) continue;
      while (ri < b.runs.length - 1 && runStarts[ri + 1] <= a) {
        ri++;
      }
      final run = b.runs[ri];
      final h = hs.lastWhere((h) => h.start <= a && h.end >= z, orElse: () => _none);
      final hl = !identical(h, _none);
      final link = run.link;
      final inlineCode = run.code && b.kind != BlockKind.code;
      out.add(
        TextSpan(
          text: b.text.substring(a, z),
          recognizer: link == null || link.isEmpty ? null : _linkRecognizer(index, ri, link),
          style: TextStyle(
            fontStyle: run.italic ? FontStyle.italic : null,
            fontWeight: run.bold ? FontWeight.w700 : null,
            fontFamily: inlineCode ? mono : null,
            fontSize: inlineCode ? base.fontSize! * .86 : null,
            fontVariations: inlineCode ? const [FontVariation.weight(450)] : (run.bold ? const [FontVariation.weight(700)] : null),
            color: link != null ? (s.theme.dark ? Lume.amber : Lume.accent) : null,
            backgroundColor: hl ? h.color.on(s.theme) : (inlineCode ? _codeBg(s.theme) : null),
            decoration: TextDecoration.combine([
              if (hl && h.note.isNotEmpty) TextDecoration.underline,
              if (link != null && !(hl && h.note.isNotEmpty)) TextDecoration.underline,
              if (run.strike) TextDecoration.lineThrough,
            ]),
            decorationColor: link != null && !(hl && h.note.isNotEmpty) ? (s.theme.dark ? Lume.amber : Lume.accent).withValues(alpha: .6) : Lume.accent,
            decorationThickness: 1.5,
          ),
        ),
      );
    }
    return out;
  }

  static final _none = Highlight(id: '', block: -1, start: 0, end: 0, color: HighlightColor.amarelo, text: '', created: DateTime(2000));
}

/// Barra que aparece sobre o texto selecionado: 4 cores, nota, copiar.
class HighlightToolbar extends StatelessWidget {
  const HighlightToolbar({
    super.key,
    required this.anchors,
    required this.onColor,
    required this.onNote,
    required this.onCopy,
    required this.onRemove,
    this.canRemove = false,
    this.dark = false,
  });
  final TextSelectionToolbarAnchors anchors;
  final ValueChanged<HighlightColor> onColor;
  final VoidCallback onNote, onCopy, onRemove;
  final bool canRemove, dark;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    final fg = dark ? Lume.ink : const Color(0xFFF6F0E4);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, top, 12, 0),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchors.primaryAnchor - Offset(12, top + 12),
          anchorBelow: (anchors.secondaryAnchor ?? anchors.primaryAnchor) - Offset(12, top - 24),
        ),
        child: Material(
          key: const ValueKey('hl-toolbar'),
          color: dark ? const Color(0xFFEDE3D1) : Lume.ink,
          elevation: 8,
          shadowColor: Colors.black38,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in HighlightColor.values)
                  Tooltip(
                    message: c.label,
                    child: InkResponse(
                      key: ValueKey('hl-${c.name}'),
                      onTap: () => onColor(c),
                      radius: 22,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: fg.withValues(alpha: .5), width: 1.5),
                        ),
                      ),
                    ),
                  ),
                Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 6), color: fg.withValues(alpha: .25)),
                IconButton(
                  key: const ValueKey('hl-note'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Nota',
                  onPressed: onNote,
                  icon: Icon(Icons.sticky_note_2_outlined, color: fg),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copiar',
                  onPressed: onCopy,
                  icon: Icon(Icons.content_copy_rounded, size: 20, color: fg),
                ),
                if (canRemove)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remover destaque',
                    onPressed: onRemove,
                    icon: Icon(Icons.format_color_reset_outlined, color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TocSheet extends StatelessWidget {
  const TocSheet({super.key, required this.book, required this.currentIndex});
  final Book book;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      maxChildSize: .94,
      builder: (context, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sumário', style: Lume.s(22, w: 650, family: Lume.serif)),
                      const SizedBox(height: 2),
                      Text('${book.meta.title} · ${book.toc.length} capítulos', style: Lume.s(14, color: Lume.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: ScrollController(initialScrollOffset: (currentIndex - 3).clamp(0, 1 << 20) * 52.0),
              itemCount: book.toc.length,
              itemExtent: 52,
              itemBuilder: (context, i) {
                final e = book.toc[i];
                final here = i == currentIndex;
                return InkWell(
                  onTap: () => Navigator.pop(context, e.block),
                  child: Container(
                    color: here ? Lume.accentSoft : null,
                    padding: EdgeInsets.only(left: 24.0 + e.depth * 16, right: 20),
                    child: Row(
                      children: [
                        if (here)
                          Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(Icons.circle, size: 8, color: Lume.accent),
                          ),
                        Expanded(
                          child: Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Lume.s(16, w: here ? 650 : 450, family: Lume.serif, color: here ? Lume.accent : Lume.ink),
                          ),
                        ),
                        Text(pct(book.progressAt(e.block)), style: Lume.s(13, color: Lume.muted)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> editNoteDialog(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Lume.card,
      title: Text('Nota', style: Lume.s(20, w: 650, family: Lume.serif)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        decoration: const InputDecoration(hintText: 'O que este trecho te fez pensar?', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Salvar')),
      ],
    ),
  );
}

/// Estilo, alinhamento e espaços de um bloco de texto.
class _TextSpec {
  const _TextSpec(this.style, this.align, {this.top = 0, this.bottom = 0, this.left = 0});
  final TextStyle style;
  final TextAlign align;
  final double top, bottom, left;
}
