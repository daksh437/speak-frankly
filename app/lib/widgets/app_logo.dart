import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Speak Frankly logo mark (white speech bubble with sound bars), matching
/// the app/store icon. Sits inside a gradient badge in place of an emoji.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/logo_mark.svg', width: size, height: size);
  }
}
