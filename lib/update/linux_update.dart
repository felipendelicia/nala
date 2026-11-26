import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

const _bundle = 'Nala-Linux';
const _state = '.nala-updates';
const _releases = 'releases';
const _launcher = 'Abrir-Nala.sh';
const _binary = 'apuntes';
const _maxExpandedSize = 256 * 1024 * 1024;
const _versionExpression = r'(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){2}';
final _versionPattern = RegExp('^$_versionExpression\$');
final _slotPattern = RegExp('^$_versionExpression-[0-9A-Za-z]{1,32}\$');
const _writeError = LinuxUpdateException(
  'No se pudo preparar la actualización. Revisá el espacio y los permisos de la carpeta donde descomprimiste Nala.',
);

class LinuxUpdateException implements Exception {
  const LinuxUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LinuxUpdate {
  const LinuxUpdate({this.executablePath, this.installRoot});

  final String? executablePath;
  final String? installRoot;

  String get _executable => executablePath ?? Platform.resolvedExecutable;

  Future<String> installedVersion() => _bundleVersion(p.dirname(_executable));

  Future<void> ensureCanStage() async {
    final root = await _portableRoot();
    final state = p.join(root, _state);
    final type = await FileSystemEntity.type(state, followLinks: false);
    final directory = switch (type) {
      FileSystemEntityType.notFound => root,
      FileSystemEntityType.directory => state,
      _ => throw _writeError,
    };
    final result = await Process.run('test', ['-w', directory]);
    if (result.exitCode != 0) throw _writeError;
  }

  /// The caller verifies the release and its download before staging the bundle.
  Future<void> stage(File package, String version) async {
    if (!_versionPattern.hasMatch(version)) {
      throw const FormatException('La versión de Linux no es válida.');
    }
    final root = await _portableRoot();
    try {
      await _stage(root, package, version);
    } on FileSystemException {
      throw _writeError;
    }
  }

  Future<void> _stage(String root, File package, String version) async {
    final state = await _managedDirectory(p.join(root, _state));
    final releases = await _managedDirectory(p.join(state.path, _releases));
    final staging = await state.createTemp('.stage-');
    final slot =
        '$version-${p.basename(staging.path).substring('.stage-'.length)}';
    final pending = File(p.join(state.path, 'pending'));
    final marker = File(
      p.join(state.path, '${p.basename(staging.path)}-pending'),
    );

    try {
      await Isolate.run(() => _extract(package, staging));
      final bundle = p.join(staging.path, _bundle);
      if (await _bundleVersion(bundle) != version) {
        throw const FormatException(
          'El paquete no coincide con la versión publicada.',
        );
      }
      for (final resource in [
        _binary,
        'data/icudtl.dat',
        'lib/libapp.so',
        'lib/libflutter_linux_gtk.so',
      ]) {
        final file = File(p.join(bundle, resource));
        if (!await file.exists() || await file.length() == 0) {
          throw const FormatException('El paquete Linux está incompleto.');
        }
      }
      await staging.rename(p.join(releases.path, slot));

      final superseded = await _readMarker(pending);
      await marker.writeAsString('$slot\n', flush: true);
      await marker.rename(pending.path);
      if (superseded != null) {
        await _removeSuperseded(state, releases, superseded);
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await marker.exists()) await marker.delete();
    }
  }

  Future<String> _portableRoot() async {
    final advertised =
        installRoot ?? Platform.environment['NALA_PORTABLE_ROOT'];
    const error = LinuxUpdateException(
      'Abrí Nala con Abrir-Nala.sh desde el paquete Linux para instalar actualizaciones.',
    );
    if (!Platform.isLinux || advertised == null || !p.isAbsolute(advertised)) {
      throw error;
    }
    try {
      final root = await Directory(advertised).resolveSymbolicLinks();
      final executable = await File(_executable).resolveSymbolicLinks();
      final relative = p.split(p.relative(executable, from: root));
      final supported = switch (relative) {
        [_bundle, _binary] => true,
        [_state, _releases, final slot, _bundle, _binary] =>
          _slotPattern.hasMatch(slot),
        _ => false,
      };
      if (supported && await File(p.join(root, _launcher)).exists()) {
        return root;
      }
    } on FileSystemException {
      throw error;
    }
    throw error;
  }
}

Future<Directory> _managedDirectory(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.directory) {
    throw _writeError;
  }
  return Directory(path).create();
}

