import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/config/board_config.dart';
import '../../core/config/capture_config.dart';
import '../painters/guide_painter.dart';
import 'result_screen.dart';

/// Pantalla de captura: vista previa con marcas para centrar el teléfono y
/// un botón para tomar la foto que se analizará.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  final BoardConfig _config = BoardConfig.uniform(
    roi: kTableRoi,
    clipY: kBaseLineFraction,
  );

  CameraController? _controller;
  String? _error;
  bool _busy = false;
  bool _torch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamera', 'No se encontró ninguna cámara.');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(kCaptureOrientation);
      // Enfoque y exposición en el centro: ahí va la tabla.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      } on CameraException {
        // Algunos equipos no permiten elegir el punto; se sigue igual.
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    final next = !_torch;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = next);
    } on CameraException {
      // Sin linterna disponible: se mantiene el estado anterior.
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(jpeg: bytes, config: _config),
        ),
      );
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo tomar la foto: ${e.description ?? e.code}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: c != null
                  ? _preview(c)
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        )
                      : const CircularProgressIndicator(),
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Centre la tabla dentro del marco y alinee la base de los '
                  'sujetadores con la línea roja. Mantenga el teléfono quieto.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Linterna',
                    onPressed: c == null ? null : _toggleTorch,
                    icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
                  ),
                  const SizedBox(height: 20),
                  FloatingActionButton.large(
                    tooltip: 'Tomar foto',
                    onPressed: (c == null || _busy) ? null : _capture,
                    child: _busy
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.camera_alt),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(CameraController c) {
    // En horizontal, el lado largo es el ancho.
    final a = c.value.aspectRatio;
    final landscape = a > 1 ? a : 1 / a;
    return AspectRatio(
      aspectRatio: landscape,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(c),
          CustomPaint(
            painter: GuidePainter(roi: kTableRoi, baseFraction: kBaseLineFraction),
          ),
        ],
      ),
    );
  }
}
