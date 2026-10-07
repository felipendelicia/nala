import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../document/asset_store.dart';
import '../document/notebook.dart';
import '../document/notebook_recording.dart';
import '../editor/editor_controller.dart';
import 'audio_service.dart';
import 'seek_audio_player.dart';

/// One explicit class recording per editor. Pending asynchronous microphone
/// starts are invalidated before losing focus, so they cannot capture later.
/// AppServices owns the shared device lifetime; this session stops only audio
/// that it started.
class NotebookAudioSession extends ChangeNotifier with WidgetsBindingObserver {
  NotebookAudioSession({
    required this.device,
    required this.assets,
    required this.directory,
    required this.controller,
    DateTime Function()? now,
    String Function()? newId,
  }) : now = now ?? DateTime.now,
       newId = newId ?? const Uuid().v4 {
    player = SeekAudioPlayer(
      device: device,
      assets: assets,
      directory: directory,
    );
    _lease = AudioDeviceLease(device);
    player.addListener(_notify);
    WidgetsBinding.instance.addObserver(this);
  }
  final AudioDevice device;
  final AssetStore assets;
  final String directory;
  final EditorController controller;
  final DateTime Function() now;
  final String Function() newId;
  late final SeekAudioPlayer player;
  late final AudioDeviceLease _lease;
  Timer? _timer;
  File? _file;
  DateTime? _startedAt;
  String? _recordingId;
  NotebookRecording? _pendingAttachment;
  Future<void>? _starting, _stopping, _cancelling;
  bool _recording = false,
      _busy = false,
      _closed = false,
      _ownsCapture = false,
      _pendingSave = false;
  int _generation = 0, _elapsedMs = 0;
  Object? _error;

  bool get recording => _recording;
  bool get busy => _busy;
  bool get pendingSave => _pendingSave;
  bool get playing => player.playing;
  String? get activePlaybackId => player.activeId;
  String? get activeRecordingId => recording ? _recordingId : null;
  Object? get error => _error ?? player.error;
  int get positionMs => _startedAt == null || !recording
      ? _elapsedMs
      : now().difference(_startedAt!).inMilliseconds.clamp(0, 0x7fffffff);
  int get durationMs => positionMs;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> start() {
    if (_closed || busy || recording || pendingSave) return Future.value();
    final operation = _start();
    _starting = operation;
    return operation.whenComplete(() {
      if (identical(_starting, operation)) _starting = null;
    });
  }

