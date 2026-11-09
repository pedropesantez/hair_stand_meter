import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/config/board_config.dart';
import '../../core/config/photo_params.dart';
import '../../vision/photo_pipeline.dart';
import '../painters/photo_overlay_painter.dart';

/// Analiza la foto tomada y muestra los mechones contados con su valor fijo.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.jpeg, required this.config});

  final Uint8List jpeg;
  final BoardConfig config;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final Future<PhotoResult> _future;

  @override
  void initState() {
    super.initState();
    _future = PhotoPipeline.process(
      jpeg: widget.jpeg,
      config: widget.config,
      params: const PhotoParams(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<PhotoResult>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No se pudo analizar la foto.\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Repetir foto'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Analizando la foto…'),
                ],
              ),
            );
          }
          return _ResultBody(
            result: snap.data!,
            onRetake: () => Navigator.of(context).pop(),
          );
        },
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.result, required this.onRetake});

  final PhotoResult result;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final analysis = result.analysis;
    final warnings = analysis.quality.warnings;
    return Column(
      children: [
        if (warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Card(
              color: Colors.orange.shade900,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  warnings.join('\n'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
                Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: analysis.photoWidth / analysis.photoHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(result.roiJpeg, fit: BoxFit.fill, gaplessPlayback: true),
                  CustomPaint(painter: PhotoOverlayPainter(analysis)),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: FilledButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Repetir foto'),
          ),
        ),
      ],
    );
  }
}
