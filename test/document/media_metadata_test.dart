import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/document/page_link.dart';
import 'package:apuntes/sync/sync_engine.dart';
import '../support/study_fixture.dart';

void main() {
  test(
    'image crop originals, opacity, locks and destinations survive saving',
    () {
      final map = studyPayload();
      final image = map['pages'][0]['objects'][1];
      image['originalAssetId'] = 'e' * 64;
      image['opacity'] = .35;
      image['locked'] = true;
      image['link'] = {'notebookId': 'other-notebook', 'pageId': 'other-page'};
      final book = NotebookCodec.decode(jsonEncode(map));
      final saved = jsonDecode(NotebookCodec.encode(book));
      expect(saved['pages'][0]['objects'][1]['originalAssetId'], 'e' * 64);
      expect(saved['pages'][0]['objects'][1]['opacity'], .35);
      expect(saved['pages'][0]['objects'][1]['locked'], true);
      expect(saved['pages'][0]['objects'][1]['link'], image['link']);
      expect(notebookAssets(book), contains('e' * 64));
    },
  );

  test(
    'math source and transparent render remain distinct saved resources',
    () {
      final map = studyPayload();
      map['pages'][0]['objects'][1]['kind'] = 'latex';
      map['pages'][0]['objects'][1]['text'] = r'\frac{1}{2}';
      final saved = jsonDecode(
        NotebookCodec.encode(NotebookCodec.decode(jsonEncode(map))),
      );
      expect(saved['pages'][0]['objects'][1]['text'], r'\frac{1}{2}');
      expect(saved['pages'][0]['objects'][1]['assetId'], 'c' * 64);
    },
  );

  for (final (field, value) in <(String, Object)>[
    ('opacity', -0.1),
    ('opacity', 1.1),
    ('opacity', '0.5'),
    ('locked', 'true'),
    ('originalAssetId', 'bad'),
    ('link', {'notebookId': '', 'pageId': 'p'}),
    ('link', {'notebookId': 'n', 'pageId': ''}),
  ]) {
    test('invalid $field metadata $value rejects the notebook', () {
      final map = studyPayload();
      map['pages'][0]['objects'][1][field] = value;
      expect(
        () => NotebookCodec.decode(jsonEncode(map)),
        throwsFormatException,
      );
    });
  }

  test('default fields remain absent in old object JSON', () {
    final old =
        studyPayload()['pages'][0]['objects'][1] as Map<String, dynamic>;
    expect(PageObject.fromJson(old).toJson(), old);
  });

  test(
    'copyWith updates media references and explicitly clears optional metadata',
    () {
      final image = PageObject(
        id: 'i',
        kind: PageObjectKind.image,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        assetId: 'a' * 64,
        originalAssetId: 'b' * 64,
        link: PageLink(notebookId: 'n', pageId: 'p'),
        opacity: .5,
        locked: true,
      );
      final moved = image.copyWith(x: 2);
      expect(moved.originalAssetId, 'b' * 64);
      expect(moved.link!.pageId, 'p');
      final cleared = image.copyWith(
        assetId: 'c' * 64,
        originalAssetId: null,
        link: null,
        locked: false,
        opacity: 1,
      );
      expect(cleared.assetId, 'c' * 64);
      expect(cleared.originalAssetId, isNull);
      expect(cleared.link, isNull);
      expect(cleared.locked, false);
      expect(cleared.opacity, 1);
    },
  );
}
