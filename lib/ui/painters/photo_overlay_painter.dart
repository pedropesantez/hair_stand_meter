import 'package:flutter/material.dart';

import '../../core/models/photo_analysis.dart';

/// Un color fijo por MEDIDA (cm). Todos los mechones de la misma medida
/// tienen el mismo color. Índice = cm − 7:
///   7 rosado, 8 morado, 9 rojo, 10 verde, 11 amarillo claro, 12 naranja,
///   13 celeste, 14 lila, 15 verde limón, 16 amarillo brillante, 17 azul,
///   18 blanco, 19 negro.
const List<Color> kLevelPalette = [
  Color(0xFFF48FB1), // 7 rosado
  Color(0xFF9C27B0), // 8 morado
  Color(0xFFE53935), // 9 rojo
  Color(0xFF43A047), // 10 verde
  Color(0xFFFFF59D), // 11 amarillo claro
  Color(0xFFFB8C00), // 12 naranja
  Color(0xFF81D4FA), // 13 celeste
  Color(0xFFCE93D8), // 14 lila
  Color(0xFFCDDC39), // 15 verde limón
  Color(0xFFFFEB3B), // 16 amarillo brillante
  Color(0xFF1E88E5), // 17 azul
  Color(0xFFFFFFFF), // 18 blanco
  Color(0xFF000000), // 19 negro
];

/// Gris para los mechones que quedan bajo la primera línea o sin referencia.
const Color kBelowLevelColor = Color(0xFFBDBDBD);

/// Color del mechón según su medida fija.
Color colorForStrand(HairStrand s) {
  final cm = s.cm;
  if (cm == null) return kBelowLevelColor;
  final raw = cm - 7;
  final i = raw < 0 ? 0 : (raw > kLevelPalette.length - 1 ? kLevelPalette.length - 1 : raw);
  return kLevelPalette[i];
}

/// Dibuja sobre la foto las líneas de referencia (con su valor en cm) y cada
/// mechón: caja, punta y su medida encima, sin número de orden.
class PhotoOverlayPainter extends CustomPainter {
  const PhotoOverlayPainter(this.analysis);

  final PhotoAnalysis analysis;

  static const _lineColor = Color(0xFFFFD54F);

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(double xn, double yn) => Offset(xn * size.width, yn * size.height);

    final linePaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final line in analysis.lines) {
      canvas.drawLine(at(0, line.yAt(0)), at(1, line.yAt(1)), linePaint);
      _label(canvas, '${line.cm}', at(0.004, line.yAt(0.004)),
          textColor: _lineColor, background: const Color(0xB0000000), below: false);
    }

    for (final s in analysis.strands) {
      final color = colorForStrand(s);
      final boxPaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final tipPaint = Paint()..color = color;
      final b = s.box;
      final rect = Rect.fromLTRB(
        b.left * size.width,
        b.top * size.height,
        b.right * size.width,
        b.bottom * size.height,
      );
      canvas.drawRect(rect, boxPaint);
      canvas.drawCircle(at(s.xCenter, s.tipY), 5, tipPaint);
      _label(canvas, s.label, rect.topCenter,
          textColor: _ink(color), background: color, below: true);
    }
  }

  /// Negro o blanco, lo que mejor se lee sobre [c].
  static Color _ink(Color c) => c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    required Color textColor,
    required Color background,
    required bool below,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          background: Paint()..color = background,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dy = below ? -tp.height - 2 : -tp.height / 2;
    tp.paint(canvas, anchor.translate(below ? -tp.width / 2 : 0, dy));
  }

  @override
  bool shouldRepaint(PhotoOverlayPainter old) => old.analysis != analysis;
}
