import 'dart:math' as math;
import 'dart:typed_data';

import '../core/config/board_config.dart';
import '../core/models/strand_result.dart';
import 'hair_mask.dart';
import 'line_detector.dart';
import 'morphology.dart';

/// Medición por DENSIDAD (no por longitud máxima).
///
/// Pipeline por frame:
///   gris → máscara → apertura morfológica → por cada carril:
///   perfil D(y) → suavizado → D_ref → punto final → rango k
class DensityAnalyzer {
  DensityAnalyzer({
    required this.config,
    required this.params,
    HairMaskProvider? maskProvider,
  }) : maskProvider = maskProvider ??
            (params.useAdaptiveThreshold
                ? AdaptiveMeanMaskProvider(hairIsDark: params.hairIsDarkerThanBoard)
                : OtsuMaskProvider(hairIsDark: params.hairIsDarkerThanBoard));

  final BoardConfig config;
  final AnalysisParams params;
  final HairMaskProvider maskProvider;

  FrameAnalysis analyze(Uint8List gray, int w, int h) {
    final sw = Stopwatch()..start();

    // 0) Líneas dibujadas sobre la tabla (sobre la imagen en gris, antes de
    //    segmentar, porque las líneas se quitan con la apertura).
    final baseRow = math.min(h - 1, math.max(1, (config.clipY * h).floor() - 1));
    final detected = LineDetector.detect(
      gray: gray,
      width: w,
      height: h,
      rowLimit: baseRow,
      params: params,
    );

    // 1) Segmentación: 1 = cabello.
    var mask = maskProvider.computeMask(gray, w, h);

    // 2) Apertura: elimina cabellos sueltos (angostos) y líneas impresas (bajas).
    mask = Morphology.open(
      mask, w, h, params.openingKernelWidth, params.openingKernelHeight,
    );

    final lineRows = _lineRowFlags(h);
    final strands = List<StrandResult>.generate(
      config.strandCount,
      (i) => _analyzeLane(i, mask, w, h, lineRows),
      growable: false,
    );

    return FrameAnalysis(
      strands: strands,
      processingMicros: sw.elapsedMicroseconds,
      sampleWidth: w,
      sampleHeight: h,
      detectedLines: detected,
    );
  }

  /// Filas ocupadas por las líneas impresas (se ignoran y se interpolan).
  Uint8List _lineRowFlags(int h) {
    final flags = Uint8List(h);
    for (final line in config.linesFromBase) {
      final c = (line.yAt(0.5) * h).round();
      for (var d = -params.lineMaskHalfHeight; d <= params.lineMaskHalfHeight; d++) {
        final y = c + d;
        if (y >= 0 && y < h) flags[y] = 1;
      }
    }
    return flags;
  }

  StrandResult _analyzeLane(int index, Uint8List mask, int w, int h, Uint8List lineRows) {
    final lane = config.laneRect(index);
    final x0 = (lane.left * w).round().clamp(0, w - 1);
    final x1 = (lane.right * w).round().clamp(x0 + 1, w);
    final laneW = x1 - x0;
    // Fila base: justo encima de los sujetadores. Se analizan filas 0..baseRow.
    final baseRow = ((config.clipY * h).floor() - 1).clamp(1, h - 1);
    final rows = baseRow + 1;

    // 3) Perfil de densidad: D(y) = (1/W) Σx M(x, y)
    final raw = Float32List(rows);
    for (var y = 0; y < rows; y++) {
      if (lineRows[y] == 1) {
        raw[y] = double.nan;
        continue;
      }
      var count = 0;
      final off = y * w;
      for (var x = x0; x < x1; x++) {
        count += mask[off + x];
      }
      raw[y] = count / laneW;
    }
    _fillNaN(raw);

    // 4) Suavizado vertical (media móvil centrada).
    final d = _movingAverage(raw, params.smoothingWindow);

    // 5) Densidad de referencia: mediana de la zona base (robusta a outliers).
    final zoneRows = math.max(3, (rows * params.baseZoneFraction).round()).clamp(1, rows);
    final zone = Float32List.fromList(d.sublist(rows - zoneRows))..sort();
    final ref = zone[zone.length ~/ 2];

    if (ref < params.minReferenceDensity) {
      return StrandResult(laneIndex: index, lane: lane, referenceDensity: ref, profile: d);
    }

    // 6) Punto final del volumen principal.
    final yThr = _endpointByThreshold(d, ref);
    final yMass = _endpointByMass(d);
    final yEnd = switch (params.endpointStrategy) {
      EndpointStrategy.relativeThreshold => yThr,
      EndpointStrategy.massQuantile => yMass,
      EndpointStrategy.conservative => math.max(yThr, yMass), // y mayor = más corto
    };

    final endpointY = yEnd / h;

    // 7) Clasificación en rango.
    // La medición se hace en el centro del carril: las líneas pueden estar
    // ligeramente inclinadas, así que cada carril compara con su propia altura.
    final rangeIndex = config.rangeIndexFor(
      endpointY,
      tolerance: params.lineSnapTolerance,
      xn: lane.center.dx,
    );

    return StrandResult(
      laneIndex: index,
      lane: lane,
      endpointY: endpointY,
      rangeIndex: rangeIndex,
      confidence: _confidence(d, yEnd, h),
      referenceDensity: ref,
      profile: d,
    );
  }

