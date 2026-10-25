/// v6.5 APPLE-STYLE POI CHIPS («отрисовка poi — совершенно другой стиль»).
///
/// The Apple-Maps-like cartographies (Atlas / Onyx, see apple_docs.dart)
/// render every point of interest as a COLORED CHIP — a soft circular
/// badge with a category glyph — exactly like Apple Maps does:
///   • light theme:  white/cream chip + saturated colored glyph;
///   • dark theme:   charcoal chip + muted colored glyph.
///
/// The chips are drawn on a Flutter canvas at style-load time and
/// registered with MapLibre via addImage() (no PNG assets, no sprite
/// sheet, no network). The style documents reference them through the
/// `icon-image` match expressions baked into apple_docs.dart
/// (names: a-food, a-cafe, a-bar, a-shop, a-health, …).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'sprites.dart';
import 'style_pack.dart';

/// Bitmap size of one chip.
///
/// MapLibre sizes a symbol as `image_px × icon-size`, so this canvas and the
/// docs' `icon-size` are two halves of one decision: the product sets the
/// on-screen size (and with it the collision box), the canvas only sets how
/// sharp that size is painted. v6.9.0: 192 × 0.30 ≈ 57.6 css px ≈ 158 device
/// px on a ×2.75 screen — still a slight downscale of the bitmap, which a
/// 144 px canvas could not have reached. Every dimension inside [_renderChip]
/// is relative to this constant, so it changes resolution, never layout.
const double kChipSrc = 192;

Clr _clrOf(Color c) {
  final v = c.toARGB32();
  return Clr(
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
    ((v >> 24) & 0xFF) / 255,
  );
}

Color _colorOf(Clr c) =>
    Color.fromARGB(((c.a * 255).round()).clamp(0, 255), c.r, c.g, c.b);

// ── Category palette (Apple-like) ─────────────────────────────────────────
const Color _kOrange = Color(0xFFF28322);
const Color _kPink = Color(0xFFE0517E);
const Color _kRed = Color(0xFFE2484F);
const Color _kBlue = Color(0xFF4C84E0);
const Color _kGray = Color(0xFF8E97A3);
const Color _kTeal = Color(0xFF1FBFD8);
const Color _kBrown = Color(0xFF8A6F5C);
const Color _kGreen = Color(0xFF3FAE54);
const Color _kPurple = Color(0xFFA06BE8);

const Color _kOrangeD = Color(0xFFF6883C);
const Color _kPinkD = Color(0xFFE180C5);
const Color _kRedD = Color(0xFFF3757C);
const Color _kBlueD = Color(0xFF65A1FD);
const Color _kGrayD = Color(0xFF9BA7B5);
const Color _kTealD = Color(0xFF16B7D3);
const Color _kBrownD = Color(0xFFB09A88);
const Color _kGreenD = Color(0xFF3BB183);
const Color _kPurpleD = Color(0xFFA992FE);

class _ChipSpec {
  const _ChipSpec(this.name, this.glyph, this.light, this.dark);
  final String name;
  final Path Function() glyph;
  final Color light; // glyph color on the white chip
  final Color dark; // glyph color on the charcoal chip
}

const List<_ChipSpec> _kChips = [
  _ChipSpec('a-food', poiGlyphFood, _kOrange, _kOrangeD),
  _ChipSpec('a-cafe', poiGlyphCafe, _kOrange, _kOrangeD),
  _ChipSpec('a-bar', _gBar, _kOrange, _kOrangeD),
  _ChipSpec('a-shop', poiGlyphShop, _kPink, _kPinkD),
  _ChipSpec('a-health', poiGlyphHealth, _kRed, _kRedD),
  _ChipSpec('a-bank', poiGlyphMoney, _kGray, _kGrayD),
  _ChipSpec('a-post', _gPost, _kGray, _kGrayD),
  _ChipSpec('a-civic', _gCivic, _kBlue, _kBlueD),
  _ChipSpec('a-office', poiGlyphWork, _kGray, _kGrayD),
  _ChipSpec('a-school', _gSchool, _kBlue, _kBlueD),
  _ChipSpec('a-book', _gBook, _kBlue, _kBlueD),
  _ChipSpec('a-star', poiGlyphStar, _kPurple, _kPurpleD),
  _ChipSpec('a-hotel', poiGlyphHotel, _kTeal, _kTealD),
  _ChipSpec('a-parking', poiGlyphParking, _kBlue, _kBlueD),
  _ChipSpec('a-fuel', poiGlyphFuel, _kGray, _kGrayD),
  _ChipSpec('a-worship', _gWorship, _kBrown, _kBrownD),
  _ChipSpec('a-sport', _gSport, _kGreen, _kGreenD),
  _ChipSpec('a-camp', _gCamp, _kGreen, _kGreenD),
  _ChipSpec('a-info', _gInfo, _kGray, _kGrayD),
  _ChipSpec('a-bus', poiGlyphBus, _kBlue, _kBlueD),
  _ChipSpec('a-train', _gTrain, _kBlue, _kBlueD),
  _ChipSpec('a-plane', _gPlane, _kBlue, _kBlueD),
  _ChipSpec('a-ferry', _gFerry, _kBlue, _kBlueD),
  _ChipSpec('a-park', _gTree, _kGreen, _kGreenD),
  _ChipSpec('a-poi', _gPoi, _kGray, _kGrayD),
];

