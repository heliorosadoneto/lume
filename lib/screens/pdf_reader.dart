// Leitor de PDF do Lume: a página aparece como no original (PDFium via pdfrx),
// com rolagem contínua ou página a página, zoom com pinça, barra de páginas,
// "ir para a página", marcadores, sumário do PDF e os temas do app.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../epub.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key, required this.meta, this.now});
  final BookMeta meta;
  final DateTime Function()? now;
  @override
  State<PdfReaderScreen> createState() => PdfReaderScreenState();
}

class PdfReaderScreenState extends State<PdfReaderScreen> {
  BookMeta get meta => widget.meta;
  late final PdfDocumentRef ref = PdfDocumentRefFile(meta.path);
  final viewer = PdfViewerController();
  late PageController pager;
  final zoomer = TransformationController();

  late ReaderSettings s = Store.settings;
  bool paged = Store.pdfPaged;
  bool original = Store.pdfOriginal;
  late List<Bookmark> bms = Store.bookmarks(meta.id);
  PdfDocument? doc;

  /// Página atual (1 = primeira).
  late int page;
  int? pageCount = 0;
  double? _sliderPreview;
  double zoom = 1; // relativo ao "caber na tela"

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    page = (Store.pos(meta.id)?.block ?? 0) + 1;
    pageCount = Store.pages(meta.id);
    pager = PageController(initialPage: page - 1);
    viewer.addListener(_onViewerZoom);
    zoomer.addListener(_onPagedZoom);
  }

  @override
  void dispose() {
    viewer.removeListener(_onViewerZoom);
    zoomer.dispose();
    pager.dispose();
    super.dispose();
  }

  int get count => pageCount ?? doc?.pages.length ?? 1;
  ColorFilter? get filter => original ? null : pdfPageFilter(s.theme);

  void _ready(PdfDocument d) {
    if (doc == d) return;
    doc = d;
    if (pageCount != d.pages.length) Store.setPages(meta.id, d.pages.length);
    pageCount = d.pages.length;
    page = page.clamp(1, d.pages.length);
    _save();
    if (mounted) setState(() {});
  }

  void _save() => Store.savePos(meta.id, ReadingPos(page - 1, 0, count <= 1 ? 1 : page / count, _now()));

  void _onPage(int? n) {
    if (n == null || n == page) return;
    setState(() => page = n);
    _save();
  }

  void _onViewerZoom() {
    if (!viewer.isReady) return;
    final z = viewer.currentZoom / viewer.coverScale;
    if ((z - zoom).abs() > .01) setState(() => zoom = z);
  }

  void _onPagedZoom() {
    final z = zoomer.value.getMaxScaleOnAxis();
    if ((z - zoom).abs() > .01) setState(() => zoom = z);
  }

  Future<void> goTo(int n, {bool animate = true}) async {
    n = n.clamp(1, count);
    setState(() => page = n);
    _save();
    if (paged) {
      zoomer.value = Matrix4.identity();
      if (!pager.hasClients) return;
      if (animate && (pager.page! - (n - 1)).abs() <= 1) {
        await pager.animateToPage(n - 1, duration: const Duration(milliseconds: 280), curve: Curves.easeInOutCubic);
      } else {
        pager.jumpToPage(n - 1);
      }
    } else if (viewer.isReady) {
      await _alignTop(n, animate ? const Duration(milliseconds: 250) : Duration.zero);
    }
  }

  /// Leva o topo da página n ao topo da tela (o goToPage centraliza páginas
  /// menores que a tela, o que deixa o fim da página anterior à vista).
  Future<void> _alignTop(int n, Duration duration) async {
    if (!viewer.isReady) return;
    final r = viewer.layout.pageLayouts[n - 1];
    final h = viewer.viewSize.height / viewer.currentZoom;
    await viewer.goToArea(rect: Rect.fromLTWH(r.left, r.top - 6, r.width, h), anchor: PdfPageAnchor.top, duration: duration);
  }

  void resetZoom() {
    if (paged) {
      zoomer.value = Matrix4.identity();
    } else if (viewer.isReady) {
      viewer.setZoom(viewer.centerPosition, viewer.coverScale);
    }
  }

  // ---------- marcadores ----------
  bool get bookmarked => bms.any((b) => b.block == page - 1);

  Future<void> toggleBookmark() async {
    final i = page - 1;
    if (bookmarked) {
      setState(() => bms.removeWhere((b) => b.block == i));
    } else {
      var excerpt = '';
      try {
        final t = await doc?.pages[i].loadText();
        excerpt = (t?.fullText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      } catch (_) {}
      if (excerpt.length > 120) excerpt = '${excerpt.substring(0, 120)}…';
      setState(() => bms.add(Bookmark(i, excerpt, _now())));
    }
    Store.saveBookmarks(meta.id, bms);
  }

  // ---------- painéis ----------
  Future<void> openGoTo() async {
    final n = await goToPageDialog(context, page, count);
    if (n != null) await goTo(n, animate: false);
  }

  Future<void> openContents() async {
    var outline = <PdfOutlineNode>[];
    try {
      outline = await doc?.loadOutline() ?? [];
    } catch (_) {}
    if (!mounted) return;
    final r = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PdfContentsSheet(bookId: meta.id, title: meta.title, page: page, count: count, outline: outline, bookmarks: bms),
    );
    setState(() => bms = Store.bookmarks(meta.id));
    if (r != null) await goTo(r, animate: false);
  }

  Future<void> openAppearance() async {
    await showModalBottomSheet<void>(
      context: context,
      barrierColor: Colors.black12,
      builder: (_) => StatefulBuilder(
        builder: (context, set) => PdfAppearanceSheet(
          theme: s.theme,
          paged: paged,
          original: original,
          onTheme: (t) {
            set(() {});
            setState(() => s = Store.settings..theme = t);
            Store.settings = s;
          },
          onPaged: (v) {
            set(() {});
            setState(() {
              paged = v;
              zoom = 1;
              zoomer.value = Matrix4.identity();
              pager.dispose();
              pager = PageController(initialPage: page - 1);
            });
            Store.pdfPaged = v;
          },
          onOriginal: (v) {
            set(() {});
            setState(() => original = v);
            Store.pdfOriginal = v;
          },
        ),
      ),
    );
  }

  // ---------- interface ----------
  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Column(children: [
            _topBar(t),
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: ClipRect(child: paged ? _pagedView(t) : _scrollView(t))),
                if (zoom > 1.05)
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(child: _ZoomPill(zoom: zoom, dark: t.dark, onReset: resetZoom)),
                  ),
              ]),
            ),
            _bottomBar(t),
          ]),
        ),
      ),
    );
  }

  Widget _scrollView(PageTheme t) => PdfViewer(
        ref,
        key: const ValueKey('pdf-scroll'),
        controller: viewer,
        params: PdfViewerParams(
          backgroundColor: t.bg,
          margin: 14,
          pageImageColorFilter: filter,
          pageDropShadow: BoxShadow(color: Colors.black.withValues(alpha: t.dark ? .5 : .14), blurRadius: 10, offset: const Offset(0, 3)),
          calculateInitialPageNumber: (d, c) => page.clamp(1, d.pages.length),
          onViewerReady: (d, c) {
            _ready(d);
            // começa com o topo da página salva alinhado ao topo da tela
            _alignTop(page, Duration.zero);
          },
          onPageChanged: _onPage,
          loadingBannerBuilder: (context, done, total) => _loading(t),
          errorBannerBuilder: (context, e, st, r) => _error(t, e),
        ),
      );

  Widget _pagedView(PageTheme t) => PdfDocumentViewBuilder(
        documentRef: ref,
        loadingBuilder: (context) => _loading(t),
        errorBuilder: (context, e, st) => _error(t, e),
        builder: (context, d) {
          if (d == null) return _loading(t);
          if (doc != d) WidgetsBinding.instance.addPostFrameCallback((_) => _ready(d));
          return LayoutBuilder(
            builder: (context, c) => Stack(children: [
              PageView.builder(
                key: const ValueKey('pdf-paged'),
                controller: pager,
                physics: zoom > 1.02 ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                itemCount: d.pages.length,
                onPageChanged: (i) {
                  zoomer.value = Matrix4.identity();
                  _onPage(i + 1);
                },
                itemBuilder: (context, i) => _pagedPage(t, d, i + 1),
              ),
              if (zoom <= 1.02) ...[
                Positioned(left: 0, top: 0, bottom: 0, width: c.maxWidth * .18, child: _tapZone(-1)),
                Positioned(right: 0, top: 0, bottom: 0, width: c.maxWidth * .18, child: _tapZone(1)),
              ],
            ]),
          );
        },
      );

  Widget _pagedPage(PageTheme t, PdfDocument d, int n) {
    final pageWidget = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: PdfPageView(
        document: d,
        pageNumber: n,
        // renderiza com o dobro da resolução da tela para o zoom ficar nítido
        pageSizeCallback: (size, pg, rot) {
          final sc = math.min(300 / 72, math.min(size.width / pg.width, size.height / pg.height) * 2);
          return Size(pg.width * sc, pg.height * sc);
        },
        decoration: BoxDecoration(color: Colors.white, boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: t.dark ? .5 : .14), blurRadius: 10, offset: const Offset(0, 3)),
        ]),
      ),
    );
    final f = filter;
    return GestureDetector(
      onDoubleTapDown: (e) => _dtap = e.localPosition,
      onDoubleTap: () {
        if (zoom > 1.05) {
          zoomer.value = Matrix4.identity();
        } else {
          const sc = 2.5;
          final o = _dtap * (1 - sc);
          zoomer.value = Matrix4.identity()
            ..translateByDouble(o.dx, o.dy, 0, 1)
            ..scaleByDouble(sc, sc, 1, 1);
        }
      },
      child: InteractiveViewer(
        key: ValueKey('zoom$n'),
        transformationController: n == page ? zoomer : null,
        minScale: 1,
        maxScale: 5,
        child: f == null ? pageWidget : ColorFiltered(colorFilter: f, child: pageWidget),
      ),
    );
  }

  Offset _dtap = Offset.zero;

  Widget _tapZone(int dir) => GestureDetector(
        key: ValueKey('pdfpage$dir'),
        behavior: HitTestBehavior.translucent,
        onTap: () => goTo(page + dir),
      );

  Widget _loading(PageTheme t) => Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: t.dark ? Lume.amber : Lume.accent)),
      );

  Widget _error(PageTheme t, Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            e.toString().toLowerCase().contains('password')
                ? 'Este PDF é protegido por senha. Por enquanto o Lume não abre PDFs com senha.'
                : 'Não foi possível abrir este PDF.\n$e',
            textAlign: TextAlign.center,
            style: Lume.s(15.5, color: t.muted, h: 1.4),
          ),
        ),
      );

  Widget _topBar(PageTheme t) {
    Widget btn(IconData i, String tip, VoidCallback f, {Color? color}) =>
        IconButton(icon: Icon(i, color: color ?? t.ink.withValues(alpha: .78)), tooltip: tip, onPressed: f);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(children: [
        btn(Icons.arrow_back_rounded, 'Biblioteca', () => Navigator.of(context).maybePop()),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(15.5, w: 650, color: t.ink)),
            Text(meta.author.isEmpty ? 'PDF · $count páginas' : '${meta.author} · PDF',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Lume.s(13, color: t.muted)),
          ]),
        ),
        btn(Icons.toc_rounded, 'Sumário e marcadores', openContents),
        btn(Icons.pin_outlined, 'Ir para a página', openGoTo),
        btn(Icons.text_fields_rounded, 'Aparência', openAppearance),
        btn(bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, 'Marcador', toggleBookmark,
            color: bookmarked ? Lume.accent : null),
      ]),
    );
  }

  Widget _bottomBar(PageTheme t) {
    final shown = (_sliderPreview?.round() ?? page).clamp(1, count);
    final accent = t.dark ? Lume.amber : Lume.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            thumbColor: accent,
            inactiveTrackColor: t.muted.withValues(alpha: .25),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            key: const ValueKey('pdf-slider'),
            min: 1,
            max: math.max(2, count).toDouble(),
            value: shown.toDouble().clamp(1, math.max(2, count).toDouble()),
            onChanged: count <= 1 ? null : (v) => setState(() => _sliderPreview = v),
            onChangeEnd: (v) {
              _sliderPreview = null;
              goTo(v.round(), animate: false);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            InkWell(
              key: const ValueKey('pdf-page-label'),
              borderRadius: BorderRadius.circular(8),
              onTap: openGoTo,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('Página $shown de $count', style: Lume.s(13.5, color: _sliderPreview != null ? accent : t.muted, w: 600)),
              ),
            ),
            const Spacer(),
            Text('${pct(count <= 1 ? 1 : shown / count)} do livro', style: Lume.s(13, color: t.muted)),
          ]),
        ),
      ]),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  const _ZoomPill({required this.zoom, required this.dark, required this.onReset});
  final double zoom;
  final bool dark;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? Lume.ink : Lume.paper;
    return Material(
      key: const ValueKey('zoom-pill'),
      color: (dark ? const Color(0xFFEDE3D1) : Lume.ink).withValues(alpha: .9),
      shape: const StadiumBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onReset,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.zoom_in_rounded, size: 18, color: fg),
            const SizedBox(width: 6),
            Text('${(zoom * 100).round()}%', style: Lume.s(14, w: 650, color: fg)),
            Container(width: 1, height: 16, margin: const EdgeInsets.symmetric(horizontal: 10), color: fg.withValues(alpha: .3)),
            Text('Ajustar à tela', style: Lume.s(14, color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// Aparência do PDF: tema da página, modo de leitura e cores originais.
class PdfAppearanceSheet extends StatelessWidget {
  const PdfAppearanceSheet(
      {super.key,
      required this.theme,
      required this.paged,
      required this.original,
      required this.onTheme,
      required this.onPaged,
      required this.onOriginal});
  final PageTheme theme;
  final bool paged, original;
  final ValueChanged<PageTheme> onTheme;
  final ValueChanged<bool> onPaged, onOriginal;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aparência do PDF', style: Lume.s(22, w: 650, family: Lume.serif)),
          const SizedBox(height: 4),
          Text('A página continua como no original; o tema muda o papel e a tinta.', style: Lume.s(14, color: Lume.muted)),
          const SizedBox(height: 18),
          Row(children: [
            for (final t in PageTheme.values)
              Expanded(
                child: GestureDetector(
                  key: ValueKey('pdftheme-${t.name}'),
                  onTap: () => onTheme(t),
                  child: Column(children: [
                    Container(
                      height: 54,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t == theme ? Lume.accent : Lume.line, width: t == theme ? 2.4 : 1),
                      ),
                      alignment: Alignment.center,
                      child: Text('Aa', style: Lume.s(19, w: 600, color: t.ink, family: Lume.serif)),
                    ),
                    const SizedBox(height: 6),
                    Text(t.label, style: Lume.s(13, color: t == theme ? Lume.accent : Lume.muted, w: t == theme ? 650 : 400)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          Text('Modo de leitura', style: Lume.s(15, w: 650)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              key: const ValueKey('pdf-mode'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.swap_vert_rounded), label: Text('Rolagem contínua')),
                ButtonSegment(value: true, icon: Icon(Icons.swap_horiz_rounded), label: Text('Página a página')),
              ],
              selected: {paged},
              onSelectionChanged: (v) => onPaged(v.first),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cores originais da página'),
            subtitle: const Text('Ignora o tema nas páginas (útil para fotos e mapas)'),
            value: original,
            onChanged: onOriginal,
          ),
        ]),
      );
}

/// Sumário do PDF (quando o arquivo tem) e marcadores.
class PdfContentsSheet extends StatefulWidget {
  const PdfContentsSheet(
      {super.key,
      required this.bookId,
      required this.title,
      required this.page,
      required this.count,
      required this.outline,
      required this.bookmarks});
  final String bookId, title;
  final int page, count;
  final List<PdfOutlineNode> outline;
  final List<Bookmark> bookmarks;
  @override
  State<PdfContentsSheet> createState() => _PdfContentsSheetState();
}

class _PdfContentsSheetState extends State<PdfContentsSheet> {
  late final entries = <(String, int, int)>[
    for (final e in _flatten(widget.outline, 0))
      if (e.$1.dest?.pageNumber != null) (e.$1.title, e.$1.dest!.pageNumber, e.$2)
  ];
  late List<Bookmark> bms = [...widget.bookmarks]..sort((a, b) => a.block.compareTo(b.block));

  static Iterable<(PdfOutlineNode, int)> _flatten(List<PdfOutlineNode> l, int depth) sync* {
    for (final n in l) {
      yield (n, depth);
      yield* _flatten(n.children, depth + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = entries.lastIndexWhere((e) => e.$2 <= widget.page);
    return DefaultTabController(
      length: 2,
      initialIndex: entries.isEmpty && bms.isNotEmpty ? 1 : 0,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .86,
        maxChildSize: .94,
        builder: (context, ctrl) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sumário', style: Lume.s(22, w: 650, family: Lume.serif)),
                  const SizedBox(height: 2),
                  Text('${widget.title} · ${widget.count} páginas', style: Lume.s(14, color: Lume.muted)),
                ]),
              ),
            ]),
          ),
          TabBar(
            labelStyle: Lume.s(15, w: 650),
            unselectedLabelStyle: Lume.s(15),
            labelColor: Lume.accent,
            unselectedLabelColor: Lume.muted,
            indicatorColor: Lume.accent,
            tabs: [Tab(text: 'Capítulos (${entries.length})'), Tab(text: 'Marcadores (${bms.length})')],
          ),
          Expanded(
            child: TabBarView(children: [
              entries.isEmpty
                  ? _empty('Este PDF não tem sumário.\nUse “Ir para a página” ou a barra de páginas.')
                  : ListView.builder(
                      controller: ScrollController(initialScrollOffset: (current - 3).clamp(0, 1 << 20) * 52.0),
                      itemCount: entries.length,
                      itemExtent: 52,
                      itemBuilder: (context, i) {
                        final (title, pg, depth) = entries[i];
                        final here = i == current;
                        return InkWell(
                          onTap: () => Navigator.pop(context, pg),
                          child: Container(
                            color: here ? Lume.accentSoft : null,
                            padding: EdgeInsets.only(left: 24.0 + depth * 16, right: 20),
                            child: Row(children: [
                              if (here)
                                const Padding(padding: EdgeInsets.only(right: 10), child: Icon(Icons.circle, size: 8, color: Lume.accent)),
                              Expanded(
                                child: Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Lume.s(16, w: here ? 650 : 450, family: Lume.serif, color: here ? Lume.accent : Lume.ink)),
                              ),
                              Text('p. $pg', style: Lume.s(13, color: Lume.muted)),
                            ]),
                          ),
                        );
                      },
                    ),
              bms.isEmpty
                  ? _empty('Nenhum marcador ainda.\nToque no ícone de marcador para guardar a página.')
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: bms.length,
                      separatorBuilder: (_, _) => const Divider(indent: 24, endIndent: 24),
                      itemBuilder: (context, i) {
                        final b = bms[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(24, 2, 12, 2),
                          leading: const Icon(Icons.bookmark_rounded, color: Lume.accent),
                          title: Text('Página ${b.block + 1}'),
                          subtitle: Text(b.excerpt.isEmpty ? fmtDate(b.created) : b.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: 'Remover marcador',
                            icon: const Icon(Icons.close_rounded, color: Lume.muted),
                            onPressed: () {
                              setState(() => bms.remove(b));
                              final all = widget.bookmarks..removeWhere((x) => x.block == b.block);
                              Store.saveBookmarks(widget.bookId, all);
                            },
                          ),
                          onTap: () => Navigator.pop(context, b.block + 1),
                        );
                      },
                    ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _empty(String t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t, textAlign: TextAlign.center, style: Lume.s(15.5, color: Lume.muted, h: 1.4)),
        ),
      );
}

Future<int?> goToPageDialog(BuildContext context, int page, int count) {
  final ctrl = TextEditingController(text: '$page');
  return showDialog<int>(
    context: context,
    builder: (context) {
      void submit() {
        final n = int.tryParse(ctrl.text.trim());
        if (n != null && n >= 1 && n <= count) Navigator.pop(context, n);
      }

      return AlertDialog(
        backgroundColor: Lume.card,
        title: Text('Ir para a página', style: Lume.s(20, w: 650, family: Lume.serif)),
        content: TextField(
          key: const ValueKey('goto-field'),
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(helperText: 'De 1 a $count', border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(key: const ValueKey('goto-ok'), onPressed: submit, child: const Text('Ir')),
        ],
      );
    },
  );
}
