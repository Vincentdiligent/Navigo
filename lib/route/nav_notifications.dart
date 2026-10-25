/// v5.7: PREMIUM TURN-BY-TURN NOTIFICATIONS + the location foreground
/// service.
///
/// The user: «самое главное нет ПУШ уведомлений как без них? нужен … пуш
/// уведомления красивые чтобы знать куда ехать пуш на заблокированном
/// тоже красиво и удобно было бы чтобы навигация работала».
///
/// Implementation (no new packages — build-safe in this sandbox):
///   • NavService.kt — a native FOREGROUND SERVICE (type=location) that
///     keeps the navigation alive while the screen is off / the app is in
///     the background;
///   • the SAME service owns the ongoing «Навигация» notification:
///     IMPORTANCE_HIGH (heads-up), CATEGORY_NAVIGATION, VISIBILITY_PUBLIC
///     (full content on the lock screen), BigText style, green accent;
///   • every maneuver / progress tick re-posts the notification through
///     the [MethodChannel];
///   • [keepScreenOn] pins FLAG_KEEP_SCREEN_ON while the HUD is up.
library;

import 'package:flutter/services.dart';

class NavNotifications {
  NavNotifications._();

  static const MethodChannel _ch = MethodChannel('navigo/nav');

  /// POST_NOTIFICATIONS (Android 13+) + ACCESS_BACKGROUND_LOCATION
  /// (Android 10+) so locked-screen navigation keeps tracking.
  static Future<void> requestPermissions() async {
    try {
      await _ch.invokeMethod('requestPermissions');
    } catch (_) {}
  }

  /// Starts (or updates) the navigation notification. [title] — the next
  /// maneuver, [text] — street + ETA. The first call starts the FGS.
  static Future<void> show({
    required String title,
    required String text,
  }) async {
    try {
      await _ch.invokeMethod('show', {'title': title, 'text': text});
    } catch (_) {}
  }

  /// Convenience alias — every progress tick calls [update].
  static Future<void> update({
    required String title,
    required String text,
  }) =>
      show(title: title, text: text);

  /// Removes the notification and stops the foreground service.
  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  /// Keeps the screen awake while the navigation HUD is on screen.
  static Future<void> keepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  /// v5.8: hands a place / ETA to the Android share sheet (ACTION_SEND).
  static Future<void> shareText(String title, String text) async {
    try {
      await _ch.invokeMethod('share', {'title': title, 'text': text});
    } catch (_) {}
  }
}
