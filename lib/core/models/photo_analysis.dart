import 'package:flutter/painting.dart';

import '../config/board_config.dart';

/// Un mechón detectado en la foto.
class HairStrand {
  const HairStrand({
    required this.index,
    required this.box,
    required this.xCenter,
    required this.tipY,
    required this.label,
    this.cm,
  });

  /// Número del mechón, de izquierda a derecha, empezando en 1.
  final int index;

  /// Caja del mechón, normalizada en el ROI de la tabla.
  final Rect box;

  /// Centro horizontal del mechón, normalizado en el ROI.
  final double xCenter;

  /// Punta del volumen principal, normalizada en el ROI (0 = arriba).
  final double tipY;

  /// Texto del valor: "8 cm", "< 7 cm" (bajo la primera línea) o "≥ 14 cm"
  /// (por encima de la última).
  final String label;

  /// Valor fijo en cm: la línea inferior entre la que queda la punta.
  /// null si la punta quedó por debajo de la primera línea.
  final int? cm;

}

/// Calidad de la foto, con mensajes para el usuario.
class PhotoQuality {
  const PhotoQuality({
    required this.sharpness,
    required this.meanLuma,
    required this.warnings,
  });

  final double sharpness;
  final double meanLuma;
  final List<String> warnings;

  bool get ok => warnings.isEmpty;
}

/// Resultado del análisis de una foto fija.
class PhotoAnalysis {
  const PhotoAnalysis({
    required this.photoWidth,
    required this.photoHeight,
    required this.strands,
    required this.lines,
    required this.quality,
  });

  /// Tamaño (px) de la imagen de análisis, que es el ROI ya recortado.
  final int photoWidth;
  final int photoHeight;

  /// Mechones detectados, de izquierda a derecha.
  final List<HairStrand> strands;

  /// Líneas de la tabla, ordenadas de abajo hacia arriba (7 cm primero).
  final List<MeasurementLine> lines;

  final PhotoQuality quality;

}
