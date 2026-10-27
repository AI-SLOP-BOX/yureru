import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';

// Keep the horizontal/vertical edge profile close to the 320×180 glow image's
// native resolution. Thirty-two broad zones collapsed roads and other narrow
// features into a few oversized, visibly shifted bands.
const ambientZoneCount = 32;
const ambientEdgeSampleCount = 256;

class AmbientEdgeColors {
  const AmbientEdgeColors({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    this.contentRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.matteMask,
  });

  final List<Color> top;
  final List<Color> bottom;
  final List<Color> left;
  final List<Color> right;

  /// Active picture bounds after removing encoded black letterbox bars.
  /// Expressed in normalized source-frame coordinates.
  final Rect contentRect;

  /// 320×180 alpha map for static black, white, or transparent edge pixels.
  /// Keeps contrasting text drawn over a letterbox visible.
  final Uint8List? matteMask;
}

AmbientEdgeColors blendAmbientEdges(
  AmbientEdgeColors previous,
  AmbientEdgeColors current, {
  double response = 0.48,
}) {
  List<Color> blend(List<Color> oldColors, List<Color> newColors) => [
    for (var i = 0; i < newColors.length; i++)
      Color.lerp(oldColors[i], newColors[i], response.clamp(0.0, 1.0))!,
  ];
  return AmbientEdgeColors(
    top: blend(previous.top, current.top),
    bottom: blend(previous.bottom, current.bottom),
    left: blend(previous.left, current.left),
    right: blend(previous.right, current.right),
    contentRect: Rect.fromLTRB(
      ui.lerpDouble(
        previous.contentRect.left,
        current.contentRect.left,
        response,
      )!,
      ui.lerpDouble(
        previous.contentRect.top,
        current.contentRect.top,
        response,
      )!,
      ui.lerpDouble(
        previous.contentRect.right,
        current.contentRect.right,
        response,
      )!,
      ui.lerpDouble(
        previous.contentRect.bottom,
        current.contentRect.bottom,
        response,
      )!,
    ),
    matteMask: current.matteMask,
  );
}

double ambientEdgesDifference(AmbientEdgeColors a, AmbientEdgeColors b) {
  final aGroups = [a.top, a.bottom, a.left, a.right];
  final bGroups = [b.top, b.bottom, b.left, b.right];
  var total = 0.0;
  var count = 0;
  for (var group = 0; group < aGroups.length; group++) {
    for (var i = 0; i < aGroups[group].length; i++) {
      final first = aGroups[group][i];
      final second = bGroups[group][i];
      total += (first.r - second.r).abs() * 255;
      total += (first.g - second.g).abs() * 255;
      total += (first.b - second.b).abs() * 255;
      count += 3;
    }
  }
  total +=
      (a.contentRect.left - b.contentRect.left).abs() * 1000 +
      (a.contentRect.top - b.contentRect.top).abs() * 1000 +
      (a.contentRect.right - b.contentRect.right).abs() * 1000 +
      (a.contentRect.bottom - b.contentRect.bottom).abs() * 1000;
  count += 4;
  return count == 0 ? 0 : total / count;
}

/// Stabilizes tiny per-frame sampling noise, follows ordinary motion quickly,
/// and snaps on scene cuts so a large color change does not trail behind.
AmbientEdgeColors updateAmbientEdges(
  AmbientEdgeColors previous,
  AmbientEdgeColors sampled, {
  double deadband = 1.5,
  double sceneCut = 24.0,
  double response = 0.9,
}) {
  final difference = ambientEdgesDifference(previous, sampled);
  if (difference < deadband) return previous;
  if (difference >= sceneCut) return sampled;
  return blendAmbientEdges(previous, sampled, response: response);
}

