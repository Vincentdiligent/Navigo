/// Sprite pipeline: crisp vector glyphs drawn on a Flutter canvas at startup
/// and registered with MapLibre via addImage(). No PNG assets.
///
/// v5.7 PREMIUM MARKERS (the user: «маркер маршрута детский и мелкий …
/// лучше сделай только стрелку без круга … маркеры сделай без кругов и
/// красивее и премиум … иконки дом или работа тоже крупнее!»):
///   • the moving marker (puck) is now a LARGE standalone glyph — NO disc,
///     NO circle: gradient body, thick white halo, soft drop shadow;
///   • route start/finish pins are big premium teardrops (52 dp wide) with
///     a soft shadow and a checkered-flag finish glyph;
///   • Home / Work / Favorites left the small circular badges for the same
///     teardrop pins with house / briefcase / star glyphs — much bigger.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// v5.7: the moving marker canvas (glyph fills ~70% — the rest is halo +
/// shadow). The pins are 72×92 teardrops (~52 dp head, tip on the point).
const int kPuckSpriteSize = 88;
const int kPinSpriteW = 72;
const int kPinSpriteH = 92;

/// Draws one sprite and returns RGBA bytes for MapLibre.
Future<ui.Image> _render(int w, int h, void Function(Canvas, Size) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas, Size(w.toDouble(), h.toDouble()));
  final picture = recorder.endRecording();
  return picture.toImage(w, h);
}

