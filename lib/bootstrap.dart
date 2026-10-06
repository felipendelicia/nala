import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'document/asset_store.dart';
import 'document/sqlite_notebook_repository.dart';
import 'library/library_controller.dart';

class AppServices {
  AppServices._({
    required this.root,
    required this.deviceId,
    required this.repository,
    required this.assets,
    required this.library,
  });
  final String root, deviceId;
  final SqliteNotebookRepository repository;
  final FileAssetStore assets;
  final LibraryController library;
  static Future<AppServices> open(String root) async {
    await Directory(root).create(recursive: true);
    final device = File(p.join(root, 'device-id.txt'));
    final id = await device.exists()
        ? await device.readAsString()
        : '${Platform.isAndroid ? 'Tablet' : 'PC'}-${const Uuid().v4().substring(0, 8)}';
    if (!await device.exists()) await device.writeAsString(id, flush: true);
    final repository = await SqliteNotebookRepository.open(
      p.join(root, 'local', 'notes.db'),
    );
    final library = LibraryController(repository: repository, deviceId: id);
    await library.refresh();
    return AppServices._(
      root: root,
      deviceId: id,
      repository: repository,
      assets: FileAssetStore(p.join(root, 'local', 'assets')),
      library: library,
    );
  }

  Future<void> close() async {
    library.dispose();
    await repository.close();
  }
}
