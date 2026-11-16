import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Retângulo da moldura de leitura dentro de uma área [s]: centralizado, largo e baixo, como um código de barras.
/// Usado para desenhar a moldura e para dizer ao leitor que só leia ali dentro.
Rect retanguloMoldura(Size s) {
  final largura = math.min(s.width * 0.85, 460.0);
  final altura = math.min(largura * 0.5, s.height * 0.4);
  return Rect.fromCenter(center: s.center(Offset.zero), width: largura, height: altura);
}

/// Escurece tudo fora da moldura, marca os cantos e traça a linha de leitura no meio, com a dica embaixo.
/// Não recebe toques (fica por cima da câmera).
class MolduraLeitura extends StatelessWidget {
  const MolduraLeitura({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(builder: (context, c) {
          final r = retanguloMoldura(c.biggest);
          return Stack(fit: StackFit.expand, children: [
            CustomPaint(key: const ValueKey('moldura_leitura'), painter: _PintorMoldura(r)),
            Positioned(
              left: 16,
              right: 16,
              top: r.bottom + 20,
              child: const Text(
                'Centralize o código de barras na moldura',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 4)]),
              ),
            ),
          ]);
        }),
      );
}

class _PintorMoldura extends CustomPainter {
  _PintorMoldura(this.r);
  final Rect r;

  @override
  void paint(Canvas canvas, Size size) {
    const raio = Radius.circular(14);
    final janela = RRect.fromRectAndRadius(r, raio);

    // Fora da moldura, escurecido.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(janela),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Contorno fino e cantos grossos.
    canvas.drawRRect(janela, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white54);
    final canto = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    final t = math.min(32.0, r.shortestSide / 3);
    for (final (x, y, dx, dy) in [
      (r.left, r.top, 1.0, 1.0),
      (r.right, r.top, -1.0, 1.0),
      (r.left, r.bottom, 1.0, -1.0),
      (r.right, r.bottom, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * t)
          ..lineTo(x, y)
          ..lineTo(x + dx * t, y),
        canto,
      );
    }

    // Linha de leitura no meio.
    canvas.drawLine(
      Offset(r.left + 12, r.center.dy),
      Offset(r.right - 12, r.center.dy),
      Paint()
        ..strokeWidth = 2
        ..color = Colors.redAccent.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_PintorMoldura antigo) => antigo.r != r;
}
