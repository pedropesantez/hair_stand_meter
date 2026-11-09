import 'package:flutter/painting.dart';

import '../models/detected_line.dart';

/// Línea horizontal de medición sobre la tabla.
class MeasurementLine {
  const MeasurementLine({
    required this.label,
    required this.cm,
    required this.y,
    String? shortLabel,
    this.slope = 0,
  }) : shortLabel = shortLabel ?? label;

  /// Texto completo, p. ej. "7 cm".
  final String label;

  /// Valor fijo de la línea en centímetros.
  final int cm;

  /// Texto compacto para dibujar sobre carriles estrechos, p. ej. "7".
  final String shortLabel;

  /// Posición vertical normalizada DENTRO del ROI de la tabla, en el centro
  /// horizontal (0.0 = borde superior del ROI, 1.0 = borde inferior).
  final double y;

  /// Pendiente de la línea (cambio de y por unidad de x). Las líneas dibujadas
  /// a mano no son perfectamente horizontales; 0 = horizontal.
  final double slope;

  /// Posición vertical de la línea en la columna normalizada [xn] (0..1).
  double yAt(double xn) => y + slope * (xn - 0.5);
}

/// Cómo se decide dónde termina el "volumen principal" del mechón.
enum EndpointStrategy {
  /// Última fila (subiendo desde la base) con densidad ≥ τ·D_ref,
  /// tolerando huecos de hasta G filas. Estrategia por defecto.
  relativeThreshold,

  /// Fila donde la masa acumulada desde la base alcanza el cuantil q.
  massQuantile,

  /// El más corto de los dos anteriores (más conservador).
  conservative,
}

/// Parámetros del algoritmo. Los tamaños en píxeles se refieren a la imagen
/// de análisis (sampleWidth × sampleHeight), NO a la resolución de la cámara.
class AnalysisParams {
  const AnalysisParams({
    this.sampleWidth = 400,
    this.sampleHeight = 200,
    this.subSamples = 3,
    this.hairIsDarkerThanBoard = true,
    this.useAdaptiveThreshold = false,
    this.openingKernelWidth = 5,
    this.openingKernelHeight = 3,
    this.smoothingWindow = 5,
    this.baseZoneFraction = 0.15,
    this.relativeDensityThreshold = 0.45,
    this.gapToleranceRows = 4,
    this.massQuantile = 0.97,
    this.minReferenceDensity = 0.12,
    this.lineMaskHalfHeight = 1,
    this.lineSnapTolerance = 0.004,
    this.endpointStrategy = EndpointStrategy.relativeThreshold,
    this.temporalWindow = 7,
    this.lineProbeOffset = 2,
    this.lineMinContrast = 20,
    this.lineColumnStart = 0.10,
    this.lineMaxSlope = 0.06,
    this.lineSlopeStep = 0.004,
    this.lineMinCover = 0.5,
    this.lineMinSeparation = 0.035,
    this.lineMaxCount = 15,
    this.lineStabilityWindow = 9,
    this.lineStabilityMinFrames = 6,
  });

  /// Resolución de la imagen de análisis, en orientación HORIZONTAL (la app
  /// se usa con el teléfono en landscape): más ancha que alta.
  final int sampleWidth;
  final int sampleHeight;

  /// Sub-muestras por eje al promediar cada píxel de análisis (filtro de
  /// área). Atenúa cabellos de 1-2 px antes incluso de binarizar.
  final int subSamples;

  /// true: cabello oscuro sobre tabla clara. false: cabello claro sobre tabla oscura.
  final bool hairIsDarkerThanBoard;

  /// Umbral adaptativo local (iluminación no uniforme) en lugar de Otsu global.
  final bool useAdaptiveThreshold;

  /// Kernel de la apertura morfológica (kw × kh). kw elimina cabellos
  /// verticales finos; kh elimina las líneas impresas horizontales.
  final int openingKernelWidth;
  final int openingKernelHeight;

  /// Ventana (filas) de la media móvil sobre el perfil de densidad.
  final int smoothingWindow;

  /// Fracción del largo del carril (justo encima de los sujetadores) usada
  /// para medir la densidad de referencia D_ref del mechón.
  final double baseZoneFraction;

  /// τ: fracción de D_ref por debajo de la cual una fila ya no es "volumen".
  final double relativeDensityThreshold;

