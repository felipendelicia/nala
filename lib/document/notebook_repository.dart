import 'notebook.dart';
import 'revision.dart';

abstract interface class NotebookRepository {
  Future<List<DocumentEntry>> list();
  Future<Notebook?> load(String documentId, {String? headId});
  Future<bool> isDeleted(String documentId);
  Future<void> commit(Revision revision);
  Future<List<Revision>> pending();
  Future<List<Revision>> history(String documentId);
  Future<void> markUploaded(String revisionId);
  Future<void> acceptRemote(Revision revision);
  Future<void> close();
}

abstract interface class RevisionLookupRepository {
  Future<Revision?> lookupRevision(String documentId, String revisionId);
}

abstract interface class NotebookCatalogRepository {
  Future<List<CatalogEntry>> listCatalog();
  Future<NotebookPage?> loadPreview(
    String documentId, {
    required String headId,
  });
}
