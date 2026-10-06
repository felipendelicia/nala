import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'notebook_codec.dart';
import 'revision.dart';

class DocumentWorker {
  const DocumentWorker({this.events});
  final SendPort? events;
  Future<String> encode(Revision revision) =>
      compute(_encode, (revision, events));
  Future<Revision> decode(Uint8List bytes) => compute(_decode, (bytes, events));
  Future<String> canonical(Uint8List bytes) =>
      compute(_canonical, (bytes, events));
  Future<bool> equal(Revision a, Revision b) => compute(_equal, (a, b, events));
  Future<Uint8List> multipart(
    String metadata,
    String payload,
    String boundary,
  ) => compute(_multipart, (metadata, payload, boundary, events));
}

String _encode((Revision, SendPort?) request) {
  NotebookCodec.diagnostics = request.$2;
  return NotebookCodec.encodeRevision(request.$1);
}

Revision _decode((Uint8List, SendPort?) request) {
  NotebookCodec.diagnostics = request.$2;
  NotebookCodec.reportWork('utf8-decode');
  return NotebookCodec.decodeRevision(utf8.decode(request.$1));
}

String _canonical((Uint8List, SendPort?) request) =>
    NotebookCodec.encodeRevision(_decode(request));
bool _equal((Revision, Revision, SendPort?) request) {
  NotebookCodec.diagnostics = request.$3;
  return NotebookCodec.encodeRevision(request.$1) ==
      NotebookCodec.encodeRevision(request.$2);
}

Uint8List _multipart((String, String, String, SendPort?) request) {
  NotebookCodec.diagnostics = request.$4;
  NotebookCodec.reportWork('utf8-multipart');
  final (metadata, payload, boundary, _) = request;
  return Uint8List.fromList(
    utf8.encode(
      '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$payload\r\n--$boundary--\r\n',
    ),
  );
}
