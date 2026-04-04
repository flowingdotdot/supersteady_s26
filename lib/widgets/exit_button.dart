import 'package:flutter/material.dart';

class ExitButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool showImage;

  const ExitButton({super.key, required this.onTap, this.showImage = false});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      right: 32,
      child: GestureDetector(
        onTap: onTap,
        child: showImage
            ? Image.asset('assets/images/icon/home_btn.png', width: 70, height: 70)
            : Container(width: 70, height: 70, color: const Color(0x01000000)),
      ),
    );
  }
}
