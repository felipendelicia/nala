# Nala study tools Implementation Plan

> **For agentic workers:** Use executing-plans for shared integration and dispatching-parallel-agents for disjoint feature modules. Felipe explicitly requested autonomous execution; no intermediate approval is required.

**Goal:** Deliver all nine approved editing and study improvements in Android and Linux Nala.
**Architecture:** Backward-compatible immutable notebook data, hash-addressed media, independent feature controllers and a document workspace. Integrate through the existing editor, repository and PDF pipeline.
**Tech Stack:** Flutter/Dart, SQLite, PDFium, native Android ML Kit and local Linux OCR.
**Spec:** docs/superpowers/specs/2026-10-07-study-tools.md

## Global Constraints

- Preserve legacy notes, ink, PDF originals, undo and account partitions.
- Flutter commands run sequentially through tool/flutter-safe, with 2300 MiB RAM, 256 MiB swap and two CPU.
- All new document resources use AssetStore and participate in revision asset enumeration.
- Tests never use a real microphone or user notebook.
- User interface remains in Spanish and supports narrow layouts, dark mode and reading mode.

## Review Focus

- Old documents with missing optional fields must decode unchanged.
- Cut/paste between pages must generate unique object and stroke IDs without losing media references.
- Switching active panels must stop hidden audio and restore temporary S Pen tools.
- Search/recognition completing after another edit must not overwrite that edit.
- New text, images, backgrounds, recordings and cards must survive SQLite reopen and cloud round-trip.

### Task 1: Document foundation
Files: document/page_object.dart, document/notebook_recording.dart, study/study_card.dart, document/notebook.dart, document/notebook_codec.dart, sync/sync_engine.dart, pdf/pdf_export_service.dart, editor/paper_canvas.dart, editor/paper_background.dart.
Interfaces: PageObject (id, kind text/image, x,y,width,height, rotation, text, argb,fontSize,assetId); NotebookPage.objects; Notebook.recordings (NotebookRecording id,title,assetId,durationMs,createdAt), studyCards (StudyCard id,front,back,dueAt,intervalDays,repetitions,ease), coverAssetId; InkStroke audioRecordingId/audioOffsetMs and extended copyWith; PageBackground.image.
- [x] Add failing codec/asset/PDF tests for optional fields, media export and legacy decode.
- [x] Implement immutable data with validation and optional JSON fields.
- [x] Include all resources in sync and render objects/backgrounds in canvas/PDF.
- [x] Run focused tests and record evidence.

### Task 2: Editing tools
Files: editor/shape_tools.dart, selection_operations.dart, pen_favorites.dart, editor_screen.dart, advanced_toolbar.dart, text_object_dialog.dart, media/image_import.dart.
- [x] Add geometry/clipboard/widget failing tests.
- [x] Implement hold recognition, explicit forms, ruler, selection transformations and media/text insertion.
- [x] Add persistent favorites and responsive Spanish controls.
- [x] Verify undo, PDF and editor interactions.

### Task 3: Workspace, templates and search
Files: workspace/document_workspace.dart, library/library_screen.dart, templates/*, search/*, Android OCR bridge.
- [x] Add tests for independent tabs, template reopen and search results.
- [x] Implement template registry and applying backgrounds/covers.
- [x] Implement title/PDF/text search and Android recognition with explicit model download.
- [x] Add document tabs and two independent panes, focused input and safe close.
- [x] Verify native text extraction and platform availability.

### Task 4: Audio and study
Files: audio/notebook_audio_session.dart, audio/recording_panel.dart, audio/seek_audio_player.dart, study/study_scheduler.dart, study/study_panel.dart.
- [x] Add failing lifecycle/timeline/repetition/persistence tests using synthetic audio.
- [x] Implement explicit recording with time-tagged strokes and seek playback.
- [x] Implement editable cards and due-card practice, with copy from selection/text.
- [x] Provide reusable widgets and integrate them in the editor.

### Task 5: Verification and delivery
- [x] Format, analyze and run complete tests through tool/flutter-safe.
- [x] Run native Linux feature/PDF flows, inspect screenshots and exported PDF.
- [x] Review the full diff, fix demonstrated defects and rerun affected checks.
- [x] Build Linux x64 and Android ARM64 sequentially; document exact results and physical checks.