  Future<void> _start() async {
    final token = ++_generation;
    _busy = true;
    _error = null;
    player.error = null;
    _elapsedMs = 0;
    _notify();
    try {
      await player.stop();
      await Directory(directory).create(recursive: true);
      if (_closed || token != _generation) return;
      _recordingId = newId();
      _file = File('$directory/class-${const Uuid().v4()}.wav');
      await _lease.acquire(
        owner: this,
        releasePrevious: suspend,
        isCurrent: () => !_closed && token == _generation,
        activate: () async {
          _ownsCapture = true;
          await device.start(_file!.path);
          if (_closed || token != _generation) {
            if (_lease.owns(this)) await device.cancel();
            _ownsCapture = false;
            _lease.release(this);
            return;
          }
          _startedAt = now().toUtc();
          _recording = true;
          _timer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
        },
      );
    } catch (e) {
      if (token == _generation) _error = e;
      if (_ownsCapture && _lease.owns(this)) {
        try {
          await device.cancel();
        } catch (_) {}
      }
      _ownsCapture = false;
      _lease.release(this);
      await _deleteTemporary();
    } finally {
      if (token == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  InkStroke markStroke(InkStroke stroke) => !recording
      ? stroke
      : stroke.copyWith(
          audioRecordingId: _recordingId,
          audioOffsetMs: positionMs,
        );

  Future<void> stop() {
    if (_stopping != null) return _stopping!;
    if (!recording && !pendingSave) return Future.value();
    final operation = _stop();
    _stopping = operation;
    return operation.whenComplete(() {
      if (identical(_stopping, operation)) _stopping = null;
    });
  }

  Future<void> retrySave() => stop();

  Future<void> _stop() async {
    final token = _generation;
    final id = _recordingId!, createdAt = _startedAt!;
    final wasRecording = recording;
    _elapsedMs = positionMs;
    _recording = false;
    _busy = true;
    _error = null;
    _timer?.cancel();
    _notify();
    var persisted = false, recoverable = pendingSave;
    try {
      if (wasRecording && _lease.owns(this)) await device.stop();
      _ownsCapture = false;
      if (token != _generation) return;
      if (_file == null || !await _file!.exists()) {
        recoverable = false;
        throw const FormatException(
          'La grabación está vacía. Volvé a intentarlo.',
        );
      }
      // A filesystem read/write failure is recoverable. Only WAV validation
      // establishes that a stopped capture is invalid and may be discarded.
      recoverable = true;
      final bytes = await _file!.readAsBytes();
      final WavAudio wave;
      try {
        wave = WavAudio.parse(bytes);
      } on FormatException {
        recoverable = false;
        rethrow;
      }
      _elapsedMs = wave.durationMs;
      _pendingSave = true;
      var attachment = _pendingAttachment;
      if (attachment == null) {
        final assetId = await assets.put(bytes);
        if (token != _generation) return;
        attachment = NotebookRecording(
          id: id,
          title: 'Clase ${controller.notebook.recordings.length + 1}',
          assetId: assetId,
          durationMs: wave.durationMs,
          createdAt: createdAt,
        );
        _pendingAttachment = attachment;
      }
      if (token != _generation) return;
      if (controller.notebook.recordings.any((r) => r.id == id)) {
        await controller.retrySave();
      } else {
        await controller.apply(
          (n) => n.copyWith(recordings: [...n.recordings, attachment!]),
        );
      }
      if (controller.savingError != null) throw controller.savingError!;
      persisted = true;
      _pendingSave = false;
      _error = null;
    } catch (e) {
      if (token == _generation) {
        _error = e;
        _pendingSave = recoverable;
      }
      if (_ownsCapture && _lease.owns(this)) {
        try {
          await device.cancel();
          _ownsCapture = false;
        } catch (_) {}
      }
    } finally {
      if (persisted || !recoverable) {
        if (!persisted && token == _generation) await _unlink(id);
        await _deleteTemporary();
      }
      if (!_ownsCapture) _lease.release(this);
      if (token == _generation) {
        if (persisted || !recoverable) {
          _recordingId = null;
          _startedAt = null;
          _pendingAttachment = null;
          _pendingSave = false;
        }
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> _unlink(String id, {bool removeRecording = false}) async {
    if (!controller.notebook.pages.any(
          (p) => p.strokes.any((s) => s.audioRecordingId == id),
        ) &&
        !(removeRecording &&
            controller.notebook.recordings.any((r) => r.id == id))) {
      return;
    }
    await controller.apply(
      (n) => n.copyWith(
        recordings: removeRecording
            ? n.recordings.where((r) => r.id != id).toList()
            : n.recordings,
        pages: [
          for (final page in n.pages)
            page.copyWith(
              strokes: [
                for (final stroke in page.strokes)
                  if (stroke.audioRecordingId == id)
                    stroke.copyWith(audioRecordingId: null, audioOffsetMs: null)
                  else
                    stroke,
              ],
            ),
        ],
      ),
    );
  }

  Future<void> cancel() {
    if (_cancelling != null) return _cancelling!;
    final operation = _cancel();
    _cancelling = operation;
    return operation.whenComplete(() {
      if (identical(_cancelling, operation)) _cancelling = null;
    });
  }

  Future<void> _cancel() async {
    _generation++;
    final starting = _starting, stopping = _stopping, id = _recordingId;
    final discardPending = pendingSave;
    _elapsedMs = positionMs;
    _recording = false;
    _busy = true;
    _timer?.cancel();
    try {
      if (stopping != null) await stopping;
      if (_ownsCapture && _lease.owns(this)) await device.cancel();
      await starting;
      _ownsCapture = false;
      await player.stop();
      if (id != null &&
          (discardPending ||
              !controller.notebook.recordings.any((r) => r.id == id))) {
        await _unlink(id, removeRecording: discardPending);
      }
      _error = null;
    } catch (e) {
      _error = e;
    } finally {
      await _deleteTemporary();
      if (!_ownsCapture) _lease.release(this);
      _recordingId = null;
      _startedAt = null;
      _pendingAttachment = null;
      _pendingSave = false;
      _busy = false;
      _notify();
    }
  }

  /// Call before switching the active document, closing the editor or exiting.
  Future<void> suspend() async {
    if (_cancelling != null) {
      await _cancelling;
    } else if (recording || _stopping != null || pendingSave) {
      await stop();
    } else if (_starting != null || _ownsCapture) {
      await cancel();
    }
    await player.stop();
    if (pendingSave) {
      throw StateError(
        'La grabación sigue pendiente. Reintentá guardarla o descartala antes de cerrar.',
      );
    }
  }

  Future<void> playStroke(InkStroke stroke) async {
    final recording = controller.notebook.recordings
        .where((r) => r.id == stroke.audioRecordingId)
        .firstOrNull;
    if (recording != null) {
      await playRecording(recording, offsetMs: stroke.audioOffsetMs ?? 0);
    }
  }

  Future<void> playRecording(
    NotebookRecording recording, {
    int offsetMs = 0,
  }) async {
    if (_closed || busy || this.recording) return;
    _error = null;
    await player.play(
      recording.assetId,
      offsetMs: offsetMs,
      recordingId: recording.id,
    );
    _notify();
  }

  Future<void> stopPlayback() => player.stop();

  Future<void> _deleteTemporary() async {
    final file = _file;
    _file = null;
    try {
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      _error ??= e;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (audioLeavesForeground(state)) {
      unawaited(
        suspend().catchError((Object e) {
          _error = e;
          _notify();
        }),
      );
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    final finishing = suspend();
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(_notify);
    unawaited(finishing.whenComplete(player.dispose).catchError((Object _) {}));
    super.dispose();
  }
}
