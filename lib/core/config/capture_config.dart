import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Orientación fija de la app y de la captura. La app se usa con el teléfono
/// en horizontal para que la cámara abarque más superficie de la tabla.
///
/// Si la foto aparece de cabeza en tu teléfono, cambia este valor a
/// DeviceOrientation.landscapeRight.
const DeviceOrientation kCaptureOrientation = DeviceOrientation.landscapeLeft;

/// Marco de la tabla dentro de la vista previa (fracciones de la imagen).
/// Es lo que se recorta de la foto antes de analizarla.
const Rect kTableRoi = Rect.fromLTWH(0.06, 0.10, 0.88, 0.78);

/// Altura de la base de los sujetadores dentro del marco (0 = arriba,
/// 1 = abajo). La línea roja de la pantalla se alinea con esta altura.
const double kBaseLineFraction = 0.98;
