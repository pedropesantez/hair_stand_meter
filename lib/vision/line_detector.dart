import 'dart:math' as math;
import 'dart:typed_data';

import '../core/config/board_config.dart';
import '../core/models/detected_line.dart';

/// Detecta las líneas horizontales que se dibujaron sobre el papel.
///
/// Las líneas a mano no son perfectamente horizontales, así que no basta con
/// proyectar filas. El método:
///  1. Para cada píxel mide cuánto más oscuro es que el papel arriba y abajo a
///     una distancia d: D = min(I(y−d), I(y+d)) − I(y). Sólo es positivo en
///     trazos finos y oscuros; un borde de papel o un cabello grueso no lo son.
///  2. Cada columna aporta sus máximos locales de D: son los "puntos de trazo".
///  3. Transformada de Hough: se prueban rectas con distintas pendientes y se
///     cuenta cuántos puntos caen sobre cada una. Una línea real recibe votos
///     de casi todas las columnas; el cabello vertical no suma.
///  4. Se eliminan duplicados (rectas vecinas) y se devuelven de abajo hacia
///     arriba, de modo que la primera es la más cercana a los sujetadores.
class LineDetector {
  const LineDetector._();

  /// [gray]: imagen de análisis en gris, [width] × [height], ya en horizontal.
  /// [rowLimit]: fila por debajo de la cual no se buscan líneas (sujetadores).
  static List<DetectedLine> detect({
    required Uint8List gray,
    required int width,
    required int height,
    required int rowLimit,
    required AnalysisParams params,
  }) {
    final w = width;
    final h = height;
    final d = math.max(1, params.lineProbeOffset);
    final yMin = d;
    final yMax = math.min(rowLimit, h - d); // exclusivo
    final x0 = math.max(0, math.min(w - 1, (w * params.lineColumnStart).floor()));
    final xEnd = w; // exclusivo
    final nCols = xEnd - x0;
    if (yMax - yMin < 2 * d + 1 || nCols < 8) return const [];

    // 1) Matriz de "trazo oscuro" D(x, y), sólo donde hay vecinos a ±d.
    final dip = Int32List(w * h);
    for (var y = yMin; y < h - d; y++) {
      final rowC = y * w;
      final rowU = (y - d) * w;
      final rowD = (y + d) * w;
      for (var x = x0; x < xEnd; x++) {
        final up = gray[rowU + x];
        final dn = gray[rowD + x];
        dip[rowC + x] = (up < dn ? up : dn) - gray[rowC + x];
      }
    }

    // 2) Puntos de trazo: máximos locales en vertical (±2 filas) por columna.
    final px = <int>[];
    final py = <int>[];
    for (var x = x0; x < xEnd; x++) {
      for (var y = yMin; y < yMax; y++) {
        final v = dip[y * w + x];
        if (v < params.lineMinContrast) continue;
        var isPeak = true;
        for (var k = -2; k <= 2 && isPeak; k++) {
          if (k == 0) continue;
          final yy = y + k;
          if (yy < yMin || yy >= yMax) continue;
          final vv = dip[yy * w + x];
          // En empate gana la fila superior.
          if (vv > v || (vv == v && k < 0)) isPeak = false;
        }
        if (isPeak) {
          px.add(x);
          py.add(y);
        }
      }
    }
    if (px.isEmpty) return const [];

    // 3) Hough: rectas r(x) = ρ + s·(x − xc), con pendientes s acotadas.
    final xc = (x0 + xEnd - 1) / 2.0;
    final slopeMax = params.lineMaxSlope;
    final step = params.lineSlopeStep > 0 ? params.lineSlopeStep : 0.004;
    final nSlopes = (2 * slopeMax / step).round() + 1;
    final minVotes = params.lineMinCover * nCols;

    final candidates = <_Candidate>[];
    final votes = Int32List(h);
    final smoothed = Int32List(h);
    for (var si = 0; si < nSlopes; si++) {
      final s = -slopeMax + si * step;
      votes.fillRange(0, h, 0);
      for (var i = 0; i < px.length; i++) {
        final r = (py[i] - s * (px[i] - xc)).round();
        if (r >= 0 && r < h) votes[r]++;
      }
      // Ventana de ±1 fila: tolera el error de redondeo de la pendiente.
      for (var r = 0; r < h; r++) {
        var v = votes[r];
        if (r > 0) v += votes[r - 1];
        if (r < h - 1) v += votes[r + 1];
        smoothed[r] = v;
      }
      for (var r = 1; r < h - 1; r++) {
        final v = smoothed[r];
        if (v >= minVotes && v >= smoothed[r - 1] && v > smoothed[r + 1]) {
          candidates.add(_Candidate(v, s, r));
        }
      }
    }
    if (candidates.isEmpty) return const [];
    candidates.sort((a, b) => b.votes.compareTo(a.votes));

    // 4) Supresión de duplicados: dos rectas a menos de minSep filas son la
    //    misma línea, sin importar su pendiente.
    final minSep = math.max(3.0, params.lineMinSeparation * h);
    final accepted = <_Candidate>[];
    for (final c in candidates) {
      if (accepted.length >= params.lineMaxCount) break;
      var clash = false;
      for (final a in accepted) {
        if ((c.row - a.row).abs() < minSep) {
          clash = true;
          break;
        }
      }
      if (!clash) accepted.add(c);
    }

    // Conversión a coordenadas normalizadas del ROI.
    //   y_norm = r / h  ;  pendiente normalizada = s · w / h
    final xMid = (w - 1) / 2.0;
    final lines = <DetectedLine>[];
    for (final c in accepted) {
      final yMid = (c.row + c.slope * (xMid - xc)) / h;
      if (yMid <= 0 || yMid >= 1) continue;
      lines.add(DetectedLine(
        y: yMid,
        slope: c.slope * w / h,
        coverage: math.min(1.0, c.votes / nCols),
      ));
    }
    lines.sort((a, b) => b.y.compareTo(a.y)); // de abajo hacia arriba
    return lines;
  }
}

class _Candidate {
  const _Candidate(this.votes, this.slope, this.row);
  final int votes;
  final double slope;
  final int row;
}
