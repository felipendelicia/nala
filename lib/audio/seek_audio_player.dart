import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../document/asset_store.dart';
import 'audio_service.dart';

/// Coordinates transitions on one native device across editor panes. The queue
/// covers acquisition/start only, never the duration of a recording or playback.
class AudioDeviceLease {
  AudioDeviceLease(AudioDevice device)
    : _state = _states[device] ??= _AudioDeviceLeaseState();
  static final _states = Expando<_AudioDeviceLeaseState>();
  final _AudioDeviceLeaseState _state;

  bool owns(Object owner) => identical(_state.owner, owner);
  void release(Object owner) {
    if (!owns(owner)) return;
    _state.owner = null;
    _state.releasePrevious = null;
  }

  Future<void> acquire({
    required Object owner,
    required Future<void> Function() releasePrevious,
    required bool Function() isCurrent,
    required Future<void> Function() activate,
  }) {
    final operation = _state.tail.then((_) async {
      if (!isCurrent()) return;
      final previous = _state.owner;
      if (previous != null && !identical(previous, owner)) {
        await _state.releasePrevious!();
        if (identical(_state.owner, previous)) {
          throw StateError('No se pudo detener el audio del panel anterior.');
        }
      }
      if (!isCurrent()) return;
      _state.owner = owner;
      _state.releasePrevious = releasePrevious;
      await activate();
    });
    _state.tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}

class _AudioDeviceLeaseState {
  Object? owner;
  Future<void> Function()? releasePrevious;
  Future<void> tail = Future.value();
}

/// Validated, uncompressed WAV audio. Seeking produces a separate WAV with
/// whole sample frames; the content-addressed original is never rewritten.
class WavAudio {
  WavAudio._(this._format, this._samples, this._sampleRate, this._frameSize);
  final Uint8List _format, _samples;
  final int _sampleRate, _frameSize;

  int get durationMs => _samples.length * 1000 ~/ (_sampleRate * _frameSize);

  factory WavAudio.parse(Uint8List bytes) {
    const invalid = FormatException('El recurso no contiene audio WAV válido.');
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw invalid;
    }
    final header = ByteData.sublistView(bytes);
    final end = header.getUint32(4, Endian.little) + 8;
    if (end != bytes.length) throw invalid;
    Uint8List? format, samples;
    var cursor = 12;
    while (cursor < end) {
      if (cursor + 8 > end) throw invalid;
      final kind = String.fromCharCodes(bytes.sublist(cursor, cursor + 4));
      final size = header.getUint32(cursor + 4, Endian.little);
      final start = cursor + 8, next = start + size + (size.isOdd ? 1 : 0);
      if (next > end) throw invalid;
      if (kind == 'fmt ') {
        if (format != null || size < 16) throw invalid;
        format = Uint8List.fromList(bytes.sublist(start, start + size));
      } else if (kind == 'data') {
        if (samples != null || size == 0) throw invalid;
        samples = Uint8List.fromList(bytes.sublist(start, start + size));
      }
      cursor = next;
    }
    if (format == null || samples == null) throw invalid;
    final fmt = ByteData.sublistView(format);
    final encoding = fmt.getUint16(0, Endian.little);
    final channels = fmt.getUint16(2, Endian.little);
    final rate = fmt.getUint32(4, Endian.little);
    final byteRate = fmt.getUint32(8, Endian.little);
    final frameSize = fmt.getUint16(12, Endian.little);
    final bits = fmt.getUint16(14, Endian.little);
    if ((encoding != 1 && encoding != 3) ||
        channels == 0 ||
        rate == 0 ||
        frameSize == 0 ||
        (encoding == 1 && ![8, 16, 24, 32].contains(bits)) ||
        (encoding == 3 && ![32, 64].contains(bits)) ||
        frameSize != channels * bits ~/ 8 ||
        byteRate != rate * frameSize ||
        samples.length % frameSize != 0) {
      throw invalid;
    }
    return WavAudio._(format, samples, rate, frameSize);
  }

