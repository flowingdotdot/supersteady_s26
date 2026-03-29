import 'package:flutter/material.dart';

class ExitButton extends StatefulWidget {
  final VoidCallback onTap;

  const ExitButton({super.key, required this.onTap});

  @override
  State<ExitButton> createState() => _ExitButtonState();
}

class _ExitButtonState extends State<ExitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const _imagePath = 'assets/images/icon/home_btn.png';

    return Positioned(
      top: 40,
      right: 32,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: Opacity(
          opacity: _pressed ? 0.6 : 1.0,
          child: Image.asset(_imagePath, width: 70, height: 70),
        ),
      ),
    );
  }
}
