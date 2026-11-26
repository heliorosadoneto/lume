// Leitor de PDF do Lume: a página aparece como no original (PDFium via pdfrx),
// com rolagem contínua ou página a página, zoom com pinça, barra de páginas,
// "ir para a página", marcadores, sumário do PDF e os temas do app.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../epub.dart';
import '../fullscreen.dart';
import '../pdf_analysis.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key, required this.meta, this.now, this.crops, this.onTextMode, this.textMode, this.notice});
  final BookMeta meta;
  final DateTime Function()? now;

  /// Área com conteúdo de cada página (para cortar as margens brancas).
  final List<PageCrop>? crops;

  /// Troca para o modo texto. [textMode]: true = disponível, false = PDF sem
  /// texto (escaneado), null = ainda analisando.
  final VoidCallback? onTextMode;
  final bool? textMode;

  /// Aviso curto mostrado ao abrir (por exemplo: PDF escaneado).
  final String? notice;
  @override
  State<PdfReaderScreen> createState() => PdfReaderScreenState();
}

class PdfReaderScreenState extends State<PdfReaderScreen> {
  BookMeta get meta => widget.meta;
  late final PdfDocumentRef ref = PdfDocumentRefFile(meta.path);
  var viewer = PdfViewerController();
  late PageController pager;
  final zoomer = TransformationController();

  late ReaderSettings s = Store.settings;
  bool paged = Store.pdfPaged;
  bool original = Store.pdfOriginal;
  bool cropOn = Store.pdfCrop;
  List<PageCrop>? get crops => cropOn ? widget.crops : null;
  List<double> _contentTops = [];
  late List<Bookmark> bms = Store.bookmarks(meta.id);
  PdfDocument? doc;

  /// Página atual (1 = primeira).
  late int page;
  int? pageCount = 0;
  double? _sliderPreview;
  double zoom = 1; // relativo ao "caber na tela"

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  // ---------- tela cheia ----------
  /// Com "Tela cheia ao ler", barras do Android e botões começam escondidos;
  /// um toque no centro da página os mostra (por cima, sem mexer na página).
  late bool _chrome = !s.fullscreen;
  double _safeTop = 0, _safeBottom = 0;
  final _toggle = TapDebounce();
  bool get _showBars => !s.fullscreen || _chrome;

