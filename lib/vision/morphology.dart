import 'dart:typed_data';

/// Morfología binaria con kernel rectangular kw × kh, separable y O(w·h)
/// gracias a sumas prefijas (el costo no depende del tamaño del kernel).
class Morphology {
  const Morphology._();

  /// Apertura = erosión seguida de dilatación.
  /// Borra toda estructura más angosta que kw (cabellos sueltos verticales)
  /// o más baja que kh (líneas impresas horizontales) y conserva intacto el
  /// volumen grueso del mechón.
  static Uint8List open(Uint8List m, int w, int h, int kw, int kh) =>
      dilate(erode(m, w, h, kw, kh), w, h, kw, kh);

  static Uint8List erode(Uint8List m, int w, int h, int kw, int kh) =>
      _vertical(_horizontal(m, w, h, kw, all: true), w, h, kh, all: true);

  static Uint8List dilate(Uint8List m, int w, int h, int kw, int kh) =>
      _vertical(_horizontal(m, w, h, kw, all: false), w, h, kh, all: false);

  /// all = true  → erosión (todos los píxeles de la ventana son 1)
  /// all = false → dilatación (al menos uno es 1)
  static Uint8List _horizontal(Uint8List src, int w, int h, int k, {required bool all}) {
    if (k <= 1) return Uint8List.fromList(src);
    final r = k ~/ 2;
    final dst = Uint8List(w * h);
    final prefix = Int32List(w + 1);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        prefix[x + 1] = prefix[x] + src[row + x];
      }
      for (var x = 0; x < w; x++) {
        final a = x - r < 0 ? 0 : x - r;
        final b = x + r >= w ? w - 1 : x + r;
        final count = prefix[b + 1] - prefix[a];
        dst[row + x] = all ? (count == b - a + 1 ? 1 : 0) : (count > 0 ? 1 : 0);
      }
    }
    return dst;
  }

  static Uint8List _vertical(Uint8List src, int w, int h, int k, {required bool all}) {
    if (k <= 1) return Uint8List.fromList(src);
    final r = k ~/ 2;
    final dst = Uint8List(w * h);
    final prefix = Int32List(h + 1);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        prefix[y + 1] = prefix[y] + src[y * w + x];
      }
      for (var y = 0; y < h; y++) {
        final a = y - r < 0 ? 0 : y - r;
        final b = y + r >= h ? h - 1 : y + r;
        final count = prefix[b + 1] - prefix[a];
        dst[y * w + x] = all ? (count == b - a + 1 ? 1 : 0) : (count > 0 ? 1 : 0);
      }
    }
    return dst;
  }
}
