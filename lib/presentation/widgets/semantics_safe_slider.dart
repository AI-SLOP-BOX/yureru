import 'package:flutter/material.dart';

/// Keeps a Material Slider's overlay semantics attached to its own subtree.
///
/// Flutter 3.47 has an accessibility-bridge bug where a Slider on a pushed
/// route can emit an orphan semantics node. The small overlay prevents the
/// Slider's portal child from being reparented outside its semantics subtree.
Widget semanticsSafeSlider(Widget slider) =>
    Overlay.wrap(clipBehavior: Clip.none, child: slider);
