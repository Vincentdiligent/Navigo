/// v6.8: free on-device voices («Добавь оффлайн озвучку … чтобы для всех
/// подошло!»).
///
/// The phone's system TTS is missing on devices without Google speech services
/// (microG) and answers with silence on others, so the app carries its own
/// neural speech: sherpa-onnx runs a Piper VITS model entirely offline. Only
/// the inference engine ships in the APK — each voice (~63 MB) is a download
/// the user starts on purpose, one per language.
///
/// Where things live (all under the app's own support directory):
///   navigo-tts/espeak-ng-data/**   phonemizer tables, unpacked from assets
///   navigo-tts/espeak-ng-data/ru_dict  the per-language spelling rules,
///                                      downloaded with the voice (shared dir,
///                                      because espeak-ng looks there)
///   navigo-tts/<pack id>/model.onnx + tokens.txt
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One file inside a voice pack.
class VoiceFile {
  const VoiceFile(
    this.remote,
    this.local,
    this.bytes, {
    this.shared = false,
    this.optional = false,
  });

  /// Name inside the Hugging Face repository.
  final String remote;

  /// Name it gets on the device.
  final String local;

  /// Verified content-length; also the "is it really installed" check. Zero
  /// means "any non-empty file counts".
  final int bytes;

  /// Lands in the shared espeak-ng-data directory instead of the pack folder.
  final bool shared;

  /// espeak spelling rules: nice to have, never blocks a voice.
  final bool optional;
}

class VoicePack {
  const VoicePack({
    required this.id,
    required this.lang,
    required this.label,
    required this.license,
    required this.files,
  });

  /// Piper repository suffix, e.g. `ru_RU-dmitri-medium`.
  final String id;

  /// BCP-47 primary subtag this pack speaks.
  final String lang;

  /// Language name in its own language (what every language picker shows).
  final String label;

  final String license;
  final List<VoiceFile> files;

  int get totalBytes => files.fold(0, (a, f) => a + f.bytes);

  /// The model is always the first entry; the token table is the non-shared
  /// one (the dict lives in the shared espeak directory).
  VoiceFile get model => files.first;
  VoiceFile get tokens => files.firstWhere((f) => f.local == 'tokens.txt');

  static const _host = 'https://huggingface.co/csukuangfj/vits-piper-';

  String url(VoiceFile f) => '$_host$id/resolve/main/${f.remote}';
}

/// Exactly one pack per language, so "which voice for Russian?" never needs
/// a second setting: the catalog entry IS the choice.
class VoicePacks {
  VoicePacks._();