  /// G: filas consecutivas por debajo de τ antes de dar el mechón por terminado.
  final int gapToleranceRows;

  /// q: cuantil de masa para EndpointStrategy.massQuantile.
  final double massQuantile;

  /// D_ref mínima para considerar que hay un mechón en el carril.
  final double minReferenceDensity;

  /// Filas (± alrededor de cada línea impresa) que se ignoran e interpolan.
  final int lineMaskHalfHeight;

  /// Si el final queda a menos de esta distancia (normalizada) por debajo de
  /// una línea, se considera que la alcanzó.
  final double lineSnapTolerance;

  final EndpointStrategy endpointStrategy;

  /// Frames usados por el suavizado temporal (moda + histéresis).
  final int temporalWindow;

  // ── Detección de líneas dibujadas ───────────────────────────────────────

  /// Distancia (filas) arriba/abajo de un píxel para comparar contra el papel.
  /// Debe ser mayor que la mitad del grosor de una línea.
  final int lineProbeOffset;

  /// Contraste mínimo (niveles de gris) entre el trazo y el papel.
  final int lineMinContrast;

  /// Fracción izquierda de la imagen que se ignora al buscar líneas: ahí
  /// suelen estar las etiquetas impresas ("14cm", …).
  final double lineColumnStart;

  /// Pendiente máxima considerada (dy/dx en píxeles de análisis).
  final double lineMaxSlope;

  /// Paso de pendiente al recorrer las posibles rectas.
  final double lineSlopeStep;

  /// Fracción mínima de columnas en las que la recta debe verse para aceptarla.
  final double lineMinCover;

  /// Separación mínima entre líneas, como fracción de sampleHeight.
  final double lineMinSeparation;

  /// Máximo de líneas a aceptar.
  final int lineMaxCount;

  /// Frames sobre los que se busca consenso antes de fijar las líneas, y
  /// cuántos de ellos deben coincidir en el número de líneas.
  final int lineStabilityWindow;
  final int lineStabilityMinFrames;
}

/// Geometría de la tabla. Todo es dinámico: N mechones y X líneas.
class BoardConfig {
  BoardConfig({
    required this.roi,
    required this.strandCount,
    required List<MeasurementLine> lines,
    required this.clipY,
    this.lanePadding = 0.12,
    List<Color>? palette,
  })  : assert(strandCount > 0, 'Debe haber al menos un mechón'),
        assert(lines.isNotEmpty, 'Debe haber al menos una línea'),
        linesFromBase = List.unmodifiable(
          [...lines]..sort((a, b) => b.y.compareTo(a.y)),
        ),
        palette = palette == null ? null : List.unmodifiable(palette);

  /// Configuración uniforme: líneas equiespaciadas y carriles del mismo ancho.
  /// Se usa sólo como marcador hasta que se detectan las líneas reales.
  factory BoardConfig.uniform({
    int strandCount = 6,
    int lineCount = 8,
    int firstLineCm = 7,
    int stepCm = 1,
    Rect roi = const Rect.fromLTWH(0.06, 0.10, 0.88, 0.78),
    double clipY = 0.92,
    double firstLineY = 0.84,
    double lastLineY = 0.06,
    List<Color>? palette,
  }) {
    final lines = List<MeasurementLine>.generate(lineCount, (i) {
      final t = lineCount == 1 ? 0.0 : i / (lineCount - 1);
      final cm = firstLineCm + i * stepCm;
      return MeasurementLine(
        label: '$cm cm',
        cm: cm,
        shortLabel: '$cm',
        y: firstLineY + (lastLineY - firstLineY) * t,
      );
    });
    return BoardConfig(
      roi: roi,
      strandCount: strandCount,
      lines: lines,
      clipY: clipY,
      palette: palette,
    );
  }

  /// Hardware actual: 6 mechones (las líneas se detectan en la imagen).
  factory BoardConfig.sixStrandsEightLines() => BoardConfig.uniform();

