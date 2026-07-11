import 'package:flutter/material.dart';

/// The Speak Frankly logo mark (white speaking head), matching the app/store
/// icon. Sits inside a gradient badge — consistent across every device.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/logo_head.png', width: size, height: size);
  }
}