  static const List<VoicePack> all = [
    VoicePack(
      id: 'ru_RU-dmitri-medium',
      lang: 'ru',
      label: 'Русский',
      license: 'CC0',
      files: [
        VoiceFile('ru_RU-dmitri-medium.onnx', 'model.onnx', 63201422),
        VoiceFile('tokens.txt', 'tokens.txt', 907),
        VoiceFile('espeak-ng-data/ru_dict', 'ru_dict', 8532392,
            shared: true, optional: true),
      ],
    ),
    VoicePack(
      id: 'en_US-joe-medium',
      lang: 'en',
      label: 'English',
      license: 'CC0',
      files: [
        VoiceFile('en_US-joe-medium.onnx', 'model.onnx', 63201425),
        VoiceFile('tokens.txt', 'tokens.txt', 899),
        VoiceFile('espeak-ng-data/en_dict', 'en_dict', 166944,
            shared: true, optional: true),
      ],
    ),
    VoicePack(
      id: 'fr_FR-siwis-medium',
      lang: 'fr',
      label: 'Français',
      license: 'CC BY 4.0',
      files: [
        VoiceFile('fr_FR-siwis-medium.onnx', 'model.onnx', 63201421),
        VoiceFile('tokens.txt', 'tokens.txt', 921),
        VoiceFile('espeak-ng-data/fr_dict', 'fr_dict', 63727,
            shared: true, optional: true),
      ],
    ),
    VoicePack(
      id: 'es_ES-davefx-medium',
      lang: 'es',
      label: 'Español',
      license: 'CC0',
      files: [
        VoiceFile('es_ES-davefx-medium.onnx', 'model.onnx', 63201422),
        VoiceFile('tokens.txt', 'tokens.txt', 907),
        VoiceFile('espeak-ng-data/es_dict', 'es_dict', 49252,
            shared: true, optional: true),
      ],
    ),
    VoicePack(
      id: 'de_DE-thorsten-medium',
      lang: 'de',
      label: 'Deutsch',
      license: 'CC0',
      files: [
        VoiceFile('de_DE-thorsten-medium.onnx', 'model.onnx', 63201421),
        VoiceFile('tokens.txt', 'tokens.txt', 907),
        VoiceFile('espeak-ng-data/de_dict', 'de_dict', 68276,
            shared: true, optional: true),
      ],
    ),
    VoicePack(
      id: 'pt_BR-faber-medium',
      lang: 'pt',
      label: 'Português (Brasil)',
      license: 'CC0',
      files: [
        VoiceFile('pt_BR-faber-medium.onnx', 'model.onnx', 63201428),
        VoiceFile('tokens.txt', 'tokens.txt', 907),
        VoiceFile('espeak-ng-data/pt_dict', 'pt_dict', 67817,
            shared: true, optional: true),
      ],
    ),
    VoicePack(
      id: 'tr_TR-fettah-medium',
      lang: 'tr',
      label: 'Türkçe',
      license: 'CC0',
      files: [
        VoiceFile('tr_TR-fettah-medium.onnx', 'model.onnx', 63201422),
        VoiceFile('tokens.txt', 'tokens.txt', 921),
        VoiceFile('espeak-ng-data/tr_dict', 'tr_dict', 46793,
            shared: true, optional: true),
      ],
    ),
    VoicePack(
      id: 'pl_PL-gosia-medium',
      lang: 'pl',
      label: 'Polski',
      license: 'CC0',
      files: [
        VoiceFile('pl_PL-gosia-medium.onnx', 'model.onnx', 63201421),
        VoiceFile('tokens.txt', 'tokens.txt', 907),
        VoiceFile('espeak-ng-data/pl_dict', 'pl_dict', 76730,
            shared: true, optional: true),
      ],
    ),
  ];

  static VoicePack? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Packs whose language matches [lang], catalog order (the recommended one
  /// for each of the app's own interface languages comes first).
  static List<VoicePack> forLang(String lang) =>
      all.where((p) => p.lang == lang.toLowerCase()).toList();
}

/// Install state + the downloader. One global instance: the settings page
/// drives it, the speech engine reads it.
class VoicePackStore extends ChangeNotifier {
  VoicePackStore._();

  static final VoicePackStore I = VoicePackStore._();

  static const _zipAsset = 'assets/tts/espeak-ng-data.zip';

  /// Bump when the bundled phonemizer changes: old copies get unpacked again.
  static const _dataStamp = 'navigo-espeak-1';

  Directory? _root;
  final Map<String, double> _progress = {};
  final Map<String, String> _errors = {};
  final Set<String> _busy = {};

  double? progressOf(String id) => _progress[id];
  String errorOf(String id) => _errors[id] ?? '';
  bool isBusy(String id) => _busy.contains(id);

  Future<Directory> _rootDir() async {
    final r = _root;
    if (r != null) return r;
    final sup = await getApplicationSupportDirectory();
    final d = Directory('${sup.path}/navigo-tts');
    if (!await d.exists()) await d.create(recursive: true);
    return _root = d;
  }

  /// The espeak-ng-data directory Piper needs (from the APK, unzipped once).
  Future<String> espeakDataDir() async {
    final root = await _rootDir();
    final data = Directory('${root.path}/espeak-ng-data');
    final stamp = File('${root.path}/.espeak-stamp');
    final stamped = await stamp.exists() &&
        (await stamp.readAsString()).trim() == _dataStamp;
    if (!await data.exists() || !stamped) {
      if (await data.exists()) await data.delete(recursive: true);
      await data.create(recursive: true);
      final bytes = (await rootBundle.load(_zipAsset)).buffer.asUint8List();
      for (final e in ZipDecoder().decodeBytes(bytes)) {
        if (!e.isFile) continue;
        // entry: espeak-ng-data/lang/gmw/... — keep everything below the root.
        final rel = e.name.split('/').skip(1).join('/');
        if (rel.isEmpty) continue;
        final out = File('${data.path}/$rel');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(e.readBytes() as List<int>, flush: true);
      }
      await stamp.writeAsString(_dataStamp);
    }
    return data.path;
  }

