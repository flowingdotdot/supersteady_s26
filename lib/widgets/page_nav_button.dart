import 'package:flutter/material.dart';

class PageNavButton extends StatefulWidget {
  final bool isLeft;
  final bool isWhite;
  final bool isVisible;
  final VoidCallback onTap;

  const PageNavButton({
    super.key,
    required this.isLeft,
    required this.onTap,
    this.isWhite = false,
    this.isVisible = true,
  });

  @override
  State<PageNavButton> createState() => _PageNavButtonState();
}

class _PageNavButtonState extends State<PageNavButton> {
  bool _pressed = false;

  String get _imagePath {
    if (widget.isLeft) {
      return widget.isWhite
          ? 'assets/images/icon/back_w.png'
          : 'assets/images/icon/back_bk.png';
    } else {
      return widget.isWhite
          ? 'assets/images/icon/next_w.png'
          : 'assets/images/icon/next_bk.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.isLeft ? 16 : null,
      right: widget.isLeft ? null : 16,
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
          child: Opacity(
            opacity: widget.isVisible ? (_pressed ? 0.6 : 1.0) : 0.0,
            child: Image.asset(_imagePath, width: 50, height: 50),
          ),
        ),
      ),
    );
  }
}
