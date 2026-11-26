import 'dart:math' as math;

import 'package:flutter/material.dart';

sealed class PageAction {
  const PageAction();
}

final class MovePageAction extends PageAction {
  const MovePageAction(this.targetIndex);

  final int targetIndex;
}

final class DeletePageAction extends PageAction {
  const DeletePageAction();
}

enum _PageActionChoice { move, delete }

Future<PageAction?> showPageActions(
  BuildContext context, {
  required int index,
  required int pageCount,
}) async {
  final pageNumber = index + 1;
  final canChangePages = pageCount > 1;
  final choice = await showDialog<_PageActionChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Hoja $pageNumber'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Mover hoja'),
            enabled: canChangePages,
            onTap: canChangePages
                ? () => Navigator.pop(dialogContext, _PageActionChoice.move)
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Eliminar hoja'),
            enabled: canChangePages,
            onTap: canChangePages
                ? () => Navigator.pop(dialogContext, _PageActionChoice.delete)
                : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
  if (!context.mounted) return null;
  switch (choice) {
    case _PageActionChoice.move:
      final target = await _showMoveTarget(context, index, pageCount);
      return target == null ? null : MovePageAction(target);
    case _PageActionChoice.delete:
      final confirm = await _confirmDelete(context, pageNumber);
      return confirm == true ? const DeletePageAction() : null;
    case null:
      return null;
  }
}

Future<int?> _showMoveTarget(BuildContext context, int index, int pageCount) =>
    showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mover hoja ${index + 1}'),
        content: SizedBox(
          width: 320,
          height: math.min(336, 48.0 * (pageCount - 1)),
          child: ListView.builder(
            itemCount: pageCount - 1,
            itemExtent: 48,
            itemBuilder: (context, option) {
              final target = option < index ? option : option + 1;
              return ListTile(
                title: Text('Posición ${target + 1}'),
                onTap: () => Navigator.pop(dialogContext, target),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

Future<bool?> _confirmDelete(BuildContext context, int pageNumber) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar hoja $pageNumber?'),
        content: const Text('La hoja se quitará de este apunte.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
