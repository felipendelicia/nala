import 'package:flutter/material.dart';
import '../audio/audio_comment_session.dart';
import '../audio/comment_audio_player.dart';
import '../document/page_comment.dart';
import '../ui/app_theme.dart';

class CommentsPanel extends StatelessWidget {
  const CommentsPanel({
    super.key,
    required this.comments,
    required this.onOpen,
    required this.onClose,
    this.onAdd,
    this.onDelete,
    this.player,
  });
  final List<PageComment> comments;
  final ValueChanged<PageComment> onOpen;
  final VoidCallback onClose;
  final VoidCallback? onAdd;
  final ValueChanged<PageComment>? onDelete;
  final CommentAudioPlayer? player;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(
      width: 288,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Comentarios de esta hoja',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar comentarios',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (onAdd != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Agregar comentario'),
              ),
            ),
          Expanded(
            child: comments.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Las ideas y notas de voz de esta hoja aparecen acá.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment = comments[index];
                      return Card(
                        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => onOpen(comment),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          comment.text.isEmpty
                                              ? 'Nota de voz'
                                              : comment.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  if (comment.audioAssetId != null &&
                                      player != null)
                                    Expanded(
                                      child: AnimatedBuilder(
                                        animation: player!,
                                        builder: (context, _) =>
                                            TextButton.icon(
                                              onPressed: () => player!.play(
                                                comment.audioAssetId!,
                                              ),
                                              icon: Icon(
                                                player!.activeId ==
                                                        comment.audioAssetId
                                                    ? Icons.stop_circle_outlined
                                                    : Icons.play_circle_outline,
                                              ),
                                              label: Text(
                                                audioDuration(
                                                  comment.audioDurationMs ?? 0,
                                                ),
                                              ),
                                            ),
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  if (onDelete != null)
                                    IconButton(
                                      tooltip: 'Eliminar comentario',
                                      onPressed: () => onDelete!(comment),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
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
          if (player != null)
            AnimatedBuilder(
              animation: player!,
              builder: (context, _) => player!.error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${player!.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    ),
  );
}

class CommentPinsPainter extends CustomPainter {
  CommentPinsPainter(this.comments, this.scale);
  final List<PageComment> comments;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < comments.length; i++) {
      final comment = comments[i];
      final position = Offset(comment.x, comment.y);
      canvas.drawCircle(position, 12 / scale, Paint()..color = nalaAnnotation);
      canvas.drawCircle(
        position,
        12 / scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / scale
          ..color = Colors.white,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12 / scale,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, position - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(CommentPinsPainter old) =>
      old.comments != comments || old.scale != scale;
}