  /// Sube desde la base. La última fila con D(y) ≥ τ·D_ref es el final,
  /// salvo que aparezcan más de G filas seguidas por debajo del umbral.
  /// Los cabellos sueltos que sobrevivan a la morfología tienen D(y) ≪ τ·D_ref
  /// y nunca extienden el final.
  int _endpointByThreshold(Float32List d, double ref) {
    final thr = params.relativeDensityThreshold * ref;
    var last = d.length - 1;
    var gap = 0;
    for (var y = d.length - 1; y >= 0; y--) {
      if (d[y] >= thr) {
        last = y;
        gap = 0;
      } else if (++gap > params.gapToleranceRows) {
        break;
      }
    }
    return last;
  }

  /// Fila donde la masa acumulada desde la base alcanza q·masa_total.
  int _endpointByMass(Float32List d) {
    var total = 0.0;
    for (final v in d) {
      total += v;
    }
    if (total <= 0) return d.length - 1;
    final target = params.massQuantile * total;
    var acc = 0.0;
    for (var y = d.length - 1; y >= 0; y--) {
      acc += d[y];
      if (acc >= target) return y;
    }
    return 0;
  }

  /// Contraste entre el cuerpo del mechón y la franja inmediatamente superior.
  double _confidence(Float32List d, int yEnd, int h) {
    var body = 0.0;
    for (var y = yEnd; y < d.length; y++) {
      body += d[y];
    }
    body /= (d.length - yEnd);
    if (body <= 0) return 0;

    final tailLen = math.max(3, (h * 0.05).round());
    final t0 = math.max(0, yEnd - tailLen);
    var tail = 0.0;
    for (var y = t0; y < yEnd; y++) {
      tail += d[y];
    }
    tail = yEnd > t0 ? tail / (yEnd - t0) : 0;

    var c = ((body - tail) / body).clamp(0.0, 1.0);
    if (yEnd == 0) c *= 0.5; // llega al borde del ROI: puede salirse de cuadro
    return c;
  }

  static void _fillNaN(Float32List a) {
    var lastValid = -1;
    for (var i = 0; i < a.length; i++) {
      if (a[i].isNaN) continue;
      if (lastValid == -1) {
        for (var j = 0; j < i; j++) {
          a[j] = a[i];
        }
      } else if (i - lastValid > 1) {
        final v0 = a[lastValid], v1 = a[i];
        for (var j = lastValid + 1; j < i; j++) {
          a[j] = v0 + (v1 - v0) * (j - lastValid) / (i - lastValid);
        }
      }
      lastValid = i;
    }
    if (lastValid == -1) {
      a.fillRange(0, a.length, 0);
    } else {
      for (var j = lastValid + 1; j < a.length; j++) {
        a[j] = a[lastValid];
      }
    }
  }

  static Float32List _movingAverage(Float32List a, int window) {
    if (window <= 1) return Float32List.fromList(a);
    final r = window ~/ 2;
    final prefix = Float64List(a.length + 1);
    for (var i = 0; i < a.length; i++) {
      prefix[i + 1] = prefix[i] + a[i];
    }
    final out = Float32List(a.length);
    for (var i = 0; i < a.length; i++) {
      final lo = i - r < 0 ? 0 : i - r;
      final hi = i + r >= a.length ? a.length - 1 : i + r;
      out[i] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
    }
    return out;
  }
}
