import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hair_strand_meter/core/config/board_config.dart';
import 'package:hair_strand_meter/core/models/detected_line.dart';
import 'package:hair_strand_meter/vision/density_analyzer.dart';
import 'package:hair_strand_meter/vision/line_detector.dart';

const _w = 400;
const _h = 200;
const _paper = 220;
const _ink = 90;
const _hair = 60;
const _sponge = 130;
const _base = 185; // fila de los sujetadores

/// Tabla sintética: papel claro, líneas dibujadas (2 px, posiblemente inclinadas),
/// sujetadores debajo de [_base].
Uint8List _table(List<int> lineRows, double slope) {
  final img = Uint8List(_w * _h)..fillRange(0, _w * _h, _paper);
  const xc = (40 + _w - 1) / 2.0; // mismo centro que usa el detector
  for (final y0 in lineRows) {
    for (var x = 0; x < _w; x++) {
      final yc = (y0 + slope * (x - xc)).round();
      img[yc * _w + x] = _ink;
      img[(yc + 1) * _w + x] = _ink;
    }
  }
  for (var y = _base; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      img[y * _w + x] = _sponge;
    }
  }
  return img;
}

/// Mechón denso en la mitad izquierda, con la punta en [tipRow].
void _strand(Uint8List img, int tipRow) {
  for (var y = tipRow; y < _base; y++) {
    for (var x = 80; x <= 120; x++) {
      img[y * _w + x] = _hair;
    }
  }
}

const _params = AnalysisParams(sampleWidth: _w, sampleHeight: _h);

List<DetectedLine> _detect(Uint8List img) => LineDetector.detect(
      gray: img,
      width: _w,
      height: _h,
      rowLimit: _base,
      params: _params,
    );

void main() {
  const rows = [30, 46, 62, 78, 94]; // de arriba hacia abajo, en x central
  const slope = 0.02; // pendiente en píxeles de análisis (dy/dx)

  test('Detecta las líneas dibujadas aunque estén inclinadas', () {
    final lines = _detect(_table(rows, slope));

    expect(lines.length, 5);
    // Ordenadas de abajo hacia arriba: la primera es la más cercana a los sujetadores.
    expect(lines.first.y, greaterThan(lines.last.y));

    const xMid = (_w - 1) / 2.0;
    const xc = (40 + _w - 1) / 2.0;
    for (var i = 0; i < lines.length; i++) {
      final expectedRow = rows[rows.length - 1 - i] + slope * (xMid - xc);
      expect(lines[i].y, closeTo(expectedRow / _h, 0.012), reason: 'línea ${i + 1}');
      // Pendiente normalizada = s · w / h.
      expect(lines[i].slope, closeTo(slope * _w / _h, 0.01), reason: 'pendiente ${i + 1}');
    }
  });

  test('La primera línea dibujada es 7 cm y las demás suben de 1 cm', () {
    final labeled = BoardConfig.measurementLinesFrom(_detect(_table(rows, slope)));

    expect(labeled.length, 5);
    expect(labeled.first.label, '7 cm');
    expect(labeled.last.label, '11 cm');
  });

  test('Mide el rango de un mechón con líneas inclinadas', () {
    // Punta del mechón entre la línea de 8 cm (fila ~78) y la de 9 cm (fila ~62).
    final img = _table(rows, slope);
    _strand(img, 68);

    final detected = _detect(img);
    expect(detected.length, 5);

    final cfg = BoardConfig(
      roi: const Rect.fromLTWH(0, 0, 1, 1),
      strandCount: 2,
      lines: BoardConfig.measurementLinesFrom(detected),
      clipY: _base / _h,
    );
    final result = DensityAnalyzer(config: cfg, params: _params).analyze(img, _w, _h);

    expect(result.strands[0].rangeIndex, 2);
    expect(cfg.rangeLabel(2), '8 cm – 9 cm');
    expect(result.strands[1].rangeIndex, isNull, reason: 'Carril vacío');
  });
}
