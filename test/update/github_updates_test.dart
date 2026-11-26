import 'dart:convert';
import 'dart:io';

import 'package:apuntes/update/github_updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

const _apk = 'Nala.apk';
const _archive = 'Nala-Linux-x64.tar.gz';
const _abcHash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const _releaseBase = 'https://github.com/felipendelicia/nala/releases/download';

Map<String, Object?> _asset(String tag, String name) => {
  'name': name,
  'state': 'uploaded',
  'size': 3,
  'digest': 'sha256:$_abcHash',
  'browser_download_url': '$_releaseBase/$tag/$name',
};

Map<String, Object?> _release(
  String tag,
  List<Map<String, Object?>> assets, {
  bool draft = false,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': true,
  'published_at': draft ? null : '2026-11-26T15:00:00Z',
  'assets': assets,
};

http.Response _json(Object value, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(value), 200, headers: headers ?? {});

GitHubUpdates _updates(http.Client client) {
  final updates = GitHubUpdates(client: client);
  addTearDown(updates.close);
  return updates;
}

void main() {
  test(
    'selects the highest numeric published prerelease for Android',
    () async {
      final updates = _updates(
        MockClient((request) async {
          expect(request.url.host, 'api.github.com');
          expect(request.url.path, '/repos/felipendelicia/nala/releases');
          return _json([
            _release('v1.2.9', [_asset('v1.2.9', _apk)]),
            _release('v1.2.10', [_asset('v1.2.10', _apk)]),
            _release('v2.0.0', [_asset('v2.0.0', _archive)]),
            _release('v3.0.0', [_asset('v3.0.0', _apk)], draft: true),
            _release('v4.0.0-beta', [_asset('v4.0.0-beta', _apk)]),
          ]);
        }),
      );

      final release = await updates.check(
        installedVersion: '1.2.8+18',
        target: UpdateTarget.androidArm64,
      );

      expect(release?.version, '1.2.10');
      expect(release?.assetName, _apk);
      expect(release?.downloadUri, Uri.parse('$_releaseBase/v1.2.10/$_apk'));
      expect(release?.size, 3);
      expect(release?.sha256, _abcHash);
    },
  );

  test('ignores a newer release without the Linux x64 asset', () async {
    final updates = _updates(
      MockClient(
        (_) async => _json([
          _release('v2.1.0', [_asset('v2.1.0', _apk)]),
          _release('v2.0.1', [_asset('v2.0.1', 'Nala-Linux-arm64.tar.gz')]),
          _release('v2.0.0', [_asset('v2.0.0', _archive)]),
        ]),
      ),
    );

    final release = await updates.check(
      installedVersion: '1.2.9',
      target: UpdateTarget.linuxX64,
    );

    expect(release?.version, '2.0.0');
    expect(release?.assetName, _archive);
  });

  test('returns no update for equal or older releases', () async {
    final updates = _updates(
      MockClient(
        (_) async => _json([
          _release('v1.2.9', [_asset('v1.2.9', _apk)]),
          _release('v1.2.10', [_asset('v1.2.10', _apk)]),
        ]),
      ),
    );

    expect(
      await updates.check(
        installedVersion: '1.2.10+18',
        target: UpdateTarget.androidArm64,
      ),
      isNull,
    );
  });

  test('includes later pages when comparing release versions', () async {
    final updates = _updates(
      MockClient((request) async {
        if (request.url.queryParameters['page'] == '2') {
          return _json([
            _release('v2.0.0', [_asset('v2.0.0', _apk)]),
          ]);
        }
        return _json(
          [
            _release('v1.2.10', [_asset('v1.2.10', _apk)]),
          ],
          headers: {
            'link':
                '<https://api.github.com/repos/felipendelicia/nala/'
                'releases?per_page=100&page=2>; rel="next"',
          },
        );
      }),
    );

    final release = await updates.check(
      installedVersion: '1.2.8',
      target: UpdateTarget.androidArm64,
    );

    expect(release?.version, '2.0.0');
  });

  for (final (field, value) in <(String, Object?)>[
    (
      'browser_download_url',
      'https://github.com/other/nala/releases/download/v2.0.0/Nala.apk',
    ),
    ('browser_download_url', '$_releaseBase/v2.0.1/Nala.apk'),
    ('digest', null),
    ('digest', 'sha512:$_abcHash'),
    ('size', 0),
    ('size', 999999999999),
  ]) {
    test('rejects invalid $field ($value) on a matching asset', () async {
      final updates = _updates(
        MockClient(
          (_) async => _json([
            _release('v2.0.0', [
              {..._asset('v2.0.0', _apk), field: value},
            ]),
          ]),
        ),
      );

      await expectLater(
        updates.check(
          installedVersion: '1.2.8',
          target: UpdateTarget.androidArm64,
        ),
        throwsFormatException,
      );
    });
  }

  test('throws on a failed GitHub query', () async {
    final updates = _updates(
      MockClient((_) async => http.Response('rate limited', 403)),
    );

    await expectLater(
      updates.check(
        installedVersion: '1.2.8',
        target: UpdateTarget.androidArm64,
      ),
      throwsA(isA<HttpException>()),
    );
  });

  group('downloading an update', () {
    late Directory directory;
    final release = UpdateRelease(
      version: '2.0.0',
      assetName: _apk,
      downloadUri: Uri.parse('$_releaseBase/v2.0.0/$_apk'),
      size: 3,
      sha256: _abcHash,
    );

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('nala-update-test-');
      addTearDown(() => directory.delete(recursive: true));
    });

    test(
      'allows a GitHub asset redirect and keeps parallel downloads distinct',
      () async {
        final redirect = Uri.parse(
          'https://release-assets.githubusercontent.com/github-production-release-asset/123/package',
        );
        final updates = _updates(
          MockClient.streaming((request, _) async {
            expect(request.followRedirects, isFalse);
            if (request.url == release.downloadUri) {
              return http.StreamedResponse(
                const Stream.empty(),
                302,
                headers: {'location': redirect.toString()},
              );
            }
            expect(request.url, redirect);
            return http.StreamedResponse(
              Stream.fromIterable([utf8.encode('a'), utf8.encode('bc')]),
              200,
            );
          }),
        );

        final files = await Future.wait([
          updates.download(release, directory: directory),
          updates.download(release, directory: directory),
        ]);

        expect(files.map((file) => file.path).toSet(), hasLength(2));
        expect(await directory.list().toList(), hasLength(2));
        for (final file in files) {
          expect(file.parent.path, directory.path);
          expect(p.extension(file.path), '.apk');
          expect(await file.readAsString(), 'abc');
        }
      },
    );

    test(
      'rejects an unrelated redirect before sending a second request',
      () async {
        var requests = 0;
        final updates = _updates(
          MockClient((_) async {
            requests++;
            return http.Response(
              '',
              302,
              headers: {'location': 'https://elsewhere.example/Nala.apk'},
            );
          }),
        );

        await expectLater(
          updates.download(release, directory: directory),
          throwsA(isA<HttpException>()),
        );
        expect(requests, 1);
        expect(await directory.list().toList(), isEmpty);
      },
    );

    for (final (problem, body) in [
      ('truncated download', 'ab'),
      ('oversized download', 'abcd'),
      ('wrong SHA-256', 'abd'),
    ]) {
      test('cleans up a $problem and can retry', () async {
        var response = body;
        final updates = _updates(
          MockClient.streaming(
            (_, _) async => http.StreamedResponse(
              Stream.fromIterable(response.codeUnits.map((byte) => [byte])),
              200,
            ),
          ),
        );

        await expectLater(
          updates.download(release, directory: directory),
          throwsFormatException,
        );
        expect(await directory.list().toList(), isEmpty);

        response = 'abc';
        final file = await updates.download(release, directory: directory);
        expect(await file.readAsString(), 'abc');
        expect(await directory.list().toList(), hasLength(1));
      });
    }
  });
}
