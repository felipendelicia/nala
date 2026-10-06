import 'package:flutter/material.dart';
import '../audio/audio_comment_session.dart';
import '../audio/comment_audio_player.dart';
import '../audio/audio_service.dart';
import '../document/asset_store.dart';
import '../document/page_comment.dart';

class CommentDialog extends StatefulWidget {
  const CommentDialog({
    super.key,
    required this.comment,
    required this.readOnly,
    this.assets,
    this.audio,
    this.directory,
    this.player,
  });
  final PageComment comment;
  final bool readOnly;
  final AssetStore? assets;
  final AudioDevice? audio;
  final String? directory;
  final CommentAudioPlayer? player;
  @override
  State<CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<CommentDialog> {
  late final text = TextEditingController(text: widget.comment.text);
  late final AudioCommentSession? session =
      widget.assets != null &&
          widget.audio != null &&
          widget.directory != null &&
          !widget.readOnly
      ? AudioCommentSession(
          device: widget.audio!,
          assets: widget.assets!,
          directory: widget.directory!,
        )
      : null;
  bool removedAudio = false, saving = false, allowPop = false;
  Object? error;
  Future<void> cancel() async {
    if (saving) return;
    try {
      await session?.cancel();
      await widget.player?.stop();
    } finally {
      if (mounted) {
        setState(() => allowPop = true);
        Navigator.pop(context);
      }
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      var id = removedAudio ? null : widget.comment.audioAssetId;
      var duration = removedAudio ? null : widget.comment.audioDurationMs;
      if (session?.recording == true) await session!.stop();
      if (session?.error != null) throw session!.error!;
      if (session?.ready == true) {
        final attachment = await session!.commit();
        if (attachment == null) {
          throw StateError('No se pudo guardar el audio.');
        }
        id = attachment.assetId;
        duration = attachment.durationMs;
      }
      if (text.text.trim().isEmpty && id == null) {
        throw StateError('Escribí algo o grabá una nota de voz.');
      }
      await session?.close();
      await widget.player?.stop();
      if (mounted) {
        setState(() => allowPop = true);
        Navigator.pop(
          context,
          widget.comment.copyWith(
            text: text.text.trim(),
            audioAssetId: id,
            audioDurationMs: duration,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> record() async {
    await widget.player?.stop();
    await session?.start();
  }

  @override
  void dispose() {
    text.dispose();
    session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session ?? text,
    builder: (context, _) => PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel();
      },
      child: AlertDialog(
        title: const Text('Comentario'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.readOnly)
                  Text(
                    widget.comment.text.isEmpty
                        ? 'Nota de voz'
                        : widget.comment.text,
                  )
                else
                  TextField(
                    controller: text,
                    autofocus: true,
                    maxLines: 5,
                    minLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Una idea, una duda, algo para repasar…',
                    ),
                  ),
                const SizedBox(height: 16),
                if (!removedAudio && widget.comment.audioAssetId != null)
                  Row(
                    children: [
                      if (widget.player != null)
                        Expanded(
                          child: AnimatedBuilder(
                            animation: widget.player!,
                            builder: (context, _) => OutlinedButton.icon(
                              onPressed: saving || session?.recording == true
                                  ? null
                                  : () => widget.player!.play(
                                      widget.comment.audioAssetId!,
                                    ),
                              icon: Icon(
                                widget.player!.activeId ==
                                        widget.comment.audioAssetId
                                    ? Icons.stop
                                    : Icons.play_arrow,
                              ),
                              label: Text(
                                'Escuchar · ${audioDuration(widget.comment.audioDurationMs ?? 0)}',
                              ),
                            ),
                          ),
                        ),
                      if (!widget.readOnly)
                        IconButton(
                          tooltip: 'Quitar audio',
                          onPressed: saving
                              ? null
                              : () {
                                  widget.player?.stop();
                                  setState(() => removedAudio = true);
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                if (session != null) ...[
                  if (session!.recording)
                    Row(
                      children: [
                        const Icon(Icons.circle, color: Colors.red, size: 12),
                        const SizedBox(width: 8),
                        Text(audioDuration(session!.durationMs)),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: session!.busy ? null : session!.stop,
                          icon: const Icon(Icons.stop),
                          label: const Text('Terminar grabación'),
                        ),
                      ],
                    )
                  else if (session!.ready)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: saving ? null : session!.preview,
                            icon: Icon(
                              session!.playing ? Icons.stop : Icons.play_arrow,
                            ),
                            label: Text(
                              'Escuchar · ${audioDuration(session!.durationMs)}',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Descartar grabación',
                          onPressed: saving ? null : session!.cancel,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: saving || session!.busy ? null : record,
                      icon: const Icon(Icons.mic_none),
                      label: Text(
                        session!.busy
                            ? 'Preparando micrófono…'
                            : 'Grabar nota de voz',
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'La grabación se detiene al salir de Nala.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                if (error != null || session?.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${error ?? session?.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (session?.error != null)
                  TextButton(
                    onPressed: saving ? null : session!.cancel,
                    child: const Text('Continuar sin audio'),
                  ),
                if (saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : cancel,
            child: Text(widget.readOnly ? 'Cerrar' : 'Cancelar'),
          ),
          if (!widget.readOnly)
            FilledButton(
              onPressed: saving || session?.busy == true ? null : save,
              child: const Text('Guardar comentario'),
            ),
        ],
      ),
    ),
  );
}
