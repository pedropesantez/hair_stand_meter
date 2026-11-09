import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hair_strand_meter/core/config/board_config.dart';
import 'package:hair_strand_meter/core/config/photo_params.dart';
import 'package:hair_strand_meter/ui/painters/photo_overlay_painter.dart';
import 'package:hair_strand_meter/vision/photo_analyzer.dart';

const _w = 200;
const _h = 300;
const _base = 294; // floor(0.98 · 300): fila de los sujetadores

/// Mechón sintético: columnas [x0]..[x1] desde [tip] hasta la base.
class _Strand {
  const _Strand(this.x0, this.x1, this.tip);
  final int x0;
  final int x1;
  final int tip;
}

/// Foto sintética del marco de la tabla:
///  * papel claro; líneas azules de 3 px (7, 8, 9 y 10 cm) de lado a lado;
///  * sujetadores amarillos debajo de la base;
///  * mechones oscuros que se dibujan ENCIMA de las líneas (como en la foto real).
Uint8List _photo(List<_Strand> strands, {bool withLines = true}) {
  final rgb = Uint8List(_w * _h * 3);
  void px(int x, int y, int r, int g, int b) {
    final i = (y * _w + x) * 3;
    rgb[i] = r;
    rgb[i + 1] = g;
    rgb[i + 2] = b;
  }

  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      if (y >= _base) {
        px(x, y, 230, 200, 80); // sujetador amarillo
      } else {
        px(x, y, 235, 235, 230); // papel
      }
    }
  }
  for (final row in withLines ? [250, 210, 170, 130] : const <int>[]) {
    for (var x = 0; x < _w; x++) {
      for (var dy = -1; dy <= 1; dy++) {
        px(x, row + dy, 40, 60, 160); // tinta azul
      }
    }
  }
  for (final s in strands) {
    for (var y = s.tip; y < _base; y++) {
      for (var x = s.x0; x <= s.x1; x++) {
        px(x, y, 60, 60, 60); // cabello
      }
    }
  }
  return rgb;
}

PhotoAnalysis _analyze(Uint8List rgb) => PhotoAnalyzer.analyze(
      rgb: rgb,
      width: _w,
      height: _h,
      config: BoardConfig.uniform(clipY: _base / _h),
      params: const PhotoParams(analysisWidth: _w),
    );

void main() {
  test('Cuenta todos los mechones y les asigna valores fijos', () {
    final analysis = _analyze(_photo([
      _Strand(40, 45, 200), // entre 8 y 9 cm  ⇒ 8 cm
      _Strand(110, 115, 245), // entre 7 y 8 cm ⇒ 7 cm
      _Strand(150, 157, 262), // bajo la primera línea ⇒ < 7 cm
    ]));

    expect(analysis.lines.map((l) => l.cm).toList(), [7, 8, 9, 10]);
    expect(analysis.strands.length, 3);
    expect(analysis.strands[0].label, '8 cm');
    expect(analysis.strands[0].cm, 8);
    expect(analysis.strands[1].label, '7 cm');
    expect(analysis.strands[1].cm, 7);
    expect(analysis.strands[2].label, '< 7 cm');
    expect(analysis.strands[2].cm, isNull);
    expect(analysis.strands[0].xCenter, closeTo(43 / _w, 0.01));
  });

  test('La altura es el cabello más alto, no la zona más densa', () {
    // Cuerpo grueso desde la fila 240 y un cabello suelto de 1 px que sube
    // hasta la fila 200 (entre 8 y 9 cm). Debe contar como 8 cm.
    final analysis = _analyze(_photo([
      _Strand(60, 65, 240),
      _Strand(65, 65, 200),
    ]));

    expect(analysis.strands.length, 1);
    expect(analysis.strands[0].label, '8 cm');
    expect(analysis.strands[0].tipY, closeTo(200 / _h, 0.01));
  });

  test('Cuenta 20 mechones juntos y colorea por nivel', () {
    final strands = [
      for (var i = 0; i < 20; i++)
        _Strand(8 + 9 * i, 11 + 9 * i, i.isEven ? 200 : 245),
    ];
    final analysis = _analyze(_photo(strands));

    expect(analysis.strands.length, 20);
    expect(analysis.strands.map((s) => s.index).toList(),
        List.generate(20, (i) => i + 1));
    // Mismo nivel ⇒ mismo color; niveles distintos ⇒ colores distintos.
    expect(analysis.strands[0].label, '8 cm');
    expect(analysis.strands[2].label, '8 cm');
    expect(colorForStrand(analysis.strands[0]),
        colorForStrand(analysis.strands[2]));
    expect(analysis.strands[1].label, '7 cm');
    expect(colorForStrand(analysis.strands[0]),
        isNot(colorForStrand(analysis.strands[1])));
  });

  test('Sin líneas dibujadas avisa en vez de inventar valores', () {
    final analysis = _analyze(
      _photo([_Strand(40, 45, 200)], withLines: false),
    );

    expect(analysis.lines, isEmpty);
    expect(analysis.quality.warnings.any((w) => w.contains('líneas')), isTrue);
  });
}