/// Samples all four visible edges so glow direction follows the actual shot.
/// Black letterbox rows/columns are skipped before sampling.
AmbientEdgeColors sampleAmbientEdges(
  Uint8List rgba,
  int width,
  int height, {
  int zoneCount = ambientEdgeSampleCount,
  int? rowBytes,
  bool bgra = false,
}) {
  final stride = rowBytes ?? width * 4;
  if (width <= 0 ||
      height <= 0 ||
      stride < width * 4 ||
      rgba.length < stride * height) {
    final black = List<Color>.filled(zoneCount, Colors.black);
    return AmbientEdgeColors(
      top: black,
      bottom: black,
      left: black,
      right: black,
    );
  }

  var top = 0;
  var bottom = height;
  var left = 0;
  var right = width;
  while (top < height * 0.3 &&
      _isEdgeMatteRow(rgba, width, top, stride, bgra)) {
    top++;
  }
  while (bottom > height * 0.7 &&
      _isEdgeMatteRow(rgba, width, bottom - 1, stride, bgra)) {
    bottom--;
  }
  while (left < width * 0.3 &&
      _isEdgeMatteColumn(rgba, width, height, left, stride, bgra)) {
    left++;
  }
  while (right > width * 0.7 &&
      _isEdgeMatteColumn(rgba, width, height, right - 1, stride, bgra)) {
    right--;
  }

  final minX = width * 0.025;
  final minY = height * 0.025;
  if (left < minX) left = 0;
  if (width - right < minX) right = width;
  if (top < minY) top = 0;
  if (height - bottom < minY) bottom = height;
  if (right - left < width * 0.45 || bottom - top < height * 0.45) {
    left = 0;
    right = width;
    top = 0;
    bottom = height;
  }

  // Read a shallow strip from inside the visible picture instead of a single
  // near-border scanline. That avoids letterbox antialiasing and prevents a
  // bright one-row highlight from becoming a hard horizontal light band.
  final sampleInsetX = ((right - left) * 0.005).round().clamp(
    0,
    right - left - 1,
  );
  final sampleInsetY = ((bottom - top) * 0.005).round().clamp(
    0,
    bottom - top - 1,
  );
  final sideCornerInsetY = sampleInsetY;
  // Sample a narrow strip close to each edge, averaging enough pixels to keep
  // texture and compression noise from making the reflected colors gritty.
  // Stay close to the actual edge so the ambient light meets the visible
  // frame color. A wide inward band sampled a different scene region and
  // showed up as a horizontal/vertical seam at the player boundary.
  final horizontalBand = ((bottom - top) * 0.008).round().clamp(3, 5);
  final verticalBand = ((right - left) * 0.008).round().clamp(3, 5);

  final contentRect = Rect.fromLTRB(
    left / width,
    top / height,
    right / width,
    bottom / height,
  );
  return AmbientEdgeColors(
    top: _sampleZones(
      rgba,
      width,
      zoneCount,
      start: left,
      end: right,
      fixedStart: top + sampleInsetY,
      fixedCount: horizontalBand,
      horizontal: true,
      rowBytes: stride,
      bgra: bgra,
    ),
    bottom: _sampleZones(
      rgba,
      width,
      zoneCount,
      start: left,
      end: right,
      fixedStart: bottom - sampleInsetY - horizontalBand,
      fixedCount: horizontalBand,
      horizontal: true,
      rowBytes: stride,
      bgra: bgra,
    ),
    left: _sampleZones(
      rgba,
      width,
      zoneCount,
      start: top + sideCornerInsetY,
      end: bottom - sideCornerInsetY,
      fixedStart: left + sampleInsetX,
      fixedCount: verticalBand,
      horizontal: false,
      rowBytes: stride,
      bgra: bgra,
    ),
    right: _sampleZones(
      rgba,
      width,
      zoneCount,
      start: top + sideCornerInsetY,
      end: bottom - sideCornerInsetY,
      fixedStart: right - sampleInsetX - verticalBand,
      fixedCount: verticalBand,
      horizontal: false,
      rowBytes: stride,
      bgra: bgra,
    ),
    contentRect: contentRect,
    matteMask: _sampleEdgeMatteMask(
      rgba,
      width,
      height,
      stride,
      bgra,
      contentRect,
    ),
  );
}

