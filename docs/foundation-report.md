# Document foundation evidence — 2026-10-07

Task 1 is implemented without changing the notebook schema version. Legacy notebooks omit every new optional field when re-encoded. No dependencies or commits were added. Tests use temporary databases, synthetic audio bytes, generated images and the existing PDF fixtures.

## Interfaces and behavior

- `PageObjectKind { text, image }`; `PageObject` requires `id, kind, x, y, width, height`; defaults `rotation=0, text='', argb=0xff202020, fontSize=16`; optional `assetId`. Rotation is radians around the rectangle center. `copyWith` supports `id, x, y, width, height, rotation, text, argb, fontSize` and preserves kind/media. Its constructor validates finite geometry, positive dimensions/font size, color, nonempty text objects and required SHA256 image asset IDs. Document models do not import UI rectangle types.
- `NotebookRecording` requires `id, title, assetId, durationMs, createdAt`; its constructor validates nonempty IDs/title, SHA256 asset ID and nonnegative duration. `copyWith(title)` supports renaming without changing media.
- `StudyCard` requires `id, front, back, dueAt`; defaults `intervalDays=0, repetitions=0, ease=2.5`. Scheduling counts are integers; ease is a positive finite double. `copyWith` supports all its fields.
- `Notebook.recordings` and `studyCards`, plus `NotebookPage.objects`, are immutable lists defaulting to empty. Notebook has nullable `coverAssetId`. Copies preserve these fields; `coverAssetId:null` explicitly clears the cover.
- `NotebookPage.copyWith` also supports `width, height`. Optional `recognizedText=''` and nullable SHA256 `recognitionFingerprint` round-trip through JSON for cross-device search; `recognitionFingerprint:null` explicitly clears the fingerprint.
- `InkStroke` has optional `audioRecordingId` and `audioOffsetMs`; the pair must be present together, with nonempty ID and nonnegative integer offset. `copyWith` supports `id, argb, width, points` and the nullable audio fields. Existing pressure-curve and sensitivity metadata are preserved. Both audio fields can be explicitly cleared. Unresolved recording IDs are allowed while capture is active; they do not enumerate nonexistent assets.
- `PageBackground.image(assetId)` encodes as `kind:image`. `isImage`, `isPdf` and `kind` distinguish the variants. Image/PDF/background/cover IDs validate SHA256 syntax. Cornell and weekly enum values append to the existing enum ordering; the Spanish menu label helper includes both.
- Decode rejects duplicate page-object IDs throughout a notebook, and duplicate recording/card IDs. New optional fields retain schema version 1.
- `notebookAssets` includes cover, recording audio, object images, image/PDF backgrounds and existing comment audio. Pull verifies every referenced resource before accepting a remote revision.
- `PaperCanvas` takes optional `AssetStore assets`, reads image bytes through that store and paints object order below ink. Text uses fixed document font sizes. Cornell and weekly guide geometry is shared by canvas and PDF export.
- PDF composition retains the existing Unicode font and worker-isolate behavior. Object images and image backgrounds use stored image bytes directly; PDF originals retain the established native render pipeline. Text/image objects are placed and rotated below ink, and comment markers remain above ink.

## Commands and results

1. `tool/flutter-safe test test/document/study_codec_test.dart test/pdf/study_export_test.dart` — RED: new resources were discarded, duplicate/invalid fields accepted, image backgrounds rejected, and PDF Unicode object text absent. One initial fixture inferred a string-only card map; the fixture was corrected before the repeated RED run.
2. `tool/flutter-safe test test/document/study_codec_test.dart test/editor/study_canvas_test.dart` — RED: expected new-field, validation, object rendering and Cornell/weekly failures.
3. `tool/flutter-safe test test/document/study_codec_test.dart --plain-name 'recognized text and fingerprint survive save for cross-device search'` — RED: recognized text was absent after re-encoding.
4. Initial combined GREEN attempt exposed nullable PDF asset arguments; those were fixed. The guide image readback also stalled because a widget test awaited engine raster work inside its fake async clock. That run was stopped; image readback now uses `tester.runAsync`.
5. `tool/flutter-safe test test/editor/study_canvas_test.dart test/pdf/export_test.dart test/pdf/study_export_test.dart` — PASS, 9 tests.
6. Final command:

```sh
tool/flutter-safe test \
  test/document/notebook_codec_test.dart \
  test/document/study_codec_test.dart \
  test/editor/paper_canvas_test.dart \
  test/editor/study_canvas_test.dart \
  test/pdf/export_test.dart \
  test/pdf/study_export_test.dart \
  test/sync/sync_engine_test.dart \
  test/sync/study_media_sync_test.dart
```

PASS: **39 tests**, exit 0, service runtime 10.197 seconds. The existing fixture generator emits its existing Helvetica Unicode warning; exported object/comment Unicode is verified with the bundled font.

The focused tests prove unchanged legacy JSON; data and defaults through the codec; duplicate/malformed resource rejection; unresolved active audio links; recognized-text persistence; temporary SQLite close/reopen; verified cloud resource transfer and rejection of a corrupted cover before notebook visibility; text positioning and visible template guides; PDF Unicode extraction; exact blue image/red ink pixel ordering; direct image background export; existing PDF password, page-size, transparency and worker-isolate behavior.

Files were formatted with the bundled Dart formatter. `git diff --check` passed. Generated PDF evidence is `.dart_tool/pdf-qa/study-objects.pdf`, together with the existing export fixtures. The parent agent owns the integrated full-suite, analysis, editor UI and native delivery checks; those are not claimed by this focused report.
