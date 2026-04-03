import 'package:flutter/material.dart';

class StartButton extends StatelessWidget {
  final VoidCallback onTap;

  const StartButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 500, height: 130, color: const Color(0x01000000)),
    );
    //const Color(0x01000000)),
  }
}
