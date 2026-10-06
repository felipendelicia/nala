import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

bool audioLeavesForeground(AppLifecycleState state) =>
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached ||
    state == AppLifecycleState.hidden ||
    (Platform.isLinux && state == AppLifecycleState.inactive);

class AudioPermissionDenied implements Exception {
  const AudioPermissionDenied();
  @override
  String toString() =>
      'Necesitás permitir el micrófono para grabar una nota de voz.';
}

abstract interface class AudioDevice {
  Future<void> start(String path);
  Future<void> stop();
  Future<void> cancel();
  Future<void> play(String path);
  Future<void> stopPlayback();
  Future<void> dispose();
}

AudioDevice nativeAudioDevice() =>
    Platform.isAndroid ? AndroidAudioDevice() : LinuxAudioDevice();

class AndroidAudioDevice implements AudioDevice {
  static const channel = MethodChannel('nala/audio');
  @override
  Future<void> start(String path) async {
    try {
      await channel.invokeMethod<void>('start', {'path': path});
    } on PlatformException catch (e) {
      if (e.code == 'MIC_PERMISSION_DENIED') {
        throw const AudioPermissionDenied();
      }
      rethrow;
    }
  }

  @override
  Future<void> stop() => channel.invokeMethod<void>('stop');
  @override
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
  @override
  Future<void> play(String path) =>
      channel.invokeMethod<void>('play', {'path': path});
  @override
  Future<void> stopPlayback() => channel.invokeMethod<void>('stopPlayback');
  @override
  Future<void> dispose() async {
    await cancel();
    await stopPlayback();
  }
}

class LinuxAudioDevice implements AudioDevice {
  Process? _capture, _playback;
  bool _starting = false;
  int _generation = 0;
  int _playbackGeneration = 0;
  Future<int>? _captureExit;
  int? _captureFailure;
  String? _command(String preferred, String fallback) {
    for (final name in [preferred, fallback]) {
      for (final dir in (Platform.environment['PATH'] ?? '/usr/bin:/bin').split(
        ':',
      )) {
        final file = File('$dir/$name');
        if (file.existsSync()) return file.path;
      }
    }
    return null;
  }

  @override
  Future<void> start(String path) async {
    if (_capture != null || _starting) {
      throw StateError('Ya hay una grabación en curso.');
    }
    final command = _command('pw-record', 'arecord');
    if (command == null) {
      throw StateError(
        'No hay un grabador disponible. Se necesitan las herramientas de audio de PipeWire o ALSA.',
      );
    }
    _starting = true;
    final token = ++_generation;
    try {
      await stopPlayback();
      if (token != _generation) throw StateError('Grabación cancelada.');
      final process = await Process.start(Platform.resolvedExecutable, [
        '--nala-audio-helper',
        command,
        ...command.endsWith('pw-record')
            ? ['--rate', '16000', '--channels', '1', '--format', 's16', path]
            : ['-f', 'S16_LE', '-r', '16000', '-c', '1', '-t', 'wav', path],
      ]);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      if (token != _generation) {
        await _end(process);
        throw StateError('Grabación cancelada.');
      }
      _capture = process;
      _captureFailure = null;
      _captureExit = process.exitCode.then((code) {
        if (token == _generation && code != 0 && code != 130) {
          _captureFailure = code;
        }
        return code;
      });
      final exited = await Future.any<int?>([
        _captureExit!,
        Future<int?>.delayed(const Duration(milliseconds: 150), () => null),
      ]);
      if (exited != null) {
        _capture = null;
        throw StateError(
          'No se pudo acceder al micrófono. Revisá el dispositivo de entrada.',
        );
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _end(Process? process) async {
    if (process == null) return;
    process.kill(ProcessSignal.sigint);
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      throw StateError('No se pudo cerrar la grabación correctamente.');
    }
  }

  @override
  Future<void> stop() async {
    final process = _capture;
    _capture = null;
    await _end(process);
    if (_captureFailure != null) {
      throw StateError('La grabación se interrumpió. Revisá el micrófono.');
    }
  }

  @override
  Future<void> cancel() async {
    _generation++;
    final process = _capture;
    _capture = null;
    await _end(process);
  }

  @override
  Future<void> play(String path) async {
    if (_capture != null || _starting) {
      throw StateError('Terminá la grabación antes de escuchar.');
    }
    await stopPlayback();
    final command = _command('pw-play', 'aplay');
    if (command == null) {
      throw StateError('No hay un reproductor de audio disponible.');
    }
    final token = ++_playbackGeneration;
    final process = await Process.start(Platform.resolvedExecutable, [
      '--nala-audio-helper',
      command,
      path,
    ]);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    if (token != _playbackGeneration) {
      await _end(process);
      return;
    }
    _playback = process;
    final code = await process.exitCode;
    if (identical(_playback, process)) {
      _playback = null;
      if (code != 0) throw StateError('No se pudo reproducir la nota de voz.');
    }
  }

  @override
  Future<void> stopPlayback() async {
    _playbackGeneration++;
    final process = _playback;
    _playback = null;
    await _end(process);
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await stopPlayback();
  }
}
