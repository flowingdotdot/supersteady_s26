import 'package:flutter/material.dart';

class PageNavButton extends StatefulWidget {
  final bool isLeft;
  final VoidCallback onTap;

  const PageNavButton({super.key, required this.isLeft, required this.onTap});

  @override
  State<PageNavButton> createState() => _PageNavButtonState();
}

class _PageNavButtonState extends State<PageNavButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.isLeft ? 0 : null,
      right: widget.isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: Center(
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
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}
