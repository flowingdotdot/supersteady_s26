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
    return Positioned(
      top: 32,
      right: 32,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
