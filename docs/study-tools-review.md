# Independent study-tools review — 2026-10-07

Reviewed the working tree against `a483c00` and the study-tools specification, including untracked feature modules. This pass was read-only apart from this report; the integration lead owns Flutter tests and builds. Findings below describe the implementation before the lead's corrective pass.

## Strengths

- Optional document fields preserve legacy JSON defaults, immutable lists and hash-addressed resources. Image objects, covers and recordings participate in revision asset verification.
- Recognition saving checks the content fingerprint after asynchronous hashing and applies results through the current editor snapshot.
- Clipboard transforms preserve relative geometry and media, while new objects and strokes receive fresh IDs. Canvas and PDF share template guide geometry.
- Audio ownership is coordinated across players and recording sessions; native acquisition is serialized, with generation checks for canceled starts and temporary playback cleanup.

## Findings

1. **[P1] Failed recording storage deletes the only recoverable capture.** `lib/audio/notebook_audio_session.dart:147-165`. Stop a valid recording with an `AssetStore.put` that throws. `_stop` catches the storage error, then unlinks timed strokes and unconditionally deletes the temporary WAV. `suspend` resolves successfully, allowing the editor/workspace to close after losing the recording. Preserve a valid stopped WAV and its links for retry; distinguish failed persistence from cancellation/corrupt capture, and propagate unresolved saving failure to close. Add a failing-asset-store recovery test.

2. **[P2] Activating a pane cancels the first pen/selection gesture.** `lib/editor/editor_screen.dart:147-150` and `:1486-1488`. Press the stylus or primary mouse button on an inactive split pane. `pointerDown` focuses it and starts `router.down`; the ensuing active-widget update calls `router.reset`, canceling the gesture before its release. Test a complete first gesture with a frame while the pointer is down. Reset outgoing input on deactivation and avoid canceling a gesture that activated its incoming pane.

3. **[P2] Keyboard shortcuts can edit the previous or hidden pane.** `lib/editor/editor_screen.dart:1792-1825`. The retained editors use `Focus(autofocus: widget.active)` without requesting/unfocusing a focus node or guarding shortcut callbacks. Flutter autofocus is one-shot and only acts when its focus scope has no established focus. Clicking another pane's canvas changes workspace activation but does not transfer keyboard focus, so undo/delete/paste can reach the former editor. Explicitly transfer focus on activation, disable inactive shortcut actions and cover switching between both visible and offstage tabs.

4. **[P2] A valid small image template makes insertion fail.** `lib/templates/template_store.dart:128-133`, `lib/editor/editor_screen.dart:802-805` and `:880-886`. Import a 32×32 PNG, add a page with it, then insert text: `target.height - 48` becomes negative, and the new `PageObject` throws for negative height outside a catch. Image insertion also computes a negative size. Image template validation accepts any positive pixel size. Normalize template page geometry or make insertion margins fit the page, with tests for small portrait/landscape image templates.

## Declined to judge

- Real microphone capture, native-device stylus latency and physical handwriting recognition quality: unavailable to this read-only review and assigned to the delivery validation pass.
- Actual latest-build test results: the integration lead is running these sequentially; this review does not claim fresh execution.

## Assessment

**Ready to merge: With fixes.** The architecture supports the approved tools, but recovery from a recording storage failure and pane input/focus behavior require correction. The supplied focused-test reports cover important foundations; the above interaction and failure cases need regression coverage.

## Corrective re-review

The four original findings are addressed in the corrective source pass:

- Stopped valid audio and its ink links survive asset/repository failures. `pendingSave`, save retry and confirmed discard are exposed, and unresolved saving failure blocks session/workspace close. The new tests exercise a rejecting asset store and repository.
- Activation preserves the gesture that initiated focus; deactivation still resets outgoing input. The workspace regression now pumps a frame while the incoming first stylus stroke is down.
- A dedicated focus node is requested on activation, unfocused on deactivation, and inactive editors have no shortcut bindings. The workspace regression checks active-pane undo after the first contact.
- Text/image insertion margins scale down with the page; a 32×32 page has positive usable dimensions. A widget regression checks positive text dimensions and containment.

Two recovery-path interactions need adjustment before the final verdict:

1. **[P2] Forced recovery panel reveal can leave multiple sidebars open.** `lib/editor/editor_screen.dart:1141`. The audio-suspension failure handler sets `showRecording=true` without clearing `showPages` and `showComments`. Unlike the normal audio open action, this can put several fixed-width sidebars into the body's row, overflowing a narrow/split pane and obscuring recovery controls. Clear the other sidebar flags when revealing pending audio.

2. **[P2] Normal deletion of a pending attached recording is undone by save retry.** `lib/audio/recording_panel.dart:131` and `lib/audio/notebook_audio_session.dart:179-182`. Fail repository commit after the valid recording is attached to the current notebook, restore storage, then use its normal delete action. That action removes the recording/links but does not clear `pendingSave` or the retained attachment; retry/close re-adds the deleted recording. Route deletion of this pending recording through confirmed session discard, or disable its ordinary actions until the pending save is resolved.

This re-review inspected source and regression-test intent; it did not execute Flutter or claim test results.

## Final source re-review

Both follow-up interactions are addressed. The forced recovery-panel reveal clears the page/comment sidebar flags (`lib/editor/editor_screen.dart:1141-1145`). Ordinary recording rename/delete actions are disabled while a save is pending or the session is busy (`lib/audio/recording_panel.dart:328-342`); explicit pending discard remains available and is exercised by the recovery-control widget test.

**No remaining source findings in the reviewed scope. Ready to merge from this source review, subject to the integration lead's final tests and delivery checks.** All six reported issues have been corrected. This final pass ran no Flutter commands and changed only this report.
