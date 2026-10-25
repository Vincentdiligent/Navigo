/// Voice guidance (TTS) wrapper with graceful degradation.
///
/// v6.2 HARDENING («Голосовые подсказки не работают исправь както?»):
///  • the engine is initialized STEP-BY-STEP — one failing setter no longer
///    kills the whole voice («_ok=false» forever);
///  • languages are tried as full BCP-47 codes first (ru-RU, fr-FR, es-ES,
///    de-DE, en-US), then bare codes — several engines answer only to the
///    full form;
///  • the manifest now declares the TTS_SERVICE <queries> intent (the REAL
///    root cause: on Android 11+ TextToSpeech could not even bind to the
///    engine app because of package visibility — this wrapper never stood
///    a chance);
///  • an [enabled] gate wires the sound button + settings switch to the
///    actual speaker (the toggle used to change a flag nobody read).
///
/// v6.8 OFFLINE VOICE («хочу чтобы для всех подошло», microG included): the
/// system engine is now only one of two speakers. When the user has downloaded
/// a Piper voice for the interface language it speaks, so a phone without
/// Google speech services still hears the turns. [mode] rules: `auto` prefers
/// the offline voice whenever one is installed, `system` / `offline` force it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/strings.dart';
import '../voice/piper_tts.dart';
import '../voice/voice_packs.dart';
import 'maneuver_text.dart';
import 'nav_session.dart';

class NavVoice {
  NavVoice();

  /// v6.2: the live instance (created in the HomeScreen boot) — the
  /// settings «Проверить голос» row speaks through it.
  static NavVoice? I;

  final FlutterTts _tts = FlutterTts();
  bool _ok = false;

  /// v6.2: the master switch, synced from AppState.voiceOn. When false,
  /// [speak] is a no-op — the button in the nav top bar finally rules the
  /// speaker.
  bool enabled = true;

  /// `auto` | `system` | `offline` — mirrors AppState.voiceEngine.
  String mode = 'auto';

  Locale _locale = const Locale('en');

  /// The offline voice picked for [_locale] (installed, maybe still loading).
  VoicePack? _pack;
  bool _offlineOk = false;
  Future<void>? _loading;

  /// v6.2: full-code first, bare code second — engines disagree on what
  /// «ru» means, «ru-RU» never fails on a phone that has Russian at all.
  static const Map<String, List<String>> _langs = {
    'ru': ['ru-RU', 'ru'],
    'fr': ['fr-FR', 'fr'],
    'es': ['es-ES', 'es'],
    'de': ['de-DE', 'de'],
    'en': ['en-US', 'en'],
    'pt': ['pt-BR', 'pt'],
    'tr': ['tr-TR', 'tr'],
    'pl': ['pl-PL', 'pl'],
  };

  Future<bool> init(Locale locale) async {
    _locale = locale;
    try {
      final code = locale.languageCode.toLowerCase();
      final candidates = [...?_langs[code], 'en-US', 'en'];
      var set = false;
      for (final cand in candidates) {
        try {
          if (await _tts.isLanguageAvailable(cand) == true) {
            await _tts.setLanguage(cand);
            set = true;
            break;
          }
        } catch (_) {
          // try the next candidate
        }
      }
      if (!set) {
        // Last resort: force English. If even that throws the engine is
        // broken and _ok stays false (silent no-op everywhere).
        await _tts.setLanguage('en-US');
      }
      try {
        await _tts.setSpeechRate(0.5);
      } catch (_) {}
      try {
        await _tts.setVolume(1.0);
      } catch (_) {}
      try {
        await _tts.setPitch(1.0);
      } catch (_) {}
      // Fire-and-forget speaking (the default) — announcements must never
      // block the navigation loop.
      try {
        await _tts.awaitSpeakCompletion(false);
      } catch (_) {}
      _ok = true;
    } catch (_) {
      _ok = false;
    }
    await pickVoice();
    return _ok || _offlineOk;
  }

  /// The interface language changed, or a voice was downloaded / deleted:
  /// re-pick the speaker.
  Future<void> pickVoice() async {
    final lang = _locale.languageCode.toLowerCase();
    VoicePack? pack;
    if (mode != 'system') {
      pack = await VoicePackStore.I.packFor(lang);
    }
    _pack = pack;
    if (pack == null) {
      _offlineOk = false;
      // Offline mode dropped: hand the model's tens of MB of RAM back.
      await PiperTts.I.forget();
      _loading = null;
      return;
    }
    final pending = _loading;
    if (pending != null) await pending;
    // ignore: discarded_futures
    final f = PiperTts.I.use(pack).then((live) {
      _offlineOk = live;
    });
    _loading = f;
    if (_offlineOk) return;
    await f;
  }

  void setLocale(Locale locale) => _locale = locale;

  bool get available => _ok || _offlineOk;

  /// Which speaker is live: `offline`, `system` or `none`.
  String get engineLabel => _offlineOk ? 'offline' : (_ok ? 'system' : 'none');

  /// The offline voice this language resolves to (null = none installed).
  VoicePack? get offlinePack => _pack;

  bool get usingOffline => _offlineOk;

  /// v6.7: is a speech engine actually available on this phone?
  ///
  /// [speak] is a silent no-op when the engine is missing, so the settings
  /// test button produced neither sound nor message. Proven on a device with
  /// no TTS app installed: logcat «speak failed: not bound to TTS engine»,
  /// `query-services -a android.intent.action.TTS_SERVICE` → none, and
  /// `getLanguages` comes back empty — that emptiness is the honest signal.
  /// v6.8: an installed offline voice answers the same question.
  Future<bool> engineReady() async {
    if (_offlineOk) return true;
    if (!_ok) return false;
    try {
      final langs = await _tts.getLanguages;
      return langs is List && langs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// v6.2: the test utterance ignores the mute gate on purpose — the user
  /// pressed «Проверить голос» to hear something, and the switch being off
  /// used to make the button silently do nothing.
  Future<void> test() async {
    final was = enabled;
    enabled = true;
    try {
      await speak(S.of('voiceCheck'));
    } finally {
      enabled = was;
    }
  }

  Future<void> speak(String text) async {
    if (!enabled || text.isEmpty) return;
    if (_pack != null && !_offlineOk) {
      // The first prompt after a cold start may catch the voice mid-load.
      await _loading;
    }
    if (_offlineOk) {
      await PiperTts.I.say(text);
      return;
    }
    if (!_ok) return;
    try {
      await _tts.speak(text);
      // No stop() before speak(): on several engines the stop() → speak()
      // pair issued back-to-back swallows the utterance. flutter_tts
      // interrupts the previous queue by itself when speak() is called.
    } catch (_) {}
  }

  /// Builds a localized sentence for an OSRM maneuver key. v5.9: the word
  /// mapping itself lives in [maneuverTitle] — the HUD sheet speaks the
  /// same language the TTS does.
  String localize(String maneuverKey, String street) {
    final core = maneuverTitle(maneuverKey);
    return NavSession.sentence(
      maneuverText: core,
      street: street,
      onWord: S.of('on'),
    );
  }

  Future<void> shutdown() async {
    try {
      await _tts.stop();
    } catch (_) {}
    await PiperTts.I.shutdown();
    _offlineOk = false;
  }
}