List<Color> _softenAmbientProfile(
  List<Color> colors, {
  double softness = 1,
  double blurFraction = 0.055,
}) {
  if (colors.length < 3) return colors;
  // Smooth only along the sampled edge. This removes narrow window frames,
  // subtitles and compression blocks from becoming long color bars without
  // turning the ambient field into a blurred copy of the whole video.
  // A broad blur across 30% of the edge erased nearly all spatial color
  // variation, turning the room spill into a few huge, uniform stripes.
  // Keep the near-frame profile local. A second, wider profile is blended in
  // only farther out, so narrow color streaks fan into a continuous wall glow
  // instead of being copied as rigid vertical or horizontal bars.
  final sigma = (colors.length * blurFraction * softness.clamp(0.5, 1.5)).clamp(
    1.0,
    colors.length * 0.20,
  );
  final radius = (sigma * 3).ceil();
  return [
    for (var center = 0; center < colors.length; center++)
      _weightedColorAverage(colors, center, sigma, radius),
  ];
}

Color _weightedColorAverage(
  List<Color> colors,
  int center,
  double sigma,
  int radius,
) {
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var sum = 0.0;
  for (var offset = -radius; offset <= radius; offset++) {
    final index = (center + offset).clamp(0, colors.length - 1);
    final weight = math.exp(-(offset * offset) / (2 * sigma * sigma));
    red += colors[index].r * weight;
    green += colors[index].g * weight;
    blue += colors[index].b * weight;
    sum += weight;
  }
  return Color.fromARGB(
    255,
    (red / sum * 255).round().clamp(0, 255),
    (green / sum * 255).round().clamp(0, 255),
    (blue / sum * 255).round().clamp(0, 255),
  );
}

List<Color> _sampleZones(
  Uint8List rgba,
  int width,
  int zoneCount, {
  required int start,
  required int end,
  required int fixedStart,
  required int fixedCount,
  required bool horizontal,
  required int rowBytes,
  required bool bgra,
}) {
  final result = <Color>[];
  for (var zone = 0; zone < zoneCount; zone++) {
    final zoneStart = start + ((end - start) * zone / zoneCount).floor();
    final zoneEnd = start + ((end - start) * (zone + 1) / zoneCount).ceil();
    var red = 0;
    var green = 0;
    var blue = 0;
    var count = 0;
    for (var point = 0; point < 3; point++) {
      final moving = (zoneStart + (point + 0.5) * (zoneEnd - zoneStart) / 3)
          .floor()
          .clamp(zoneStart, zoneEnd - 1);
      for (var inset = 0; inset < fixedCount; inset++) {
        final x = horizontal ? moving : fixedStart + inset;
        final y = horizontal ? fixedStart + inset : moving;
        final index = y * rowBytes + x * 4;
        red += _red(rgba, index, bgra);
        green += rgba[index + 1];
        blue += _blue(rgba, index, bgra);
        count++;
      }
    }
    result.add(
      Color.fromARGB(255, red ~/ count, green ~/ count, blue ~/ count),
    );
  }
  return result;
}

int _red(Uint8List pixels, int index, bool bgra) =>
    pixels[index + (bgra ? 2 : 0)];

int _blue(Uint8List pixels, int index, bool bgra) =>
    pixels[index + (bgra ? 0 : 2)];

int _edgeMatteKind(Uint8List rgba, int index, bool bgra) {
  if (rgba[index + 3] <= 8) return 0; // Fully transparent video pixels.
  final red = _red(rgba, index, bgra);
  final green = rgba[index + 1];
  final blue = _blue(rgba, index, bgra);
  // Require near-solid black/white before calling edge pixels a letterbox.
  // Dark scenes often have very low luminance; a looser threshold can mark
  // real picture rows as matte and paint ambient light over the video.
  if (red < 8 && green < 8 && blue < 8) return 1;
  if (red > 248 && green > 248 && blue > 248) return 2;
  return 3;
}

bool _isEdgeMatteColumn(
  Uint8List rgba,
  int width,
  int height,
  int x,
  int rowBytes,
  bool bgra,
) {
  final kinds = List<int>.filled(3, 0);
  final stride = (height / 80).ceil().clamp(1, height);
  var count = 0;
  for (var y = 0; y < height; y += stride) {
    final i = y * rowBytes + x * 4;
    final kind = _edgeMatteKind(rgba, i, bgra);
    if (kind < kinds.length) kinds[kind]++;
    count++;
  }
  return kinds.reduce((a, b) => a > b ? a : b) / count >= 0.90;
}

