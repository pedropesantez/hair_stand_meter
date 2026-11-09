import 'dart:typed_data';

/// Produce una máscara binaria (1 = cabello, 0 = fondo) del mismo tamaño que
/// la imagen de análisis.
///
/// Es el ÚNICO punto que cambia entre el enfoque clásico y el de ML: un
/// modelo TFLite de segmentación implementa esta misma interfaz y el resto
/// del pipeline (morfología + densidad + rangos) no se toca.
abstract interface class HairMaskProvider {
  Uint8List computeMask(Uint8List gray, int width, int height);
}

/// Umbral global de Otsu. Ideal con buena iluminación y contraste
/// cabello/tabla bimodal (p. ej. cabello oscuro sobre tabla blanca).
class OtsuMaskProvider implements HairMaskProvider {
  const OtsuMaskProvider({this.hairIsDark = true, this.minContrast = 25});

  final bool hairIsDark;

  /// Si las medias de las dos clases difieren menos que esto, no hay cabello.
  final int minContrast;

  @override
  Uint8List computeMask(Uint8List gray, int width, int height) {
    final hist = Int32List(256);
    for (final v in gray) {
      hist[v]++;
    }
    final total = gray.length;
    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }

    var sumB = 0.0;
    var wB = 0;
    var bestVar = -1.0;
    var thr = 127;
    var bestMeanB = 0.0, bestMeanF = 0.0;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > bestVar) {
        bestVar = between;
        thr = t;
        bestMeanB = mB;
        bestMeanF = mF;
      }
    }

    final mask = Uint8List(gray.length);
    if (bestMeanF - bestMeanB < minContrast) return mask; // tabla vacía
    for (var i = 0; i < gray.length; i++) {
      final dark = gray[i] <= thr;
      mask[i] = (hairIsDark ? dark : !dark) ? 1 : 0;
    }
    return mask;
  }
}

/// Umbral adaptativo por media local (imagen integral). Robusto a sombras y
/// gradientes de luz sobre la tabla. blockSize debe ser MAYOR que el ancho
/// de un mechón en la imagen de análisis.
class AdaptiveMeanMaskProvider implements HairMaskProvider {
  const AdaptiveMeanMaskProvider({
    this.hairIsDark = true,
    this.blockSize = 41,
    this.offset = 18,
  });

  final bool hairIsDark;
  final int blockSize;
  final int offset;

  @override
  Uint8List computeMask(Uint8List gray, int width, int height) {
    final stride = width + 1;
    final integral = Int32List(stride * (height + 1));
    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      for (var x = 0; x < width; x++) {
        rowSum += gray[y * width + x];
        integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + rowSum;
      }
    }

    final r = blockSize ~/ 2;
    final mask = Uint8List(gray.length);
    for (var y = 0; y < height; y++) {
      final y0 = y - r < 0 ? 0 : y - r;
      final y1 = y + r + 1 > height ? height : y + r + 1;
      for (var x = 0; x < width; x++) {
        final x0 = x - r < 0 ? 0 : x - r;
        final x1 = x + r + 1 > width ? width : x + r + 1;
        final sum = integral[y1 * stride + x1] -
            integral[y0 * stride + x1] -
            integral[y1 * stride + x0] +
            integral[y0 * stride + x0];
        final mean = sum / ((x1 - x0) * (y1 - y0));
        final g = gray[y * width + x];
        final isHair = hairIsDark ? g < mean - offset : g > mean + offset;
        mask[y * width + x] = isHair ? 1 : 0;
      }
    }
    return mask;
  }
}
