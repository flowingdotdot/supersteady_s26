import 'package:flutter/material.dart';

class IdleButton extends StatefulWidget {
  final VoidCallback onTap;

  const IdleButton({super.key, required this.onTap});

  @override
  State<IdleButton> createState() => _IdleButtonState();
}

class _IdleButtonState extends State<IdleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Opacity(
        opacity: _pressed ? 0.6 : 1.0,
        child: Image.asset('assets/images/icon/idle_btn.png', width: 350),
      ),
    );
  }
}
