import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SkipNextIcon extends StatelessWidget {
  final double size;
  final Color color;

  const SkipNextIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/skip_next.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
