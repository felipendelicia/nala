import 'package:flutter/material.dart';

import '../document/notebook_recording.dart';
import '../editor/editor_controller.dart';
import 'audio_comment_session.dart' show audioDuration;
import 'audio_service.dart' show AudioPermissionDenied;
import 'notebook_audio_session.dart';

class RecordingPanel extends StatefulWidget {
  const RecordingPanel({
    super.key,
    required this.session,
    required this.controller,
    required this.onClose,
  });
  final NotebookAudioSession session;
  final EditorController controller;
  final VoidCallback onClose;
  @override
  State<RecordingPanel> createState() => _RecordingPanelState();
}

class _RecordingPanelState extends State<RecordingPanel> {
  bool _closing = false;

  String get _errorMessage {
    if (widget.session.pendingSave) {
      return 'No se pudo guardar. La grabación se conserva para reintentar.';
    }
    final error = widget.session.error;
    if (error is AudioPermissionDenied) {
      return 'Permití el uso del micrófono para grabar la clase.';
    }
    if (error is FormatException) return error.message;
    return 'No se pudo usar el audio. Revisá el dispositivo y volvé a intentarlo.';
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await widget.session.suspend();
      if (mounted) widget.onClose();
    } catch (_) {
      // The session retains the WAV and exposes the storage error. Keep its
      // retry/discard controls accessible while closing is blocked.
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _discardPending() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar grabación pendiente'),
        content: const Text(
          'Se borrará el audio que todavía no se pudo guardar. La tinta se conserva sin sus vínculos a esta grabación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar grabación'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.session.cancel();
  }

  Future<void> _rename(NotebookRecording recording) async {
    var title = recording.title;
    var valid = true;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Nombre de la grabación'),
          content: TextFormField(
            initialValue: title,
            onChanged: (value) => title = value,
            autofocus: true,
            maxLength: 160,
            decoration: InputDecoration(
              labelText: 'Nombre',
              errorText: valid ? null : 'Escribí un nombre.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value = title.trim();
                if (value.isEmpty) {
                  update(() => valid = false);
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Guardar nombre'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await widget.controller.apply(
      (n) => n.copyWith(
        recordings: [
          for (final current in n.recordings)
            if (current.id == recording.id)
              current.copyWith(title: result)
            else
              current,
        ],
      ),
    );
  }

  Future<void> _delete(NotebookRecording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar grabación'),
        content: const Text(
          'La tinta se conserva y deja de estar vinculada a este audio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.session.stopPlayback();
    await widget.controller.apply(
      (n) => n.copyWith(
        recordings: n.recordings.where((r) => r.id != recording.id).toList(),
        pages: [
          for (final page in n.pages)
            page.copyWith(
              strokes: [
                for (final stroke in page.strokes)
                  if (stroke.audioRecordingId == recording.id)
                    stroke.copyWith(audioRecordingId: null, audioOffsetMs: null)
                  else
                    stroke,
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.session, widget.controller]),
    builder: (context, _) {
      final session = widget.session,
          recordings = widget.controller.notebook.recordings;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          width: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Audio de clase',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar audio',
                      onPressed: _closing ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      session.recording
                          ? 'Grabando · ${audioDuration(session.durationMs)}'
                          : session.pendingSave
                          ? 'Grabación pendiente de guardar · ${audioDuration(session.durationMs)}'
                          : 'Iniciá una grabación para vincular lo que escribís con el audio.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: session.busy || _closing
                          ? null
                          : session.pendingSave
                          ? session.retrySave
                          : session.recording
                          ? session.stop
                          : session.start,
                      icon: Icon(
                        session.pendingSave
                            ? Icons.save_outlined
                            : session.recording
                            ? Icons.stop_circle_outlined
                            : Icons.mic_none,
                      ),
                      label: Text(
                        session.pendingSave
                            ? 'Reintentar guardar'
                            : session.recording
                            ? 'Detener y guardar'
                            : 'Grabar clase',
                      ),
                    ),
                    if (session.pendingSave)
                      TextButton.icon(
                        onPressed: session.busy || _closing
                            ? null
                            : _discardPending,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Descartar grabación pendiente'),
                      ),
                    if (session.busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (session.playing)
                      TextButton.icon(
                        onPressed: session.stopPlayback,
                        icon: const Icon(Icons.stop),
                        label: const Text('Detener reproducción'),
                      ),
                    if (session.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _errorMessage,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: recordings.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Las grabaciones guardadas aparecen acá.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: recordings.length,
                        itemBuilder: (context, index) {
                          final recording = recordings[index];
                          final date = recording.createdAt.toLocal();
                          final playing =
                              session.activePlaybackId == recording.id;
                          return Card(
                            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    recording.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${audioDuration(recording.durationMs)} · ${date.day}/${date.month}/${date.year}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  Wrap(
                                    spacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      TextButton.icon(
                                        onPressed:
                                            session.recording || session.busy
                                            ? null
                                            : () => playing
                                                  ? session.stopPlayback()
                                                  : session.playRecording(
                                                      recording,
                                                    ),
                                        icon: Icon(
                                          playing
                                              ? Icons.stop
                                              : Icons.play_arrow,
                                        ),
                                        label: Text(
                                          playing ? 'Detener' : 'Escuchar',
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Renombrar grabación',
                                        onPressed:
                                            session.pendingSave || session.busy
                                            ? null
                                            : () => _rename(recording),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar grabación',
                                        onPressed:
                                            session.pendingSave || session.busy
                                            ? null
                                            : () => _delete(recording),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
