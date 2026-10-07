import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/audio/audio_service.dart';
import 'package:apuntes/audio/notebook_audio_session.dart';
import 'package:apuntes/audio/seek_audio_player.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

Uint8List pcmWav({int frames = 1000}) {
  final bytes = Uint8List(44 + frames * 2);
  final header = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
  bytes.setRange(36, 40, 'data'.codeUnits);
  header
    ..setUint32(4, bytes.length - 8, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 1000, Endian.little)
    ..setUint32(28, 2000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, frames * 2, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    header.setInt16(44 + frame * 2, frame, Endian.little);
  }
  return bytes;
}

// The only fake boundary is the microphone/speaker. Documents, timelines,
// temporary WAV files, hash storage and repository writes are real.
class TimelineAudioDevice implements AudioDevice {
  String? capturePath;
  bool capturing = false, denied = false, externalPlaybackActive = false;
  Completer<void>? startGate;
  Completer<void>? stopGate;
  bool corruptOutput = false;
  final startEntered = Completer<void>();
  final secondStartEntered = Completer<void>();
  int starts = 0;
  Uint8List? playedBytes;
  String? playedPath;
  Completer<void>? playback;

  @override
  Future<void> start(String path) async {
    starts++;
    if (starts == 2) secondStartEntered.complete();
    if (!startEntered.isCompleted) startEntered.complete();
    if (startGate != null) await startGate!.future;
    if (denied) throw const AudioPermissionDenied();
    capturePath = path;
    capturing = true;
  }

  @override
  Future<void> stop() async {
    if (!capturing) return;
    capturing = false;
    if (stopGate != null) await stopGate!.future;
    await File(
      capturePath!,
    ).writeAsBytes(corruptOutput ? Uint8List(44) : pcmWav());
  }

  @override
  Future<void> cancel() async => capturing = false;

  @override
  Future<void> play(String path) async {
    playedPath = path;
    playedBytes = await File(path).readAsBytes();
    if (playback != null) await playback!.future;
  }

  @override
  Future<void> stopPlayback() async {
    externalPlaybackActive = false;
    if (playback != null && !playback!.isCompleted) playback!.complete();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await stopPlayback();
  }
}

class PausableRepository extends MemoryRepository {
  bool paused = false;
  final committing = Completer<void>(), release = Completer<void>();
  @override
  Future<void> commit(Revision revision) async {
    if (paused) {
      if (!committing.isCompleted) committing.complete();
      await release.future;
    }
    await super.commit(revision);
  }
}

class RejectingAssets extends MemoryAssets {
  bool reject = true;
  @override
  Future<String> put(Uint8List bytes) async {
    if (reject) throw const FileSystemException('Almacenamiento sin espacio.');
    return super.put(bytes);
  }
}