int _dominantEdgeMatteKind(
  Uint8List pixels,
  int width,
  int height,
  int rowBytes,
  bool bgra, {
  required bool horizontal,
  required int position,
}) {
  final length = horizontal ? width : height;
  final stride = (length / 80).ceil().clamp(1, length);
  final kinds = List<int>.filled(3, 0);
  var count = 0;
  for (var sample = 0; sample < length; sample += stride) {
    final x = horizontal ? sample : position;
    final y = horizontal ? position : sample;
    final kind = _edgeMatteKind(pixels, y * rowBytes + x * 4, bgra);
    if (kind < kinds.length) kinds[kind]++;
    count++;
  }
  var dominantKind = 0;
  for (var kind = 1; kind < kinds.length; kind++) {
    if (kinds[kind] > kinds[dominantKind]) dominantKind = kind;
  }
  return kinds[dominantKind] / count >= 0.90 ? dominantKind : 3;
}

Uint8List _sampleEdgeMatteMask(
  Uint8List pixels,
  int sourceWidth,
  int sourceHeight,
  int rowBytes,
  bool bgra,
  Rect contentRect,
) {
  const width = 320;
  const height = 180;
  final mask = Uint8List(width * height);
  final activeLeft = (contentRect.left * sourceWidth).floor();
  final activeTop = (contentRect.top * sourceHeight).floor();
  final activeRight = (contentRect.right * sourceWidth).ceil();
  final activeBottom = (contentRect.bottom * sourceHeight).ceil();
  final rowKinds = <int, int>{};
  final columnKinds = <int, int>{};

  for (var y = 0; y < height; y++) {
    final sourceY = (y * sourceHeight / height).floor().clamp(
      0,
      sourceHeight - 1,
    );
    for (var x = 0; x < width; x++) {
      final sourceX = (x * sourceWidth / width).floor().clamp(
        0,
        sourceWidth - 1,
      );
      final outsideVertical = sourceY < activeTop || sourceY >= activeBottom;
      final outsideHorizontal = sourceX < activeLeft || sourceX >= activeRight;
      if (!outsideVertical && !outsideHorizontal) continue;

      final kind = outsideVertical
          ? rowKinds.putIfAbsent(
              sourceY,
              () => _dominantEdgeMatteKind(
                pixels,
                sourceWidth,
                sourceHeight,
                rowBytes,
                bgra,
                horizontal: true,
                position: sourceY,
              ),
            )
          : columnKinds.putIfAbsent(
              sourceX,
              () => _dominantEdgeMatteKind(
                pixels,
                sourceWidth,
                sourceHeight,
                rowBytes,
                bgra,
                horizontal: false,
                position: sourceX,
              ),
            );
      final pixelKind = _edgeMatteKind(
        pixels,
        sourceY * rowBytes + sourceX * 4,
        bgra,
      );
      if (kind < 3 && pixelKind == kind) mask[y * width + x] = 255;
    }
  }
  return mask;
}

