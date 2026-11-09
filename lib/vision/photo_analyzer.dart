import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../core/config/board_config.dart';
import '../core/config/photo_params.dart';
import '../core/models/photo_analysis.dart';
import 'line_detector.dart';

/// Análisis de UNA foto fija de la tabla.
///
/// Recibe el marco de la tabla ya recortado, en horizontal y con
/// [PhotoParams.analysisWidth] px de ancho, en RGB (3 bytes por píxel).
///
/// Orden de trabajo:
///  1. Máscara de cabello: píxeles neutros (sin el amarillo de los sujetadores,
///     sin el azul de las líneas, poco saturados) y oscuros según Otsu.
///  2. Se quitan las fibras horizontales: sólo se conservan tramos verticales
///     de al menos [PhotoParams.verticalRunMin] píxeles.
///  3. Componentes conectados (8 vecinos). Un mechón es un componente que
///     llega hasta la base de los sujetadores. Se cuentan TODOS primero.
///  4. La altura de cada mechón es su cabello MÁS ALTO (el último pelo),
///     no la zona donde hay más cabello.
///  5. Valor fijo: se cuentan las líneas que esa altura alcanza. Si queda
///     entre la línea k y la k+1 se reporta el valor de la línea k
///     (entre 8 y 9 cm ⇒ "8 cm").
class PhotoAnalyzer {
  const PhotoAnalyzer._();

  static PhotoAnalysis analyze({
    required Uint8List rgb,
    required int width,
    required int height,
    required BoardConfig config,
    required PhotoParams params,
  }) {
    final roiW = width;
    final roiH = height;
    final roiN = roiW * roiH;

    // 1) Luminancia y neutralidad (sin amarillo ni azul, poco saturado).
    final gray0 = Uint8List(roiN);
    final neutral0 = Uint8List(roiN);
    final ink0 = Uint8List(roiN); // tinta azul de las líneas
    final yellowLimit = 2 * params.yellowThreshold;
    final blueLimit = 2 * params.blueThreshold;
    for (var i = 0; i < roiN; i++) {
      final r = rgb[3 * i];
      final g = rgb[3 * i + 1];
      final b = rgb[3 * i + 2];
      gray0[i] = (299 * r + 587 * g + 114 * b) ~/ 1000;
      final yellow = (r + g - 2 * b) > yellowLimit;
      final blue = (2 * b - r - g) > blueLimit;
      final chroma = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      neutral0[i] = (!yellow && !blue && chroma < params.hairMaxChroma) ? 1 : 0;
      ink0[i] = blue ? 1 : 0;
    }

    // Fila base (en el marco completo): por debajo sólo están los sujetadores.
    final baseRoi = math.min(roiH - 1, math.max(1, (config.clipY * roiH).floor()));

    // Trabajo sobre el marco completo.
    final w = roiW;
    final h = roiH;
    final gray = gray0;
    final neutral = neutral0;
    final ink = ink0;
    final baseRow = baseRoi;

    // Umbral del papel (Otsu sobre todo el marco).
    final hAll = List<int>.filled(256, 0);
    for (final g in gray0) {
      hAll[g]++;
    }
    final paperThr = _otsu(hAll);
    // Papel = neutro y más claro que el umbral de hoja.
    final paper = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      paper[i] = (neutral[i] == 1 && gray[i] > paperThr) ? 1 : 0;
    }
    // Contraste de cada píxel sobre el papel de su entorno.
    final contrast = _localContrast(gray, paper, w, h, params.tipBackgroundRadius);
    // Cabello sensible a la punta: oscuro sobre el papel, o tinta de una línea
    // que cruza un cabello (sólo si forma tramos verticales largos).
    final sens = _verticalRuns(
      _tipMask(neutral, ink, contrast, w, h, baseRow, params.tipMinContrast),
      w,
      h,
      params.verticalRunMin,
    );

