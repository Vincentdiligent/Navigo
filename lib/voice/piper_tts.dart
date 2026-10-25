/// v6.8: the on-device speech engine (sherpa-onnx + a Piper voice).
///
/// Two hard facts shaped this file:
///  • `OfflineTts.generate()` is SYNCHRONOUS FFI — 0.2…2 s of CPU per
///    sentence. Running it on the UI isolate would stutter the map, so every
///    synthesis happens in one long-lived worker isolate (sherpa's bindings
///    are per-isolate, hence `initBindings()` inside the worker);
///  • sherpa only produces samples, it does not play them. The worker writes
///    a WAV into the app's own directory and the UI thread plays it with
///    audioplayers, so a nav call-to-talk never blocks navigation.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:path_provider/path_provider.dart';

import 'voice_packs.dart';

/// Sent to the worker: `load` builds the engine, `say` renders one sentence,
/// `free` releases it. Answers always carry the request id.
void _ttsWorker(SendPort main) {
  final rp = ReceivePort();
  main.send(rp.sendPort);

  sherpa.OfflineTts? tts;
  String loadedKey = '';

  rp.listen((dynamic msg) {
    if (msg is! Map) return;
    final id = msg['id'] as int? ?? -1;
    final op = msg['op'] as String? ?? '';
    try {
      switch (op) {
        case 'load':
          final key = '${msg['key']}';
          if (tts != null && loadedKey == key) {
            main.send({'id': id, 'ok': true, 'already': true});
            return;
          }
          tts?.free();
          tts = null;
          sherpa.initBindings();
          tts = sherpa.OfflineTts(
            sherpa.OfflineTtsConfig(
              model: sherpa.OfflineTtsModelConfig(
                vits: sherpa.OfflineTtsVitsModelConfig(
                  model: '${msg['model']}',
                  tokens: '${msg['tokens']}',
                  dataDir: '${msg['dataDir']}',
                ),
                numThreads: 2,
                debug: false,
                provider: 'cpu',
              ),
              // 0 = render the whole sentence in one go (no streaming split).
              maxNumSenetences: 0,
            ),
          );
          loadedKey = key;
          main.send({
            'id': id,
            'ok': true,
            'rate': tts!.sampleRate,
            'speakers': tts!.numSpeakers,
          });
        case 'say':
          final engine = tts;
          if (engine == null) throw 'голос не загружен';
          final audio = engine.generate(
            text: '${msg['text']}',
            sid: 0,
            speed: (msg['speed'] as num?)?.toDouble() ?? 0.95,
          );
          if (audio.samples.isEmpty) {
            throw 'пустой звук: проверьте espeak-ng-data и модель';
          }
          final out = '${msg['out']}';
          if (!sherpa.writeWave(
            filename: out,
            samples: audio.samples,
            sampleRate: audio.sampleRate,
          )) {
            throw 'не удалось записать $out';
          }
          main.send({'id': id, 'ok': true, 'out': out});
        case 'free':
          tts?.free();
          tts = null;
          loadedKey = '';
          main.send({'id': id, 'ok': true});
        default:
          throw 'неизвестная команда $op';
      }
    } catch (e) {
      main.send({'id': id, 'ok': false, 'err': '$e'});
    }
  });
}

/// Offline speech for one language at a time.
class PiperTts {
  PiperTts._();

  static final PiperTts I = PiperTts._();

  Isolate? _iso;
  ReceivePort? _rp;
  SendPort? _toWorker;
  final Map<int, Completer<Map<String, Object?>>> _replies = {};
  final AudioPlayer _player = AudioPlayer();

  int _req = 0;
  int _slot = 0;
  Directory? _out;
  String? _wavPath;

  /// Id of the voice currently resident in the worker isolate.
  String? get loadedId => _loaded;
  String? _loaded;

  /// Last engine failure — the settings page shows it instead of silence.
  String lastError = '';

  Future<SendPort> _worker() async {
    final existing = _toWorker;
    if (existing != null) return existing;
    final rp = ReceivePort();
    _rp = rp;
    final portC = Completer<SendPort>();
    rp.listen((dynamic msg) {
      if (msg is SendPort) {
        if (!portC.isCompleted) portC.complete(msg);
        return;
      }
      if (msg is Map) {
        final id = msg['id'] as int? ?? -1;
        _replies.remove(id)?.complete(Map<String, Object?>.from(msg));
      }
    });
    _iso = await Isolate.spawn(_ttsWorker, rp.sendPort);
    return _toWorker = await portC.future;
  }

  Future<Map<String, Object?>> _ask(
    Map<String, Object?> msg, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final port = await _worker();
    final id = ++_req;
    final c = Completer<Map<String, Object?>>();
    _replies[id] = c;
    port.send({'id': id, ...msg});
    try {
      return await c.future.timeout(timeout);
    } on TimeoutException {
      _replies.remove(id);
      return {'ok': false, 'err': 'превышено время ожидания голоса'};
    }
  }

  Future<Directory> _outDir() async {
    final d = _out;
    if (d != null) return d;
    final sup = await getApplicationSupportDirectory();
    final dir = Directory('${sup.path}/navigo-tts/speech');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _out = dir;
  }

  /// Loads [pack] into the engine. True when the voice can speak.
  Future<bool> use(VoicePack pack) async {
    final store = VoicePackStore.I;
    final res = await _ask({
      'op': 'load',
      'key': pack.id,
      'model': await store.modelPath(pack),
      'tokens': await store.tokensPath(pack),
      'dataDir': await store.espeakDataDir(),
    }, timeout: const Duration(minutes: 2));
    if (res['ok'] == true) {
      lastError = '';
      _loaded = pack.id;
      return true;
    }
    lastError = '${res['err']}';
    _loaded = null;
    return false;
  }

  /// Renders [text] and plays it, interrupting whatever is still sounding —
  /// the same cut-in behaviour the system engine gives navigation prompts.
  Future<void> say(String text) async {
    if (text.trim().isEmpty || _loaded == null) return;
    final dir = await _outDir();
    final path = '${dir.path}/s${++_slot}.wav';
    final res = await _ask({
      'op': 'say',
      'text': text,
      'out': path,
    }, timeout: const Duration(seconds: 90));
    if (res['ok'] != true) {
      lastError = '${res['err']}';
      return;
    }
    lastError = '';
    final old = _wavPath;
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      _wavPath = path;
    } catch (e) {
      lastError = '$e';
    }
    if (old != null && old != path) {
      final f = File(old);
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Releases the model (tens of MB of RAM) and the isolate.
  Future<void> shutdown() async {
    if (_loaded != null) {
      await _ask({'op': 'free'}, timeout: const Duration(seconds: 5));
      _loaded = null;
    }
    await stop();
    final wav = _wavPath;
    if (wav != null) {
      final f = File(wav);
      if (await f.exists()) await f.delete();
      _wavPath = null;
    }
    _toWorker = null;
    _rp?.close();
    _rp = null;
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
  }

  /// The voice was deleted or swapped: drop whatever is in memory.
  Future<void> forget() async {
    if (_loaded == null) return;
    await _ask({'op': 'free'}, timeout: const Duration(seconds: 5));
    _loaded = null;
  }
}