/// Samples color zones along the top edge of an RGBA video frame.
/// Uniform black/white or transparent rows at the frame edges are treated as
/// empty matte, not picture content.
List<Color> sampleAmbientZones(
  Uint8List rgba,
  int width,
  int height, {
  int zoneCount = ambientZoneCount,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return List.filled(zoneCount, Colors.black);
  }

  var top = 0;
  var bottom = height;
  final minBarHeight = (height * 0.025).round().clamp(2, 16);
  while (top < height * 0.3 &&
      _isEdgeMatteRow(rgba, width, top, width * 4, false)) {
    top++;
  }
  while (bottom > height * 0.7 &&
      _isEdgeMatteRow(rgba, width, bottom - 1, width * 4, false)) {
    bottom--;
  }
  if (top < minBarHeight) top = 0;
  if (height - bottom < minBarHeight) bottom = height;
  if (bottom - top < height * 0.45) {
    top = 0;
    bottom = height;
  }

  final contentHeight = bottom - top;
  final sampleTop = (top + contentHeight * 0.025).round().clamp(
    top,
    bottom - 1,
  );
  final sampleRows = (contentHeight * 0.015).round().clamp(1, 5);
  final samplesPerZone = 6;
  final result = <Color>[];

  for (var zone = 0; zone < zoneCount; zone++) {
    final left = (zone * width / zoneCount).floor();
    final right = ((zone + 1) * width / zoneCount).ceil().clamp(
      left + 1,
      width,
    );
    var red = 0;
    var green = 0;
    var blue = 0;
    var count = 0;
    for (var sample = 0; sample < samplesPerZone; sample++) {
      final x = (left + (sample + 0.5) * (right - left) / samplesPerZone)
          .floor()
          .clamp(left, right - 1);
      for (var row = 0; row < sampleRows; row++) {
        final y = (sampleTop + row).clamp(top, bottom - 1);
        final index = (y * width + x) * 4;
        red += rgba[index];
        green += rgba[index + 1];
        blue += rgba[index + 2];
        count++;
      }
    }
    result.add(
      Color.fromARGB(255, red ~/ count, green ~/ count, blue ~/ count),
    );
  }
  return result;
}

bool _isEdgeMatteRow(
  Uint8List rgba,
  int width,
  int y,
  int rowBytes,
  bool bgra,
) {
  final kinds = List<int>.filled(3, 0);
  final stride = (width / 80).ceil().clamp(1, width);
  var count = 0;
  for (var x = 0; x < width; x += stride) {
    final i = y * rowBytes + x * 4;
    final kind = _edgeMatteKind(rgba, i, bgra);
    if (kind < kinds.length) kinds[kind]++;
    count++;
  }
  return kinds.reduce((a, b) => a > b ? a : b) / count >= 0.90;
}

