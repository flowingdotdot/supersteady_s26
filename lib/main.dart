import 'package:flutter/material.dart';

import 'exhibition_page.dart';
import 'motor_controller.dart';
import 'udp_controller.dart';
import 'widgets/debug_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UdpController.instance.init();
  await MotorController.instance.setup();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const ExhibitionPage(),
      builder: (context, child) => DebugOverlay(child: child!),
    );
  }
}