  Uint8List seek(int offsetMs) {
    final totalFrames = _samples.length ~/ _frameSize;
    final firstFrame = offsetMs * _sampleRate ~/ 1000;
    if (offsetMs < 0 || firstFrame >= totalFrames) {
      throw RangeError('No hay audio en esa posición de la grabación.');
    }
    final data = _samples.sublist(firstFrame * _frameSize);
    final formatPadding = _format.length.isOdd ? 1 : 0;
    final dataPadding = data.length.isOdd ? 1 : 0;
    final dataStart = 28 + _format.length + formatPadding;
    final result = Uint8List(dataStart + data.length + dataPadding);
    final header = ByteData.sublistView(result);
    result.setRange(0, 4, 'RIFF'.codeUnits);
    result.setRange(8, 16, 'WAVEfmt '.codeUnits);
    header
      ..setUint32(4, result.length - 8, Endian.little)
      ..setUint32(16, _format.length, Endian.little);
    result.setRange(20, 20 + _format.length, _format);
    result.setRange(dataStart - 8, dataStart - 4, 'data'.codeUnits);
    header.setUint32(dataStart - 4, data.length, Endian.little);
    result.setRange(dataStart, dataStart + data.length, data);
    return result;
  }
}

class SeekAudioPlayer extends ChangeNotifier with WidgetsBindingObserver {
  SeekAudioPlayer({
    required this.device,
    required this.assets,
    required this.directory,
  }) {
    _lease = AudioDeviceLease(device);
    WidgetsBinding.instance.addObserver(this);
  }
  final AudioDevice device;
  final AssetStore assets;
  final String directory;
  late final AudioDeviceLease _lease;
  Object? _leaseOwner;
  String? activeId;
  Object? error;
  bool _closed = false;
  int _generation = 0;
  int? _playbackOwner;
  Future<void>? _playback;
  Future<void>? _stopping;
  bool get playing => activeId != null;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> play(
    String assetId, {
    int offsetMs = 0,
    String? recordingId,
  }) async {
    if (_closed) return;
    await stop();
    if (_closed) return;
    final token = ++_generation;
    activeId = recordingId ?? assetId;
    error = null;
    _notify();
    final operation = _play(assetId, offsetMs, token);
    _playback = operation;
    await operation;
    if (identical(_playback, operation)) _playback = null;
  }

  Future<void> _play(String assetId, int offsetMs, int token) async {
    File? file;
    final owner = Object();
    try {
      final bytes = WavAudio.parse(await assets.read(assetId)).seek(offsetMs);
      if (_closed || token != _generation) return;
      await Directory(directory).create(recursive: true);
      if (_closed || token != _generation) return;
      file = File('$directory/seek-${const Uuid().v4()}.wav');
      await file.writeAsBytes(bytes, flush: true);
      if (_closed || token != _generation) return;
      Future<void>? nativePlayback;
      await _lease.acquire(
        owner: owner,
        releasePrevious: stop,
        isCurrent: () => !_closed && token == _generation,
        activate: () async {
          _leaseOwner = owner;
          _playbackOwner = token;
          nativePlayback = device.play(file!.path);
        },
      );
      await nativePlayback;
    } catch (e) {
      if (token == _generation) error = e;
    } finally {
      if (_playbackOwner == token) _playbackOwner = null;
      if (identical(_leaseOwner, owner)) _leaseOwner = null;
      _lease.release(owner);
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (e) {
        if (token == _generation) error ??= e;
      }
      if (token == _generation) {
        activeId = null;
        _notify();
      }
    }
  }

  Future<void> stop() {
    if (_stopping != null) return _stopping!;
    final operation = _stop();
    _stopping = operation;
    return operation.whenComplete(() {
      if (identical(_stopping, operation)) _stopping = null;
    });
  }

  Future<void> _stop() async {
    _generation++;
    final previous = _playback;
    final owner = _leaseOwner;
    activeId = null;
    try {
      // The native device is shared across editor panes. An idle player must
      // never stop playback belonging to another pane or a voice comment.
      if (_playbackOwner != null && owner != null && _lease.owns(owner)) {
        await device.stopPlayback();
        _playbackOwner = null;
      }
      await previous;
      if (owner != null) _lease.release(owner);
    } catch (e) {
      error = e;
    }
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (audioLeavesForeground(state)) unawaited(stop());
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop());
    super.dispose();
  }
}
