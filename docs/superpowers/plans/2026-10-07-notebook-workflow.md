# Notebook workflow implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development with exclusive file ownership and serialized Flutter verification. Steps use checkboxes for tracking.

**Goal:** Deliver six working notebook features in Nala 0.6.0 on Android and Linux.

**Architecture:** Extend page objects additively, store reusable content and toolbar settings alongside existing registries, and restore validated logical backups through an atomic repository batch. Root integrates editor/workspace interactions; independent agents implement isolated subsystems.

**Tech Stack:** Flutter/Dart, SQLite, image, archive, flutter_math_fork.

**Spec:** `docs/superpowers/specs/2026-10-07-notebook-workflow.md`

## Global Constraints

- Keep the compact header and reading layout; grayscale/Manrope appearance.
- Preserve previous document decoding, Android signature and existing Gradle memory limits.
- Serialize Flutter through `tool/flutter-safe`; agents request verification from root.
- Use temporary roots for tests and release smoke; never real user notes.
- Deliver Android ARM64 and Linux x64; archive previous dist 0.5.1.

## Review Focus

- Repeated recropping must retain original bytes and undo must restore previous appearance.
- Existing open link targets must navigate without rebuilding editor controllers or losing ink.
- Locked objects must resist stale selections, clipboard cut and direct transform operations.
- Corrupt/oversized backups must leave existing documents and registries unchanged.
- Concurrent split panes must see persistent toolbar/element updates without lost writes.

## Task 1: Objects, image editing and math (media agent)

**Own:** `lib/document/page_object.dart`, `lib/document/page_link.dart`, media/math dialogs and helpers, `lib/editor/paper_canvas.dart`, `lib/editor/selection_operations.dart`, asset enumeration and `lib/pdf/pdf_export_service.dart`; their focused tests. Root owns editor and workspace integration.

**Interfaces:** `PageLink(notebookId:, pageId:)`; `PageObject` optional `originalAssetId`, `opacity=1`, `locked=false`, `link`; latex kind with source text plus image asset. Provide `showImageEditor` and `showLatexEditor` returning edited object or result and document exact signatures to root before integration.

- [x] Write failing tests for old/new codec round trip, invalid metadata, original asset enumeration, locked selection and formula/image export.
- [x] Ask root to run focused tests and record the failure; implement model and rendering.
- [x] Add crop/reset/opacity image dialog and validated math preview/capture with edit source.
- [x] Ask root for focused green verification; return interfaces and review risks.

## Task 2: Reusable elements and link picker (elements agent)

**Own:** `lib/elements/*`, `lib/links/*`, focused tests. Consume Task 1 model contract; do not modify shared model/editor files.

**Interfaces:** Element store rooted at library root, JSON registry `elements/registry.json`, list/save/remove/rename/insert APIs documented to root. Link picker returns `PageLink` and user-facing label, using repository entries and pages.

- [x] Write failing tests for save/reopen, new IDs, normalized placement, stripped recording references and retained assets.
- [x] Ask root for red verification; implement bounded, serialized atomic registry and element picker.
- [x] Implement searchable notebook/page picker and unavailable destination handling contract.
- [x] Ask root for green verification and return integration signatures.

## Task 3: Restorable backup (backup agent)

**Own:** `lib/backup/*`, `lib/document/sqlite_notebook_repository.dart`, `lib/library/library_screen.dart`, Android generic save handler, PDF document saver optional MIME extension; focused tests. Do not edit bootstrap or page model.

**Interfaces:** Backup service consumes root/repository/assets/device ID; archive manifest covers all heads plus referenced assets and whitelisted registries/preferences. Restore creates copies/remaps links. Repository atomic import batch receives folders/revisions and queues uploads once committed. Backup library dialog is available from library menu.

- [x] Write failing round-trip tests including folders, conflict heads, recording, original image, formula, templates and elements.
- [x] Ask root for red verification; implement manifest export, bounded validation and atomic document import.
- [x] Test corrupt hashes, duplicate paths, traversal, missing assets and ID remapping; preserve current library on rejection.
- [x] Add native `.nala.zip` save/open and preview/restore dialog; ask root for green verification.

## Task 4: Toolbar and integration (root)

**Own:** toolbar preferences/dialog, editor toolbar/advanced toolbar, bootstrap if necessary, EditorScreen and DocumentWorkspace, pubspec/dependencies, integration tests, docs and packaging.

- [x] Add dependencies and write persistent toolbar ordering/placement tests; run red then implement.
- [x] Integrate element actions, image/math edit, link insert/attach/open and unlock with undo through EditorController.
- [x] Keep stable editor keys; add navigation request token/page ID for already open linked tabs.
- [x] Verify all unit/widget tests, analysis and native Linux flows including PDF and backup restore.
- [x] Request independent subsystem review; fix findings and rerun affected checks.
- [x] Build both releases serially, preserve 0.5.1, package and verify manifests/hashes/native smoke.
- [x] Update guide/progress/delivery records, commit reviewed changes and provide final artifact links.
