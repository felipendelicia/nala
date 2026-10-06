import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'document/asset_store.dart';
import 'document/notebook_repository.dart';
import 'document/sqlite_notebook_repository.dart';
import 'library/library_controller.dart';
import 'pdf/pdf_service.dart';
import 'pdf/document_files.dart';
import 'audio/audio_service.dart';

class AppServices {
  AppServices({
    required this.root,
    required this.deviceId,
    required this.repository,
    required this.assets,
    required this.library,
    PdfService? pdf,
    DocumentFiles? files,
    AudioDevice? audio,
  }) : pdf = pdf ?? PdfService(assets: assets),
       files = files ?? NativeDocumentFiles(),
       audio = audio ?? nativeAudioDevice();
  final String root, deviceId;
  final NotebookRepository repository;
  final AssetStore assets;
  final LibraryController library;
  final PdfService pdf;
  final DocumentFiles files;
  final AudioDevice audio;
  static Future<AppServices> open(String root, {DocumentFiles? files}) async {
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
    return AppServices(
      root: root,
      deviceId: id,
      repository: repository,
      assets: FileAssetStore(p.join(root, 'local', 'assets')),
      library: library,
      files: files,
    );
  }

  Future<void> close() async {
    await audio.dispose();
    pdf.dispose();
    library.dispose();
    await repository.close();
  }
}
