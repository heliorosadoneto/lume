import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'theme.dart';

String fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Caminho mais legível: "/storage/emulated/0/Livros" → "Armazenamento interno/Livros".
String friendlyPath(String path) {
  const internal = '/storage/emulated/0';
  final i = path.indexOf(internal);
  if (i < 0) return path;
  final rest = path.substring(i + internal.length);
  return 'Armazenamento interno${rest.isEmpty ? '' : rest}';
}

String pct(double v) => '${(v * 100).clamp(0, 100).round()}%';

/// Capa do livro; sem imagem, desenha uma capa tipográfica no tom do app.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.cover, required this.title, required this.width, this.radius = 8});
  final Uint8List? cover;
  final String title;
  final double width, radius;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.5;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [BoxShadow(color: Color(0x262B2622), blurRadius: 10, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: cover != null
          ? Image.memory(cover!, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: (width * 3).round())
          : Container(
              color: const Color(0xFF6E4A35),
              padding: EdgeInsets.all(width * 0.1),
              alignment: Alignment.center,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: Lume.s(width * 0.13, w: 600, color: const Color(0xFFF6E7CF), family: Lume.serif, h: 1.2),
              ),
            ),
    );
  }
}

/// Logo do Lume: a lua de páginas com o vaga-lume, em fundo terracota.
class LumeMark extends StatelessWidget {
  const LumeMark({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .3),
      boxShadow: [BoxShadow(color: const Color(0x33B85C38), blurRadius: size * .25, offset: Offset(0, size * .06))],
    ),
    child: Image.asset('assets/logo/lume.png', width: size, height: size, filterQuality: FilterQuality.medium),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 10)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Lume.s(19, w: 650, family: Lume.serif)),
        ),
        ?trailing,
      ],
    ),
  );
}

class ThinProgress extends StatelessWidget {
  const ThinProgress(this.value, {super.key, this.color = Lume.accent, this.track = Lume.line, this.height = 4});
  final double value, height;
  final Color color, track;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(value: value, minHeight: height, color: color, backgroundColor: track),
  );
}
