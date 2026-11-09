import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/config/board_config.dart';
import '../core/config/photo_params.dart';
import '../core/models/photo_analysis.dart';
import 'photo_analyzer.dart';

/// Resultado del procesamiento de una foto: el análisis y el marco de la tabla
/// ya recortado, para mostrarlo junto a las marcas.
class PhotoResult {
  const PhotoResult({required this.analysis, required this.roiJpeg});

  final PhotoAnalysis analysis;

  /// Marco de la tabla en horizontal, con el mismo tamaño que se analizó.
  final Uint8List roiJpeg;
}

/// Decodifica la foto, corrige la orientación EXIF, recorta el marco de la
/// tabla y lo analiza. Corre en un isolate para no congelar la pantalla.
class PhotoPipeline {
  const PhotoPipeline._();

  static Future<PhotoResult> process({
    required Uint8List jpeg,
    required BoardConfig config,
    required PhotoParams params,
  }) {
    return Isolate.run(() => _run(jpeg, config, params));
  }

  static PhotoResult _run(
    Uint8List jpeg,
    BoardConfig config,
    PhotoParams params,
  ) {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) {
      throw const FormatException('No se pudo leer la foto.');
    }

    // Aplica la rotación EXIF para que la foto quede derecha en horizontal.
    final upright = img.bakeOrientation(decoded);
    final fullW = upright.width;
    final fullH = upright.height;

    final roi = config.roi;
    final x0 = _clampInt((roi.left * fullW).round(), 0, fullW - 1);
    final y0 = _clampInt((roi.top * fullH).round(), 0, fullH - 1);
    final cw = _clampInt((roi.width * fullW).round(), 1, fullW - x0);
    final ch = _clampInt((roi.height * fullH).round(), 1, fullH - y0);

    final crop = img.copyCrop(upright, x: x0, y: y0, width: cw, height: ch);
    final outW = params.analysisWidth;
    final outH = math.max(1, (outW * ch / cw).round());
    final small = img.copyResize(
      crop,
      width: outW,
      height: outH,
      interpolation: img.Interpolation.average,
    );

    final rgb = Uint8List(outW * outH * 3);
    var k = 0;
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final p = small.getPixel(x, y);
        rgb[k++] = p.r.toInt();
        rgb[k++] = p.g.toInt();
        rgb[k++] = p.b.toInt();
      }
    }

    final analysis = PhotoAnalyzer.analyze(
      rgb: rgb,
      width: outW,
      height: outH,
      config: config,
      params: params,
    );

    return PhotoResult(
      analysis: analysis,
      roiJpeg: Uint8List.fromList(img.encodeJpg(small, quality: 90)),
    );
  }

  static int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
}
