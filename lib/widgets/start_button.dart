import 'package:flutter/material.dart';

class StartButton extends StatefulWidget {
  final VoidCallback onTap;

  const StartButton({super.key, required this.onTap});

  @override
  State<StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<StartButton> {
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
        child: Image.asset('assets/images/icon/start_btn.png', width: 400),
      ),
    );
  }
}
