import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/audio/audio_service.dart';
import 'package:apuntes/audio/audio_comment_session.dart';
import 'package:apuntes/document/asset_store.dart';

// The microphone/speaker are external devices; use a deterministic WAV at that
// boundary while exercising real session lifecycle, files and hash storage.
class TestAudioDevice implements AudioDevice {
  bool denied = false, capturing = false;
  String? path;
  @override
  Future<void> start(String path) async {
    if (denied) throw const AudioPermissionDenied();
    this.path = path;
    capturing = true;
  }

  @override
  Future<void> stop() async {
    if (!capturing) return;
    capturing = false;
    final bytes = Uint8List(76)
      ..setRange(0, 4, 'RIFF'.codeUnits)
      ..setRange(8, 12, 'WAVE'.codeUnits);
    await File(path!).writeAsBytes(bytes);
  }

  @override
  Future<void> cancel() async {
    capturing = false;
  }

  @override
  Future<void> play(String path) async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> dispose() async {
    await cancel();
  }
}

class DelayedAudioDevice extends TestAudioDevice {
  final started = Completer<void>();
  final permission = Completer<void>();
  @override
  Future<void> start(String path) async {
    started.complete();
    await permission.future;
    await super.start(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive]) {
    test('el audio se detiene al pasar a $state en escritorio', () async {
      final root = await Directory.systemTemp.createTemp('nala-audio-hidden-');
      final device = TestAudioDevice();
      final session = AudioCommentSession(
        device: device,
        assets: FileAssetStore('${root.path}/assets'),
        directory: '${root.path}/temp',
      );
      try {
        await session.start();
        session.didChangeAppLifecycleState(state);
        expect(device.capturing, isFalse);
        expect(session.recording, isFalse);
      } finally {
        await session.close();
        session.dispose();
        await root.delete(recursive: true);
      }
    });
    test('una preparación tardía no graba después de $state', () async {
      final root = await Directory.systemTemp.createTemp(
        'nala-audio-hidden-start-',
      );
      final device = DelayedAudioDevice();
      final session = AudioCommentSession(
        device: device,
        assets: FileAssetStore('${root.path}/assets'),
        directory: '${root.path}/temp',
      );
      final start = session.start();
      await device.started.future;
      session.didChangeAppLifecycleState(state);
      device.permission.complete();
      await start;
      expect(device.capturing, isFalse);
      expect(await session.commit(), isNull);
      await session.close();
      session.dispose();
      await root.delete(recursive: true);
    });
  }
  test(
    'cerrar mientras se prepara el micrófono impide una captura tardía',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-audio-late-');
      final device = DelayedAudioDevice();
      final session = AudioCommentSession(
        device: device,
        assets: FileAssetStore('${root.path}/assets'),
        directory: '${root.path}/temp',
      );
      final starting = session.start();
      await device.started.future;
      session.dispose();
      device.permission.complete();
      await starting;
      expect(device.capturing, isFalse);
      expect(await Directory('${root.path}/assets').exists(), isFalse);
      await root.delete(recursive: true);
    },
  );
  test(
    'suspender detiene la captura y conserva una voz lista para guardar',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-audio-pause-');
      final device = TestAudioDevice();
      final session = AudioCommentSession(
        device: device,
        assets: FileAssetStore('${root.path}/assets'),
        directory: '${root.path}/temp',
      );
      await session.start();
      final ready = Completer<void>();
      session.addListener(() {
        if (session.ready && !ready.isCompleted) ready.complete();
      });
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      await ready.future.timeout(const Duration(seconds: 3));
      expect(device.capturing, isFalse);
      expect(session.recording, isFalse);
      expect(await session.commit(), isNotNull);
      await session.close();
      session.dispose();
      await root.delete(recursive: true);
    },
  );
  test('guardar voz usa un recurso por hash y elimina el temporal', () async {
    final root = await Directory.systemTemp.createTemp('nala-audio-test-');
    final device = TestAudioDevice();
    final assets = FileAssetStore('${root.path}/assets');
    final session = AudioCommentSession(
      device: device,
      assets: assets,
      directory: '${root.path}/temp',
    );
    await session.start();
    expect(session.recording, isTrue);
    await session.stop();
    final temporary = File(device.path!);
    expect(await temporary.exists(), isTrue);
    final attachment = await session.commit();
    expect(attachment, isNotNull);
    expect(await assets.read(attachment!.assetId), hasLength(76));
    expect(await temporary.exists(), isFalse);
    expect(device.capturing, isFalse);
    await session.close();
    session.dispose();
    await root.delete(recursive: true);
  });
  test(
    'cancelar y denegar permiso no crean audio ni dejan captura activa',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-audio-cancel-');
      final device = TestAudioDevice();
      final session = AudioCommentSession(
        device: device,
        assets: FileAssetStore('${root.path}/assets'),
        directory: '${root.path}/temp',
      );
      await session.start();
      await session.cancel();
      expect(device.capturing, isFalse);
      expect(await session.commit(), isNull);
      expect(await Directory('${root.path}/assets').exists(), isFalse);
      device.denied = true;
      await session.start();
      expect(session.error, isA<AudioPermissionDenied>());
      expect(session.recording, isFalse);
      expect(await session.commit(), isNull);
      await session.close();
      session.dispose();
      await root.delete(recursive: true);
    },
  );
}