  /// Convierte las líneas detectadas en líneas de medición.
  ///
  /// La línea más cercana a los sujetadores es la PRIMERA línea dibujada y
  /// recibe el valor [firstLineCm]; las siguientes suben de 1 en 1 cm.
  static List<MeasurementLine> measurementLinesFrom(
    List<DetectedLine> detected, {
    int firstLineCm = 7,
    int stepCm = 1,
  }) {
    final sorted = [...detected]..sort((a, b) => b.y.compareTo(a.y));
    return [
      for (var i = 0; i < sorted.length; i++)
        MeasurementLine(
          label: '${firstLineCm + i * stepCm} cm',
          cm: firstLineCm + i * stepCm,
          shortLabel: '${firstLineCm + i * stepCm}',
          y: sorted[i].y,
          slope: sorted[i].slope,
        ),
    ];
  }

  /// Rectángulo de la tabla, normalizado sobre la vista previa.
  final Rect roi;

  /// N: cantidad de mechones (carriles verticales).
  final int strandCount;

  /// X líneas ordenadas desde la más cercana a los sujetadores hacia arriba.
  final List<MeasurementLine> linesFromBase;

  /// Borde superior de los sujetadores (normalizado en el ROI). Es la base
  /// desde la que crece el mechón; todo lo que está debajo se ignora.
  final double clipY;

  /// Margen interno de cada carril (fracción de su ancho) para no contar
  /// cabello del mechón vecino.
  final double lanePadding;

  /// Colores por rango. Si es null se genera una rampa de tonos.
  final List<Color>? palette;

  int get lineCount => linesFromBase.length;

  /// X líneas ⇒ X + 1 rangos (antes de la 1.ª, entre cada par, después de la última).
  int get rangeCount => lineCount + 1;

  /// Carril del mechón [i], normalizado en el ROI.
  Rect laneRect(int i) {
    final w = 1.0 / strandCount;
    final pad = w * lanePadding;
    return Rect.fromLTRB(i * w + pad, 0, (i + 1) * w - pad, clipY);
  }

  /// k = cantidad de líneas que el volumen principal alcanza o supera, medidas
  /// en la columna normalizada [xn] (centro del carril).
  /// Rango k ⇒ el mechón termina entre la línea k y la línea k+1.
  int rangeIndexFor(double endpointY, {double tolerance = 0, double xn = 0.5}) {
    var reached = 0;
    for (final line in linesFromBase) {
      if (endpointY <= line.yAt(xn) + tolerance) {
        reached++;
      } else {
        break;
      }
    }
    return reached;
  }

  /// Límites verticales (normalizados en el ROI) del rango k en la columna [xn].
  (double top, double bottom) rangeBoundsAt(int k, double xn) {
    final bottom = k <= 0 ? clipY : linesFromBase[k - 1].yAt(xn);
    final top = k >= lineCount ? 0.0 : linesFromBase[k].yAt(xn);
    return (top, bottom);
  }

  /// Límites del rango k en el centro de la tabla.
  (double top, double bottom) rangeBounds(int k) => rangeBoundsAt(k, 0.5);

  String rangeLabel(int k) {
    if (k <= 0) return 'Antes de ${linesFromBase.first.label}';
    if (k >= lineCount) return 'Más de ${linesFromBase.last.label}';
    return '${linesFromBase[k - 1].label} – ${linesFromBase[k].label}';
  }

  String shortRangeLabel(int k) {
    if (k <= 0) return '<${linesFromBase.first.shortLabel}';
    if (k >= lineCount) return '>${linesFromBase.last.shortLabel}';
    return '${linesFromBase[k - 1].shortLabel}–${linesFromBase[k].shortLabel}';
  }

  Color colorForRange(int k) {
    final p = palette;
    if (p != null && p.isNotEmpty) return p[k % p.length];
    // Rampa de tono equiespaciada: rangos vecinos siempre distinguibles.
    final t = rangeCount == 1 ? 0.0 : k / (rangeCount - 1);
    final hue = (190 + 300 * t) % 360;
    return HSVColor.fromAHSV(1, hue, 0.80, 0.95).toColor();
  }

  BoardConfig copyWith({
    Rect? roi,
    int? strandCount,
    List<MeasurementLine>? lines,
    double? clipY,
    double? lanePadding,
    List<Color>? palette,
  }) {
    return BoardConfig(
      roi: roi ?? this.roi,
      strandCount: strandCount ?? this.strandCount,
      lines: lines ?? linesFromBase,
      clipY: clipY ?? this.clipY,
      lanePadding: lanePadding ?? this.lanePadding,
      palette: palette ?? this.palette,
    );
  }
}
