import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../document/asset_store.dart';

enum UpdateTarget { androidArm64, linuxX64 }

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.assetName,
    required this.downloadUri,
    required this.size,
    required this.sha256,
  });

  final String version;
  final String assetName;
  final Uri downloadUri;
  final int size;
  final String sha256;
}

class GitHubUpdates {
  GitHubUpdates({http.Client? client}) : _client = client ?? http.Client();

  static const _repository = 'felipendelicia/nala';
  static const _apk = 'Nala.apk';
  static const _linux = 'Nala-Linux-x64.tar.gz';
  static const _maxAssetBytes = 512 * 1024 * 1024;
  static const _maxMetadataBytes = 16 * 1024 * 1024;
  static const _assetHosts = {
    'release-assets.githubusercontent.com',
    'objects.githubusercontent.com',
  };
  static const _redirectStatuses = {301, 302, 303, 307, 308};
  static final _nextLink = RegExp(r';\s*rel="next"');
  static final _digestPattern = RegExp(r'^[a-fA-F0-9]{64}$');

  final http.Client _client;

  Future<UpdateRelease?> check({
    required String installedVersion,
    required UpdateTarget target,
  }) async {
    final installed = _Version.parse(installedVersion.split('+').first);
    if (installed == null) {
      throw const FormatException('La versión instalada no es válida.');
    }
    final assetName = switch (target) {
      UpdateTarget.androidArm64 => _apk,
      UpdateTarget.linuxX64 => _linux,
    };
    final deadline = _Deadline(const Duration(seconds: 25));
    _Version newest = installed;
    Map<String, Object?>? candidate;

    for (var page = 1; ; page++) {
      final uri = Uri.https('api.github.com', '/repos/$_repository/releases', {
        'per_page': '100',
        'page': '$page',
      });
      final response = await _get(uri, deadline, 'application/vnd.github+json');
      await _requireSuccess(response);
      final bytes = BytesBuilder(copy: false);
      await _readBody(response, deadline, _maxMetadataBytes, bytes.add);
      final releases = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (releases is! List<Object?>) {
        throw const FormatException('La lista de versiones no es válida.');
      }

      for (final release in releases) {
        if (release case {'draft': true}) continue;
        if (release case {
          'draft': false,
          'tag_name': String tag,
          'published_at': Object? publishedAt,
          'assets': List<Object?> assets,
        }) {
          if (publishedAt == null || !tag.startsWith('v')) continue;
          final version = _Version.parse(tag.substring(1));
          if (version == null || version.compareTo(newest) <= 0) continue;
          if (publishedAt is! String ||
              DateTime.tryParse(publishedAt) == null) {
            throw const FormatException(
              'La fecha de publicación no es válida.',
            );
          }
          for (final asset in assets) {
            if (asset is! Map<String, Object?> || asset['name'] is! String) {
              throw const FormatException('La lista de archivos no es válida.');
            }
            if (asset['name'] == assetName) {
              newest = version;
              candidate = asset;
              break;
            }
          }
        } else {
          throw const FormatException(
            'Los datos de la versión no son válidos.',
          );
        }
      }

      if (!_nextLink.hasMatch(response.headers['link'] ?? '')) break;
    }

    if (candidate == null) return null;
    final version = newest.toString();
    final uri = _assetUri(version, assetName);
    final size = candidate['size'];
    final digest = candidate['digest'];
    if (candidate['state'] != 'uploaded' ||
        candidate['browser_download_url'] != uri.toString() ||
        size is! int ||
        !_isAssetSizeValid(size) ||
        digest is! String ||
        !digest.startsWith('sha256:') ||
        !_digestPattern.hasMatch(digest.substring(7))) {
      throw const FormatException('El archivo de actualización no es válido.');
    }
    return UpdateRelease(
      version: version,
      assetName: assetName,
      downloadUri: uri,
      size: size,
      sha256: digest.substring(7).toLowerCase(),
    );
  }

