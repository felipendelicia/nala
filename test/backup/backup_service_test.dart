import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:apuntes/backup/backup_service.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/notebook_recording.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';

void main() {
  late Directory source, target;
  late SqliteNotebookRepository sourceRepo, targetRepo;
  late FileAssetStore sourceAssets, targetAssets;
  late BackupService exporter, importer;
  final now = DateTime.utc(2026, 10, 7);
  late String imageId, originalId, audioId;
  Future<void> config(Directory root, String path, Object value) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
  }

  Revision rev(String id, String? parent, String title) {
    final book = Notebook(
      id: 'source-book',
      title: title,
      subject: 'Math',
      folderId: 'folder',
      updatedAt: now,
      recordings: [
        NotebookRecording(
          id: 'recording',
          title: 'Class',
          assetId: audioId,
          durationMs: 100,
          createdAt: now,
        ),
      ],
      pages: [
        NotebookPage(
          id: 'source-page',
          width: 100,
          height: 100,
          background: PageBackground.image(imageId),
          comments: [
            PageComment(
              id: 'comment',
              x: 10,
              y: 10,
              text: 'Audio',
              createdAt: now,
              audioAssetId: audioId,
              audioDurationMs: 100,
            ),
          ],
          strokes: [
            InkStroke(
              id: 'stroke',
              tool: InkTool.pen,
              argb: 0xff202020,
              width: 2,
              points: [const InkPoint(x: 1, y: 1, pressure: 1)],
              audioRecordingId: 'recording',
              audioOffsetMs: 10,
            ),
          ],
        ),
      ],
    );
    final map = jsonDecode(NotebookCodec.encode(book)) as Map<String, dynamic>;
    (map['pages'] as List).single['objects'] = [
      {
        'id': 'image',
        'kind': 'image',
        'x': 10,
        'y': 10,
        'width': 20,
        'height': 20,
        'argb': 0xff202020,
        'assetId': imageId,
        'originalAssetId': originalId,
        'link': {'notebookId': 'source-book', 'pageId': 'source-page'},
      },
      {
        'id': 'formula',
        'kind': 'latex',
        'x': 40,
        'y': 10,
        'width': 20,
        'height': 20,
        'argb': 0xff202020,
        'text': r'x^2',
        'assetId': imageId,
      },
    ];
    return Revision(
      id: id,
      deviceId: 'private-device',
      parentId: parent,
      createdAt: now,
      notebook: NotebookCodec.decode(jsonEncode(map)),
    );
  }

  setUp(() async {
    source = await Directory.systemTemp.createTemp('nala-backup-source-');
    target = await Directory.systemTemp.createTemp('nala-backup-target-');
    sourceRepo = await SqliteNotebookRepository.open('${source.path}/notes.db');
    targetRepo = await SqliteNotebookRepository.open('${target.path}/notes.db');
    sourceAssets = FileAssetStore('${source.path}/assets');
    targetAssets = FileAssetStore('${target.path}/assets');
    exporter = BackupService(
      root: source.path,
      repository: sourceRepo,
      assets: sourceAssets,
      deviceId: 'source-device',
    );
    importer = BackupService(
      root: target.path,
      repository: targetRepo,
      assets: targetAssets,
      deviceId: 'target-device',
    );
    imageId = await sourceAssets.put(Uint8List.fromList([1, 2, 3]));
    originalId = await sourceAssets.put(Uint8List.fromList([3, 2, 1]));
    audioId = await sourceAssets.put(Uint8List.fromList([4, 5, 6]));
    await sourceRepo.saveFolder(
      NoteFolder(id: 'folder', name: 'Class', updatedAt: now),
    );
    await sourceRepo.acceptRemote(rev('base', null, 'Base'));
    await sourceRepo.acceptRemote(rev('left', 'base', 'Left'));
    await sourceRepo.acceptRemote(rev('right', 'base', 'Right'));
    await config(source, 'templates/registry.json', {
      'version': 1,
      'templates': [
        {
          'id': 'template',
          'name': 'Template',
          'width': 100,
          'height': 100,
          'background': {'kind': 'image', 'assetId': imageId},
          'coverAssetId': imageId,
        },
      ],
    });
    final elementObjects = rev(
      'fixture',
      null,
      'Fixture',
    ).notebook.pages.single.objects.map((o) => o.toJson()).toList();
    await config(source, 'elements/registry.json', {
      'version': 1,
      'elements': [
        {
          'id': 'element',
          'name': 'Diagram',
          'width': 100,
          'height': 100,
          'strokes': [],
          'objects': elementObjects,
        },
      ],
    });
    await config(source, 'appearance.json', {'theme': 'dark'});
    await File('${source.path}/device-id.txt').writeAsString('secret-device');
    await config(source, 'credentials.json', {'token': 'secret-token'});
  });
  tearDown(() async {
    await sourceRepo.close();
    await targetRepo.close();
    await source.delete(recursive: true);
    await target.delete(recursive: true);
  });

  test(
    'recovery preserves histories, conflicts, media and remaps links while retaining existing notes',
    () async {
      await targetRepo.commit(
        Revision(
          id: 'existing-rev',
          deviceId: 'target',
          parentId: null,
          createdAt: now,
          notebook: Notebook.blank(
            id: 'existing',
            pageId: 'existing-page',
            title: 'Existing',
            pattern: PaperPattern.blank,
            now: now,
          ),
        ),
      );
      var changes = 0;
      targetRepo.onLocalChange = () => changes++;
      final bytes = await exporter.export();
      final preview = await importer.inspect(bytes);
      expect(preview.notebookCount, 1);
      expect(preview.headCount, 2);
      expect(preview.revisionCount, 3);
      expect(preview.assetCount, 3);
      expect(preview.elementCount, 1);
      expect(preview.templateCount, 1);
      final result = await importer.restore(bytes);
      final entries = await targetRepo.list();
      expect(entries.length, 3);
      expect(await targetRepo.load('existing'), isNotNull);
      final recovered = entries
          .where((e) => e.notebook.id != 'existing')
          .toList();
      expect(recovered.map((e) => e.notebook.id).toSet().length, 1);
      expect(recovered.every((e) => e.isConflict), isTrue);
      final book = recovered.first.notebook;
      expect(book.pages.single.id, isNot('source-page'));
      final data = jsonDecode(NotebookCodec.encode(book));
      expect(data['pages'][0]['objects'][0]['link'], {
        'notebookId': book.id,
        'pageId': book.pages.single.id,
      });
      expect((await targetRepo.history(book.id)).length, 3);
      expect(await targetAssets.read(originalId), [3, 2, 1]);
      expect(await targetAssets.read(audioId), [4, 5, 6]);
      expect(
        (await targetRepo.listFolders()).any(
          (f) => f.id == result.recoveryFolderId,
        ),
        isTrue,
      );
      expect(changes, 1);
      final elements =
          jsonDecode(
                await File(
                  '${target.path}/elements/registry.json',
                ).readAsString(),
              )['elements']
              as List;
      expect(elements.single['id'], isNot('element'));
      expect(elements.single['objects'][0]['link'], {
        'notebookId': book.id,
        'pageId': book.pages.single.id,
      });
      expect(elements.single['objects'][1]['text'], r'x^2');
      expect(
        (jsonDecode(
                  await File(
                    '${target.path}/templates/registry.json',
                  ).readAsString(),
                )['templates']
                as List)
            .single['id'],
        isNot('template'),
      );

      final zip = ZipDecoder().decodeBytes(bytes);
      expect(
        zip.files.any(
          (f) => f.name.contains('credentials') || f.name.contains('device-id'),
        ),
        isFalse,
      );
      expect(
        utf8.decode(zip.findFile('manifest.json')!.content as List<int>),
        isNot(contains('secret-device')),
      );
    },
  );

  test(
    'corrupt hash rejects recovery before any library or preference mutation',
    () async {
      await config(target, 'appearance.json', {'theme': 'light'});
      final archive = ZipDecoder().decodeBytes(await exporter.export());
      final file = archive.files.firstWhere(
        (f) => f.name.startsWith('assets/'),
      );
      final rewritten = Archive();
      for (final item in archive.files) {
        final data = item.name == file.name
            ? Uint8List.fromList([9])
            : Uint8List.fromList(item.content as List<int>);
        rewritten.addFile(ArchiveFile(item.name, data.length, data));
      }
      await expectLater(
        importer.restore(Uint8List.fromList(ZipEncoder().encode(rewritten))),
        throwsFormatException,
      );
      expect(await targetRepo.list(), isEmpty);
      expect(await targetRepo.listFolders(), isEmpty);
      expect(
        jsonDecode(await File('${target.path}/appearance.json').readAsString()),
        {'theme': 'light'},
      );
    },
  );

  test('unknown paths and duplicate ZIP names are rejected', () async {
    final bytes = await exporter.export();
    for (final name in [
      '../escape',
      '/absolute',
      r'C:\escape',
      'extra.txt',
      'manifest.json',
    ]) {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (name == 'manifest.json') {
        archive.modifyAtIndex(0, ArchiveFile('manifest.json', 1, [1]));
      } else {
        archive.addFile(ArchiveFile(name, 1, [1]));
      }
      await expectLater(
        importer.inspect(Uint8List.fromList(ZipEncoder().encode(archive))),
        throwsFormatException,
        reason: name,
      );
    }
    expect(await targetRepo.list(), isEmpty);
  });

  test(
    'missing asset reference is rejected even with a rehashed manifest',
    () async {
      final archive = ZipDecoder().decodeBytes(await exporter.export());
      final absent = sha256.convert([100]).toString();
      final manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content as List<int>),
      );
      final changed = Archive();
      for (final file in archive.files.where(
        (f) => f.name != 'manifest.json',
      )) {
        var data = Uint8List.fromList(file.content as List<int>);
        if (file.name.startsWith('revisions/')) {
          data = Uint8List.fromList(
            utf8.encode(utf8.decode(data).replaceAll(originalId, absent)),
          );
          manifest['files'][file.name] = {
            'size': data.length,
            'sha256': sha256.convert(data).toString(),
          };
        }
        changed.addFile(ArchiveFile(file.name, data.length, data));
      }
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      changed.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );
      await expectLater(
        importer.restore(Uint8List.fromList(ZipEncoder().encode(changed))),
        throwsFormatException,
      );
      expect(await targetRepo.listFolders(), isEmpty);
    },
  );

  test(
    'oversized declared content is rejected without creating recovered data',
    () async {
      final bytes = Uint8List.fromList(await exporter.export());
      final data = ByteData.sublistView(bytes);
      final end = bytes.length - 22;
      var offset = data.getUint32(end + 16, Endian.little);
      while (data.getUint32(offset, Endian.little) == 0x02014b50) {
        final length = data.getUint16(offset + 28, Endian.little);
        final name = utf8.decode(
          bytes.sublist(offset + 46, offset + 46 + length),
        );
        if (name.startsWith('assets/')) {
          final local = data.getUint32(offset + 42, Endian.little);
          data.setUint32(offset + 24, 64 * 1024 * 1024 + 1, Endian.little);
          data.setUint32(local + 22, 64 * 1024 * 1024 + 1, Endian.little);
          break;
        }
        offset +=
            46 +
            length +
            data.getUint16(offset + 30, Endian.little) +
            data.getUint16(offset + 32, Endian.little);
      }
      await expectLater(importer.restore(bytes), throwsFormatException);
      expect(await targetRepo.list(), isEmpty);
      expect(await targetRepo.listFolders(), isEmpty);
    },
  );

  test(
    'CRC corruption is rejected even when all manifest hashes still match',
    () async {
      final bytes = Uint8List.fromList(await exporter.export());
      final data = ByteData.sublistView(bytes);
      final central = data.getUint32(bytes.length - 22 + 16, Endian.little);
      final local = data.getUint32(central + 42, Endian.little);
      final oldCrc = data.getUint32(central + 16, Endian.little);
      data.setUint32(central + 16, oldCrc ^ 1, Endian.little);
      data.setUint32(local + 14, oldCrc ^ 1, Endian.little);
      await expectLater(importer.inspect(bytes), throwsFormatException);
      expect(await targetRepo.listFolders(), isEmpty);
    },
  );

  for (final completed in [true, false]) {
    test(
      'recording history survives ${completed ? 'completion' : 'discard'} after an intermediate unfinalized revision',
      () async {
        final pending = Notebook(
          id: 'live-note',
          title: 'Live note',
          subject: '',
          updatedAt: now,
          pages: [
            NotebookPage(
              id: 'live-page',
              width: 100,
              height: 100,
              background: const PageBackground.paper(PaperPattern.blank),
              strokes: [
                InkStroke(
                  id: 'live-stroke',
                  tool: InkTool.pen,
                  argb: 0xff202020,
                  width: 2,
                  points: [const InkPoint(x: 10, y: 10, pressure: 1)],
                  audioRecordingId: 'live-recording',
                  audioOffsetMs: 10,
                ),
              ],
            ),
          ],
        );
        await sourceRepo.acceptRemote(
          Revision(
            id: 'live-pending',
            deviceId: 'fixture',
            parentId: null,
            createdAt: now,
            notebook: pending,
          ),
        );
        final finished = completed
            ? pending.copyWith(
                recordings: [
                  NotebookRecording(
                    id: 'live-recording',
                    title: 'Class',
                    assetId: audioId,
                    durationMs: 100,
                    createdAt: now,
                  ),
                ],
              )
            : pending.copyWith(
                pages: [
                  pending.pages.single.copyWith(
                    strokes: [
                      pending.pages.single.strokes.single.copyWith(
                        audioRecordingId: null,
                        audioOffsetMs: null,
                      ),
                    ],
                  ),
                ],
              );
        await sourceRepo.acceptRemote(
          Revision(
            id: 'live-finished',
            deviceId: 'fixture',
            parentId: 'live-pending',
            createdAt: now,
            notebook: finished,
          ),
        );
        await importer.restore(await exporter.export());
        final recovered = (await targetRepo.list()).singleWhere(
          (e) => e.notebook.title == 'Live note',
        );
        final history = await targetRepo.history(recovered.notebook.id);
        expect(history, hasLength(2));
        expect(
          history.first.notebook.pages.single.strokes.single.audioRecordingId,
          isNotNull,
        );
        if (completed) {
          expect(
            recovered.notebook.pages.single.strokes.single.audioRecordingId,
            recovered.notebook.recordings.single.id,
          );
          expect(
            await targetAssets.read(
              recovered.notebook.recordings.single.assetId,
            ),
            [4, 5, 6],
          );
        } else {
          expect(
            recovered.notebook.pages.single.strokes.single.audioRecordingId,
            isNull,
          );
          expect(recovered.notebook.recordings, isEmpty);
        }
      },
    );
  }

  test(
    'oversized export checks a sparse asset length before hashing or loading its bytes',
    () async {
      final file = await File(
        '${sourceAssets.directory}/$originalId',
      ).open(mode: FileMode.writeOnly);
      await file.truncate(64 * 1024 * 1024 + 1);
      await file.close();
      await expectLater(
        exporter.export(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'limit reported before invalid hash read',
            contains('límite'),
          ),
        ),
      );
      expect(await targetRepo.list(), isEmpty);
    },
  );

  test(
    'interrupted recording head backs up ink with a warning without changing source metadata',
    () async {
      final pending = Notebook(
        id: 'interrupted',
        title: 'Interrupted',
        subject: '',
        updatedAt: now,
        pages: [
          NotebookPage(
            id: 'interrupted-page',
            width: 100,
            height: 100,
            background: const PageBackground.paper(PaperPattern.blank),
            strokes: [
              InkStroke(
                id: 'interrupted-stroke',
                tool: InkTool.pen,
                argb: 0xff202020,
                width: 2,
                points: [const InkPoint(x: 10, y: 10, pressure: 1)],
                audioRecordingId: 'unavailable-recording',
                audioOffsetMs: 10,
              ),
            ],
          ),
        ],
      );
      await sourceRepo.acceptRemote(
        Revision(
          id: 'interrupted-revision',
          deviceId: 'fixture',
          parentId: null,
          createdAt: now,
          notebook: pending,
        ),
      );
      await sourceRepo.close();
      sourceRepo = await SqliteNotebookRepository.open(
        '${source.path}/notes.db',
      );
      exporter = BackupService(
        root: source.path,
        repository: sourceRepo,
        assets: sourceAssets,
        deviceId: 'source',
      );
      final bytes = await exporter.export();
      final preview = await importer.inspect(bytes);
      expect(preview.warnings.join(' '), contains('grabación'));
      await importer.restore(bytes);
      final recovered = (await targetRepo.list()).singleWhere(
        (e) => e.notebook.title == 'Interrupted',
      );
      expect(
        recovered.notebook.pages.single.strokes.single.points.single.x,
        10,
      );
      expect(
        recovered.notebook.pages.single.strokes.single.audioRecordingId,
        isNull,
      );
      expect(
        (await sourceRepo.load(
          'interrupted',
        ))!.pages.single.strokes.single.audioRecordingId,
        'unavailable-recording',
      );
    },
  );

  test(
    'a full existing element registry preserves incoming content separately while notebooks recover',
    () async {
      final elements = [
        for (var index = 0; index < 1000; index++)
          {
            'id': 'existing-element-$index',
            'name': 'Existing $index',
            'width': 10,
            'height': 10,
            'strokes': [],
            'objects': [
              {
                'id': 'existing-object-$index',
                'kind': 'text',
                'text': 'Old',
                'x': 1,
                'y': 1,
                'width': 5,
                'height': 5,
              },
            ],
          },
      ];
      await config(target, 'elements/registry.json', {
        'version': 1,
        'elements': elements,
      });
      final result = await importer.restore(await exporter.export());
      expect(await targetRepo.list(), hasLength(2));
      final existing =
          jsonDecode(
                await File(
                  '${target.path}/elements/registry.json',
                ).readAsString(),
              )['elements']
              as List;
      expect(existing, hasLength(1000));
      expect(existing.first['id'], 'existing-element-0');
      expect(result.elementCount, 0);
      final recovered =
          jsonDecode(
                await File(
                  '${target.path}/recovery-registries/${result.recoveryFolderId}/elements/registry.json',
                ).readAsString(),
              )['elements']
              as List;
      expect(recovered, hasLength(1));
      expect(recovered.single['name'], 'Diagram');
      expect(result.warnings.join(' '), contains('recovery-registries'));
    },
  );

  test(
    'global appearance override restores the actual app setting outside the account partition',
    () async {
      final global = await Directory.systemTemp.createTemp(
        'nala-backup-appearance-',
      );
      addTearDown(() => global.delete(recursive: true));
      final sourceFile = File('${global.path}/source-appearance.json');
      final targetFile = File('${global.path}/target-appearance.json');
      await sourceFile.writeAsString(jsonEncode({'theme': 'dark'}));
      await targetFile.writeAsString(jsonEncode({'theme': 'light'}));
      await config(source, 'appearance.json', {'theme': 'light'});
      await config(target, 'appearance.json', {'theme': 'system'});
      final exporterWithAppearance = BackupService(
        root: source.path,
        repository: sourceRepo,
        assets: sourceAssets,
        deviceId: 'source',
        appearanceFile: sourceFile,
      );
      final importerWithAppearance = BackupService(
        root: target.path,
        repository: targetRepo,
        assets: targetAssets,
        deviceId: 'target',
        appearanceFile: targetFile,
      );
      final result = await importerWithAppearance.restore(
        await exporterWithAppearance.export(),
        restorePreferences: true,
      );
      expect(jsonDecode(await targetFile.readAsString()), {'theme': 'dark'});
      expect(
        jsonDecode(await File('${target.path}/appearance.json').readAsString()),
        {'theme': 'system'},
      );
      expect(
        jsonDecode(
          await File(
            '${target.path}/recovery-preferences/${result.recoveryFolderId}/appearance.json',
          ).readAsString(),
        ),
        {'theme': 'light'},
      );
    },
  );

  test(
    'post-commit notification errors cannot roll back recovered registries',
    () async {
      var notifications = 0;
      targetRepo.onLocalChange = () {
        notifications++;
        throw StateError('listener failure');
      };
      final result = await importer.restore(await exporter.export());
      expect(result.notebookCount, 1);
      expect(notifications, 1);
      expect(await targetRepo.list(), hasLength(2));
      expect(await targetRepo.pending(), hasLength(3));
      expect(
        jsonDecode(
          await File('${target.path}/elements/registry.json').readAsString(),
        )['elements'],
        hasLength(1),
      );
      expect(
        jsonDecode(
          await File('${target.path}/templates/registry.json').readAsString(),
        )['templates'],
        hasLength(1),
      );
    },
  );

  test(
    'database failure rolls back registry changes and leaves no recovered tree',
    () async {
      await config(target, 'templates/registry.json', {
        'version': 1,
        'templates': [
          {
            'id': 'old-template',
            'name': 'Old template',
            'width': 10,
            'height': 10,
            'background': {'kind': 'paper', 'pattern': 'blank'},
          },
        ],
      });
      await config(target, 'elements/registry.json', {
        'version': 1,
        'elements': [
          {
            'id': 'old-element',
            'name': 'Old element',
            'width': 10,
            'height': 10,
            'strokes': [],
            'objects': [
              {
                'id': 'old-object',
                'kind': 'text',
                'text': 'Old',
                'x': 1,
                'y': 1,
                'width': 5,
                'height': 5,
              },
            ],
          },
        ],
      });
      final sql = sqlite3.open('${target.path}/notes.db');
      sql.execute(
        "CREATE TRIGGER fail_queue BEFORE INSERT ON upload_queue BEGIN SELECT RAISE(ABORT,'disk failure'); END",
      );
      sql.close();
      await expectLater(
        importer.restore(await exporter.export()),
        throwsStateError,
      );
      expect(await targetRepo.list(), isEmpty);
      expect(await targetRepo.listFolders(), isEmpty);
      expect(
        jsonDecode(
          await File('${target.path}/templates/registry.json').readAsString(),
        )['templates'],
        hasLength(1),
      );
      expect(
        jsonDecode(
          await File('${target.path}/templates/registry.json').readAsString(),
        )['templates'][0]['id'],
        'old-template',
      );
      expect(
        jsonDecode(
          await File('${target.path}/elements/registry.json').readAsString(),
        )['elements'][0]['id'],
        'old-element',
      );
    },
  );
}