// ── Extra glyphs (24×24 design box) that sprites.dart does not have ───────

Path _gBar() => Path()
  ..moveTo(7, 2)
  ..lineTo(17, 2)
  ..cubicTo(17, 7.4, 15, 10.4, 13, 11.2)
  ..lineTo(13, 20)
  ..lineTo(16, 20)
  ..lineTo(16, 22)
  ..lineTo(8, 22)
  ..lineTo(8, 20)
  ..lineTo(11, 20)
  ..lineTo(11, 11.2)
  ..cubicTo(9, 10.4, 7, 7.4, 7, 2)
  ..close()
  ..moveTo(9.3, 4)
  ..cubicTo(9.5, 6.8, 10.6, 8.6, 12, 9.2)
  ..cubicTo(13.4, 8.6, 14.5, 6.8, 14.7, 4)
  ..close();

Path _gPost() => Path()
  ..fillType = PathFillType.evenOdd
  ..moveTo(3, 5)
  ..lineTo(21, 5)
  ..lineTo(21, 19)
  ..lineTo(3, 19)
  ..close()
  ..moveTo(5.1, 7)
  ..lineTo(12, 12.4)
  ..lineTo(18.9, 7)
  ..close();

Path _gCivic() => Path()
  ..moveTo(12, 2)
  ..lineTo(14, 4.5)
  ..lineTo(10, 4.5)
  ..close()
  ..moveTo(11.2, 5.5)
  ..lineTo(12.8, 5.5)
  ..lineTo(12.8, 8)
  ..lineTo(11.2, 8)
  ..close()
  ..moveTo(5, 9)
  ..lineTo(19, 9)
  ..lineTo(19, 21)
  ..lineTo(14.5, 21)
  ..lineTo(14.5, 15)
  ..lineTo(9.5, 15)
  ..lineTo(9.5, 21)
  ..lineTo(5, 21)
  ..close();

Path _gSchool() => Path()
  ..moveTo(12, 3)
  ..lineTo(22.5, 8)
  ..lineTo(12, 13)
  ..lineTo(1.5, 8)
  ..close()
  ..moveTo(6, 10.6)
  ..lineTo(6, 15)
  ..cubicTo(6, 16.8, 8.7, 18.2, 12, 18.2)
  ..cubicTo(15.3, 18.2, 18, 16.8, 18, 15)
  ..lineTo(18, 10.6)
  ..lineTo(12, 13.5)
  ..close()
  ..moveTo(20.6, 9.4)
  ..lineTo(21.6, 9.9)
  ..lineTo(21.6, 15.4)
  ..lineTo(20.6, 15.4)
  ..close();

Path _gBook() => Path()
  ..moveTo(12, 5.2)
  ..cubicTo(10, 3.7, 7.2, 3, 4, 3)
  ..lineTo(3, 3)
  ..lineTo(3, 19)
  ..lineTo(4, 19)
  ..cubicTo(7.2, 19, 10, 19.7, 12, 21.2)
  ..cubicTo(14, 19.7, 16.8, 19, 20, 19)
  ..lineTo(21, 19)
  ..lineTo(21, 3)
  ..lineTo(20, 3)
  ..cubicTo(16.8, 3, 14, 3.7, 12, 5.2)
  ..close()
  ..moveTo(12, 7.2)
  ..cubicTo(13.6, 6.2, 15.6, 5.6, 19, 5.1)
  ..lineTo(19, 16.9)
  ..cubicTo(16, 17.2, 13.7, 17.9, 12, 19)
  ..close();

Path _gWorship() => Path()
  // cross
  ..moveTo(11, 1.5)
  ..lineTo(13, 1.5)
  ..lineTo(13, 4.5)
  ..lineTo(15.5, 4.5)
  ..lineTo(15.5, 6.5)
  ..lineTo(13, 6.5)
  ..lineTo(13, 9)
  ..lineTo(11, 9)
  ..lineTo(11, 6.5)
  ..lineTo(8.5, 6.5)
  ..lineTo(8.5, 4.5)
  ..lineTo(11, 4.5)
  ..close()
  // chapel body
  ..moveTo(12, 10.5)
  ..lineTo(18, 14.6)
  ..lineTo(18, 21)
  ..lineTo(6, 21)
  ..lineTo(6, 14.6)
  ..close();

