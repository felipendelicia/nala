import 'package:flutter/material.dart';

import '../editor/editor_controller.dart';
import 'study_card.dart';
import 'study_scheduler.dart';

class StudyPanel extends StatefulWidget {
  const StudyPanel({
    super.key,
    required this.controller,
    this.initialFront,
    this.onClose,
  });
  final EditorController controller;
  final String? initialFront;
  final VoidCallback? onClose;
  @override
  State<StudyPanel> createState() => _StudyPanelState();
}

class _StudyPanelState extends State<StudyPanel> {
  bool _reviewing = false,
      _answerVisible = false,
      _busy = false,
      _initialUsed = false;
  String? _currentCardId;
  StudyScheduler get _scheduler => StudyScheduler(now: widget.controller.now);

  @override
  void didUpdateWidget(StudyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFront != widget.initialFront) _initialUsed = false;
    if (oldWidget.controller != widget.controller) {
      _reviewing = false;
      _answerVisible = false;
      _currentCardId = null;
    }
  }

  Future<void> _edit([StudyCard? card]) async {
    var front = card?.front ?? (_initialUsed ? '' : widget.initialFront ?? '');
    var back = card?.back ?? '';
    var valid = true;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(card == null ? 'Nueva tarjeta' : 'Editar tarjeta'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: front,
                    onChanged: (value) => front = value,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Pregunta',
                      hintText: 'Lo que querés recordar',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: back,
                    onChanged: (value) => back = value,
                    minLines: 2,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'Respuesta'),
                  ),
                  if (!valid)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Completá la pregunta y la respuesta.'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final question = front.trim(), answer = back.trim();
                if (question.isEmpty || answer.isEmpty) {
                  update(() => valid = false);
                  return;
                }
                Navigator.pop(context, (question, answer));
              },
              child: const Text('Guardar tarjeta'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final updated =
        card?.copyWith(front: result.$1, back: result.$2) ??
        StudyCard(
          id: widget.controller.newId(),
          front: result.$1,
          back: result.$2,
          dueAt: widget.controller.now().toUtc(),
        );
    await widget.controller.apply(
      (n) => n.copyWith(
        studyCards: [
          for (final existing in n.studyCards)
            if (existing.id == updated.id) updated else existing,
          if (card == null) updated,
        ],
      ),
    );
    if (mounted) {
      setState(() {
        _initialUsed = true;
      });
    }
  }

  Future<void> _delete(StudyCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar tarjeta'),
        content: const Text(
          'Se eliminará esta pregunta y su programación de repaso.',
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
    await widget.controller.apply(
      (n) => n.copyWith(
        studyCards: n.studyCards.where((c) => c.id != card.id).toList(),
      ),
    );
  }

  Future<void> _grade(StudyCard card, StudyRating rating) async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.controller.apply(
      (n) => n.copyWith(
        studyCards: [
          for (final current in n.studyCards)
            if (current.id == card.id)
              _scheduler.review(current, rating)
            else
              current,
        ],
      ),
    );
    if (mounted) {
      setState(() {
        _answerVisible = false;
        _currentCardId = null;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final cards = widget.controller.notebook.studyCards;
      final pending = _scheduler.due(cards);
      final card =
          pending.where((c) => c.id == _currentCardId).firstOrNull ??
          pending.firstOrNull;
      if (card?.id != _currentCardId) {
        _currentCardId = card?.id;
        _answerVisible = false;
      }
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
                        'Tarjetas de estudio',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        tooltip: 'Cerrar estudio',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('Nueva tarjeta'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _reviewing = !_reviewing;
                                _answerVisible = false;
                              }),
                        icon: Icon(
                          _reviewing ? Icons.list_alt : Icons.school_outlined,
                        ),
                        label: Text(
                          _reviewing ? 'Ver tarjetas' : 'Repasar pendientes',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${cards.length} tarjetas · ${pending.length} pendientes',
                  ),
                ),
              ),
              Expanded(child: _reviewing ? _review(card) : _list(cards)),
              if (widget.controller.savingError != null)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No se pudo guardar. Tus cambios siguen en este cuaderno.',
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _list(List<StudyCard> cards) => cards.isEmpty
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Creá una pregunta con su respuesta para empezar a repasar.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      : ListView.builder(
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index], due = card.dueAt.toLocal();
            return Card(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.front,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.back,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      card.dueAt.isAfter(widget.controller.now())
                          ? 'Próximo repaso: ${due.day}/${due.month}/${due.year}'
                          : 'Pendiente de repaso',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Editar tarjeta',
                          onPressed: () => _edit(card),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Eliminar tarjeta',
                          onPressed: () => _delete(card),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

  Widget _review(StudyCard? card) => card == null
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No hay tarjetas pendientes.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(card.front, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              if (!_answerVisible)
                FilledButton(
                  onPressed: () => setState(() => _answerVisible = true),
                  child: const Text('Mostrar respuesta'),
                )
              else ...[
                const Divider(),
                Text(card.back, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                const Text('¿Cuánto recordaste?'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      StudyRating.again: 'Otra vez',
                      StudyRating.hard: 'Difícil',
                      StudyRating.good: 'Bien',
                      StudyRating.easy: 'Fácil',
                    }.entries)
                      OutlinedButton(
                        onPressed: _busy ? null : () => _grade(card, entry.key),
                        child: Text(entry.value),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
}
