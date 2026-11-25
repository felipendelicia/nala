# Servidor privado de Nala Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** Synchronize one private notebook library between Android and Linux through the owner's server, with durable offline editing.

**Architecture:** A Python service stores immutable revisions, folders and content-addressed assets. Flutter uses the existing repository and synchronization engine with an authenticated HTTP adapter and incremental revision cursors. The owner configures the server URL and a separate credential on each device.

**Tech Stack:** Flutter, Dart, Python 3, SQLite, HTTPS reverse proxy and OCI container.

**Spec:** `docs/superpowers/specs/2026-11-24-servidor-nala-design.md`.

## Global Constraints

Preserve local notebooks, revision identifiers, folder tombstones and conflict branches. Confirm a new synchronization destination before uploading. Keep device credentials in secure storage or in memory for the session. Preserve Android and Linux support. Remove the previous cloud integration from the current distribution.

## Review Focus

Check partial attachment retries, confirmation lost after an accepted revision, resuming an offline queue after restart, migration when two catalogs contain common revisions, and server identity changes after a restore.

## HTTP contract

All routes below are under `/v1`. Requests use `Authorization: Bearer <token>`. `GET /identity` returns `{"id":"<opaque generation>"}`. Other requests send `X-Nala-Server` with that identity. A mismatch returns `409` with `{"error":"server_changed"}` before processing. Credentials invalid or revoked return `401`. Responses must not redirect clients.

- `GET /revisions?after=0&limit=50` returns `{"items":[<NotebookCodec revision objects>],"next":<integer cursor>,"more":<bool>}`. `PUT /revisions` accepts one revision object. Revisiting the same revision and content succeeds. Missing assets or different content for a revision ID returns `409`.
- `GET /folders` returns `{"items":[<NoteFolder JSON objects>]}`. `PUT /folders` accepts this batch shape and merges it atomically, using the same deterministic merge ordering as the app. A single folder object is also accepted.
- `HEAD /assets/<sha256>` returns `200` with `Upload-Offset` equal to the complete length, or `404` with `Upload-Offset` equal to the staged length or zero. An active upload also returns `Upload-Length` with its declared total. `PATCH /assets/<sha256>` accepts raw bytes with decimal `Upload-Offset` and `Upload-Length` headers, up to 4 MiB per request. An offset of zero can restart a partial upload when its previous total differs. A successful response is `204` with the new `Upload-Offset`. A stale offset returns `409` with the current offset. Completion verifies SHA-256 before publishing the asset. `GET /assets/<sha256>` returns raw bytes and supports a single `Range: bytes=<offset>-` request with `206`/`Content-Range`.

## Tasks

### 1. Private service and container

- [x] In `server/`, add the Python command line, service, SQLite/asset persistence, container and tests. Commands are `serve`, `token-create <label>`, `token-revoke <label>`, `backup <archive>` and `restore <archive>`. Configure the data path with `NALA_DATA_DIR` and the listen port with `NALA_PORT`. `restore` requires a stopped, empty service and rotates the server identity.
- [x] Run Python tests over real HTTP. Cover authentication, revocation, immutable revisions, missing assets, resumed chunk upload, pagination, folder ordering, backup and restore. Check the operational container configuration.

### 2. Synchronization transport

- [x] Add `lib/sync/server_remote_store.dart` with `ServerRemoteStore`, adhering to `RemoteStore` and an incremental pull interface. Reuse the document worker. Persist a cursor only after the consumer accepts each page and associate it with server identity and the active local library. Retain existing retry, conflict and offline behavior.
- [x] Run focused Flutter transport and engine tests. Exercise invalid authentication, blocked redirects, identity mismatch, replays, interrupted transfer and incremental pull failure.

### 3. App configuration and migration

- [x] Update `lib/account/cloud_controller.dart`, `lib/account/cloud_panel.dart`, `lib/app.dart` and dependencies. Connect a URL and token only after identity is checked and the user confirms. Persist identity and URL separately from the credential. Stage an initial full upload from the current catalog, and preserve previously selected legacy catalogs from their local paths. Suspend uploads for identity changes or restored server generations until confirmation.
- [x] Remove the previous integration's network, authentication and tests. Refresh plugin manifests. Exercise initial migration, identity mismatch and revocation in Flutter tests.

### 4. Delivery and integration

- [x] Replace obsolete instructions with `docs/server-setup.md`, covering HTTPS, deployment, portable backups and device setup. Update current documentation and clean out older integration instructions.
- [ ] Run a client-to-server round trip with two temporary SQLite catalogs, attachment migration, restart and offline conflicts. Run Flutter analysis and the Flutter suite. Build Android ARM64 and Linux x64.
- [ ] Deploy to the owner's server once the host, access, HTTPS endpoint and backup destination are available. Verify the deployed endpoint and both clients as access permits.
