import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Print de tela em docs/screenshots com sombras de verdade: o flutter_test
/// desliga as sombras e desenha um contorno preto no lugar (debugDisableShadows).
Future<void> snapShot(String name) async {
  final binding = TestWidgetsFlutterBinding.instance as AutomatedTestWidgetsFlutterBinding;
  void repaint(RenderObject o) {
    o.markNeedsPaint();
    o.visitChildren(repaint);
  }

  debugDisableShadows = false;
  try {
    binding.renderViews.forEach(repaint);
    await binding.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/screenshots/$name.png'));
  } finally {
    debugDisableShadows = true;
    binding.renderViews.forEach(repaint);
    await binding.pump();
  }
}
