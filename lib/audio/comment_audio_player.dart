import 'seek_audio_player.dart';

/// Voice comments share ownership and temporary-WAV cleanup with class audio.
class CommentAudioPlayer extends SeekAudioPlayer {
  CommentAudioPlayer({
    required super.device,
    required super.assets,
    required super.directory,
  });

  @override
  Future<void> play(String assetId, {int offsetMs = 0, String? recordingId}) {
    if (activeId == (recordingId ?? assetId)) return stop();
    return super.play(assetId, offsetMs: offsetMs, recordingId: recordingId);
  }
}