Path _gSport() => Path()
  // trophy: cup + handles + stem + base (emoji_events silhouette)
  ..moveTo(7, 3)
  ..lineTo(17, 3)
  ..lineTo(17, 4.6)
  ..lineTo(20, 4.6)
  ..lineTo(20, 7.6)
  ..cubicTo(20, 9.9, 18.3, 11.8, 16.1, 12.3)
  ..cubicTo(15.6, 13.4, 14.7, 14.3, 13, 14.8)
  ..lineTo(13, 17)
  ..lineTo(16, 17)
  ..lineTo(16, 20)
  ..lineTo(8, 20)
  ..lineTo(8, 17)
  ..lineTo(11, 17)
  ..lineTo(11, 14.8)
  ..cubicTo(9.3, 14.3, 8.4, 13.4, 7.9, 12.3)
  ..cubicTo(5.7, 11.8, 4, 9.9, 4, 7.6)
  ..lineTo(4, 4.6)
  ..lineTo(7, 4.6)
  ..close()
  ..moveTo(7, 6.6)
  ..lineTo(6, 6.6)
  ..lineTo(6, 7.6)
  ..cubicTo(6, 8.7, 6.7, 9.7, 7.7, 10.1)
  ..cubicTo(7.3, 9.1, 7, 7.9, 7, 6.6)
  ..close()
  ..moveTo(17, 6.6)
  ..cubicTo(17, 7.9, 16.7, 9.1, 16.3, 10.1)
  ..cubicTo(17.3, 9.7, 18, 8.7, 18, 7.6)
  ..lineTo(18, 6.6)
  ..close();

Path _gCamp() => Path()
  ..moveTo(12, 3)
  ..lineTo(22, 20.5)
  ..lineTo(13.4, 20.5)
  ..lineTo(12, 16.5)
  ..lineTo(10.6, 20.5)
  ..lineTo(2, 20.5)
  ..close();

Path _gInfo() => Path()
  ..addOval(Rect.fromCircle(center: Offset(12, 5.4), radius: 1.9))
  ..moveTo(10.4, 9.5)
  ..lineTo(13.6, 9.5)
  ..lineTo(13.6, 19)
  ..lineTo(10.4, 19)
  ..close();

Path _gTrain() => Path()
  ..fillType = PathFillType.evenOdd
  ..moveTo(6, 2)
  ..lineTo(18, 2)
  ..cubicTo(19.7, 2, 21, 3.3, 21, 5)
  ..lineTo(21, 15)
  ..cubicTo(21, 16.7, 19.7, 18, 18, 18)
  ..lineTo(6, 18)
  ..cubicTo(4.3, 18, 3, 16.7, 3, 15)
  ..lineTo(3, 5)
  ..cubicTo(3, 3.3, 4.3, 2, 6, 2)
  ..close()
  ..moveTo(5.5, 4.6)
  ..lineTo(5.5, 10.4)
  ..lineTo(18.5, 10.4)
  ..lineTo(18.5, 4.6)
  ..close()
  ..moveTo(5.6, 19.4)
  ..lineTo(3.4, 22.6)
  ..lineTo(5.6, 22.6)
  ..lineTo(7.8, 19.4)
  ..close()
  ..moveTo(16.2, 19.4)
  ..lineTo(18.4, 22.6)
  ..lineTo(20.6, 22.6)
  ..lineTo(18.4, 19.4)
  ..close();

Path _gPlane() => Path()
  ..moveTo(21.5, 15.5)
  ..lineTo(13.5, 11)
  ..lineTo(13.5, 3.5)
  ..cubicTo(13.5, 2.67, 12.83, 2, 12, 2)
  ..cubicTo(11.17, 2, 10.5, 2.67, 10.5, 3.5)
  ..lineTo(10.5, 11)
  ..lineTo(2.5, 15.5)
  ..lineTo(2.5, 17.5)
  ..lineTo(10.5, 15)
  ..lineTo(10.5, 20.5)
  ..lineTo(8.5, 22)
  ..lineTo(8.5, 23.5)
  ..lineTo(12, 22.5)
  ..lineTo(15.5, 23.5)
  ..lineTo(15.5, 22)
  ..lineTo(13.5, 20.5)
  ..lineTo(13.5, 15)
  ..lineTo(21.5, 17.5)
  ..close();