Future<Uint8List> _png(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _renderPng(
  int w,
  int h,
  void Function(Canvas, Size) draw,
) async {
  final img = await _render(w, h, draw);
  return _png(img);
}

void _path(Canvas c, Size s, Color tint, Path p, {bool stroke = false}) {
  final paint = Paint()
    ..color = tint
    ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  // Center the 24x24 design box.
  c.save();
  c.translate((s.width - 24) / 2, (s.height - 24) / 2);
  c.drawPath(p, paint);
  c.restore();
}

// ── 24×24 glyph paths (Material-style, hand-tuned) ────────────────────────
Path _gFood() => Path()
  ..moveTo(7, 2)
  ..lineTo(7, 10)
  ..cubicTo(7, 11.2, 8, 12, 9, 12)
  ..lineTo(9, 22)
  ..lineTo(11, 22)
  ..lineTo(11, 12)
  ..cubicTo(12, 12, 13, 11.2, 13, 10)
  ..lineTo(13, 2)
  ..lineTo(11.5, 2)
  ..lineTo(11.5, 8.5)
  ..lineTo(10.7, 8.5)
  ..lineTo(10.7, 2)
  ..lineTo(9.3, 2)
  ..lineTo(9.3, 8.5)
  ..lineTo(8.5, 8.5)
  ..close()
  ..moveTo(17.5, 2)
  ..cubicTo(15.8, 2, 15, 4.4, 15, 7)
  ..lineTo(15, 10)
  ..lineTo(17, 10)
  ..lineTo(17, 22)
  ..lineTo(19, 22)
  ..lineTo(19, 2)
  ..close();

Path _gCafe() => Path()
  ..moveTo(4, 4)
  ..lineTo(15, 4)
  ..lineTo(15, 12)
  ..cubicTo(15, 14.2, 13.2, 16, 11, 16)
  ..lineTo(8, 16)
  ..cubicTo(5.8, 16, 4, 14.2, 4, 12)
  ..close()
  ..moveTo(16.5, 6)
  ..lineTo(19, 6)
  ..cubicTo(20.4, 6, 21, 7, 21, 8.2)
  ..lineTo(21, 9.8)
  ..cubicTo(21, 11.6, 19.6, 13, 18, 13)
  ..lineTo(16.5, 13)
  ..lineTo(16.5, 11.2)
  ..lineTo(18, 11.2)
  ..cubicTo(18.6, 11.2, 19.2, 10.6, 19.2, 9.8)
  ..lineTo(19.2, 8.4)
  ..cubicTo(19.2, 7.9, 18.9, 7.7, 18.4, 7.7)
  ..lineTo(16.5, 7.7)
  ..close()
  ..moveTo(3, 18.5)
  ..lineTo(19, 18.5)
  ..lineTo(19, 20.5)
  ..lineTo(3, 20.5)
  ..close();

Path _gShop() => Path()
  ..moveTo(6, 7)
  ..cubicTo(6, 4.2, 7.8, 2.5, 12, 2.5)
  ..cubicTo(16.2, 2.5, 18, 4.2, 18, 7)
  ..lineTo(18, 8.5)
  ..lineTo(21, 8.5)
  ..lineTo(20, 21)
  ..lineTo(4, 21)
  ..lineTo(3, 8.5)
  ..lineTo(6, 8.5)
  ..close()
  ..moveTo(8, 8.5)
  ..lineTo(16, 8.5)
  ..lineTo(16, 7)
  ..cubicTo(16, 5.2, 14.8, 4.4, 12, 4.4)
  ..cubicTo(9.2, 4.4, 8, 5.2, 8, 7)
  ..close();

Path _gMarket() => Path()
  ..moveTo(4, 4)
  ..lineTo(20, 4)
  ..lineTo(20, 10)
  ..cubicTo(20, 11.1, 19.1, 12, 18, 12)
  ..lineTo(18, 20.5)
  ..lineTo(6, 20.5)
  ..lineTo(6, 12)
  ..cubicTo(4.9, 12, 4, 11.1, 4, 10)
  ..close()
  ..moveTo(10.9, 13.9)
  ..lineTo(13.1, 13.9)
  ..lineTo(13.1, 18.6)
  ..lineTo(10.9, 18.6)
  ..close();

Path _gFuel() => Path()
  ..moveTo(5, 3)
  ..lineTo(13, 3)
  ..cubicTo(14.1, 3, 15, 3.9, 15, 5)
  ..lineTo(15, 21)
  ..lineTo(3, 21)
  ..lineTo(3, 5)
  ..cubicTo(3, 3.9, 3.9, 3, 5, 3)
  ..close()
  ..moveTo(4.8, 5)
  ..lineTo(4.8, 10)
  ..lineTo(13.2, 10)
  ..lineTo(13.2, 5)
  ..close()
  ..moveTo(16, 8)
  ..lineTo(18.2, 6.2)
  ..cubicTo(19.3, 5.5, 20.6, 6.2, 20.6, 7.5)
  ..lineTo(20.6, 15.5)
  ..cubicTo(20.6, 16.6, 19.7, 17.5, 18.6, 17.5)
  ..lineTo(16.5, 17.5)
  ..lineTo(16.5, 15.6)
  ..lineTo(18.4, 15.6)
  ..cubicTo(18.6, 15.6, 18.8, 15.4, 18.8, 15.2)
  ..lineTo(18.8, 9.2)
  ..lineTo(16, 11.2)
  ..close();

Path _gEv() => Path()
  ..moveTo(7, 2)
  ..lineTo(15, 2)
  ..lineTo(13.4, 8)
  ..lineTo(17, 8)
  ..lineTo(9.6, 22)
  ..lineTo(10.6, 12.6)
  ..lineTo(7, 12.6)
  ..close();

Path _gParking() => Path()
  ..moveTo(8, 4)
  ..lineTo(13.2, 4)
  ..cubicTo(16.5, 4, 18.6, 6, 18.6, 9)
  ..cubicTo(18.6, 12, 16.5, 14, 13.2, 14)
  ..lineTo(11, 14)
  ..lineTo(11, 20)
  ..lineTo(8, 20)
  ..close()
  ..moveTo(11, 6.4)
  ..lineTo(11, 11.6)
  ..lineTo(12.9, 11.6)
  ..cubicTo(14.6, 11.6, 15.6, 10.6, 15.6, 9)
  ..cubicTo(15.6, 7.4, 14.6, 6.4, 12.9, 6.4)
  ..close();

Path _gBus() => Path()
  ..moveTo(5, 3)
  ..lineTo(19, 3)
  ..cubicTo(20.1, 3, 21, 3.9, 21, 5)
  ..lineTo(21, 16)
  ..cubicTo(21, 17, 20.4, 17.8, 19.5, 18.1)
  ..lineTo(19.5, 20)
  ..lineTo(16.8, 20)
  ..lineTo(16.8, 18.5)
  ..lineTo(7.2, 18.5)
  ..lineTo(7.2, 20)
  ..lineTo(4.5, 20)
  ..lineTo(4.5, 18.1)
  ..cubicTo(3.6, 17.8, 3, 17, 3, 16)
  ..lineTo(3, 5)
  ..cubicTo(3, 3.9, 3.9, 3, 5, 3)
  ..close()
  ..moveTo(5, 5.5)
  ..lineTo(5, 12)
  ..lineTo(19, 12)
  ..lineTo(19, 5.5)
  ..close()
  ..moveTo(6, 14)
  ..cubicTo(6.8, 14, 7.5, 14.7, 7.5, 15.5)
  ..cubicTo(7.5, 16.3, 6.8, 17, 6, 17)
  ..cubicTo(5.2, 17, 4.5, 16.3, 4.5, 15.5)
  ..cubicTo(4.5, 14.7, 5.2, 14, 6, 14)
  ..close()
  ..moveTo(18, 14)
  ..cubicTo(18.8, 14, 19.5, 14.7, 19.5, 15.5)
  ..cubicTo(19.5, 16.3, 18.8, 17, 18, 17)
  ..cubicTo(17.2, 17, 16.5, 16.3, 16.5, 15.5)
  ..cubicTo(16.5, 14.7, 17.2, 14, 18, 14)
  ..close();

Path _gHealth() => Path()
  ..moveTo(9.5, 3)
  ..lineTo(14.5, 3)
  ..lineTo(14.5, 9.5)
  ..lineTo(21, 9.5)
  ..lineTo(21, 14.5)
  ..lineTo(14.5, 14.5)
  ..lineTo(14.5, 21)
  ..lineTo(9.5, 21)
  ..lineTo(9.5, 14.5)
  ..lineTo(3, 14.5)
  ..lineTo(3, 9.5)
  ..lineTo(9.5, 9.5)
  ..close();

Path _gHotel() => Path()
  ..moveTo(3, 5)
  ..lineTo(5.6, 5)
  ..lineTo(5.6, 12.4)
  ..lineTo(18.4, 12.4)
  ..lineTo(18.4, 8)
  ..lineTo(21, 8)
  ..lineTo(21, 19)
  ..lineTo(18.4, 19)
  ..lineTo(18.4, 16.4)
  ..lineTo(5.6, 16.4)
  ..lineTo(5.6, 19)
  ..lineTo(3, 19)
  ..close()
  ..moveTo(7.2, 7.6)
  ..cubicTo(8.4, 7.6, 9.4, 8.5, 9.4, 9.8)
  ..cubicTo(9.4, 11, 8.4, 12, 7.2, 12)
  ..cubicTo(6, 12, 5, 11, 5, 9.8)
  ..cubicTo(5, 8.5, 6, 7.6, 7.2, 7.6)
  ..close();

Path _gStar() => Path()
  ..moveTo(12, 2.5)
  ..lineTo(14.9, 8.6)
  ..lineTo(21.5, 9.4)
  ..lineTo(16.6, 13.9)
  ..lineTo(17.9, 20.5)
  ..lineTo(12, 17.3)
  ..lineTo(6.1, 20.5)
  ..lineTo(7.4, 13.9)
  ..lineTo(2.5, 9.4)
  ..lineTo(9.1, 8.6)
  ..close();

Path _gMoney() => Path()
  ..moveTo(4, 5)
  ..lineTo(20, 5)
  ..cubicTo(20.6, 5, 21, 5.4, 21, 6)
  ..lineTo(21, 9.5)
  ..cubicTo(19.6, 9.5, 18.6, 10.6, 18.6, 12)
  ..cubicTo(18.6, 13.4, 19.6, 14.5, 21, 14.5)
  ..lineTo(21, 18)
  ..cubicTo(21, 18.6, 20.6, 19, 20, 19)
  ..lineTo(4, 19)
  ..cubicTo(3.4, 19, 3, 18.6, 3, 18)
  ..lineTo(3, 14.5)
  ..cubicTo(4.4, 14.5, 5.4, 13.4, 5.4, 12)
  ..cubicTo(5.4, 10.6, 4.4, 9.5, 3, 9.5)
  ..lineTo(3, 6)
  ..cubicTo(3, 5.4, 3.4, 5, 4, 5)
  ..close()
  ..moveTo(12, 8.4)
  ..cubicTo(10.4, 8.4, 9.4, 10, 9.4, 12)
  ..cubicTo(9.4, 14, 10.4, 15.6, 12, 15.6)
  ..cubicTo(13.6, 15.6, 14.6, 14, 14.6, 12)
  ..cubicTo(14.6, 10, 13.6, 8.4, 12, 8.4)
  ..close();

Path _gHouse() => Path()
  ..moveTo(12, 3)
  ..lineTo(21, 11)
  ..lineTo(18.5, 11)
  ..lineTo(18.5, 20.5)
  ..lineTo(13.5, 20.5)
  ..lineTo(13.5, 14.5)
  ..lineTo(10.5, 14.5)
  ..lineTo(10.5, 20.5)
  ..lineTo(5.5, 20.5)
  ..lineTo(5.5, 11)
  ..lineTo(3, 11)
  ..close();

Path _gWork() => Path()
  ..moveTo(9, 3)
  ..lineTo(15, 3)
  ..cubicTo(15.6, 3, 16, 3.4, 16, 4)
  ..lineTo(16, 6)
  ..lineTo(20, 6)
  ..cubicTo(20.6, 6, 21, 6.4, 21, 7)
  ..lineTo(21, 20)
  ..cubicTo(21, 20.6, 20.6, 21, 20, 21)
  ..lineTo(4, 21)
  ..cubicTo(3.4, 21, 3, 20.6, 3, 20)
  ..lineTo(3, 7)
  ..cubicTo(3, 6.4, 3.4, 6, 4, 6)
  ..lineTo(8, 6)
  ..lineTo(8, 4)
  ..cubicTo(8, 3.4, 8.4, 3, 9, 3)
  ..close()
  ..moveTo(9.8, 4.8)
  ..lineTo(9.8, 6)
  ..lineTo(14.2, 6)
  ..lineTo(14.2, 4.8)
  ..close()
  ..moveTo(10.9, 11)
  ..lineTo(10.9, 13)
  ..lineTo(13.1, 13)
  ..lineTo(13.1, 11)
  ..lineTo(10.9, 11)
  ..close();

// ── v5.7 premium teardrop pins ────────────────────────────────────────────

/// Smooth teardrop pin: gradient body, white halo, soft floor shadow.
/// The tip lands exactly on the geographic point (iconAnchor: bottom).
void _pinBody(Canvas c, double w, double h, Color top, Color bottom) {
  final r = 25.0;
  final cx = w / 2;
  final cy = 30.0; // head circle center
  final tipY = h - 8.0;
  final body = Path()
    ..moveTo(cx, tipY)
    ..cubicTo(cx + 13, tipY - 15, cx + r, cy + 22, cx + r, cy)
    ..arcTo(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      0,
      -math.pi,
      false,
    )
    ..cubicTo(cx - r, cy + 22, cx - 13, tipY - 15, cx, tipY)
    ..close();
  // Floor shadow.
  c.drawOval(
    Rect.fromCenter(center: Offset(cx, tipY + 4.5), width: 24, height: 7),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
  );
  // Body with vertical premium gradient.
  c.drawPath(
    body,
    Paint()
      ..shader = ui.Gradient.linear(Offset(cx, cy - r), Offset(cx, tipY), [
        top,
        bottom,
      ]),
  );
  // White halo.
  c.drawPath(
    body,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = Colors.white,
  );
  // Glossy top highlight.
  c.save();
  c.clipPath(body);
  c.drawCircle(
    Offset(cx, cy - 14),
    r - 4,
    Paint()..color = Colors.white.withValues(alpha: 0.16),
  );
  c.restore();
}

/// White glyph (24×24 design box) centered in the pin head.
void _pinGlyph(Canvas c, double w, Path glyph) {
  c.save();
  c.translate(w / 2, 30);
  final p = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  c.translate(-12, -12);
  c.drawPath(glyph, p);
  c.restore();
}

/// Checkered finish flag drawn inside the pin head.
void _pinFlag(Canvas c, double w) {
  final cx = w / 2;
  final cy = 30.0;
  final pole = Paint()
    ..color = Colors.white
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  c.drawLine(Offset(cx - 7, cy - 12), Offset(cx - 7, cy + 12), pole);
  final cell = 5.2;
  for (var r = 0; r < 2; r++) {
    for (var col = 0; col < 3; col++) {
      if ((r + col) % 2 == 0) continue;
      c.drawRect(
        Rect.fromLTWH(cx - 4.8 + col * cell, cy - 12 + r * cell, cell, cell),
        Paint()..color = Colors.white,
      );
    }
  }
}

Future<Uint8List> _pinPng(Color base, {Path? glyph, bool flag = false}) =>
    _renderPng(kPinSpriteW, kPinSpriteH, (c, s) {
      final top = Color.lerp(base, Colors.white, 0.22)!;
      final bottom = Color.lerp(base, Colors.black, 0.22)!;
      _pinBody(c, s.width, s.height, top, bottom);
      if (flag) {
        _pinFlag(c, s.width);
      } else if (glyph != null) {
        _pinGlyph(c, s.width, glyph);
      } else {
        // Neutral dot core (drop pin).
        c.drawCircle(
          Offset(s.width / 2, 30),
          7.5,
          Paint()..color = Colors.white,
        );
      }
    });

Future<Uint8List> _poiPng(Path glyph, Color ring, {int size = 34}) =>
    _renderPng(size, size, (c, s) {
      final center = Offset(s.width / 2, s.height / 2);
      final r = s.width / 2 - 1;
      c.drawCircle(
        center,
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.92),
      );
      c.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = ring.withValues(alpha: 0.95),
      );
      _path(c, s, Colors.black87, glyph);
    });

