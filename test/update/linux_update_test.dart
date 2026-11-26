import 'dart:convert';
import 'dart:io';

import 'package:apuntes/update/linux_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory installation;
  late File launcher;
  late File legacyBinary;
  late Directory payload;
  late LinuxUpdate update;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nala-linux-update-');
    installation = await Directory(
      p.join(sandbox.path, 'installed app'),
    ).create();
    launcher = await File(
      'tool/linux/Abrir-Nala.sh',
    ).copy(p.join(installation.path, 'Abrir-Nala.sh'));
    legacyBinary = await _bundle(installation, '0.7.10');
    payload = await Directory(p.join(sandbox.path, 'payload')).create();
    update = LinuxUpdate(
      executablePath: legacyBinary.path,
      installRoot: installation.path,
    );
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  Future<ProcessResult> launch() => Process.run('bash', [launcher.path]);

  test(
    'activates a staged bundle after exit and retains the prior release',
    () async {
      expect(await update.installedVersion(), '0.7.10');
      expect((await launch()).stdout, '0.7.10\n');

      final running = await Process.start('bash', [
        launcher.path,
        '--keep-open',
      ], workingDirectory: installation.path);
      final stop = File(p.join(installation.path, 'stop'));
      final runningVersion = running.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      try {
        expect(
          await runningVersion.first.timeout(const Duration(seconds: 3)),
          '0.7.10',
        );
        await _bundle(payload, '0.7.11');
        await File(
          p.join(payload.path, 'Novedades.md'),
        ).writeAsString('Versión nueva');
        await update.stage(await _package(payload), '0.7.11');

        final concurrent = await launch();
        expect(concurrent.exitCode, 0, reason: '${concurrent.stderr}');
        expect(concurrent.stdout, isEmpty);
      } finally {
        await stop.create();
        await running.exitCode.timeout(const Duration(seconds: 3));
      }

      final restarted = await launch();
      expect(restarted.exitCode, 0, reason: '${restarted.stderr}');
      expect(restarted.stdout, '0.7.11\n');
      expect(await legacyBinary.exists(), isTrue);

      await _bundle(payload, '0.7.12');
      final state = p.join(installation.path, '.nala-updates');
      final slot = (await File(p.join(state, 'current')).readAsString()).trim();
      final newBinary = p.join(
        state,
        'releases',
        slot,
        'Nala-Linux',
        'apuntes',
      );
      final current = LinuxUpdate(
        executablePath: newBinary,
        installRoot: installation.path,
      );
      await current.stage(await _package(payload), '0.7.12');
      expect((await launch()).stdout, '0.7.12\n');
      expect(await File(newBinary).exists(), isTrue);
    },
  );

  test(
    'replaces a pending slot when the same version is downloaded again',
    () async {
      final binary = await _bundle(payload, '0.7.11');
      await update.stage(await _package(payload), '0.7.11');
      await binary.writeAsString(
        '#!/usr/bin/env bash\nprintf "corregido\\n"\n',
      );
      await update.stage(await _package(payload), '0.7.11');

      expect((await launch()).stdout, 'corregido\n');
      final releases = Directory(
        p.join(installation.path, '.nala-updates', 'releases'),
      );
      expect(await releases.list().length, 1);
    },
  );

  for (final invalid in [
    'symlink',
    'hardlink',
    'duplicate',
    'traversal',
    'version',
    'runtime',
  ]) {
    test('rejects a package with an invalid $invalid member', () async {
      final binary = await _bundle(
        payload,
        invalid == 'version' ? '0.7.10' : '0.7.11',
      );
      final bundle = binary.parent.path;
      switch (invalid) {
        case 'symlink':
          await Link(p.join(bundle, 'data', 'escape')).create('/tmp');
        case 'hardlink':
          final link = await Process.run('ln', [
            binary.path,
            p.join(bundle, 'hardlink'),
          ]);
          expect(link.exitCode, 0, reason: '${link.stderr}');
        case 'traversal':
          await File(
            p.join(bundle, 'escape'),
          ).writeAsString('fuera del paquete');
        case 'runtime':
          await File(p.join(bundle, 'lib', 'libapp.so')).delete();
      }
      final package = await _package(
        payload,
        duplicate: invalid == 'duplicate',
        traversal: invalid == 'traversal',
      );

      await expectLater(update.stage(package, '0.7.11'), throwsFormatException);
      expect((await launch()).stdout, '0.7.10\n');
      expect(
        await File(
          p.join(installation.path, '.nala-updates', 'pending'),
        ).exists(),
        isFalse,
      );
    });
  }

  test(
    'declines staging from outside the launcher-created installation',
    () async {
      final other = await Directory(p.join(sandbox.path, 'other')).create();
      final binary = await _bundle(other, '0.7.10');
      final unsupported = LinuxUpdate(
        executablePath: binary.path,
        installRoot: installation.path,
      );

      await expectLater(
        unsupported.stage(
          File(p.join(sandbox.path, 'download.tar.gz')),
          '0.7.11',
        ),
        throwsA(isA<LinuxUpdateException>()),
      );
    },
  );
}

Future<File> _bundle(Directory root, String version) async {
  final bundle = Directory(p.join(root.path, 'Nala-Linux'));
  final metadata = File(
    p.join(bundle.path, 'data', 'flutter_assets', 'version.json'),
  );
  await metadata.parent.create(recursive: true);
  await metadata.writeAsString(jsonEncode({'version': version}));
  for (final resource in [
    ['data', 'icudtl.dat'],
    ['lib', 'libapp.so'],
    ['lib', 'libflutter_linux_gtk.so'],
  ]) {
    final file = File(p.joinAll([bundle.path, ...resource]));
    await file.parent.create(recursive: true);
    await file.writeAsString('recurso de prueba');
  }
  final binary = File(p.join(bundle.path, 'apuntes'));
  await binary.writeAsString('''#!/usr/bin/env bash
printf '%s\\n' '$version'
if [[ "\${1:-}" == --keep-open ]]; then
  while [[ ! -f stop ]]; do sleep 0.02; done
fi
''');
  final chmod = await Process.run('chmod', ['755', binary.path]);
  expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
  return binary;
}

Future<File> _package(
  Directory payload, {
  bool duplicate = false,
  bool traversal = false,
}) async {
  final archive = File(p.join(payload.parent.path, 'download.tar.gz'));
  final result = await Process.run('tar', [
    '--format=ustar',
    if (traversal) '--transform=s,Nala-Linux/escape,Nala-Linux/../escape,',
    '-czf',
    archive.path,
    '-C',
    payload.path,
    'Nala-Linux',
    if (duplicate) 'Nala-Linux',
    if (await File(p.join(payload.path, 'Novedades.md')).exists())
      'Novedades.md',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return archive;
}
