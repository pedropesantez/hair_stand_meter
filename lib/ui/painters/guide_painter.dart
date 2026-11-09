import 'package:flutter/material.dart';

/// Marcas sobre la vista previa para tomar la foto siempre igual:
///  * marco de la tabla con esquinas (se oscurece lo de afuera);
///  * línea roja: altura de la base de los sujetadores;
///  * cruz central: para centrar el teléfono sobre la tabla.
class GuidePainter extends CustomPainter {
  const GuidePainter({required this.roi, required this.baseFraction});

  /// Marco normalizado (0..1) sobre la vista previa.
  final Rect roi;

  /// Altura de la base dentro del marco (0 = arriba, 1 = abajo).
  final double baseFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      roi.left * size.width,
      roi.top * size.height,
      roi.width * size.width,
      roi.height * size.height,
    );

    // Oscurece todo lo que queda fuera del marco.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(r),
    );
    canvas.drawPath(outside, Paint()..color = const Color(0x8C000000));

    // Esquinas del marco.
    final frame = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final c = size.shortestSide * 0.06;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * c, 0), frame);
      canvas.drawLine(o, o + Offset(0, dy * c), frame);
    }

    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomLeft, 1, -1);
    corner(r.bottomRight, -1, -1);

    // Línea base de los sujetadores.
    final baseY = r.top + baseFraction * r.height;
    final basePaint = Paint()
      ..color = const Color(0xFFFF5252)
      ..strokeWidth = 2.5;
    canvas.drawLine(Offset(r.left, baseY), Offset(r.right, baseY), basePaint);

    // Cruz central para centrar el teléfono.
    final center = size.center(Offset.zero);
    final cross = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 1.5;
    const half = 18.0;
    canvas.drawLine(center + const Offset(-half, 0), center + const Offset(half, 0), cross);
    canvas.drawLine(center + const Offset(0, -half), center + const Offset(0, half), cross);
    canvas.drawCircle(center, 3, cross..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(GuidePainter old) =>
      old.roi != roi || old.baseFraction != baseFraction;
}