class RejectingRepository extends MemoryRepository {
  bool reject = false;
  @override
  Future<void> commit(Revision revision) async {
    if (reject) {
      throw const FileSystemException('No se pudo guardar el cuaderno.');
    }
    await super.commit(revision);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WAV seek keeps complete frames and does not alter the original', () {
    final original = pcmWav();
    final wave = WavAudio.parse(original);
    final tail = wave.seek(250);
    expect(wave.durationMs, 1000);
    expect(tail.length, 1544);
    expect(ByteData.sublistView(tail).getUint32(40, Endian.little), 1500);
    expect(ByteData.sublistView(tail).getInt16(44, Endian.little), 250);
    expect(ByteData.sublistView(original).getInt16(44, Endian.little), 0);
    expect(original.length, 2044);
    expect(() => wave.seek(-1), throwsRangeError);
    expect(() => wave.seek(1000), throwsRangeError);
  });

  test('WAV validation rejects truncated chunks and inconsistent PCM', () {
    final truncated = pcmWav().sublist(0, 100);
    expect(() => WavAudio.parse(truncated), throwsFormatException);
    final invalid = pcmWav();
    ByteData.sublistView(invalid).setUint16(32, 3, Endian.little);
    expect(() => WavAudio.parse(invalid), throwsFormatException);
  });

  test(
    'storage failure retains valid stopped WAV and timeline links and blocks closing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nala-preserve-audio-',
      );
      final assets = RejectingAssets();
      var revision = 0;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision-${revision++}',
        now: DateTime.now,
      );
      final device = TimelineAudioDevice();
      final session = NotebookAudioSession(
        device: device,
        assets: assets,
        directory: root.path,
        controller: controller,
        newId: () => 'class-retained',
      );
      try {
        await session.start();
        final marked = session.markStroke(fixtureStroke());
        await controller.apply(
          (n) => n.copyWith(
            pages: [
              n.pages.single.copyWith(strokes: [marked]),
            ],
          ),
        );
        await session.stop();
        expect(await File(device.capturePath!).exists(), isTrue);
        expect(await File(device.capturePath!).readAsBytes(), pcmWav());
        expect(
          controller.notebook.pages.single.strokes.single.audioRecordingId,
          'class-retained',
        );
        expect(session.error, isA<FileSystemException>());
        expect(controller.notebook.recordings, isEmpty);
        await expectLater(session.suspend(), throwsStateError);
        await session.start();
        expect(device.starts, 1);
        expect(session.pendingSave, isTrue);
        assets.reject = false;
        await session.retrySave();
        expect(session.pendingSave, isFalse);
        expect(session.error, isNull);
        expect(controller.notebook.recordings.single.id, 'class-retained');
        expect(
          controller.notebook.pages.single.strokes.single.audioRecordingId,
          'class-retained',
        );
        expect(await File(device.capturePath!).exists(), isFalse);
      } finally {
        await session.cancel();
        session.dispose();
        controller.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'explicit discard after failed storage removes retained WAV and its ink links',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-discard-audio-');
      var revision = 0;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision-${revision++}',
        now: DateTime.now,
      );
      final device = TimelineAudioDevice();
      final session = NotebookAudioSession(
        device: device,
        assets: RejectingAssets(),
        directory: root.path,
        controller: controller,
      );
      try {
        await session.start();
        final marked = session.markStroke(fixtureStroke());
        await controller.apply(
          (n) => n.copyWith(
            pages: [
              n.pages.single.copyWith(strokes: [marked]),
            ],
          ),
        );
        await session.stop();
        expect(await File(device.capturePath!).exists(), isTrue);
        await session.cancel();
        expect(await File(device.capturePath!).exists(), isFalse);
        expect(
          controller.notebook.pages.single.strokes.single.audioRecordingId,
          isNull,
        );
        await session.suspend();
      } finally {
        await session.cancel();
        session.dispose();
        controller.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'repository failure keeps recoverable audio and retry saves one recording',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nala-retry-repository-audio-',
      );
      final repository = RejectingRepository();
      var revision = 0;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: repository,
        deviceId: 'test',
        newId: () => 'revision-${revision++}',
        now: DateTime.now,
      );
      final device = TimelineAudioDevice();
      final session = NotebookAudioSession(
        device: device,
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
        newId: () => 'class-once',
      );
      try {
        await session.start();
        final marked = session.markStroke(fixtureStroke());
        await controller.apply(
          (n) => n.copyWith(
            pages: [
              n.pages.single.copyWith(strokes: [marked]),
            ],
          ),
        );
        repository.reject = true;
        await session.stop();
        expect(session.pendingSave, isTrue);
        expect(await File(device.capturePath!).exists(), isTrue);
        expect(controller.notebook.recordings, hasLength(1));
        await expectLater(session.suspend(), throwsStateError);
        expect(controller.notebook.recordings, hasLength(1));
        repository.reject = false;
        await session.retrySave();
        final saved = (await repository.load(controller.notebook.id))!;
        expect(saved.recordings.single.id, 'class-once');
        expect(
          saved.pages.single.strokes.single.audioRecordingId,
          'class-once',
        );
        expect(session.pendingSave, isFalse);
        expect(await File(device.capturePath!).exists(), isFalse);
      } finally {
        repository.reject = false;
        await session.cancel();
        session.dispose();
        controller.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('recording is explicit and stroke timestamps survive saving', () async {
    final root = await Directory.systemTemp.createTemp('nala-timeline-');
    final repository = MemoryRepository();
    final assets = FileAssetStore('${root.path}/assets');
    var time = DateTime.utc(2026, 10, 7, 12);
    var revision = 0;
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: repository,
      deviceId: 'test',
      newId: () => 'revision-${revision++}',
      now: () => time,
    );
    final device = TimelineAudioDevice();
    final session = NotebookAudioSession(
      device: device,
      assets: assets,
      directory: '${root.path}/temp',
      controller: controller,
      now: () => time,
      newId: () => 'class-1',
    );
    try {
      expect(device.capturing, isFalse);
      expect(session.markStroke(fixtureStroke()).audioRecordingId, isNull);
      await session.start();
      time = time.add(const Duration(milliseconds: 250));
      final marked = session.markStroke(fixtureStroke());
      expect(marked.audioRecordingId, 'class-1');
      expect(marked.audioOffsetMs, 250);
      await controller.apply(
        (n) => n.copyWith(
          pages: [
            n.pages.single.copyWith(strokes: [marked]),
          ],
        ),
      );
      await session.suspend();
      final saved = (await repository.load(controller.notebook.id))!;
      expect(saved.recordings.single.id, 'class-1');
      expect(saved.recordings.single.durationMs, 1000);
      expect(saved.pages.single.strokes.single.audioOffsetMs, 250);
      expect(await assets.read(saved.recordings.single.assetId), pcmWav());
      expect(await File(device.capturePath!).exists(), isFalse);
      await session.playStroke(marked);
      expect(
        ByteData.sublistView(device.playedBytes!).getInt16(44, Endian.little),
        250,
      );
      expect(await File(device.playedPath!).exists(), isFalse);
    } finally {
      await session.suspend();
      session.dispose();
      controller.dispose();
      await root.delete(recursive: true);
    }
  });

  test('suspending a pending start prevents late microphone capture', () async {
    final root = await Directory.systemTemp.createTemp('nala-late-timeline-');
    final repository = MemoryRepository();
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: repository,
      deviceId: 'test',
      newId: () => 'revision',
      now: DateTime.now,
    );
    final device = TimelineAudioDevice()..startGate = Completer<void>();
    final session = NotebookAudioSession(
      device: device,
      assets: MemoryAssets(),
      directory: root.path,
      controller: controller,
    );
    final starting = session.start();
    await device.startEntered.future;
    final suspending = session.suspend();
    device.startGate!.complete();
    await Future.wait([starting, suspending]);
    expect(session.recording, isFalse);
    expect(device.capturing, isFalse);
    expect(controller.notebook.recordings, isEmpty);
    session.dispose();
    controller.dispose();
    await root.delete(recursive: true);
  });

  test(
    'background lifecycle finishes and persists an active recording',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nala-background-class-',
      );
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision',
        now: DateTime.now,
      );
      final session = NotebookAudioSession(
        device: TimelineAudioDevice(),
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
      );
      await session.start();
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      await session.suspend();
      expect(controller.notebook.recordings, hasLength(1));
      expect(session.recording, isFalse);
      session.dispose();
      controller.dispose();
      await root.delete(recursive: true);
    },
  );

  test(
    'permission denial and cancellation leave no notebook attachment',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-denied-class-');
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision',
        now: DateTime.now,
      );
      final device = TimelineAudioDevice()..denied = true;
      final session = NotebookAudioSession(
        device: device,
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
      );
      await session.start();
      expect(session.error, isA<AudioPermissionDenied>());
      device.denied = false;
      await session.start();
      await session.cancel();
      expect(controller.notebook.recordings, isEmpty);
      expect(await root.list().toList(), isEmpty);
      session.dispose();
      controller.dispose();
      await root.delete(recursive: true);
    },
  );

  test(
    'cancel removes timeline links instead of leaving an absent recording',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-unlink-class-');
      var id = 0;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision-${id++}',
        now: DateTime.now,
      );
      final session = NotebookAudioSession(
        device: TimelineAudioDevice(),
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
      );
      await session.start();
      final marked = session.markStroke(fixtureStroke());
      await controller.apply(
        (n) => n.copyWith(
          pages: [
            n.pages.single.copyWith(strokes: [marked]),
          ],
        ),
      );
      await session.cancel();
      expect(
        controller.notebook.pages.single.strokes.single.audioRecordingId,
        isNull,
      );
      expect(
        controller.notebook.pages.single.strokes.single.audioOffsetMs,
        isNull,
      );
      session.dispose();
      controller.dispose();
      await root.delete(recursive: true);
    },
  );

  test(
    'dispose finishes active recording before releasing the device',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-dispose-class-');
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision',
        now: DateTime.now,
      );
      final session = NotebookAudioSession(
        device: TimelineAudioDevice(),
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
      );
      await session.start();
      session.dispose();
      await session.suspend();
      expect(controller.notebook.recordings, hasLength(1));
      controller.dispose();
      await root.delete(recursive: true);
    },
  );

  test(
    'failed stop finishing after dispose cleans files without notifying a closed session',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nala-failed-dispose-',
      );
      var id = 0;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision-${id++}',
        now: DateTime.now,
      );
      final device = TimelineAudioDevice()
        ..corruptOutput = true
        ..stopGate = Completer<void>();
      final session = NotebookAudioSession(
        device: device,
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
      );
      await session.start();
      final marked = session.markStroke(fixtureStroke());
      await controller.apply(
        (n) => n.copyWith(
          pages: [
            n.pages.single.copyWith(strokes: [marked]),
          ],
        ),
      );
      var notifiedAfterClose = false, closed = false;
      session.addListener(() {
        if (closed) notifiedAfterClose = true;
      });
      final stopping = session.stop();
      session.dispose();
      closed = true;
      device.stopGate!.complete();
      await stopping;
      await session.suspend();
      expect(session.error, isA<FormatException>());
      expect(notifiedAfterClose, isFalse);
      expect(controller.notebook.recordings, isEmpty);
      expect(
        controller.notebook.pages.single.strokes.single.audioRecordingId,
        isNull,
      );
      expect(await root.list().toList(), isEmpty);
      controller.dispose();
      await root.delete(recursive: true);
    },
  );

  test('stopping seek playback removes its temporary WAV', () async {
    final root = await Directory.systemTemp.createTemp('nala-seek-clean-');
    final assets = MemoryAssets();
    final id = await assets.put(pcmWav());
    final device = TimelineAudioDevice()..playback = Completer<void>();
    final player = SeekAudioPlayer(
      device: device,
      assets: assets,
      directory: root.path,
    );
    final playing = player.play(id, offsetMs: 250);
    while (device.playedBytes == null) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(player.playing, isTrue);
    await player.stop();
    await playing;
    expect(player.playing, isFalse);
    expect(await root.list().toList(), isEmpty);
    expect((await assets.read(id)).length, 2044);
    player.dispose();
    await root.delete(recursive: true);
  });

  test(
    'idle session suspend and dispose preserve another panel audio ownership',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-shared-device-');
      final device = TimelineAudioDevice()
        ..capturing = true
        ..externalPlaybackActive = true;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision',
        now: DateTime.now,
      );
      final session = NotebookAudioSession(
        device: device,
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
      );
      await session.suspend();
      expect(device.externalPlaybackActive, isTrue);
      expect(device.capturing, isTrue);
      session.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(device.externalPlaybackActive, isTrue);
      expect(device.capturing, isTrue);
      controller.dispose();
      await root.delete(recursive: true);
    },
  );

  test(
    'overlapping cancellations keep capture unavailable until pending ink save completes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nala-overlap-cancel-',
      );
      final repository = PausableRepository();
      var id = 0;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: repository,
        deviceId: 'test',
        newId: () => 'revision-${id++}',
        now: DateTime.now,
      );
      final session = NotebookAudioSession(
        device: TimelineAudioDevice(),
        assets: MemoryAssets(),
        directory: root.path,
        controller: controller,
      );
      await session.start();
      final marked = session.markStroke(fixtureStroke());
      await controller.apply(
        (n) => n.copyWith(
          pages: [
            n.pages.single.copyWith(strokes: [marked]),
          ],
        ),
      );
      repository.paused = true;
      final first = session.cancel();
      await repository.committing.future;
      var secondFinished = false;
      final second = session.cancel().then((_) => secondFinished = true);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(session.busy, isTrue);
        expect(secondFinished, isFalse);
      } finally {
        repository.release.complete();
        await Future.wait([first, second]);
        await session.suspend();
        session.dispose();
        controller.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'incoming capture waits for outgoing failed stop before taking the shared microphone',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-audio-handoff-');
      final device = TimelineAudioDevice()
        ..corruptOutput = true
        ..stopGate = Completer<void>();
      EditorController controller(String name) => EditorController(
        notebook: fixtureNotebook(id: name),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'revision',
        now: DateTime.now,
      );
      final firstController = controller('first'),
          secondController = controller('second');
      final first = NotebookAudioSession(
        device: device,
        assets: MemoryAssets(),
        directory: '${root.path}/first',
        controller: firstController,
      );
      final second = NotebookAudioSession(
        device: device,
        assets: MemoryAssets(),
        directory: '${root.path}/second',
        controller: secondController,
      );
      await first.start();
      final outgoing = first.suspend();
      final incoming = second.start();
      await Future.any([
        device.secondStartEntered.future,
        Future<void>.delayed(const Duration(milliseconds: 30)),
      ]);
      try {
        expect(second.recording, isFalse);
        expect(device.starts, 1);
      } finally {
        device.stopGate!.complete();
        await Future.wait([outgoing, incoming]);
      }
      expect(second.recording, isTrue);
      expect(device.capturing, isTrue);
      device.corruptOutput = false;
      await second.suspend();
      first.dispose();
      second.dispose();
      firstController.dispose();
      secondController.dispose();
      await root.delete(recursive: true);
    },
  );
}
