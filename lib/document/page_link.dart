import 'notebook.dart' show nonEmpty;

/// A stable destination independent of open tabs and document titles.
class PageLink {
  PageLink({required this.notebookId, required this.pageId}) {
    nonEmpty(notebookId);
    nonEmpty(pageId);
  }

  final String notebookId;
  final String pageId;

  Map<String, Object> toJson() => {'notebookId': notebookId, 'pageId': pageId};

  factory PageLink.fromJson(Map<String, dynamic> json) => PageLink(
    notebookId: nonEmpty(json['notebookId']),
    pageId: nonEmpty(json['pageId']),
  );

  @override
  bool operator ==(Object other) =>
      other is PageLink &&
      notebookId == other.notebookId &&
      pageId == other.pageId;

  @override
  int get hashCode => Object.hash(notebookId, pageId);
}
