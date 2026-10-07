import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/sync/sync_engine.dart';
import '../support/fixtures.dart';
import '../support/study_fixture.dart';

void main() {
  test('legacy notebooks retain exactly their optional-field-free JSON', () {
    final old = NotebookCodec.encode(fixtureNotebook());
    expect(NotebookCodec.encode(NotebookCodec.decode(old)), old);
  });

  test('objects, recording links, cover and scheduling survive the codec', () {
    final restored =
        jsonDecode(
              NotebookCodec.encode(
                NotebookCodec.decode(jsonEncode(studyPayload())),
              ),
            )
            as Map<String, dynamic>;
    expect(restored['coverAssetId'], 'a' * 64);
    expect(restored['recordings'][0]['durationMs'], 1200);
    expect(restored['studyCards'][0]['front'], '¿Qué es λ?');
    expect(restored['pages'][0]['objects'][0]['text'], 'Álgebra λ');
    expect(restored['pages'][0]['objects'][1]['rotation'], .2);
    expect(restored['pages'][0]['strokes'][0]['audioOffsetMs'], 400);
  });

  test('all notebook media enter revision asset enumeration', () {
    final map = studyPayload();
    map['pages'][0]['background'] = {'kind': 'image', 'assetId': 'd' * 64};
    expect(notebookAssets(NotebookCodec.decode(jsonEncode(map))), {
      'a' * 64,
      'b' * 64,
      'c' * 64,
      'd' * 64,
    });
  });

  for (final field in ['objects', 'recordings', 'studyCards']) {
    test('duplicate $field identifiers are rejected', () {
      final map = studyPayload();
      final target = field == 'objects' ? map['pages'][0] : map;
      target[field] = [target[field][0], target[field][0]];
      expect(
        () => NotebookCodec.decode(jsonEncode(map)),
        throwsFormatException,
      );
    });
  }

  for (final (name, mutate) in <(String, void Function(Map<String, dynamic>))>[
    ('empty text', (map) => map['pages'][0]['objects'][0]['text'] = ' '),
    (
      'image hash',
      (map) => map['pages'][0]['objects'][1]['assetId'] = 'wrong-hash',
    ),
    ('recording duration', (map) => map['recordings'][0]['durationMs'] = -1),
    ('empty card', (map) => map['studyCards'][0]['front'] = ''),
    ('card ease', (map) => map['studyCards'][0]['ease'] = 0),
    ('cover hash', (map) => map['coverAssetId'] = 'wrong-hash'),
    (
      'orphan offset',
      (map) => map['pages'][0]['strokes'][0].remove('audioRecordingId'),
    ),
    (
      'negative offset',
      (map) => map['pages'][0]['strokes'][0]['audioOffsetMs'] = -1,
    ),
  ]) {
    test('invalid study resource is rejected ($name)', () {
      final map = studyPayload();
      mutate(map);
      expect(
        () => NotebookCodec.decode(jsonEncode(map)),
        throwsFormatException,
      );
    });
  }

  test('active recording links survive before their audio resource exists', () {
    final map = studyPayload();
    map['recordings'] = [];
    final restored =
        jsonDecode(NotebookCodec.encode(NotebookCodec.decode(jsonEncode(map))))
            as Map<String, dynamic>;
    expect(
      restored['pages'][0]['strokes'][0]['audioRecordingId'],
      'recording-1',
    );
  });

  test(
    'recognized text and fingerprint survive save for cross-device search',
    () {
      final map = studyPayload();
      map['pages'][0]['recognizedText'] = 'Una raíz λ';
      map['pages'][0]['recognitionFingerprint'] = 'e' * 64;
      final restored =
          jsonDecode(
                NotebookCodec.encode(NotebookCodec.decode(jsonEncode(map))),
              )
              as Map<String, dynamic>;
      expect(restored['pages'][0]['recognizedText'], 'Una raíz λ');
      expect(restored['pages'][0]['recognitionFingerprint'], 'e' * 64);
      map['pages'][0]['recognitionFingerprint'] = 'broken';
      expect(
        () => NotebookCodec.decode(jsonEncode(map)),
        throwsFormatException,
      );
    },
  );
}
