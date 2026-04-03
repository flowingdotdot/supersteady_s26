import 'package:flutter/material.dart';

class ExitButton extends StatelessWidget {
  final VoidCallback onTap;

  const ExitButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      right: 32,
      child: GestureDetector(
        onTap: onTap,
        child: Container(width: 70, height: 70, color: const Color(0x01000000)),
      ),
    );
  }
}