Path _gFerry() => Path()
  ..addOval(Rect.fromCircle(center: Offset(12, 5), radius: 2.6))
  ..moveTo(11, 9)
  ..lineTo(13, 9)
  ..lineTo(13, 19.4)
  ..lineTo(11, 19.4)
  ..close()
  ..moveTo(6, 12)
  ..lineTo(9, 12)
  ..lineTo(9, 14)
  ..lineTo(6, 14)
  ..close()
  ..moveTo(15, 12)
  ..lineTo(18, 12)
  ..lineTo(18, 14)
  ..lineTo(15, 14)
  ..close()
  ..moveTo(4.6, 17.2)
  ..cubicTo(5.6, 20.4, 8.4, 22.4, 12, 22.4)
  ..cubicTo(15.6, 22.4, 18.4, 20.4, 19.4, 17.2);

Path _gTree() => Path()
  ..moveTo(12, 2)
  ..lineTo(17.6, 10)
  ..lineTo(15.2, 10)
  ..lineTo(19.4, 16.2)
  ..lineTo(13.1, 16.2)
  ..lineTo(13.1, 22)
  ..lineTo(10.9, 22)
  ..lineTo(10.9, 16.2)
  ..lineTo(4.6, 16.2)
  ..lineTo(8.8, 10)
  ..lineTo(6.4, 10)
  ..close();

Path _gPoi() =>
    Path()..addOval(Rect.fromCircle(center: Offset(12, 12), radius: 5.4));

// ── Rendering ─────────────────────────────────────────────────────────────

final Map<String, Uint8List> _chipCache = {};

/// Draws one Apple-style chip and returns PNG bytes for addImage().
/// With a [deco] the chip is painted in the ACTIVE basemap palette (Atlas
/// family); without it the neutral white/charcoal Apple defaults are kept.
Future<Uint8List> _renderChip(
  _ChipSpec spec,
  bool dark,
  AtlasDeco? deco,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = kChipSrc;
  final center = Offset(s / 2, s / 2);
  final r = s * 0.325; // disc radius, % of canvas

  final body = deco == null
      ? (dark ? const Color(0xFF23262C) : Colors.white)
      : _colorOf(deco.chipBody);
  final ring = deco == null
      ? (dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.10))
      : _colorOf(deco.chipRing);
  final baseGlyph = dark ? spec.dark : spec.light;
  final glyphColor = deco == null
      ? baseGlyph
      : _colorOf(deco.glyphFor(_clrOf(baseGlyph)));

  // Soft drop shadow (the Apple chip "floats" above the map).
  canvas.drawCircle(
    center + Offset(0, s * 0.017),
    r,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, s * 0.0333),
  );

  // Chip body.
  canvas.drawCircle(center, r, Paint()..color = body);
  canvas.drawCircle(
    center,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.034
      ..color = ring,
  );

  // Category glyph: the 24×24 design box scaled to ~60% of the chip.
  final glyph = spec.glyph();
  final box = s * 0.50; // glyph design box, % of canvas
  final scale = box / 24;
  canvas.save();
  canvas.translate(center.dx - box / 2, center.dy - box / 2);
  canvas.scale(scale);
  canvas.drawPath(
    glyph,
    Paint()
      ..color = glyphColor
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(s.toInt(), s.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Three representative chip hues for the Settings theme previews. With a
/// [deco] they are harmonised exactly like the real chips of that basemap.
List<Color> poiChipSwatches({required bool dark, AtlasDeco? deco}) {
  final specs = [_kChips[0], _kChips[3], _kChips[5]];
  return [
    for (final s in specs)
      deco == null
          ? (dark ? s.dark : s.light)
          : _colorOf(deco.glyphFor(_clrOf(dark ? s.dark : s.light))),
  ];
}

/// Registers all 25 chips for the active Apple-style theme. Called from
/// [MapEngine.onStyleLoaded] right after the regular app sprites — every
/// addImage is isolated (one failure must not break the rest).
///
/// [deco] paints the chips in the palette of the theme the Atlas engine is
/// currently drawing; [cacheId] keys the bitmap cache per palette so
/// switching themes reuses the already-rendered chips (no re-paint stall).
/// [tag] is the basemap's own image-id namespace (see [chipTagFor]) — the
/// document registers its `icon-image` references under the same suffixed
/// names, so no theme can ever inherit another one's bitmaps.
Future<void> registerPoiChips(
  Future<void> Function(String name, Uint8List bytes) addImage,
  bool dark, {
  AtlasDeco? deco,
  String cacheId = '',
  String tag = '',
}) async {
  for (final spec in _kChips) {
    final key = '${spec.name}|$dark|$cacheId';
    try {
      final bytes = _chipCache[key] ??= await _renderChip(spec, dark, deco);
      await addImage('${spec.name}$tag', bytes);
    } catch (_) {
      // A missing chip degrades to a label-only POI — never fatal.
    }
  }
}
