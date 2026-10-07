import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/audio/audio_service.dart';
import 'package:apuntes/audio/comment_audio_player.dart';
import '../support/memory_repository.dart';
import 'notebook_audio_test.dart' show TimelineAudioDevice, pcmWav;

class SharedDevice implements AudioDevice {
  int stops = 0;
  @override
  Future<void> stopPlayback() async {
    stops++;
  }

  @override
  Future<void> start(String path) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> play(String path) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an idle comment player cannot stop another pane audio', () async {
    final device = SharedDevice();
    final player = CommentAudioPlayer(
      device: device,
      assets: MemoryAssets(),
      directory: '/unused',
    );
    await player.stop();
    player.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(device.stops, 0);
  });

  test(
    'comment playback still toggles off and removes its temporary WAV',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-comment-play-');
      final assets = MemoryAssets();
      final id = await assets.put(pcmWav());
      final device = TimelineAudioDevice()..playback = Completer<void>();
      final player = CommentAudioPlayer(
        device: device,
        assets: assets,
        directory: root.path,
      );
      final first = player.play(id);
      while (device.playedBytes == null) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(player.activeId, id);
      await player.play(id);
      await first;
      expect(player.activeId, isNull);
      expect(await root.list().toList(), isEmpty);
      expect(await assets.read(id), pcmWav());
      player.dispose();
      await root.delete(recursive: true);
    },
  );
}
