import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hair_strand_meter/core/config/board_config.dart';
import 'package:hair_strand_meter/vision/density_analyzer.dart';

const _w = 180, _h = 270;
const _board = 225, _hair = 35, _ink = 60, _clip = 40;

/// Tabla blanca con líneas impresas y sujetadores oscuros abajo.
Uint8List _blankBoard(BoardConfig cfg) {
  final img = Uint8List(_w * _h)..fillRange(0, _w * _h, _board);
  for (final l in cfg.linesFromBase) {
    final y = (l.y * _h).round();
    for (var x = 0; x < _w; x++) {
      img[y * _w + x] = _ink;
    }
  }
  for (var y = (cfg.clipY * _h).round(); y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      img[y * _w + x] = _clip;
    }
  }
  return img;
}

/// Dibuja un mechón grueso en el carril [lane] hasta [endY] y, opcionalmente,
/// cabellos sueltos de 1 px que llegan hasta [looseTo].
void _drawStrand(Uint8List img, BoardConfig cfg, int lane, double endY,
    {int looseHairs = 0, double? looseTo}) {
  final r = cfg.laneRect(lane);
  final x0 = (r.left * _w).round(), x1 = (r.right * _w).round();
  final cx = (x0 + x1) ~/ 2;
  final half = ((x1 - x0) * 0.35).round();
  final base = (cfg.clipY * _h).round();
  final top = (endY * _h).round();

  for (var y = top; y < base; y++) {
    for (var x = cx - half; x <= cx + half; x++) {
      img[y * _w + x] = _hair;
    }
  }
  if (looseTo != null) {
    final looseTop = (looseTo * _h).round();
    for (var k = 0; k < looseHairs; k++) {
      final hx = cx - half + 2 + k * 3;
      for (var y = looseTop; y < top; y++) {
        img[y * _w + hx] = _hair;
      }
    }
  }
}

double _between(BoardConfig c, int a, int b) =>
    (c.linesFromBase[a].y + c.linesFromBase[b].y) / 2;

void main() {
  test('Ignora cabellos sueltos: volumen en rango 2 aunque 3 cabellos lleguen a la línea 4', () {
    final cfg = BoardConfig.sixStrandsEightLines();
    final img = _blankBoard(cfg);

    // Volumen principal termina entre la línea 2 y la 3 (índices 1 y 2).
    _drawStrand(img, cfg, 0, _between(cfg, 1, 2),
        looseHairs: 3, looseTo: cfg.linesFromBase[3].y - 0.02);
    // Mechón 3 llega más lejos, sin cabellos sueltos.
    _drawStrand(img, cfg, 2, _between(cfg, 4, 5));

    final analyzer = DensityAnalyzer(config: cfg, params: const AnalysisParams());
    final result = analyzer.analyze(img, _w, _h);

    expect(result.strands[0].rangeIndex, 2, reason: 'Los cabellos sueltos no deben contar');
    expect(cfg.rangeLabel(result.strands[0].rangeIndex!), '8 cm – 9 cm');
    expect(result.strands[1].rangeIndex, isNull, reason: 'Carril vacío');
    expect(result.strands[2].rangeIndex, 5);
  });

  test('Escala a N mechones y X líneas arbitrarios', () {
    final cfg = BoardConfig.uniform(strandCount: 10, lineCount: 4);
    final img = _blankBoard(cfg);
    _drawStrand(img, cfg, 9, _between(cfg, 0, 1));

    final result = DensityAnalyzer(config: cfg, params: const AnalysisParams())
        .analyze(img, _w, _h);

    expect(result.strands.length, 10);
    expect(cfg.rangeCount, 5);
    expect(result.strands[9].rangeIndex, 1);
  });
}