/// v5.8: fixed speed camera marker — a red disc with a white camera
/// silhouette. Reads instantly at navigation zooms and never collides with
/// the POI circles (bigger and red).
Future<Uint8List> _camPng() => _renderPng(40, 40, (c, s) {
  final center = Offset(s.width / 2, s.height / 2);
  const body = Color(0xFFD5452F);
  // Drop shadow + white halo + red disc.
  c.drawCircle(
    center.translate(0, 2.5),
    15,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
  );
  c.drawCircle(center, 16, Paint()..color = Colors.white);
  c.drawCircle(center, 14, Paint()..color = body);
  // Camera body.
  final rrect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-9, -5.5, 18, 12),
    const Radius.circular(2.6),
  );
  c.drawRRect(rrect, Paint()..color = Colors.white);
  // Viewfinder hump.
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(-3.4, -8, 6.8, 4),
      const Radius.circular(1.6),
    ),
    Paint()..color = Colors.white,
  );
  // Lens.
  c.drawCircle(center.translate(0.5, 0.5), 3.4, Paint()..color = body);
  c.drawCircle(center.translate(0.5, 0.5), 1.7, Paint()..color = Colors.white);
});

/// Registers every sprite MapLibre needs. Returns the list of names for
/// diagnostics.
///
/// v5 hardening: one failing addImage (duplicate name after a style
/// reload, transient platform error) used to abort the WHOLE loop — later
/// sprites (including the user puck and the pins) silently never got
/// registered and MapLibre rendered nothing where an icon was expected.
/// Every registration is isolated.
Future<List<String>> registerSprites(
  Future<void> Function(String, Uint8List) addImage,
  Color accent,
) async {
  final added = <String>[];
  Future<void> add(String name, Uint8List bytes) async {
    try {
      await addImage(name, bytes);
      added.add(name);
    } catch (_) {
      // Already registered / transient — keep going.
    }
  }

  Future<void> poi(String name, Path glyph, {Color? ring}) async {
    await add(name, await _poiPng(glyph, ring ?? accent));
  }

  await poi('lux-food', _gFood());
  await poi('lux-cafe', _gCafe());
  await poi('lux-shop', _gShop());
  await poi('lux-market', _gMarket());
  await poi('lux-fuel', _gFuel());
  await poi('lux-ev', _gEv());
  await poi('lux-parking', _gParking());
  await poi('lux-bus', _gBus());
  await poi('lux-health', _gHealth());
  await poi('lux-hotel', _gHotel());
  await poi('lux-money', _gMoney());
  await poi('lux-attraction', _gStar());

  // v5.7: BIG premium teardrop pins for the route endpoints.
  await add(
    'lux-pin-start',
    await _pinPng(const Color(0xFF22B573), glyph: _navArrowGlyph()),
  );
  await add(
    'lux-pin-finish',
    await _pinPng(const Color(0xFFE2452F), flag: true),
  );
  await add('lux-pin-drop', await _pinPng(accent));
  // v5.7: Home / Work / Favorites — same big teardrop pins with glyphs
  // («иконки дом или работа тоже крупнее!!»). v5.8: favorites get the
  // SIX-COLOR premium palette (kFavPinColors) — lux-fav-<i> — plus the
  // legacy lux-fav (amber) for callers that do not pass a color.
  await add(
    'lux-home',
    await _pinPng(const Color(0xFF22A35F), glyph: _gHouse()),
  );
  await add(
    'lux-work',
    await _pinPng(const Color(0xFFE2452F), glyph: _gWork()),
  );
  for (var i = 0; i < kFavPinColors.length; i++) {
    await add('lux-fav-$i', await _pinPng(kFavPinColors[i], glyph: _gStar()));
  }
  await add('lux-fav', await _pinPng(kFavPinColors.first, glyph: _gStar()));
  // v5.8: fixed speed cameras from OSM — red badge with a camera glyph.
  await add('lux-cam', await _camPng());
  // v5.7: the MOVING marker set — LARGE standalone glyphs without any
  // disc («сделай только стрелку без круга … крупнее»).
  for (final kind in const [
    PuckKind.arrow,
    PuckKind.car,
    PuckKind.bike,
    PuckKind.person,
  ]) {
    await add('lux-puck-${kind.name}', await puckPng(kind, accent));
  }
  return added;
}