  void _tapped(double fx) {
    if (!s.fullscreen) return;
    // no modo página, as bordas viram a página; no contínuo, qualquer toque vale
    if (paged && (fx < .2 || fx > .8)) return;
    _toggle(() {
      if (!mounted) return;
      setState(() => _chrome = !_chrome);
      applySystemUi(immersive: !_showBars);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) applySystemUi(immersive: !_showBars);
    });
    page = (Store.pos(meta.id)?.block ?? 0) + 1;
    pageCount = Store.pages(meta.id);
    pager = PageController(initialPage: page - 1);
    viewer.addListener(_onViewerZoom);
    zoomer.addListener(_onPagedZoom);
    if (widget.notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.notice!), duration: const Duration(seconds: 6)));
      });
    }
  }

  @override
  void didUpdateWidget(PdfReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.crops == null) != (widget.crops == null) && cropOn) _newViewer();
  }

  /// O leitor contínuo é recriado quando o corte muda (layout diferente);
  /// cada PdfViewer novo precisa do seu próprio controlador.
  void _newViewer() {
    viewer.removeListener(_onViewerZoom);
    viewer = PdfViewerController()..addListener(_onViewerZoom);
    zoom = 1;
  }

  @override
  void dispose() {
    _toggle.dispose();
    applySystemUi(immersive: false);
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
    final top = n - 1 < _contentTops.length ? _contentTops[n - 1] : r.top;
    final h = viewer.viewSize.height / viewer.currentZoom;
    final w = viewer.layout.documentSize.width;
    await viewer.goToArea(rect: Rect.fromLTWH(0, top - 6, w, h), anchor: PdfPageAnchor.top, duration: duration);
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
      isScrollControlled: true,
      barrierColor: Colors.black12,
      builder: (sheet) => StatefulBuilder(
        builder: (context, set) => PdfAppearanceSheet(
          modeSwitch: widget.textMode == null && widget.onTextMode == null
              ? null
              : PdfModeSwitch(
                  text: false,
                  available: widget.textMode,
                  onChanged: (text) {
                    if (!text) return;
                    Navigator.pop(sheet);
                    widget.onTextMode?.call();
                  },
                ),
          crop: widget.crops == null ? null : cropOn,
          onCrop: (v) {
            set(() {});
            setState(() {
              cropOn = v;
              _newViewer();
            });
            Store.pdfCrop = v;
          },
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
    final mq = MediaQuery.of(context);
    _safeTop = _safeTop < mq.viewPadding.top ? mq.viewPadding.top : _safeTop;
    _safeBottom = _safeBottom < mq.viewPadding.bottom ? mq.viewPadding.bottom : _safeBottom;
    Widget reading() => Stack(children: [
      Positioned.fill(child: ClipRect(child: paged ? _pagedView(t) : _scrollView(t))),
      if (zoom > 1.05)
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(child: _ZoomPill(zoom: zoom, dark: t.dark, onReset: resetZoom)),
        ),
    ]);
    final Widget body;
    if (!s.fullscreen) {
      body = SafeArea(
        child: Column(children: [
          _topBar(t),
          Expanded(child: reading()),
          _bottomBar(t),
        ]),
      );
    } else {
      body = Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(top: _safeTop, bottom: _safeBottom),
            child: TapSpot(onTap: _tapped, child: reading()),
          ),
        ),
        if (_chrome) ...[
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Material(color: t.bg, elevation: 2, child: Padding(padding: EdgeInsets.only(top: _safeTop), child: _topBar(t))),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(color: t.bg, elevation: 2, child: Padding(padding: EdgeInsets.only(bottom: _safeBottom), child: _bottomBar(t))),
          ),
        ],
      ]);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(backgroundColor: t.bg, body: body),
    );
  }

  /// Páginas uma embaixo da outra, alinhadas pela área com texto: a largura do
  /// conteúdo mais comum ocupa a tela (as margens laterais ficam de fora).
  /// Página com conteúdo mais largo (capa, mapa) é reduzida para caber.
  PdfPageLayout _croppedLayout(List<PdfPage> pages, PdfViewerParams params) {
    final cs = crops!;
    const m = 8.0, gap = 12.0;
    PageCrop c(int i) => i < cs.length ? cs[i] : PageCrop.full;
    final widths = [for (var i = 0; i < pages.length; i++) c(i).width * pages[i].width]..sort();
    final docW = widths[((widths.length - 1) * .9).round()];
    final rects = <Rect>[];
    final tops = <double>[];
    var y = m;
    for (var i = 0; i < pages.length; i++) {
      final pg = pages[i], cr = c(i);
      final cw = cr.width * pg.width;
      final k = cw > docW ? docW / cw : 1.0;
      final left = m + (docW - cw * k) / 2 - cr.left * pg.width * k;
      rects.add(Rect.fromLTWH(left, y, pg.width * k, pg.height * k));
      tops.add(y + cr.top * pg.height * k);
      y += pg.height * k + gap;
    }
    _contentTops = tops;
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(docW + 2 * m, y - gap + m));
  }

  Widget _scrollView(PageTheme t) => PdfViewer(
        ref,
        key: ValueKey('pdf-scroll-${crops != null}-${viewer.hashCode}'),
        controller: viewer,
        params: PdfViewerParams(
          backgroundColor: t.bg,
          margin: crops != null ? 8 : 14,
          layoutPages: crops != null ? _croppedLayout : null,
          pageImageColorFilter: filter,
          pageDropShadow: crops != null
              ? null
              : BoxShadow(color: Colors.black.withValues(alpha: t.dark ? .5 : .14), blurRadius: 10, offset: const Offset(0, 3)),
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
    final cr = crops == null || n - 1 >= crops!.length ? null : crops![n - 1];
    final pageWidget = cr != null ? _croppedPage(d, n, cr) : Padding(
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

  /// Só a área com conteúdo da página, do maior tamanho que couber na tela.
  Widget _croppedPage(PdfDocument d, int n, PageCrop cr) {
    final pg = d.pages[n - 1];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: LayoutBuilder(builder: (context, c) {
        final cw = cr.width * pg.width, ch = cr.height * pg.height;
        final k = math.min(c.maxWidth / cw, c.maxHeight / ch);
        return Center(
          child: Container(
            width: cw * k,
            height: ch * k,
            color: Colors.white,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(-cr.left * pg.width * k, -cr.top * pg.height * k),
                  child: SizedBox(
                    width: pg.width * k,
                    height: pg.height * k,
                    child: PdfPageView(
                      document: d,
                      pageNumber: n,
                      pageSizeCallback: (size, p, rot) {
                        final sc = math.min(300 / 72, math.min(size.width / p.width, size.height / p.height) * 2);
                        return Size(p.width * sc, p.height * sc);
                      },
                      decoration: const BoxDecoration(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
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
      required this.onOriginal,
      this.modeSwitch,
      this.crop,
      this.onCrop});
  final PageTheme theme;
  final bool paged, original;
  final ValueChanged<PageTheme> onTheme;
  final ValueChanged<bool> onPaged, onOriginal;
  final Widget? modeSwitch;

  /// Corte das margens brancas; null esconde a opção.
  final bool? crop;
  final ValueChanged<bool>? onCrop;

  @override
  Widget build(BuildContext context) => SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aparência do PDF', style: Lume.s(22, w: 650, family: Lume.serif)),
          ?modeSwitch,
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
          if (crop != null)
            SwitchListTile(
              key: const ValueKey('pdf-crop'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Cortar margens brancas'),
              subtitle: const Text('A área com texto ocupa a largura da tela'),
              value: crop!,
              onChanged: onCrop,
            ),
        ]),
      ));
}


/// Troca entre o modo texto (o PDF refeito em parágrafos, com fonte e tamanho
/// do Lume) e a página original. Fica no topo das duas folhas de aparência.
class PdfModeSwitch extends StatelessWidget {
  const PdfModeSwitch({super.key, required this.text, required this.available, required this.onChanged});

  /// Modo atual: true = texto.
  final bool text;

  /// true = o PDF tem texto; false = escaneado; null = ainda analisando.
  final bool? available;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            key: const ValueKey('pdf-text-mode'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: true,
                enabled: available != false,
                icon: const Icon(Icons.subject_rounded),
                label: const Text('Modo texto'),
              ),
              const ButtonSegment(value: false, icon: Icon(Icons.picture_as_pdf_outlined), label: Text('Página original')),
            ],
            selected: {text},
            onSelectionChanged: (v) => onChanged(v.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(switch ((text, available)) {
          (true, _) =>
            'O texto do PDF refeito em parágrafos: fonte, tamanho e margens como nos EPUBs. '
                'Tabelas, fórmulas e imagens só aparecem na página original.',
          (false, false) => 'Este PDF é escaneado (as páginas são imagens), então não há texto para o modo texto.',
          (false, null) => 'O modo texto ainda está sendo preparado…',
          _ => 'A página como no arquivo. O modo texto deixa a letra do tamanho que você quiser.',
        }, style: Lume.s(13.5, color: Lume.muted, h: 1.35)),
      ],
    ),
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
                                Padding(padding: EdgeInsets.only(right: 10), child: Icon(Icons.circle, size: 8, color: Lume.accent)),
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
                          leading: Icon(Icons.bookmark_rounded, color: Lume.accent),
                          title: Text('Página ${b.block + 1}'),
                          subtitle: Text(b.excerpt.isEmpty ? fmtDate(b.created) : b.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: 'Remover marcador',
                            icon: Icon(Icons.close_rounded, color: Lume.muted),
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
