import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Monochrome SVG assets inherit button size, foreground and disabled opacity.
class AppSvgIcon extends StatelessWidget {
  const AppSvgIcon(this.name, {super.key, this.size, this.color});

  final String name;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final foreground = color ?? theme.color ?? Colors.black;
    final dimension = size ?? theme.size ?? 24;
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: dimension,
      height: dimension,
      colorFilter: ColorFilter.mode(
        foreground.withValues(alpha: foreground.a * (theme.opacity ?? 1)),
        BlendMode.srcIn,
      ),
      excludeFromSemantics: true,
    );
  }
}
