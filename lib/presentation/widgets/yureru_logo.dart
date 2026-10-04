import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Crisp, vector-rendered animated wave logo blended with soundwave aesthetics.
class YureruWaveLogo extends StatefulWidget {
  final double size;
  final bool animate;
  const YureruWaveLogo({super.key, this.size = 36, this.animate = false});

  @override
  State<YureruWaveLogo> createState() => _YureruWaveLogoState();
}

class _YureruWaveLogoState extends State<YureruWaveLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant YureruWaveLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _ctrl.repeat();
      } else {
        _ctrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveLogoPainter(phase: _ctrl.value * 2 * math.pi),
          );
        },
      ),
    );
  }
}

class _BarData {
  final double xRatio;
  final double baseH;
  final double animAmp;
  final double speedMult;
  final Color color;
  const _BarData({
    required this.xRatio,
    required this.baseH,
    required this.animAmp,
    required this.speedMult,
    required this.color,
  });
}

class _WaveLogoPainter extends CustomPainter {
  final double phase;
  _WaveLogoPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Glowing ambient background ring
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0x33A855F7),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.48, bgPaint);

    // Three sleek fluid wave pills
    final bars = [
      _BarData(xRatio: 0.28, baseH: 0.45, animAmp: 0.12, speedMult: 1.0, color: const Color(0xFF38BDF8)),
      _BarData(xRatio: 0.50, baseH: 0.70, animAmp: 0.16, speedMult: 1.4, color: const Color(0xFF8B5CF6)),
      _BarData(xRatio: 0.72, baseH: 0.48, animAmp: 0.10, speedMult: 1.2, color: const Color(0xFFEC4899)),
    ];

    for (final bar in bars) {
      final barW = w * 0.14;
      final currentHeightRatio = (bar.baseH + math.sin(phase * bar.speedMult) * bar.animAmp).clamp(0.2, 0.85);
      final barH = h * currentHeightRatio;
      final x = w * bar.xRatio - barW / 2;
      final y = (h - barH) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, barH),
        Radius.circular(barW / 2),
      );

      final barPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bar.color,
            bar.color.withValues(alpha: 0.75),
          ],
        ).createShader(Rect.fromLTWH(x, y, barW, barH));

      // Glow shadow
      canvas.drawRRect(
        rect,
        Paint()
          ..color = bar.color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveLogoPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}

class YureruBrandHeader extends StatelessWidget {
  final double iconSize;
  final bool animate;
  final Color? color;
  const YureruBrandHeader({super.key, this.iconSize = 32, this.animate = false, this.color});

  @override
  Widget build(BuildContext context) {
    final textColor = color ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF0F172A));
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        YureruWaveLogo(size: iconSize, animate: animate),
        const SizedBox(width: 10),
        Text(
          'yureru',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