  Future<File> download(
    UpdateRelease release, {
    required Directory directory,
  }) async {
    if (_Version.parse(release.version) == null ||
        (release.assetName != _apk && release.assetName != _linux) ||
        release.downloadUri != _assetUri(release.version, release.assetName) ||
        !_isAssetSizeValid(release.size) ||
        !_digestPattern.hasMatch(release.sha256)) {
      throw const FormatException('El archivo de actualización no es válido.');
    }

    await directory.create(recursive: true);
    final staging = await directory.createTemp('.nala-update-');
    final partial = File(p.join(staging.path, 'package.part'));
    try {
      final deadline = _Deadline(const Duration(minutes: 5));
      final output = await partial.open(mode: FileMode.write);
      try {
        final response = await _getAsset(release.downloadUri, deadline);
        final size = response.contentLength;
        if (size != null && size != release.size) {
          await response.stream.listen(null).cancel();
          throw const FormatException('El tamaño de la descarga no coincide.');
        }
        final received = await _readBody(
          response,
          deadline,
          release.size,
          output.writeFrom,
        );
        if (received != release.size) {
          throw const FormatException('El tamaño de la descarga no coincide.');
        }
      } finally {
        await output.close();
      }

      if (await assetFileHash(partial) != release.sha256.toLowerCase()) {
        throw const FormatException(
          'La suma SHA-256 de la descarga no coincide.',
        );
      }
      final name = 'nala-update-${const Uuid().v4()}-${release.assetName}';
      return await partial.rename(p.join(directory.path, name));
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<http.StreamedResponse> _getAsset(Uri uri, _Deadline deadline) async {
    for (var redirects = 0; ; redirects++) {
      final response = await _get(uri, deadline, 'application/octet-stream');
      if (!_redirectStatuses.contains(response.statusCode)) {
        await _requireSuccess(response);
        return response;
      }

      await response.stream.listen(null).cancel();
      final location = response.headers['location'];
      final next = location == null ? null : uri.resolve(location);
      if (redirects >= 3 ||
          next == null ||
          next.scheme != 'https' ||
          next.port != 443 ||
          next.userInfo.isNotEmpty ||
          next.hasFragment ||
          !_assetHosts.contains(next.host) ||
          next.pathSegments.isEmpty ||
          !next.pathSegments.first.startsWith(
            'github-production-release-asset',
          )) {
        throw const HttpException('La redirección de GitHub no es válida.');
      }
      uri = next;
    }
  }

  Future<http.StreamedResponse> _get(
    Uri uri,
    _Deadline deadline,
    String accept,
  ) {
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: deadline.abortTrigger)
          ..followRedirects = false
          ..headers.addAll({
            'accept': accept,
            'accept-encoding': 'identity',
            'user-agent': 'Nala',
          });
    return deadline.waitFor(_client.send(request));
  }

  static Future<void> _requireSuccess(http.StreamedResponse response) async {
    if (response.statusCode == HttpStatus.ok) return;
    await response.stream.listen(null).cancel();
    throw HttpException(
      'GitHub respondió con el código ${response.statusCode}.',
    );
  }

  static Future<int> _readBody(
    http.StreamedResponse response,
    _Deadline deadline,
    int maxBytes,
    FutureOr<void> Function(List<int>) receive,
  ) async {
    final chunks = StreamIterator(response.stream);
    var received = 0;
    try {
      while (await deadline.waitFor(chunks.moveNext())) {
        received += chunks.current.length;
        if (received > maxBytes) {
          throw const FormatException(
            'La respuesta de GitHub es demasiado grande.',
          );
        }
        await receive(chunks.current);
      }
      return received;
    } finally {
      await chunks.cancel();
    }
  }

  static Uri _assetUri(String version, String name) => Uri.https(
    'github.com',
    '/$_repository/releases/download/v$version/$name',
  );

  static bool _isAssetSizeValid(int size) => size > 0 && size <= _maxAssetBytes;

  void close() => _client.close();
}

class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch);

  static final _pattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
  );

  final int major;
  final int minor;
  final int patch;

  static _Version? parse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    final major = int.tryParse(match[1]!);
    final minor = int.tryParse(match[2]!);
    final patch = int.tryParse(match[3]!);
    if (major == null || minor == null || patch == null) return null;
    return _Version(major, minor, patch);
  }

  @override
  int compareTo(_Version other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class _Deadline {
  _Deadline(this.limit);

  final Duration limit;
  final _timer = Stopwatch()..start();
  final _abort = Completer<void>();

  Future<void> get abortTrigger => _abort.future;

  Future<T> waitFor<T>(Future<T> operation) => operation.timeout(
    limit - _timer.elapsed,
    onTimeout: () {
      if (!_abort.isCompleted) _abort.complete();
      throw TimeoutException('La solicitud a GitHub demoró demasiado.', limit);
    },
  );
}