    // 3) Umbral de Otsu sobre píxeles neutros, por encima de la base.
    final hist = List<int>.filled(256, 0);
    for (var y = 0; y < baseRow; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (neutral[i] == 1) hist[gray[i]]++;
      }
    }
    final thr = _otsu(hist);

    // 4) Cabello oscuro y sólo tramos verticales largos (quita líneas finas).
    final hair = Uint8List(w * h);
    final minRun = params.verticalRunMin;
    for (var x = 0; x < w; x++) {
      var y = 0;
      while (y < baseRow) {
        final start = y * w + x;
        if (neutral[start] == 0 || gray[start] > thr) {
          y++;
          continue;
        }
        var end = y;
        while (end + 1 < baseRow) {
          final j = (end + 1) * w + x;
          if (neutral[j] == 1 && gray[j] <= thr) {
            end++;
          } else {
            break;
          }
        }
        if (end - y + 1 >= minRun) {
          for (var k = y; k <= end; k++) {
            hair[k * w + x] = 1;
          }
        }
        y = end + 1;
      }
    }

    // 5) Componentes conectados (8 vecinos) que llegan a la base.
    final minArea = params.minAreaFraction * h * w;
    final baseTouch = baseRow - params.baseTouchFraction * h;
    final label = Int32List(w * h);
    final found = <_Found>[];
    final stack = <int>[];
    var nextLabel = 0;

    for (var s = 0; s < w * h; s++) {
      if (hair[s] == 0 || label[s] != 0) continue;
      nextLabel++;
      final pixels = <int>[];
      stack
        ..clear()
        ..add(s);
      label[s] = nextLabel;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        pixels.add(p);
        final py = p ~/ w;
        final px = p % w;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= baseRow) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx;
            if (nx < 0 || nx >= w || (dx == 0 && dy == 0)) continue;
            final q = ny * w + nx;
            if (hair[q] == 1 && label[q] == 0) {
              label[q] = nextLabel;
              stack.add(q);
            }
          }
        }
      }

      if (pixels.length < minArea) continue;
      var minX = w, maxX = -1, minY = h, maxY = -1;
      for (final p in pixels) {
        final py = p ~/ w;
        final px = p % w;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
      }
      if (maxY < baseTouch) continue;

      // 6) Ancho por fila dentro del componente (sólo para aceptar el mechón).
      final prof = Int32List(h);
      for (final p in pixels) {
        prof[p ~/ w]++;
      }
      final top = minY;
      final bottom = maxY;
      final zl = math.max(3, (params.zoneFraction * (bottom - top)).floor());

      final zone = <double>[];
      for (var r = math.max(top, bottom - zl); r <= bottom; r++) {
        zone.add(prof[r].toDouble());
      }
      final peak = _percentile(zone, 0.9);
      if (peak < 2) continue;

      // Ancla: fila más baja donde el cuerpo ya es denso.
      var anchor = -1;
      for (var r = bottom; r >= top; r--) {
        if (prof[r] >= params.denseFraction * peak) {
          anchor = r;
          break;
        }
      }
      if (anchor < 0) continue;

      final refZone = <double>[];
      for (var r = math.max(top, anchor - zl + 1); r <= anchor; r++) {
        refZone.add(prof[r].toDouble());
      }
      final ref = _percentile(refZone, 0.5);
      if (ref < 2) continue;

      // Altura del mechón: su cabello más alto.
      found.add(_Found(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        pixels: pixels,
      ));
    }

    // Altura: desde el mechón se crece por el cabello sensible, sólo dentro de
    // sus columnas, para llegar al cabello más alto aunque sea fino.
    for (var i = 0; i < found.length; i++) {
      found[i] = found[i].withTip(_growTop(found[i], sens, w, h));
    }

    // Mechones de izquierda a derecha.
    found.sort((a, b) => a.centerX.compareTo(b.centerX));

    // 7) Líneas dibujadas: la primera (la más baja) vale firstLineCm.
    final detected = LineDetector.detect(
      gray: gray,
      width: w,
      height: h,
      rowLimit: baseRow - 1,
      params: params.lines,
    );
    final lines = BoardConfig.measurementLinesFrom(
      detected,
      firstLineCm: params.firstLineCm,
    );

    // 8) Valor fijo de cada mechón.
    final strands = <HairStrand>[];
    for (var i = 0; i < found.length; i++) {
      final f = found[i];
      final xn = f.centerX / w;
      final tipN = f.topRow / h;

      // k = líneas que la altura alcanza (la punta está por encima de ellas).
      var k = 0;
      for (final line in lines) {
        if (tipN <= line.yAt(xn) + params.lineSnapTolerance) {
          k++;
        } else {
          break;
        }
      }

      int? cm;
      String text;
      if (lines.isEmpty) {
        text = 'sin líneas';
      } else if (k == 0) {
        text = '< ${lines.first.cm} cm';
      } else if (k >= lines.length) {
        cm = lines.last.cm;
        text = '≥ $cm cm';
      } else {
        cm = lines[k - 1].cm;
        text = '$cm cm';
      }

      strands.add(HairStrand(
        index: i + 1,
        box: Rect.fromLTRB(
          f.minX / w,
          f.minY / h,
          (f.maxX + 1) / w,
          (f.maxY + 1) / h,
        ),
        xCenter: xn,
        tipY: tipN,
        label: text,
        cm: cm,
      ));
    }

    // 9) Calidad de la foto (sobre la hoja).
    final sharpness = _laplacianVariance(gray, w, h);
    var sum = 0;
    for (final g in gray) {
      sum += g;
    }
    final meanLuma = (w * h) == 0 ? 0.0 : sum / (w * h);

    final warnings = <String>[];
    if (sharpness < params.minSharpness) {
      warnings.add('La foto está borrosa. Acerque el celular, espere a que '
          'enfoque y tome otra.');
    }
    if (meanLuma < params.minMeanLuma) {
      warnings.add('La foto está oscura. Use más luz o encienda la linterna.');
    }
    if (meanLuma > params.maxMeanLuma) {
      warnings.add('La foto está sobreexpuesta. Aleje el celular de la luz '
          'directa.');
    }
    if (lines.isEmpty) {
      warnings.add('No se detectaron las líneas dibujadas. Revise que toda la '
          'hoja esté dentro del marco.');
    }
    if (strands.isEmpty) {
      warnings.add('No se detectaron mechones. Revise el encuadre y que la '
          'base de los sujetadores esté sobre la línea roja.');
    }

    return PhotoAnalysis(
      photoWidth: w,
      photoHeight: h,
      strands: strands,
      lines: lines,
      quality: PhotoQuality(
        sharpness: sharpness,
        meanLuma: meanLuma,
        warnings: warnings,
      ),
    );
  }

  /// Contraste de cada píxel respecto al papel de su entorno (promedio de los
  /// píxeles de papel en una ventana de (2r+1)², con imagen integral).
  static Float64List _localContrast(
    Uint8List gray,
    Uint8List paper,
    int w,
    int h,
    int r,
  ) {
    final w1 = w + 1;
    final sumI = Float64List(w1 * (h + 1));
    final cntI = Float64List(w1 * (h + 1));
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final idx = (y + 1) * w1 + (x + 1);
        final v = paper[i] == 1 ? gray[i].toDouble() : 0.0;
        final c = paper[i] == 1 ? 1.0 : 0.0;
        sumI[idx] = v + sumI[idx - 1] + sumI[idx - w1] - sumI[idx - w1 - 1];
        cntI[idx] = c + cntI[idx - 1] + cntI[idx - w1] - cntI[idx - w1 - 1];
      }
    }
    final out = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r);
      final y1 = math.min(h - 1, y + r);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - r);
        final x1 = math.min(w - 1, x + r);
        final s = sumI[(y1 + 1) * w1 + x1 + 1] -
            sumI[y0 * w1 + x1 + 1] -
            sumI[(y1 + 1) * w1 + x0] +
            sumI[y0 * w1 + x0];
        final c = cntI[(y1 + 1) * w1 + x1 + 1] -
            cntI[y0 * w1 + x1 + 1] -
            cntI[(y1 + 1) * w1 + x0] +
            cntI[y0 * w1 + x0];
        out[y * w + x] = c > 0 ? s / c - gray[y * w + x] : 0.0;
      }
    }
    return out;
  }

  /// Píxeles de cabello sensible para la punta: neutros o tinta de línea, por
  /// encima de la base y con al menos [minContrast] sobre el papel.
  static Uint8List _tipMask(
    Uint8List neutral,
    Uint8List ink,
    Float64List contrast,
    int w,
    int h,
    int baseRow,
    int minContrast,
  ) {
    final out = Uint8List(w * h);
    for (var y = 0; y < baseRow && y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if ((neutral[i] == 1 || ink[i] == 1) && contrast[i] >= minContrast) {
          out[i] = 1;
        }
      }
    }
    return out;
  }

  /// Conserva sólo los tramos verticales de al menos [minRun] píxeles.
  static Uint8List _verticalRuns(Uint8List mask, int w, int h, int minRun) {
    final out = Uint8List(w * h);
    for (var x = 0; x < w; x++) {
      var y = 0;
      while (y < h) {
        if (mask[y * w + x] == 0) {
          y++;
          continue;
        }
        var end = y;
        while (end + 1 < h && mask[(end + 1) * w + x] == 1) {
          end++;
        }
        if (end - y + 1 >= minRun) {
          for (var k = y; k <= end; k++) {
            out[k * w + x] = 1;
          }
        }
        y = end + 1;
      }
    }
    return out;
  }

  /// Cabello más alto conectado al mechón, creciendo sólo por [sens] y dentro
  /// de sus columnas (con 2 px de margen).
  static int _growTop(_Found f, Uint8List sens, int w, int h) {
    final lo = math.max(0, f.minX - 2);
    final hi = math.min(w - 1, f.maxX + 2);
    final seen = Uint8List(w * h);
    final stack = <int>[];
    for (final p in f.pixels) {
      seen[p] = 1;
      stack.add(p);
    }
    var top = f.minY;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final py = p ~/ w;
      final px = p % w;
      if (py < top) top = py;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = py + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = px + dx;
          if (nx < lo || nx > hi || (dx == 0 && dy == 0)) continue;
          final q = ny * w + nx;
          if (seen[q] == 0 && sens[q] == 1) {
            seen[q] = 1;
            stack.add(q);
          }
        }
      }
    }
    return top;
  }

  /// Umbral de Otsu sobre un histograma de 256 niveles.
  static int _otsu(List<int> hist) {
    var total = 0;
    var sumAll = 0.0;
    for (var t = 0; t < 256; t++) {
      total += hist[t];
      sumAll += t * hist[t];
    }
    var best = -1.0;
    var thr = 100;
    var sumB = 0.0;
    var wB = 0;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;
      final d = mB - mF;
      final between = wB * wF * d * d;
      if (between > best) {
        best = between;
        thr = t;
      }
    }
    return thr;
  }

  /// Percentil con interpolación lineal (igual que numpy).
  static double _percentile(List<double> values, double q) {
    final v = [...values]..sort();
    final pos = q * (v.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    return v[lo] + (v[hi] - v[lo]) * (pos - lo);
  }

  /// Varianza del Laplaciano: mide el detalle. Fotos borrosas dan valores bajos.
  static double _laplacianVariance(Uint8List g, int w, int h) {
    var sum = 0.0;
    var sum2 = 0.0;
    var count = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final v = 4 * g[i] - g[i - 1] - g[i + 1] - g[i - w] - g[i + w];
        sum += v;
        sum2 += v * v;
        count++;
      }
    }
    if (count == 0) return 0;
    final mean = sum / count;
    return sum2 / count - mean * mean;
  }
}

class _Found {
  const _Found({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.pixels,
    this.tip,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  /// Píxeles del componente (fila * w + columna).
  final List<int> pixels;

  /// Fila del cabello más alto del mechón (null hasta calcularla).
  final int? tip;

  int get topRow => tip ?? minY;

  double get centerX => (minX + maxX + 1) / 2.0;

  _Found withTip(int t) => _Found(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        pixels: pixels,
        tip: t,
      );
}
