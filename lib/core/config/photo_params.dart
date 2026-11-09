import 'board_config.dart';

/// Parámetros del análisis de una foto fija.
///
/// Las medidas de color se refieren a valores RGB de 0 a 255.
class PhotoParams {
  const PhotoParams({
    this.analysisWidth = 840,
    this.yellowThreshold = 60,
    this.blueThreshold = 12,
    this.hairMaxChroma = 40,
    this.verticalRunMin = 9,
    this.minAreaFraction = 0.0015,
    this.baseTouchFraction = 0.05,
    this.zoneFraction = 0.15,
    this.denseFraction = 0.5,
    this.lineSnapTolerance = 0.004,
    this.firstLineCm = 7,
    this.tipMinContrast = 8,
    this.tipBackgroundRadius = 20,
    this.minSharpness = 60,
    this.minMeanLuma = 70,
    this.maxMeanLuma = 225,
    this.lines = const AnalysisParams(),
  });

  /// Ancho (px) al que se reduce el ROI antes de analizar. Con 840 px las
  /// líneas dibujadas miden ~3 px, que es lo que espera el detector de líneas.
  final int analysisWidth;

  /// Un píxel es amarillo (sujetador) si (R+G)/2 − B supera este valor.
  final int yellowThreshold;

  /// Un píxel es azul (tinta de las líneas) si B − (R+G)/2 supera este valor.
  final int blueThreshold;

  /// Cabello = píxel poco saturado: max(R,G,B) − min(R,G,B) menor que esto.
  final int hairMaxChroma;

  /// Largo mínimo (px) de un tramo vertical para considerarlo fibra. Quita las
  /// líneas horizontales, que son finas en vertical.
  final int verticalRunMin;

  /// Área mínima de un mechón, como fracción del ROI.
  final double minAreaFraction;

  /// Un mechón debe llegar a menos de esta fracción de alto por encima de la
  /// base de los sujetadores.
  final double baseTouchFraction;

  /// Fracción del largo del mechón usada para su zona de referencia.
  final double zoneFraction;

  /// Filas con al menos esta fracción del pico se consideran cuerpo denso.
  final double denseFraction;



  /// Distancia normalizada bajo la que una punta cuenta como "alcanzó" una línea.
  final double lineSnapTolerance;

  /// Valor en cm de la línea más cercana a los sujetadores.
  final int firstLineCm;

  /// Contraste mínimo (niveles de gris) de un cabello fino sobre el papel
  /// de su entorno, para encontrar la punta más alta del mechón.
  final int tipMinContrast;

  /// Radio (px) de la ventana que estima el papel alrededor de cada píxel.
  final int tipBackgroundRadius;

  /// Varianza mínima del Laplaciano. Por debajo, la foto se considera borrosa.
  final double minSharpness;

  /// Brillo medio (0-255) fuera del cual se advierte oscuridad o sobreexposición.
  final double minMeanLuma;
  final double maxMeanLuma;

  /// Parámetros de la detección de líneas.
  final AnalysisParams lines;
}
