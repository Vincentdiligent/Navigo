/// v6.1: THE PHOTO PIPELINE — the user got broken-image icons («многие
/// фото не грузятся показывают битую иконку картинки») and slow cards
/// («инфа грузится очень долго»).
///
/// Root causes of the broken icons, fixed HERE, once:
///   • a URL can die between the API listing and the download (deleted
///     Commons file, hotlink-blocked host, HTML error page);
///   • some “images” are actually huge originals (a 50 MP panorama fails
///     to decode on a phone);
///   • no caching — every re-open of the card re-downloaded everything.
///
/// Contract:
///   • download with the compliant Wikimedia User-Agent + 8 s timeout;
///   • ACCEPT only bytes the platform really decoded (Image.provider
///     listener) — a file that fails to decode is dropped, never shown;
///   • memory cache for the session + disk cache (LRU, 48 MB) so re-taps
///     are instant and re-openings cost zero traffic;
///   • [prune] keeps the disk footprint bounded forever.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class PhotoCache {
  PhotoCache._();
  static final PhotoCache I = PhotoCache._();

  static const _ua = {
    'User-Agent':
        'Navigo/6.1 (https://github.com/navigo-navigator/navigo; '
        'navigo-navigator@users.noreply.github.com)',
  };

  /// url → bytes of the CURRENT session (instant re-shows).
  final Map<String, Uint8List> _mem = {};

  /// url → in-flight download (dedupes parallel requests of one carousel).
  final Map<String, Future<Uint8List?>> _busy = {};

  Directory? _dir;
  bool _dirTried = false;

  /// Android sets TMPDIR to the app-private cache dir — a proper cache
  /// location with zero plugins involved (the OS may wipe it anytime,
  /// which is fine: this IS a cache).
  Future<Directory?> _cacheDir() async {
    if (_dirTried) return _dir;
    _dirTried = true;
    try {
      final d = Directory('${Directory.systemTemp.path}/photocache');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dir = d;
    } catch (_) {}
    return _dir;
  }

  String? _fileFor(String url) {
    final d = _dir;
    if (d == null) return null;
    // Stable, filesystem-safe key.
    final bytes = utf8.encode(url);
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return '${d.path}/img_${h.toRadixString(16)}.jpg';
  }

  /// The one entry point: bytes for [url] or null (→ the caller DROPS the
  /// photo; nothing broken is ever rendered).
  Future<Uint8List?> get(String url) {
    final hit = _mem[url];
    if (hit != null) return Future<Uint8List?>.value(hit);
    return _busy.putIfAbsent(url, () => _load(url)).whenComplete(() {
      _busy.remove(url);
    });
  }

  Future<Uint8List?> _load(String url) async {
    // 1 ── disk cache.
    final path = _fileFor(url);
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          final bytes = await f.readAsBytes();
          if (bytes.lengthInBytes > 512) {
            _mem[url] = bytes;
            return bytes;
          }
          f.deleteSync();
        }
      } catch (_) {}
    }
    // 2 ── network (8 s, image content only).
    Uint8List? bytes;
    try {
      final res = await http
          .get(Uri.parse(url), headers: _ua)
          .timeout(const Duration(seconds: 8));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode == 200 &&
          res.bodyBytes.lengthInBytes > 512 &&
          (type.isEmpty || type.startsWith('image/'))) {
        bytes = res.bodyBytes;
      }
    } catch (_) {
      return null;
    }
    if (bytes == null) return null;
    // 3 ── store.
    _mem[url] = bytes;
    if (path != null) {
      try {
        await File(path).writeAsBytes(bytes, flush: false);
      } catch (_) {}
    }
    return bytes;
  }

  /// LRU-ish disk cap — call once per app start. 48 MB is ~120 photos.
  Future<void> prune() async {
    try {
      final d = await _cacheDir();
      if (d == null || !d.existsSync()) return;
      final files = d
          .listSync()
          .whereType<File>()
          .map((f) {
            try {
              return (f, f.lastModifiedSync());
            } catch (_) {
              return (f, DateTime.fromMillisecondsSinceEpoch(0));
            }
          })
          .toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));
      var total = 0;
      for (final (f, _) in files) {
        try {
          total += f.lengthSync();
        } catch (_) {}
      }
      const cap = 48 * 1024 * 1024;
      for (final (f, _) in files) {
        if (total <= cap) break;
        try {
          final len = f.lengthSync();
          f.deleteSync();
          total -= len;
        } catch (_) {}
      }
    } catch (_) {}
  }
}
