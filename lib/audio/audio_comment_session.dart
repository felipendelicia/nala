import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import '../document/asset_store.dart';
import 'audio_service.dart';

class AudioAttachment {
  const AudioAttachment(this.assetId, this.durationMs);
  final String assetId;
  final int durationMs;
}

class AudioCommentSession extends ChangeNotifier with WidgetsBindingObserver {
  AudioCommentSession({
    required this.device,
    required this.assets,
    required this.directory,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }
  final AudioDevice device;
  final AssetStore assets;
  final String directory;
  final _clock = Stopwatch();
  File? _file;
  Timer? _timer;
  int _generation = 0;
  bool recording = false,
      busy = false,
      ready = false,
      playing = false,
      _closed = false,
      _ownsCapture = false;
  Object? error;
  int get durationMs => _clock.elapsedMilliseconds;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> start() async {
    if (_closed || busy || recording) return;
    await cancel();
    final token = ++_generation;
    busy = true;
    error = null;
    _notify();
    try {
      await device.stopPlayback();
      await Directory(directory).create(recursive: true);
      if (token != _generation || _closed) return;
      _file = File('$directory/${const Uuid().v4()}.wav');
      _ownsCapture = true;
      await device.start(_file!.path);
      if (token != _generation || _closed) {
        await device.cancel();
        return;
      }
      recording = true;
      _clock.reset();
      _clock.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _notify();
        if (durationMs >= 30 * 60 * 1000) unawaited(stop());
      });
    } catch (e) {
      if (token == _generation && !_closed) {
        error = e;
        _ownsCapture = false;
        await _deleteTemporary();
      }
    } finally {
      if (token == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> stop() async {
    if (!recording || busy) return;
    final token = _generation;
    recording = false;
    busy = true;
    _timer?.cancel();
    _clock.stop();
    _notify();
    try {
      await device.stop();
      _ownsCapture = false;
      if (token != _generation || _closed) return;
      if (_file == null ||
          !await _file!.exists() ||
          await _file!.length() <= 44) {
        throw StateError('La grabación está vacía. Volvé a intentarlo.');
      }
      ready = true;
    } catch (e) {
      if (token == _generation && !_closed) error = e;
      await device.cancel();
      _ownsCapture = false;
    } finally {
      if (token == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<AudioAttachment?> commit() async {
    if (recording) await stop();
    if (!ready || _file == null || _closed) return null;
    final bytes = await _file!.readAsBytes();
    if (bytes.length <= 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Grabación inválida.');
    }
    final attachment = AudioAttachment(await assets.put(bytes), durationMs);
    await _deleteTemporary();
    ready = false;
    _notify();
    return attachment;
  }

  Future<void> preview() async {
    if (playing) {
      await device.stopPlayback();
      return;
    }
    if (!ready || _file == null) return;
    playing = true;
    _notify();
    try {
      await device.play(_file!.path);
    } catch (e) {
      error = e;
    } finally {
      playing = false;
      _notify();
    }
  }

  Future<void> _deleteTemporary() async {
    final file = _file;
    _file = null;
    if (file != null && await file.exists()) await file.delete();
  }

  Future<void> cancel() async {
    _generation++;
    _timer?.cancel();
    _clock.stop();
    if (_ownsCapture) {
      try {
        await device.cancel();
      } finally {
        _ownsCapture = false;
      }
    }
    if (playing) await device.stopPlayback();
    recording = false;
    busy = false;
    ready = false;
    playing = false;
    error = null;
    await _deleteTemporary();
    _notify();
  }

  Future<void> close() async {
    await cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (recording) {
        unawaited(
          stop().catchError((Object e) {
            error = e;
            _notify();
          }),
        );
      } else if (busy) {
        unawaited(
          cancel().catchError((Object e) {
            error = e;
            _notify();
          }),
        );
      }
      if (playing) {
        unawaited(
          device.stopPlayback().catchError((Object e) {
            error = e;
            _notify();
          }),
        );
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}

String audioDuration(int milliseconds) =>
    '${milliseconds ~/ 60000}:${((milliseconds ~/ 1000) % 60).toString().padLeft(2, '0')}';
