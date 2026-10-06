import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import '../document/asset_store.dart';
import 'audio_service.dart';

class CommentAudioPlayer extends ChangeNotifier with WidgetsBindingObserver {
  CommentAudioPlayer({
    required this.device,
    required this.assets,
    required this.directory,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }
  final AudioDevice device;
  final AssetStore assets;
  final String directory;
  String? activeId;
  Object? error;
  int _generation = 0;
  bool _closed = false;
  final _files = <File>{};
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> play(String id) async {
    if (_closed) return;
    if (activeId == id) {
      await stop();
      return;
    }
    await stop();
    final token = ++_generation;
    activeId = id;
    error = null;
    _notify();
    File? file;
    try {
      final bytes = await assets.read(id);
      await Directory(directory).create(recursive: true);
      if (_closed || token != _generation) return;
      file = File('$directory/play-${const Uuid().v4()}.wav');
      _files.add(file);
      await file.writeAsBytes(bytes, flush: true);
      if (_closed || token != _generation) return;
      await device.play(file.path);
    } catch (e) {
      if (token == _generation) error = e;
    } finally {
      if (file != null) {
        _files.remove(file);
        if (await file.exists()) await file.delete();
      }
      if (token == _generation) {
        activeId = null;
        _notify();
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    activeId = null;
    await device.stopPlayback();
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        stop().catchError((Object e) {
          error = e;
          _notify();
        }),
      );
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop().catchError((Object _) {}));
    super.dispose();
  }
}