  Future<File> _local(VoicePack p, VoiceFile f) async {
    final root = await _rootDir();
    final dir = f.shared
        ? '${root.path}/espeak-ng-data'
        : '${root.path}/${p.id}';
    return File('$dir/${f.local}');
  }

  /// Every non-optional file present with the size it was published with.
  Future<bool> installed(VoicePack p) async {
    for (final f in p.files) {
      if (f.optional) continue;
      final file = await _local(p, f);
      if (!await file.exists()) return false;
      if (f.bytes > 0 && await file.length() != f.bytes) return false;
    }
    return true;
  }

  Future<List<bool>> installedAll() async {
    final out = <bool>[];
    for (final p in VoicePacks.all) {
      out.add(await installed(p));
    }
    return out;
  }

  /// The installed voice for [lang], or null.
  Future<VoicePack?> packFor(String lang) async {
    for (final p in VoicePacks.forLang(lang)) {
      if (await installed(p)) return p;
    }
    return null;
  }

  Future<String> modelPath(VoicePack p) async => (await _local(p, p.model)).path;

  Future<String> tokensPath(VoicePack p) async =>
      (await _local(p, p.tokens)).path;

  /// Downloads the pack file by file. Safe to call again after an interrupt:
  /// a file already at full size is skipped, a half file is replaced.
  Future<bool> install(VoicePack p) async {
    if (_busy.contains(p.id)) return false;
    _busy.add(p.id);
    _errors.remove(p.id);
    _progress[p.id] = 0;
    notifyListeners();
    var ok = true;
    try {
      await espeakDataDir();
      final done = p.files
          .where((f) => !f.optional)
          .fold<int>(0, (a, f) => a + f.bytes);
      final total = done + p.files.where((f) => f.optional).fold<int>(0, (a, f) => a + f.bytes);
      var got = 0;
      for (final f in p.files) {
        final file = await _local(p, f);
        if (await file.exists() && f.bytes > 0 && await file.length() == f.bytes) {
          got += f.bytes;
          continue;
        }
        try {
          got += await _fetch(p, f, file, total, got);
        } catch (e) {
          if (!f.optional) {
            ok = false;
            _errors[p.id] = '$e';
            break;
          }
        }
      }
      if (ok) _progress[p.id] = 1;
    } catch (e) {
      ok = false;
      _errors[p.id] = '$e';
    } finally {
      _busy.remove(p.id);
      if (!ok) _progress.remove(p.id);
      notifyListeners();
    }
    return ok;
  }

  int _lastShown = 0;

  Future<int> _fetch(
    VoicePack p,
    VoiceFile f,
    File file,
    int total,
    int already,
  ) async {
    final client = http.Client();
    var received = 0;
    try {
      final req = http.Request('GET', Uri.parse(p.url(f)))
        ..followRedirects = true
        ..headers['User-Agent'] = 'Navigo/6.8 voice pack';
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.part');
      final sink = tmp.openWrite();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastShown > 180) {
            _lastShown = now;
            _progress[p.id] =
                (((already + received) / (total == 0 ? 1 : total)) * 100)
                        .round() /
                    100;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (f.bytes > 0 && await tmp.length() != f.bytes) {
        throw HttpException('обрезан ${f.remote}');
      }
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
      // The rename kept the file outside the progress accounting.
      _progress[p.id] = (((already + received) / (total == 0 ? 1 : total)) * 100)
              .round() /
          100;
      notifyListeners();
      return received;
    } catch (e) {
      final tmp = File('${file.path}.part');
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> remove(VoicePack p) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/${p.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    for (final f in p.files) {
      if (!f.shared) continue;
      final file = await _local(p, f);
      if (await file.exists()) await file.delete();
    }
    _errors.remove(p.id);
    _progress.remove(p.id);
    notifyListeners();
  }

  /// Bytes the installed packs actually take (for the «занимает» line).
  Future<int> usedBytes() async {
    final root = await _rootDir();
    var sum = 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) sum += await e.length();
    }
    return sum;
  }
}
