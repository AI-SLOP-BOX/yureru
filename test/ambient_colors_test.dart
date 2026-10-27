import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/playback/ambient_colors.dart';

int _red(Color color) => (color.r * 255).round();
int _green(Color color) => (color.g * 255).round();
int _blue(Color color) => (color.b * 255).round();

void main() {
  test(
    'samples a smooth horizontal color progression below black letterbox',
    () {
      const width = 90;
      const height = 100;
      final pixels = Uint8List(width * height * 4);
      for (var y = 12; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final offset = (y * width + x) * 4;
          pixels[offset] = x * 2;
          pixels[offset + 1] = 80;
          pixels[offset + 2] = 180;
          pixels[offset + 3] = 255;
        }
      }

      final colors = sampleAmbientZones(pixels, width, height);

      expect(colors, hasLength(ambientZoneCount));
      expect(_red(colors.first), greaterThan(0));
      expect(_red(colors.last), greaterThan(_red(colors.first)));
      for (var i = 1; i < colors.length; i++) {
        expect(_red(colors[i]), greaterThanOrEqualTo(_red(colors[i - 1])));
      }
    },
  );

  test('returns a stable dark gradient for a fully black frame', () {
    final colors = sampleAmbientZones(Uint8List(32 * 24 * 4), 32, 24);

    expect(colors, hasLength(ambientZoneCount));
    expect(
      colors.every((color) => _red(color) == 0 && _green(color) == 0),
      isTrue,
    );
  });

  test('samples color changes on all four edges', () {
    const width = 90;
    const height = 90;
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        if (y < 8) {
          pixels[offset] = 230;
        } else if (y >= height - 8) {
          pixels[offset + 2] = 230;
        } else if (x < 8) {
          pixels[offset + 1] = 230;
        } else if (x >= width - 8) {
          pixels[offset] = 230;
          pixels[offset + 1] = 180;
        } else {
          pixels[offset] = 30;
          pixels[offset + 1] = 30;
          pixels[offset + 2] = 30;
        }
        pixels[offset + 3] = 255;
      }
    }

    final edges = sampleAmbientEdges(pixels, width, height);
    expect(_red(edges.top.first), greaterThan(_red(edges.bottom.first)));
    expect(_blue(edges.bottom.first), greaterThan(_blue(edges.top.first)));
    final sideSample = ambientEdgeSampleCount ~/ 2;
    expect(
      _green(edges.left[sideSample]),
      greaterThan(_green(edges.right[sideSample])),
    );
    expect(
      _red(edges.right[sideSample]),
      greaterThan(_red(edges.left[sideSample])),
    );
  });

  test('diffuses a diagonal edge into a smooth ambient field', () async {
    const width = 240;
    const height = 160;
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // A hard diagonal boundary at the source edge should become a soft
        // light transition outside the player, not a long stretched copy.
        final boundaryY = 30 + x * 0.5;
        final isSky = y < boundaryY;
        final i = (y * width + x) * 4;
        pixels[i] = isSky ? 110 : 8;
        pixels[i + 1] = isSky ? 150 : 18;
        pixels[i + 2] = isSky ? 170 : 32;
        pixels[i + 3] = 255;
      }
    }

    final edges = sampleAmbientEdges(pixels, width, height);
    final image = await renderAmbientGlow(
      edges,
      aperture: const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = bytes!;
    // The two nearby output points should remain part of a visible, gradual
    // light field rather than a sharply copied diagonal.
    int redAt(int x, int y) => rgba.getUint8((y * 320 + x) * 4);
    final upper = redAt(240, 171);
    final lower = redAt(220, 178);
    expect(upper, greaterThan(0));
    expect(lower, greaterThan(0));
    expect((lower - upper).abs(), lessThan(100));
    image.dispose();
  });

  test(
    'extends side colors without shifting their vertical position',
    () async {
      const width = 80;
      const height = 80;
      final pixels = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final offset = (y * width + x) * 4;
          pixels[offset] = 24 + y * 2;
          pixels[offset + 1] = 40;
          pixels[offset + 2] = 72;
          pixels[offset + 3] = 255;
        }
      }
      final edges = sampleAmbientEdges(pixels, width, height);
      final image = await renderAmbientGlow(
        edges,
        aperture: const ui.Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final near = bytes!.getUint8((90 * 320 + 260) * 4);
      final far = bytes.getUint8((90 * 320 + 300) * 4);
      expect((near - far).abs(), lessThan(3));
      image.dispose();
    },
  );

  test('samples raw padded BGRA frames without swapping color channels', () {
    const width = 64;
    const height = 32;
    const rowBytes = width * 4 + 8;
    final pixels = Uint8List(rowBytes * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = y * rowBytes + x * 4;
        pixels[offset] = 12; // blue
        pixels[offset + 1] = 80; // green
        pixels[offset + 2] = x * 3; // red
        pixels[offset + 3] = 255;
      }
    }

    final edges = sampleAmbientEdges(
      pixels,
      width,
      height,
      rowBytes: rowBytes,
      bgra: true,
    );

    expect(_red(edges.top.last), greaterThan(_red(edges.top.first)));
    expect(_blue(edges.top.first), 12);
  });

  test('smooths frame-to-frame color changes without losing edge layout', () {
    final black = List<Color>.filled(ambientZoneCount, const Color(0xFF000000));
    final red = List<Color>.filled(ambientZoneCount, const Color(0xFFFF0000));
    final blended = blendAmbientEdges(
      AmbientEdgeColors(top: black, bottom: black, left: black, right: black),
      AmbientEdgeColors(top: red, bottom: red, left: red, right: red),
      response: 0.5,
    );
    expect(_red(blended.top.first), closeTo(128, 1));
    expect(_red(blended.bottom.first), closeTo(128, 1));
  });

  test('ignores small sampling noise but snaps immediately on scene cuts', () {
    final base = List<Color>.filled(ambientZoneCount, const Color(0xFF202020));
    final noisy = List<Color>.filled(ambientZoneCount, const Color(0xFF212121));
    final cut = List<Color>.filled(ambientZoneCount, const Color(0xFFCCCCCC));
    final previous = AmbientEdgeColors(
      top: base,
      bottom: base,
      left: base,
      right: base,
    );
    final smallChange = AmbientEdgeColors(
      top: noisy,
      bottom: noisy,
      left: noisy,
      right: noisy,
    );
    final sceneCut = AmbientEdgeColors(
      top: cut,
      bottom: cut,
      left: cut,
      right: cut,
    );

    expect(updateAmbientEdges(previous, smallChange), same(previous));
    expect(updateAmbientEdges(previous, sceneCut), same(sceneCut));
  });

  test(
    'fills the room with edge colors continuously around the video',
    () async {
      final red = List<Color>.filled(ambientZoneCount, const Color(0xFFFF0000));
      final green = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFF00FF00),
      );
      final blue = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFF0000FF),
      );
      final yellow = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFFFFFF00),
      );
      final frame = await renderAmbientGlow(
        AmbientEdgeColors(top: red, bottom: blue, left: green, right: yellow),
      );
      final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(pixels, isNotNull);
      final topCenter = (20 * 320 + 160) * 4;
      expect(pixels!.getUint8(topCenter + 3), greaterThan(0));
      expect(pixels.getUint8(topCenter), greaterThan(30));
      final topOutside = (160 * 4) + 3;
      final topNearVideo = (45 * 320 + 160) * 4 + 3;
      expect(pixels.getUint8(topOutside), greaterThan(50));
      expect(pixels.getUint8(topNearVideo), greaterThan(70));
      final topMidway = (14 * 320 + 160) * 4 + 3;
      expect(
        pixels.getUint8(topMidway),
        lessThan(pixels.getUint8(topNearVideo)),
      );
      expect(pixels.getUint8(topMidway), greaterThan(0));
      final innerVideo = (90 * 320 + 160) * 4 + 3;
      expect(pixels.getUint8(innerVideo), 0);
      expect(pixels.getUint8((90 * 320 + 0) * 4 + 3), greaterThan(50));
      expect(pixels.getUint8((0 * 320 + 160) * 4 + 3), greaterThan(50));
      final bottomRim = (138 * 320 + 160) * 4 + 3;
      final leftRim = (90 * 320 + 90) * 4 + 3;
      final rightRim = (90 * 320 + 230) * 4 + 3;
      expect(pixels.getUint8(bottomRim), greaterThan(70));
      expect(pixels.getUint8(leftRim), 0);
      expect(pixels.getUint8(rightRim), greaterThan(70));
      frame.dispose();
    },
  );

  test(
    'keeps the video edge color progression aligned outside the frame',
    () async {
      final ramp = [
        for (var i = 0; i < ambientZoneCount; i++)
          Color.fromARGB(255, i * 255 ~/ (ambientZoneCount - 1), 0, 0),
      ];
      final black = List<Color>.filled(ambientZoneCount, Colors.black);
      final frame = await renderAmbientGlow(
        AmbientEdgeColors(top: black, bottom: ramp, left: black, right: black),
      );
      final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      final leftOfRamp = (150 * 320 + 120) * 4;
      final rightOfRamp = (150 * 320 + 200) * 4;
      expect(
        pixels!.getUint8(rightOfRamp),
        greaterThan(pixels.getUint8(leftOfRamp) + 70),
      );
      frame.dispose();
    },
  );

  test('uses measured video bounds for the continuation window', () async {
    final edge = List<Color>.filled(ambientZoneCount, const Color(0xFF224466));
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(top: edge, bottom: edge, left: edge, right: edge),
      aperture: const Rect.fromLTWH(0.1, 0.15, 0.6, 0.7),
    );
    final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    final horizontal = pixels!.getUint8((90 * 320 + 226) * 4 + 3);
    final vertical = pixels.getUint8((154 * 320 + 160) * 4 + 3);
    expect((horizontal - vertical).abs(), lessThan(25));
    final edgeColor = (90 * 320 + 226) * 4;
    expect(pixels.getUint8(edgeColor), 0x22);
    expect(pixels.getUint8(edgeColor + 1), 0x44);
    expect(pixels.getUint8(edgeColor + 2), 0x66);
    frame.dispose();
  });

  test('keeps the ambient field continuous at the video top edge', () async {
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(
        top: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFFEFEFEF),
        ),
        bottom: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFF222222),
        ),
        left: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFF777777),
        ),
        right: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFF888888),
        ),
      ),
      aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
    );
    final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    final outside = (44 * 320 + 160) * 4;
    final inside = (45 * 320 + 160) * 4;
    for (var channel = 0; channel < 3; channel++) {
      expect(
        (pixels!.getUint8(outside + channel) -
                pixels.getUint8(inside + channel))
            .abs(),
        lessThan(20),
      );
    }
    frame.dispose();
  });

  test('upper room glow converges toward the lower edge color', () async {
    final top = List<Color>.filled(ambientZoneCount, const Color(0xFFC04040));
    final bottom = List<Color>.filled(
      ambientZoneCount,
      const Color(0xFF2070D0),
    );
    final side = List<Color>.filled(ambientZoneCount, const Color(0xFF305060));
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(top: top, bottom: bottom, left: side, right: side),
      aperture: const Rect.fromLTWH(0.2, 0.3, 0.6, 0.4),
    );
    final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    List<int> rgbAt(int x, int y) {
      final i = (y * 320 + x) * 4;
      final alpha = pixels!.getUint8(i + 3).clamp(1, 255);
      return [
        for (var channel = 0; channel < 3; channel++)
          (pixels.getUint8(i + channel) * 255 / alpha).round().clamp(0, 255),
      ];
    }

    final upper = rgbAt(160, 20);
    final lower = rgbAt(160, 160);
    final originalTopDistance =
        (upper[0] - 192).abs() + (upper[1] - 64).abs() + (upper[2] - 64).abs();
    final lowerDistance =
        (upper[0] - lower[0]).abs() +
        (upper[1] - lower[1]).abs() +
        (upper[2] - lower[2]).abs();
    expect(lowerDistance, lessThan(originalTopDistance));
    frame.dispose();
  });

  test(
    'blends the top corner into the side spill without a scanline seam',
    () async {
      final red = List<Color>.filled(ambientZoneCount, const Color(0xFFFF0000));
      final green = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFF00FF00),
      );
      final blue = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFF0000FF),
      );
      final yellow = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFFFFFF00),
      );
      final frame = await renderAmbientGlow(
        AmbientEdgeColors(top: red, bottom: blue, left: green, right: yellow),
        aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
      );
      final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      int channelAt(int y, int channel) =>
          rgba!.getUint8((y * 320 + 79) * 4 + channel);
      expect(channelAt(43, 1), greaterThan(channelAt(43, 0)));
      expect((channelAt(43, 1) - channelAt(44, 1)).abs(), lessThan(80));
      frame.dispose();
    },
  );

  test('ambient aperture follows the rounded player corner exactly', () async {
    final edge = List<Color>.filled(ambientZoneCount, const Color(0xFF406080));
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(top: edge, bottom: edge, left: edge, right: edge),
      aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
    );
    final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    int alphaAt(int x, int y) => rgba!.getUint8((y * 320 + x) * 4 + 3);

    // (80,45) lies outside the rounded contour but inside the bounding box;
    // (81,46) lies inside the rounded picture and must remain transparent.
    expect(alphaAt(80, 45), greaterThan(0));
    expect(alphaAt(81, 46), 0);
    frame.dispose();
  });

  test(
    'ambient opacity fades as the spill moves away from the video',
    () async {
      final edge = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFF80A0C0),
      );
      final frame = await renderAmbientGlow(
        AmbientEdgeColors(top: edge, bottom: edge, left: edge, right: edge),
        aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
      );
      final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      int alphaAt(int y) => rgba!.getUint8((y * 320 + 160) * 4 + 3);

      expect(alphaAt(34), greaterThan(alphaAt(15)));
      expect(alphaAt(15), greaterThan(0));
      frame.dispose();
    },
  );

  test(
    'projects corner light along a rounded boundary without a diagonal seam',
    () async {
      final red = List<Color>.filled(ambientZoneCount, const Color(0xFFFF0000));
      final green = List<Color>.filled(
        ambientZoneCount,
        const Color(0xFF00FF00),
      );
      final black = List<Color>.filled(ambientZoneCount, Colors.black);
      final frame = await renderAmbientGlow(
        AmbientEdgeColors(top: red, bottom: black, left: green, right: black),
        aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
      );
      final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      int redAt(int x, int y) => rgba!.getUint8((y * 320 + x) * 4);
      int greenAt(int x, int y) => rgba!.getUint8((y * 320 + x) * 4 + 1);

      // Walk from the top tangent, through the rounded corner, to the left
      // tangent. The source should turn from top red to side green gradually.
      final topTangent = (redAt(84, 42), greenAt(84, 42));
      final diagonal = (redAt(78, 44), greenAt(78, 44));
      final sideTangent = (redAt(79, 43), greenAt(79, 43));
      expect(topTangent.$1, greaterThan(topTangent.$2));
      expect(diagonal.$1, greaterThan(0));
      expect(diagonal.$2, greaterThan(0));
      expect(sideTangent.$2, greaterThan(diagonal.$2));
      expect((diagonal.$1 - topTangent.$1).abs(), lessThan(150));
      expect((sideTangent.$2 - diagonal.$2).abs(), lessThan(150));
      frame.dispose();
    },
  );

  test('keeps side colors continuous where the top edge ends', () async {
    final top = List<Color>.filled(ambientZoneCount, Colors.black);
    final side = [
      for (var i = 0; i < ambientZoneCount; i++)
        Color.fromARGB(255, 0, i * 255 ~/ (ambientZoneCount - 1), 0),
    ];
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(top: top, bottom: top, left: side, right: side),
      aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
    );
    final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    int greenAt(int y) => rgba!.getUint8((y * 320 + 40) * 4 + 1);
    expect((greenAt(44) - greenAt(45)).abs(), lessThan(20));
    frame.dispose();
  });

  test('softens color streaks progressively farther from the video', () async {
    final edge = [
      for (var i = 0; i < ambientZoneCount; i++)
        Color.fromARGB(
          255,
          (128 + 110 * math.sin(i / (ambientZoneCount - 1) * math.pi * 2))
              .round(),
          90,
          170,
        ),
    ];
    final black = List<Color>.filled(ambientZoneCount, Colors.black);
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(top: edge, bottom: black, left: black, right: black),
      aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
    );
    final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    double redRangeAt(int y) {
      final reds = [
        for (var x = 82; x < 238; x++) rgba!.getUint8((y * 320 + x) * 4),
      ];
      return (reds.reduce(math.max) - reds.reduce(math.min)).toDouble();
    }

    expect(redRangeAt(0), lessThan(redRangeAt(44)));
    expect(redRangeAt(0), greaterThan(16));
    frame.dispose();
  });

  test('rolls off white edge highlights in the ambient spill', () async {
    final white = List<Color>.filled(ambientZoneCount, Colors.white);
    final black = List<Color>.filled(ambientZoneCount, Colors.black);
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(top: white, bottom: black, left: black, right: black),
    );
    final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    final edge = (20 * 320 + 160) * 4;
    expect(rgba!.getUint8(edge), lessThan(240));
    expect(rgba.getUint8(edge + 1), lessThan(240));
    expect(rgba.getUint8(edge + 2), lessThan(240));
    frame.dispose();
  });

  test(
    'anchors the glow to the active picture inside letterboxed video',
    () async {
      const width = 120;
      const height = 100;
      final pixels = Uint8List(width * height * 4);
      for (var y = 20; y < 80; y++) {
        for (var x = 0; x < width; x++) {
          final offset = (y * width + x) * 4;
          pixels[offset] = 90;
          pixels[offset + 1] = 150;
          pixels[offset + 2] = 190;
          pixels[offset + 3] = 255;
        }
      }

      final edges = sampleAmbientEdges(pixels, width, height);
      expect(edges.contentRect.top, closeTo(0.2, 0.02));
      expect(edges.contentRect.bottom, closeTo(0.8, 0.02));
      final frame = await renderAmbientGlow(
        edges,
        aperture: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
      );
      final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      int alphaAt(int y) => rgba!.getUint8((y * 320 + 160) * 4 + 3);
      // The spill reaches the window edge so the underlying black app surface
      // does not create a dark rim. The video and its letterbox remain clear.
      expect(alphaAt(0), greaterThan(50));
      expect(alphaAt(24), greaterThan(0));
      expect(alphaAt(48), 0);
      frame.dispose();
    },
  );

  test('treats stable white and transparent edge mattes as empty space', () {
    const width = 120;
    const height = 100;

    for (final alpha in [255, 0]) {
      final pixels = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final offset = (y * width + x) * 4;
          final matte = y < 20 || y >= 80;
          pixels[offset] = matte ? 255 : 50;
          pixels[offset + 1] = matte ? 255 : 130;
          pixels[offset + 2] = matte ? 255 : 190;
          pixels[offset + 3] = matte ? (alpha == 0 ? 0 : 255) : 255;
        }
      }

      final edges = sampleAmbientEdges(pixels, width, height);
      expect(edges.contentRect.top, closeTo(0.2, 0.02));
      expect(edges.contentRect.bottom, closeTo(0.8, 0.02));
      expect(_red(edges.top.first), lessThan(80));
      expect(_blue(edges.bottom.first), greaterThan(150));
    }
  });

  test('does not classify dark picture edges as black letterbox bars', () {
    const width = 120;
    const height = 100;
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final darkSceneEdge = y < 20 || y >= 80;
        pixels[offset] = darkSceneEdge ? 12 : 36;
        pixels[offset + 1] = darkSceneEdge ? 14 : 72;
        pixels[offset + 2] = darkSceneEdge ? 16 : 108;
        pixels[offset + 3] = 255;
      }
    }

    final edges = sampleAmbientEdges(pixels, width, height);
    expect(edges.contentRect, const Rect.fromLTWH(0, 0, 1, 1));
    expect(edges.matteMask!.every((pixel) => pixel == 0), isTrue);
  });

  test('keeps subtitle pixels clear while replacing a black letterbox', () {
    const width = 120;
    const height = 100;
    final pixels = Uint8List(width * height * 4);
    for (var y = 20; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final subtitle = y >= 84 && y < 90 && x >= 54 && x < 66;
        if (y < 80) {
          pixels[offset] = 60;
          pixels[offset + 1] = 120;
          pixels[offset + 2] = 180;
        } else if (subtitle) {
          pixels[offset] = 255;
          pixels[offset + 1] = 255;
          pixels[offset + 2] = 255;
        }
        pixels[offset + 3] = 255;
      }
    }

    final edges = sampleAmbientEdges(pixels, width, height);
    final mask = edges.matteMask!;
    int alphaAt(int x, int y) => mask[y * 320 + x];
    expect(alphaAt(150, 155), 0); // White subtitle remains untouched.
    expect(alphaAt(130, 155), 255); // Black background is replaced by glow.
  });

  test(
    'renders edge mattes as an ambient overlay with a clear picture hole',
    () async {
      final edges = AmbientEdgeColors(
        top: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFF7890A0),
        ),
        bottom: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFF304050),
        ),
        left: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFF506070),
        ),
        right: List<Color>.filled(
          ambientEdgeSampleCount,
          const Color(0xFF607080),
        ),
        contentRect: const Rect.fromLTRB(0, 0.2, 1, 0.8),
      );
      final matte = await renderAmbientGlow(
        edges,
        aperture: const Rect.fromLTWH(0, 0, 1, 1),
        matteOnly: true,
      );
      final bytes = await matte.toByteData(format: ui.ImageByteFormat.rawRgba);
      int alphaAt(int y) => bytes!.getUint8((y * 320 + 160) * 4 + 3);
      expect(alphaAt(90), 0);
      expect(alphaAt(20), 255);
      expect(alphaAt(160), 255);
      matte.dispose();
    },
  );

  test('preserves the original dark bottom-edge colors', () async {
    final darkBlue = List<Color>.filled(
      ambientZoneCount,
      const Color(0xFF000040),
    );
    final black = List<Color>.filled(ambientZoneCount, Colors.black);
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(
        top: black,
        bottom: darkBlue,
        left: black,
        right: black,
      ),
    );
    final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    final nearBottom = (127 * 320 + 160) * 4;
    expect(pixels!.getUint8(nearBottom + 2), greaterThan(20));
    expect(pixels.getUint8(nearBottom + 3), 0);
    frame.dispose();
  });

  test('lifts black silhouettes out of the ambient spill', () async {
    final bottom = List<Color>.filled(
      ambientZoneCount,
      const Color(0xFF3A7890),
    );
    for (var i = 12; i <= 19; i++) {
      bottom[i] = Colors.black;
    }
    final frame = await renderAmbientGlow(
      AmbientEdgeColors(
        top: List<Color>.filled(ambientZoneCount, const Color(0xFF78B6D0)),
        bottom: bottom,
        left: List<Color>.filled(ambientZoneCount, const Color(0xFF3A7890)),
        right: List<Color>.filled(ambientZoneCount, const Color(0xFF3A7890)),
      ),
      aperture: const Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
    );
    final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    final edgePixel = (145 * 320 + 160) * 4;
    final brightness =
        pixels!.getUint8(edgePixel) +
        pixels.getUint8(edgePixel + 1) +
        pixels.getUint8(edgePixel + 2);
    expect(brightness, greaterThan(30));
    frame.dispose();
  });

  test(
    'ambient spread changes how far edge colors continue into the room',
    () async {
      final edge = [
        for (var i = 0; i < ambientZoneCount; i++)
          Color.fromARGB(255, i * 255 ~/ (ambientZoneCount - 1), 60, 140),
      ];
      final edges = AmbientEdgeColors(
        top: edge,
        bottom: edge,
        left: edge,
        right: edge,
      );
      final narrow = await renderAmbientGlow(
        edges,
        aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
        spread: 0.5,
      );
      final wide = await renderAmbientGlow(
        edges,
        aperture: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
        spread: 1.5,
      );
      final narrowBytes = await narrow.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final wideBytes = await wide.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final distantPixel = (0 * 320 + 80) * 4;
      expect(
        (wideBytes!.getUint8(distantPixel) -
                narrowBytes!.getUint8(distantPixel))
            .abs(),
        greaterThan(0),
      );
      narrow.dispose();
      wide.dispose();
    },
  );
}
