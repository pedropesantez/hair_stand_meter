import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'detected_line.dart';

/// Resultado de un mechón (carril) en un frame.
class StrandResult {
  const StrandResult({
    required this.laneIndex,
    required this.lane,
    this.endpointY,
    this.rangeIndex,
    this.confidence = 0,
    this.referenceDensity = 0,
    this.profile,
  });

  final int laneIndex;

  /// Carril, normalizado en el ROI.
  final Rect lane;

  /// Final del volumen principal (normalizado en el ROI, 0 = arriba).
  /// null si el carril está vacío.
  final double? endpointY;

  /// Rango k (ver BoardConfig.rangeIndexFor). null si el carril está vacío.
  final int? rangeIndex;

  /// 0..1: contraste entre el cuerpo del mechón y lo que hay por encima.
  final double confidence;

  /// D_ref: densidad típica del mechón cerca de los sujetadores.
  final double referenceDensity;

  /// Perfil de densidad suavizado por fila (para depuración visual).
  final Float32List? profile;

  bool get isEmpty => rangeIndex == null;
}

/// Resultado de un frame completo.
class FrameAnalysis {
  const FrameAnalysis({
    required this.strands,
    required this.processingMicros,
    required this.sampleWidth,
    required this.sampleHeight,
    this.detectedLines = const [],
  });

  final List<StrandResult> strands;
  final int processingMicros;
  final int sampleWidth;
  final int sampleHeight;

  /// Líneas impresas/dibujadas detectadas en este frame, ordenadas de abajo
  /// hacia arriba (la primera es la más cercana a los sujetadores).
  final List<DetectedLine> detectedLines;
}
