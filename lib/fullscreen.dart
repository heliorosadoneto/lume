// Tela cheia ao ler: barras do Android escondidas e toque curto na área de leitura.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Esconde (imersivo) ou mostra as barras de status e de navegação do Android.
void applySystemUi({required bool immersive}) {
  SystemChrome.setEnabledSystemUIMode(immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge).catchError((Object _) {});
}

/// Reconhece o toque curto (sem arrastar, sem segurar) sem entrar na disputa de
/// gestos: o texto continua selecionável, a lista rola e o PageView desliza.
/// Chama [onTap] com a posição horizontal do toque, de 0 (esquerda) a 1 (direita).
///
/// Também reconhece o deslize rápido na horizontal ([onSwipe]: 1 = para a
/// esquerda, avança; -1 = para a direita, volta). O texto selecionável do
/// Flutter toma para si os arrastos na horizontal, então um PageView sozinho
/// não desliza por cima do texto; por isso o deslize é lido aqui.
class TapSpot extends StatefulWidget {
  const TapSpot({super.key, required this.onTap, this.onSwipe, required this.child});
  final void Function(double fx) onTap;
  final void Function(int dir)? onSwipe;
  final Widget child;
  @override
  State<TapSpot> createState() => _TapSpotState();
}

class _TapSpotState extends State<TapSpot> {
  int? _id;
  Offset _at = Offset.zero;
  Duration _t = Duration.zero;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      if (_id != null) {
        _id = -1; // dois dedos: não é toque
        return;
      }
      _id = e.pointer;
      _at = e.localPosition;
      _t = e.timeStamp;
    },
    onPointerUp: (e) {
      final d = e.localPosition - _at;
      final mine = _id == e.pointer;
      final ok = mine && d.distance < kTouchSlop && e.timeStamp - _t < const Duration(milliseconds: 300);
      if (_id == e.pointer || _id == -1) _id = null;
      if (mine && widget.onSwipe != null && d.dx.abs() >= 56 && d.dx.abs() > d.dy.abs() * 1.6 && e.timeStamp - _t < const Duration(milliseconds: 800)) {
        widget.onSwipe!(d.dx < 0 ? 1 : -1);
        return;
      }
      if (!ok) return;
      final w = (context.findRenderObject() as RenderBox).size.width;
      widget.onTap(w <= 0 ? .5 : (e.localPosition.dx / w).clamp(0.0, 1.0));
    },
    onPointerCancel: (_) => _id = null,
    child: widget.child,
  );
}

/// Executa [run] depois de [delay], a menos que outro toque chegue antes
/// (o duplo toque seleciona palavra ou dá zoom e não deve mostrar/esconder os botões).
class TapDebounce {
  Timer? _timer;
  void call(VoidCallback run, {Duration delay = const Duration(milliseconds: 260)}) {
    final pending = _timer?.isActive ?? false;
    _timer?.cancel();
    if (pending) return;
    _timer = Timer(delay, run);
  }

  void dispose() => _timer?.cancel();
}
