import 'dart:convert';
import 'package:apuntes/document/notebook_codec.dart';
import 'fixtures.dart';

Map<String, dynamic> studyPayload() {
  final map =
      jsonDecode(NotebookCodec.encode(fixtureNotebook()))
          as Map<String, dynamic>;
  map['coverAssetId'] = 'a' * 64;
  map['recordings'] = [
    <String, dynamic>{
      'id': 'recording-1',
      'title': 'Clase de álgebra',
      'assetId': 'b' * 64,
      'durationMs': 1200,
      'createdAt': '2026-10-07T12:00:00.000Z',
    },
  ];
  map['studyCards'] = [
    <String, dynamic>{
      'id': 'card-1',
      'front': '¿Qué es λ?',
      'back': 'Un valor propio',
      'dueAt': '2026-10-08T12:00:00.000Z',
    },
  ];
  map['pages'][0]['objects'] = [
    <String, dynamic>{
      'id': 'text-1',
      'kind': 'text',
      'x': 50,
      'y': 70,
      'width': 200,
      'height': 50,
      'text': 'Álgebra λ',
    },
    <String, dynamic>{
      'id': 'image-1',
      'kind': 'image',
      'x': 50,
      'y': 140,
      'width': 80,
      'height': 60,
      'assetId': 'c' * 64,
      'rotation': 0.2,
    },
  ];
  map['pages'][0]['strokes'][0]['audioRecordingId'] = 'recording-1';
  map['pages'][0]['strokes'][0]['audioOffsetMs'] = 400;
  return map;
}
