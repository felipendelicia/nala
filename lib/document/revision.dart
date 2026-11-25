import 'notebook.dart';

class Revision {
  const Revision({
    required this.id,
    required this.deviceId,
    required this.parentId,
    required this.createdAt,
    required this.notebook,
  });
  final String id, deviceId;
  final String? parentId;
  final DateTime createdAt;
  final Notebook notebook;
  // v1 sync preserves revision IDs even on clients that predate deletion.
  static const deletionIdPrefix = 'nala-deleted-v1-';
  static String deletionId(String id) => '$deletionIdPrefix$id';
  bool get deleted => id.startsWith(deletionIdPrefix);
  Revision withParent(String? parentId) => Revision(
    id: id,
    deviceId: deviceId,
    parentId: parentId,
    createdAt: createdAt,
    notebook: notebook,
  );
}

class DocumentEntry {
  const DocumentEntry({
    required this.notebook,
    required this.headId,
    required this.isConflict,
    required this.deviceId,
  });
  final Notebook notebook;
  final String headId, deviceId;
  final bool isConflict;
}

class CatalogEntry {
  const CatalogEntry({
    required this.documentId,
    required this.title,
    required this.subject,
    required this.updatedAt,
    required this.folderId,
    required this.headId,
    required this.deviceId,
    required this.isConflict,
    required this.pageCount,
    required this.coverAssetId,
    required this.firstPageId,
    required this.firstPageWidth,
    required this.firstPageHeight,
    required this.isPdf,
  });

  final String documentId, title, subject, headId, deviceId, firstPageId;
  final String? folderId, coverAssetId;
  final DateTime updatedAt;
  final bool isConflict, isPdf;
  final int pageCount;
  final double firstPageWidth, firstPageHeight;

  factory CatalogEntry.fromDocument(DocumentEntry entry) {
    final book = entry.notebook;
    final firstPage = book.pages.first;
    return CatalogEntry(
      documentId: book.id,
      title: book.title,
      subject: book.subject,
      updatedAt: book.updatedAt,
      folderId: book.folderId,
      headId: entry.headId,
      deviceId: entry.deviceId,
      isConflict: entry.isConflict,
      pageCount: book.pages.length,
      coverAssetId: book.coverAssetId,
      firstPageId: firstPage.id,
      firstPageWidth: firstPage.width,
      firstPageHeight: firstPage.height,
      isPdf: firstPage.background.isPdf,
    );
  }

  DocumentEntry withNotebook(Notebook notebook) => DocumentEntry(
    notebook: notebook,
    headId: headId,
    deviceId: deviceId,
    isConflict: isConflict,
  );
}
