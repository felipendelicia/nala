import 'dart:io';
import 'editor/pen_preferences.dart';
import 'editor/toolbar_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'document/asset_store.dart';
import 'document/notebook_repository.dart';
import 'document/sqlite_notebook_repository.dart';
import 'library/library_controller.dart';
import 'library/recent_notes.dart';
import 'pdf/pdf_service.dart';
import 'pdf/document_files.dart';
import 'pdf/pdf_share.dart';
import 'audio/audio_service.dart';
import 'ai/chat_gpt_client.dart';
import 'ai/notebook_chat_store.dart';
import 'ai/notebook_study_service.dart';
import 'pdf/pdf_export_service.dart';
import 'sync/remote_store.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_coordinator.dart';

class AppServices {
  AppServices({
    required this.root,
    required this.deviceId,
    required this.repository,
    required this.assets,
    required this.library,
    PdfService? pdf,
    DocumentFiles? files,
    PdfShare? share,
    AudioDevice? audio,
    ChatGptClient? chatGpt,
    RecentNotes? recentNotes,
    this.penPreferences,
    this.toolbarPreferences,
  }) : pdf = pdf ?? PdfService(assets: assets),
       files = files ?? NativeDocumentFiles(),
       share = share ?? NativePdfShare(),
       audio = audio ?? nativeAudioDevice(),
       recentNotes = recentNotes ?? RecentNotes(),
       chatGpt = chatGpt ?? _nativeChatGpt;
  final String root, deviceId;
  final NotebookRepository repository;
  final AssetStore assets;
  final LibraryController library;
  final PdfService pdf;
  final DocumentFiles files;
  final PdfShare share;
  final AudioDevice audio;
  final RecentNotes recentNotes;
  static final _nativeChatGpt = ChatGptClient();
  final ChatGptClient chatGpt;
  late final chatStore = NotebookChatStore(root);
  late final studyService = NotebookStudyService(
    client: chatGpt,
    exporter: PdfExportService(pdf),
  );
  final PenPreferencesController? penPreferences;
  final ToolbarPreferencesController? toolbarPreferences;
  SyncEngine? sync;
  SyncCoordinator? coordinator;
  bool _closed = false;
  void attachSync(RemoteStore remote, {bool autoStart = true}) {
    final engine = sync = SyncEngine(
      repository: repository,
      assets: assets,
      remote: remote,
    );
    coordinator = SyncCoordinator(engine);
    if (repository is SqliteNotebookRepository) {
      (repository as SqliteNotebookRepository).onLocalChange =
          coordinator!.notifyLocalChange;
    }
    if (autoStart) coordinator!.start();
  }

  Future<void> stopSync() async {
    if (repository is SqliteNotebookRepository) {
      (repository as SqliteNotebookRepository).onLocalChange = null;
    }
    coordinator?.dispose();
    coordinator = null;
    final old = sync;
    sync = null;
    old?.dispose();
    await old?.idle;
  }

  static Future<AppServices> open(
    String root, {
    DocumentFiles? files,
    PdfShare? share,
  }) async {
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
      penPreferences: await PenPreferencesController.open(root),
      toolbarPreferences: await ToolbarPreferencesController.open(root),
      deviceId: id,
      repository: repository,
      assets: FileAssetStore(p.join(root, 'local', 'assets')),
      library: library,
      recentNotes: await RecentNotes.open(root),
      files: files,
      share: share,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await stopSync();
    await audio.dispose();
    pdf.dispose();
    library.dispose();
    await recentNotes.close();
    toolbarPreferences?.dispose();
    await repository.close();
  }
}
