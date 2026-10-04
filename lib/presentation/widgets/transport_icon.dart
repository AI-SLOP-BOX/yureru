import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TransportIcon extends StatelessWidget {
  final String asset;
  final double size;
  final Color color;

  const TransportIcon({
    super.key,
    required this.asset,
    required this.size,
    required this.color,
  });

  const TransportIcon.shuffle({
    super.key,
    required this.size,
    required this.color,
  }) : asset = 'assets/shuffle.svg';

  const TransportIcon.previous({
    super.key,
    required this.size,
    required this.color,
  }) : asset = 'assets/skip_previous.svg';

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    asset,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}
