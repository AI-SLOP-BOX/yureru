import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Repeat arrows with a compact, explicit badge for single-track repeat.
class RepeatIcon extends StatelessWidget {
  final double size;
  final Color color;
  final String repeatMode;

  const RepeatIcon({
    super.key,
    required this.size,
    required this.color,
    required this.repeatMode,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: SizedBox(
        key: ValueKey(repeatMode),
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SvgPicture.asset(
              'assets/repeat.svg',
              width: size,
              height: size,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              excludeFromSemantics: true,
            ),
            if (repeatMode == 'one')
              Text(
                '1',
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.38,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (repeatMode == 'all')
              Center(
                child: Container(
                  width: size * 0.16,
                  height: size * 0.16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