/// Small navigation arrow used as the start-pin glyph.
Path _navArrowGlyph() => Path()
  ..moveTo(12, 2)
  ..lineTo(19, 20)
  ..lineTo(12, 15.5)
  ..lineTo(5, 20)
  ..close();

// ── v5.7: the moving marker (стрелка / машина / велосипед / человек) ──────

/// 88 px canvas, glyph ~66 px, NO disc. Every marker is drawn with:
///   1. a soft black drop shadow (reads over any basemap),
///   2. a thick white halo stroke,
///   3. a premium gradient body.
/// The glyph points NORTH (MapLibre rotates the icon by the course bearing).
Future<Uint8List> puckPng(PuckKind kind, Color accent) =>
    _renderPng(kPuckSpriteSize, kPuckSpriteSize, (c, s) {
      final center = Offset(s.width / 2, s.height / 2);
      c.translate(center.dx, center.dy);

      final light = Color.lerp(accent, Colors.white, 0.28)!;
      final dark = Color.lerp(accent, Colors.black, 0.24)!;
      Paint bodyPaint(Rect rect) => Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, rect.top),
          Offset(0, rect.bottom),
          [light, dark],
        );

      /// Three-pass rendering: shadow → white halo → gradient body.
      void paintGlyph({required void Function(Paint) draw, Rect? bodyRect}) {
        // 1. Drop shadow.
        c.save();
        c.translate(0, 3);
        draw(
          Paint()
            ..color = Colors.black.withValues(alpha: 0.28)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
        );
        c.restore();
        // 2. White halo.
        final halo = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.6
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;
        draw(halo);
        // 3. Gradient body (stroke for open frame glyphs).
        if (bodyRect != null) {
          draw(bodyPaint(bodyRect));
        }
      }

      switch (kind) {
        case PuckKind.arrow:
          // Sleek navigation dart — the classic premium navigator arrow.
          final arrow = Path()
            ..moveTo(0, -33)
            ..cubicTo(7, -19, 15, 8, 24, 28)
            ..lineTo(0, 14)
            ..lineTo(-24, 28)
            ..cubicTo(-15, 8, -7, -19, 0, -33)
            ..close();
          paintGlyph(
            bodyRect: arrow.getBounds(),
            draw: (p) {
              if (p.style == PaintingStyle.stroke) {
                c.drawPath(arrow, p);
              } else {
                c.drawPath(arrow, p);
              }
            },
          );
        case PuckKind.car:
          // Top-view premium car: gradient body, tinted glass, mirrors.
          final body = RRect.fromRectAndRadius(
            const Rect.fromLTWH(-15, -29, 30, 58),
            const Radius.circular(11),
          );
          paintGlyph(
            bodyRect: const Rect.fromLTWH(-15, -29, 30, 58),
            draw: (p) {
              if (p.style == PaintingStyle.stroke) {
                c.drawRRect(body, p);
              } else {
                c.drawRRect(body, p);
              }
            },
          );
          // Windshield + rear window (dark glass).
          final glass = Paint()..color = const Color(0x3D0A1622);
          c.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-11.5, -17, 23, 11),
              const Radius.circular(4),
            ),
            glass,
          );
          c.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-11.5, 14, 23, 8),
              const Radius.circular(4),
            ),
            glass,
          );
          // Roof highlight.
          c.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-8, -5, 16, 17),
              const Radius.circular(5),
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.20),
          );
          // Mirrors.
          final mirror = Paint()
            ..color = Colors.white
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round;
          c.drawLine(const Offset(-15, -9), const Offset(-21, -9), mirror);
          c.drawLine(const Offset(15, -9), const Offset(21, -9), mirror);
          final mirror2 = Paint()..color = dark;
          c.drawLine(const Offset(-18, -9), const Offset(-21, -9), mirror2);
          c.drawLine(const Offset(18, -9), const Offset(21, -9), mirror2);
        case PuckKind.bike:
          // Top-view bicycle, pointing up.
          void frame(double w, Color col) {
            final p = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w
              ..strokeCap = StrokeCap.round
              ..color = col;
            // Wheels
            c.drawCircle(const Offset(0, -19), 8.5, p);
            c.drawCircle(const Offset(0, 19), 8.5, p);
            // Frame triangle + fork + seat post
            final f = Path()
              ..moveTo(0, -19)
              ..lineTo(0, -4)
              ..lineTo(-7, 10)
              ..moveTo(0, -4)
              ..lineTo(7, 10)
              ..lineTo(0, 19)
              ..moveTo(-7, 10)
              ..lineTo(0, 19);
            c.drawPath(f, p);
            // Handlebar
            c.drawLine(const Offset(-9, -22), const Offset(9, -22), p);
            // Seat
            c.drawLine(const Offset(-5, 6), const Offset(5, 6), p);
          }

          // Shadow pass.
          c.save();
          c.translate(0, 3);
          frame(7.6, Colors.black.withValues(alpha: 0.28));
          c.restore();
          // White halo + gradient body strokes.
          frame(7.4, Colors.white);
          frame(3.2, accent);
        case PuckKind.person:
          void walker(double w, Color col, {bool fill = false}) {
            final p = Paint()
              ..color = col
              ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
              ..strokeWidth = w
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round;
            // Head
            c.drawCircle(const Offset(0, -16), 5.6, p);
            // Torso
            final torso = RRect.fromRectAndRadius(
              const Rect.fromLTWH(-6.5, -8, 13, 19),
              const Radius.circular(6.5),
            );
            c.drawRRect(torso, p);
            // Arms
            c.drawLine(const Offset(-6.5, -4), const Offset(-13, 6), p);
            c.drawLine(const Offset(6.5, -4), const Offset(13, 6), p);
            // Legs (mid-stride)
            c.drawLine(const Offset(-3, 10), const Offset(-7, 21), p);
            c.drawLine(const Offset(3, 10), const Offset(7, 21), p);
          }

          // Shadow pass.
          c.save();
          c.translate(0, 3);
          walker(6.4, Colors.black.withValues(alpha: 0.28));
          c.restore();
          // White halo, then the filled body on top.
          walker(6.2, Colors.white);
          c.save();
          walker(0, accent, fill: true);
          c.restore();
        case PuckKind.dot:
          // Classic dot stays (user opt-in).
          c.save();
          c.translate(0, 2);
          c.drawCircle(
            Offset.zero,
            11,
            Paint()
              ..color = Colors.black.withValues(alpha: 0.3)
              ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
          );
          c.restore();
          c.drawCircle(Offset.zero, 11, Paint()..color = accent);
          c.drawCircle(
            Offset.zero,
            11,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = Colors.white,
          );
      }
    });

// ── v6.5: public glyph access for poi_chips.dart (same 24×24 design box) ──
Path poiGlyphFood() => _gFood();
Path poiGlyphCafe() => _gCafe();
Path poiGlyphShop() => _gShop();
Path poiGlyphMarket() => _gMarket();
Path poiGlyphFuel() => _gFuel();
Path poiGlyphParking() => _gParking();
Path poiGlyphBus() => _gBus();
Path poiGlyphHealth() => _gHealth();
Path poiGlyphHotel() => _gHotel();
Path poiGlyphStar() => _gStar();
Path poiGlyphMoney() => _gMoney();
Path poiGlyphHouse() => _gHouse();
Path poiGlyphWork() => _gWork();
