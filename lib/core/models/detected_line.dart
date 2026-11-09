/// Línea horizontal dibujada en la tabla, detectada en la imagen.
///
/// Las líneas a mano no son perfectamente horizontales, así que cada una se
/// describe con una recta: y(x) = y + slope · (x − 0.5), en coordenadas
/// normalizadas del ROI (0 = borde superior, 1 = borde inferior).
class DetectedLine {
  const DetectedLine({required this.y, this.slope = 0, this.coverage = 0});

  /// Posición vertical en el centro horizontal del ROI (0..1).
  final double y;

  /// Cambio de y por unidad de x (en coordenadas normalizadas del ROI).
  final double slope;

  /// Fracción de columnas en las que se vio el trazo (0..1). Útil para depurar.
  final double coverage;

  /// Posición vertical de la línea en la columna normalizada [xn] (0..1).
  double yAt(double xn) => y + slope * (xn - 0.5);
}
