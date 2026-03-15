import 'package:flutter/material.dart';

import 'exhibition_page.dart';
import 'udp_controller.dart';
import 'widgets/debug_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  UdpController.instance.init();
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