Future<String?> _readMarker(File marker) async {
  if (await FileSystemEntity.type(marker.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await marker.length() > 64) {
    return null;
  }
  final slot = utf8
      .decode(await marker.readAsBytes(), allowMalformed: true)
      .trim();
  return _slotPattern.hasMatch(slot) ? slot : null;
}

Future<void> _removeSuperseded(
  Directory state,
  Directory releases,
  String slot,
) async {
  try {
    for (final name in ['current', 'previous', 'pending']) {
      if (await _readMarker(File(p.join(state.path, name))) == slot) return;
    }
    final stale = Directory(p.join(releases.path, slot));
    if (await FileSystemEntity.type(stale.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await stale.delete(recursive: true);
    }
  } on FileSystemException {
    // The replacement is already staged. Cleanup can wait.
  }
}

Future<String> _bundleVersion(String bundle) async {
  final json = File(p.join(bundle, 'data', 'flutter_assets', 'version.json'));
  if (await json.exists() && await json.length() <= 64 * 1024) {
    if (jsonDecode(await json.readAsString()) case {
      'version': final String version,
    } when _versionPattern.hasMatch(version)) {
      return version;
    }
  }
  throw const FormatException('No se pudo leer la versión del paquete Linux.');
}

Future<void> _extract(File package, Directory staging) async {
  final tar = _TarStream(package);
  final paths = <String>{};
  try {
    while (true) {
      final header = await tar.exact(512);
      if (_allZeros(header)) break;
      final entry = _TarEntry(header);
      if (paths.length >= 4096 || !paths.add(entry.path)) {
        throw const FormatException(
          'El paquete contiene demasiadas rutas o rutas duplicadas.',
        );
      }

      if (entry.path == _bundle || entry.path.startsWith('$_bundle/')) {
        final target = p.join(staging.path, entry.path);
        if (entry.directory) {
          await Directory(target).create(recursive: true);
        } else {
          final file = File(target);
          await file.parent.create(recursive: true);
          final output = await file.open(mode: FileMode.write);
          try {
            await tar.copy(entry.size, output);
          } finally {
            await output.close();
          }
          if (entry.executable) {
            final chmod = await Process.run('chmod', ['u+x', '--', target]);
            if (chmod.exitCode != 0) {
              throw FileSystemException(
                'No se pudo preparar el ejecutable de Linux.',
                target,
              );
            }
          }
        }
      } else {
        await tar.copy(entry.size);
      }
      await tar.copy((512 - entry.size % 512) % 512);
    }

    if (!_allZeros(await tar.exact(512))) {
      throw const FormatException('El final del paquete Linux no es válido.');
    }
    while (true) {
      final rest = await tar.take(64 * 1024);
      if (rest.isEmpty) break;
      if (!_allZeros(rest)) {
        throw const FormatException(
          'El paquete tiene contenido después del final.',
        );
      }
    }
    if (!paths.contains('$_bundle/$_binary')) {
      throw const FormatException(
        'El paquete no incluye el ejecutable de Nala.',
      );
    }
  } finally {
    await tar.close();
  }
}

bool _allZeros(List<int> bytes) => bytes.every((byte) => byte == 0);

class _TarEntry {
  _TarEntry(List<int> header)
    : size = _number(header, 124, 12),
      directory = header[156] == 53,
      executable = _number(header, 100, 8) & 0x49 != 0,
      path = _entryPath(header) {
    final checksum = _number(header, 148, 8);
    var sum = 0;
    for (var index = 0; index < header.length; index++) {
      sum += index >= 148 && index < 156 ? 32 : header[index];
    }
    if (sum != checksum ||
        _string(header, 257, 6) != 'ustar' ||
        ![0, 48, 53].contains(header[156]) ||
        size > _maxExpandedSize ||
        (directory && size != 0) ||
        (path == '$_bundle/$_binary' && (directory || !executable))) {
      throw const FormatException(
        'El paquete incluye un archivo o un encabezado inválido.',
      );
    }
  }

  final int size;
  final bool directory;
  final bool executable;
  final String path;

  static String _entryPath(List<int> header) {
    final name = _string(header, 0, 100);
    final prefix = _string(header, 345, 155);
    final combined = prefix.isEmpty ? name : '$prefix/$name';
    final path = header[156] == 53 && combined.endsWith('/')
        ? combined.substring(0, combined.length - 1)
        : combined;
    if (path.contains(RegExp(r'[\x00-\x1f\x7f\\]')) ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('El paquete incluye una ruta inválida.');
    }
    return path;
  }

  static int _number(List<int> header, int start, int length) {
    final parsed = int.tryParse(
      _string(header, start, length).trim(),
      radix: 8,
    );
    if (parsed == null || parsed < 0) {
      throw const FormatException(
        'El paquete incluye un tamaño o permiso inválido.',
      );
    }
    return parsed;
  }

  static String _string(List<int> bytes, int start, int length) {
    var end = start;
    while (end < start + length && bytes[end] != 0) {
      end++;
    }
    return utf8.decode(bytes.sublist(start, end));
  }
}

class _TarStream {
  _TarStream(File package)
    : _stream = StreamIterator(gzip.decoder.bind(package.openRead()));

  final StreamIterator<List<int>> _stream;
  List<int> _chunk = const [];
  int _offset = 0;
  int _total = 0;

  Future<List<int>> take(int maximum) async {
    while (_offset == _chunk.length) {
      if (!await _stream.moveNext()) return const [];
      _chunk = _stream.current;
      _offset = 0;
      _total += _chunk.length;
      if (_total > _maxExpandedSize) {
        throw const FormatException(
          'El paquete Linux supera el tamaño permitido.',
        );
      }
    }
    final end = math.min(_offset + maximum, _chunk.length);
    final bytes = _chunk.sublist(_offset, end);
    _offset = end;
    return bytes;
  }

  Future<List<int>> exact(int size) async {
    final bytes = await take(size);
    if (bytes.length == size) return bytes;
    final remainder = <int>[...bytes];
    while (remainder.length < size) {
      final next = await take(size - remainder.length);
      if (next.isEmpty) {
        throw const FormatException('El paquete está incompleto.');
      }
      remainder.addAll(next);
    }
    return remainder;
  }

  Future<void> copy(int size, [RandomAccessFile? output]) async {
    var left = size;
    while (left > 0) {
      final bytes = await take(math.min(left, 64 * 1024));
      if (bytes.isEmpty) {
        throw const FormatException('El paquete está incompleto.');
      }
      await output?.writeFrom(bytes);
      left -= bytes.length;
    }
  }

  Future<void> close() => _stream.cancel();
}
