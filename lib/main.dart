import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config/capture_config.dart';
import 'ui/screens/capture_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La app se usa en horizontal para que la cámara abarque más de la tabla.
  await SystemChrome.setPreferredOrientations([kCaptureOrientation]);
  runApp(const HairStrandMeterApp());
}

class HairStrandMeterApp extends StatelessWidget {
  const HairStrandMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medidor de mechones',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF2E7D6B),
      ),
      home: const CaptureScreen(),
    );
  }
}