Future<Uint8List?> encodeAmbientGradient(List<Color> colors) async {
  if (colors.isEmpty) return null;
  const width = 320;
  const height = 24;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final shader = ui.Gradient.linear(
    const ui.Offset(0, 0),
    ui.Offset(width.toDouble(), 0),
    colors,
    [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)],
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Encodes a full-window ambient field around the video.
///
/// This image is composited below the actual video and app controls, so the
/// video itself remains pixel-identical while its colors can continue across
/// the entire window instead of stopping at the player card.
Future<ui.Image> renderAmbientGlow(
  AmbientEdgeColors edges, {
  Rect? aperture,
  double spread = 1,
  double depth = 1,
  double softness = 1,
  bool matteOnly = false,
}) async {
  const width = 320;
  const height = 180;
  // The caller measures the real video view in the app window. Using a fixed
  // centered rectangle made edge colors stretch at the wrong scale whenever
  // the player moved or resized.
  final playerAperture =
      aperture ?? const Rect.fromLTWH(0.255, 0.30, 0.43, 0.44);
  // Edge sampling ignores encoded black bars, so the glow aperture must use
  // the same active-picture bounds. Otherwise the light is anchored to the
  // player frame and appears detached from the visible image.
  final normalizedAperture = Rect.fromLTRB(
    playerAperture.left + playerAperture.width * edges.contentRect.left,
    playerAperture.top + playerAperture.height * edges.contentRect.top,
    playerAperture.left + playerAperture.width * edges.contentRect.right,
    playerAperture.top + playerAperture.height * edges.contentRect.bottom,
  );
  final apertureLeft = normalizedAperture.left * width;
  final apertureRight = normalizedAperture.right * width;
  final apertureTop = normalizedAperture.top * height;
  final apertureBottom = normalizedAperture.bottom * height;
  // The glow is rendered at a small fixed resolution, so express the same
  // rounded player corner as a proportional radius in this coordinate space.
  final cornerRadius = math.min(
    12.0,
    math.min(apertureRight - apertureLeft, apertureBottom - apertureTop) *
        0.045,
  );
  final top = edges.top;
  final bottom = edges.bottom;
  final left = edges.left;
  final right = edges.right;
  final diffusedTop = _softenAmbientProfile(
    top,
    softness: softness,
    blurFraction: 0.07,
  );
  final diffusedBottom = _softenAmbientProfile(
    bottom,
    softness: softness,
    blurFraction: 0.07,
  );
  final diffusedLeft = _softenAmbientProfile(
    left,
    softness: softness,
    blurFraction: 0.07,
  );
  final diffusedRight = _softenAmbientProfile(
    right,
    softness: softness,
    blurFraction: 0.07,
  );
  final roomTop = _softenAmbientProfile(
    top,
    softness: softness,
    blurFraction: 0.20,
  );
  final roomBottom = _softenAmbientProfile(
    bottom,
    softness: softness,
    blurFraction: 0.20,
  );
  final roomLeft = _softenAmbientProfile(
    left,
    softness: softness,
    blurFraction: 0.20,
  );
  final roomRight = _softenAmbientProfile(
    right,
    softness: softness,
    blurFraction: 0.20,
  );
  final rgba = Uint8List(width * height * 4);
  const sideProfileInset = 0.005;

  Color colorAt(List<Color> colors, double position) {
    final scaled = position.clamp(0.0, 1.0) * (colors.length - 1);
    final first = scaled.floor();
    return Color.lerp(
      colors[first],
      colors[math.min(first + 1, colors.length - 1)],
      scaled - first,
    )!;
  }

  Color profileAverage(List<Color> colors) {
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    for (final color in colors) {
      red += color.r;
      green += color.g;
      blue += color.b;
    }
    return Color.fromARGB(
      255,
      (red / colors.length * 255).round().clamp(0, 255),
      (green / colors.length * 255).round().clamp(0, 255),
      (blue / colors.length * 255).round().clamp(0, 255),
    );
  }

  final averageTop = profileAverage(diffusedTop);
  final averageBottom = profileAverage(diffusedBottom);
  final averageLeft = profileAverage(diffusedLeft);
  final averageRight = profileAverage(diffusedRight);
  final depthBlend = (depth / 2).clamp(0.0, 1.0);
  final spreadPixels = math.min(width, height) * 0.55 * spread.clamp(0.5, 1.5);
  final glowFadeDistance = 40 + 40 * (spread.clamp(0.5, 1.5) - 0.5);

  Color edgeColorAt(
    List<Color> edge,
    List<Color> diffused,
    List<Color> room,
    Color average,
    double position,
    double distancePixels,
  ) {
    // Keep the first few pixels faithful to the video edge. Only then broaden
    // the profile into the room; starting from a blurred profile created a
    // visible color discontinuity right where the light should meet the image.
    final normalizedDistance = (distancePixels / spreadPixels).clamp(0.0, 1.0);
    final outward = math.pow(normalizedDistance, 0.8).toDouble();
    final broadProfile = Color.lerp(
      colorAt(diffused, position),
      colorAt(room, position),
      outward * (0.45 + depthBlend * 0.54),
    )!;
    final blurStart = ((distancePixels - 8) / 72).clamp(0.0, 1.0);
    final blurProgress = blurStart * blurStart * (3 - 2 * blurStart);
    final broadened = Color.lerp(
      colorAt(edge, position),
      broadProfile,
      blurProgress,
    )!;
    // A small amount of room-color mixing suppresses isolated streaks without
    // flattening the whole edge into one average hue. Most diffusion comes
    // from the progressively wider profile above, which preserves the scene's
    // broad color layout as it travels away from the video.
    final amount =
        (0.08 + depthBlend * 0.16) *
        math.pow(normalizedDistance, 0.85).toDouble();
    final source = Color.lerp(broadened, average, amount)!;
    final luminance = source.r * 0.2126 + source.g * 0.7152 + source.b * 0.0722;
    if (luminance <= 0.68) return source;
    // Softly roll off near-white highlights. A full-white strip at the video
    // edge otherwise reads as a hard border when projected across the UI.
    // Start the highlight rolloff at the exact sampled edge, then increase it
    // with distance. Applying it immediately at the boundary darkened the
    // glow side of a bright video edge and created a sharp seam.
    final highlightRetention = 1 - 0.75 * outward;
    final softenedLuminance = 0.68 + (luminance - 0.68) * highlightRetention;
    final scale = softenedLuminance / luminance;
    return Color.fromARGB(
      255,
      (source.r * scale * 255).round().clamp(0, 255),
      (source.g * scale * 255).round().clamp(0, 255),
      (source.b * scale * 255).round().clamp(0, 255),
    );
  }

  void write(int x, int y, Color color, double alpha) {
    final offset = (y * width + x) * 4;
    rgba[offset] = (color.r * 255).round().clamp(0, 255);
    rgba[offset + 1] = (color.g * 255).round().clamp(0, 255);
    rgba[offset + 2] = (color.b * 255).round().clamp(0, 255);
    rgba[offset + 3] = (alpha.clamp(0.0, 1.0) * 255).round();
  }

  final centerX = (apertureLeft + apertureRight) / 2;
  final centerY = (apertureTop + apertureBottom) / 2;
  final coreHalfWidth = (apertureRight - apertureLeft) / 2 - cornerRadius;
  final coreHalfHeight = (apertureBottom - apertureTop) / 2 - cornerRadius;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixelX = x + 0.5;
      final pixelY = y + 0.5;
      final insideX = pixelX >= apertureLeft && pixelX <= apertureRight;
      final insideY = pixelY >= apertureTop && pixelY <= apertureBottom;
      final horizontalPosition =
          (pixelX - apertureLeft) / (apertureRight - apertureLeft);
      final verticalPosition =
          (pixelY - apertureTop) / (apertureBottom - apertureTop);
      final sidePosition =
          sideProfileInset + verticalPosition * (1 - sideProfileInset * 2);

      // Rounded-rectangle signed distance: the glow aperture now follows the
      // same rounded contour as the player instead of leaving a transparent
      // rectangular notch at each video corner.
      final qx = (pixelX - centerX).abs() - coreHalfWidth;
      final qy = (pixelY - centerY).abs() - coreHalfHeight;
      final outsideX = math.max(qx, 0.0);
      final outsideY = math.max(qy, 0.0);
      final signedDistance =
          math.sqrt(outsideX * outsideX + outsideY * outsideY) +
          math.min(math.max(qx, qy), 0.0) -
          cornerRadius;

      late Color color;
      late double alpha;
      if (signedDistance <= 0) {
        // The picture and its rounded corner stay untouched by the backdrop.
        final horizontalColor = Color.lerp(
          colorAt(top, horizontalPosition),
          colorAt(bottom, horizontalPosition),
          verticalPosition,
        )!;
        final verticalColor = Color.lerp(
          colorAt(left, verticalPosition),
          colorAt(right, verticalPosition),
          horizontalPosition,
        )!;
        final sideDistance = math.min(
          horizontalPosition,
          1 - horizontalPosition,
        );
        final topBottomDistance = math.min(
          verticalPosition,
          1 - verticalPosition,
        );
        final horizontalWeight =
            sideDistance /
            (sideDistance + topBottomDistance).clamp(0.0001, 2.0);
        color = Color.lerp(
          horizontalColor,
          verticalColor,
          1 - horizontalWeight,
        )!;
        alpha = 0;
      } else if (qx > 0 && qy > 0) {
        // Project corner pixels onto the circular arc and blend the two edge
        // profiles by arc angle. This also fills the rounded-corner cutout
        // outside the video, where rectangular aperture masking left a gap.
        final isLeft = pixelX < centerX;
        final isTop = pixelY < centerY;
        final signX = isLeft ? -1.0 : 1.0;
        final signY = isTop ? -1.0 : 1.0;
        final coreX = centerX + signX * coreHalfWidth;
        final coreY = centerY + signY * coreHalfHeight;
        final dx = pixelX - coreX;
        final dy = pixelY - coreY;
        final length = math
            .sqrt(dx * dx + dy * dy)
            .clamp(0.0001, double.infinity);
        final boundaryX = coreX + dx / length * cornerRadius;
        final boundaryY = coreY + dy / length * cornerRadius;
        final arcPosition = math.atan2(dy.abs(), dx.abs()) / (math.pi / 2);
        final horizontalEdge = isTop ? top : bottom;
        final horizontalDiffused = isTop ? diffusedTop : diffusedBottom;
        final horizontalRoom = isTop ? roomTop : roomBottom;
        final horizontalAverage = isTop ? averageTop : averageBottom;
        final sideEdge = isLeft ? left : right;
        final sideDiffused = isLeft ? diffusedLeft : diffusedRight;
        final sideRoom = isLeft ? roomLeft : roomRight;
        final sideAverage = isLeft ? averageLeft : averageRight;
        final horizontalSource = edgeColorAt(
          horizontalEdge,
          horizontalDiffused,
          horizontalRoom,
          horizontalAverage,
          ((boundaryX - apertureLeft) / (apertureRight - apertureLeft)).clamp(
            0.0,
            1.0,
          ),
          signedDistance,
        );
        final sideSource = edgeColorAt(
          sideEdge,
          sideDiffused,
          sideRoom,
          sideAverage,
          ((boundaryY - apertureTop) / (apertureBottom - apertureTop)).clamp(
            0.0,
            1.0,
          ),
          signedDistance,
        );
        final easedArc = arcPosition * arcPosition * (3 - 2 * arcPosition);
        color = Color.lerp(horizontalSource, sideSource, easedArc)!;
        alpha = 1;
      } else if (qy > 0) {
        final isTop = pixelY < centerY;
        color = isTop
            ? edgeColorAt(
                top,
                diffusedTop,
                roomTop,
                averageTop,
                horizontalPosition,
                signedDistance,
              )
            : edgeColorAt(
                bottom,
                diffusedBottom,
                roomBottom,
                averageBottom,
                horizontalPosition,
                signedDistance,
              );
        alpha = 1;
      } else {
        final isLeft = pixelX < centerX;
        color = isLeft
            ? edgeColorAt(
                left,
                diffusedLeft,
                roomLeft,
                averageLeft,
                sidePosition,
                signedDistance,
              )
            : edgeColorAt(
                right,
                diffusedRight,
                roomRight,
                averageRight,
                sidePosition,
                signedDistance,
              );
        alpha = 1;
      }
      if (matteOnly) {
        final insidePicture =
            x >= apertureLeft &&
            x < apertureRight &&
            y >= apertureTop &&
            y < apertureBottom;
        // This image is composited over the video only. Replace static matte
        // pixels with the edge light, leaving the moving picture untouched.
        final mask = edges.matteMask;
        alpha = mask == null
            ? (insidePicture ? 0 : 1)
            : (mask[y * width + x] > 0 ? 1 : 0);
      } else if (signedDistance > 0) {
        // Fade each spill toward the actual window edges. Multiplying the
        // rounded side distances gives corners a radial falloff instead of
        // extending a top/bottom scanline as a hard rectangular stripe.
        final horizontalFade = insideX
            ? 1.0
            : x < apertureLeft
            ? (x / apertureLeft).clamp(0.0, 1.0)
            : ((width - 1 - x) / (width - 1 - apertureRight)).clamp(0.0, 1.0);
        final verticalFade = insideY
            ? 1.0
            : y < apertureTop
            ? (y / apertureTop).clamp(0.0, 1.0)
            : ((height - 1 - y) / (height - 1 - apertureBottom)).clamp(
                0.0,
                1.0,
              );
        final radialFade = horizontalFade * verticalFade;
        final eased = radialFade * radialFade * (3 - 2 * radialFade);
        alpha = math.pow(eased, 1.35).toDouble();
        // Let the spill dissolve into the app background within roughly
        // 40–80 source pixels, controlled by the user's spread setting.
        final distanceFade = math
            .pow((1 - signedDistance / glowFadeDistance).clamp(0.0, 1.0), 1.5)
            .toDouble();
        alpha = math.min(alpha, distanceFade);
      }
      write(x, y, color, alpha);
    }
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
    rowBytes: width * 4,
  );
  return completer.future;
}
