import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'backup_files.dart';
import 'backup_service.dart';

Future<BackupRestoreResult?> showBackupDialog(
  BuildContext context, {
  required BackupService service,
  required BackupFiles files,
  required Future<void> Function(BackupRestoreResult) onRestored,
}) => showDialog<BackupRestoreResult>(
  context: context,
  builder: (_) =>
      BackupDialog(service: service, files: files, onRestored: onRestored),
);

class BackupDialog extends StatefulWidget {
  const BackupDialog({
    super.key,
    required this.service,
    required this.files,
    required this.onRestored,
  });
  final BackupService service;
  final BackupFiles files;
  final Future<void> Function(BackupRestoreResult) onRestored;
  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  bool busy = false, preferences = false;
  String? message, fileName;
  Uint8List? bytes;
  BackupPreview? preview;
  BackupRestoreResult? result;

  Future<void> _export() async {
    setState(() {
      busy = true;
      message = 'Preparando la copia…';
    });
    try {
      final data = await widget.service.export();
      final saved = await widget.files.save(
        data,
        name:
            'Nala-${DateTime.now().toIso8601String().substring(0, 10)}.nala.zip',
      );
      if (mounted) {
        setState(
          () => message = saved ? 'Backup guardado.' : 'Guardado cancelado.',
        );
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _open() async {
    setState(() {
      busy = true;
      message = 'Abriendo y comprobando el backup…';
    });
    try {
      final selected = await widget.files.open();
      if (selected == null) {
        if (mounted) setState(() => message = null);
        return;
      }
      final checked = await widget.service.inspect(selected.bytes);
      if (mounted) {
        setState(() {
          bytes = selected.bytes;
          fileName = selected.name;
          preview = checked;
          message = null;
        });
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      busy = true;
      message = 'Recuperando las copias…';
    });
    try {
      final restored = await widget.service.restore(
        bytes!,
        restorePreferences: preferences,
      );
      // Restore succeeded even if refreshing the display/preferences fails.
      try {
        await widget.onRestored(restored);
      } catch (_) {
        restored.warnings.add(
          'Las copias están guardadas. Volvé a abrir Nala para actualizar la vista y los ajustes.',
        );
      }
      if (mounted) {
        setState(() {
          result = restored;
          message = null;
          bytes = null;
        });
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _error(Object error) {
    if (mounted) {
      setState(
        () => message = error is FormatException
            ? error.message
            : 'No se pudo completar el backup. Revisá el archivo y el espacio disponible.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Backup de la biblioteca'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result != null) ...[
                Text(
                  'Se recuperaron ${result!.notebookCount} cuadernos en una carpeta nueva.',
                ),
                const SizedBox(height: 8),
                Text(
                  '${result!.templateCount} plantillas · ${result!.elementCount} elementos',
                ),
                for (final warning in result!.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(warning),
                  ),
              ] else if (preview != null) ...[
                Text(fileName!, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Text(
                  '${preview!.notebookCount} cuadernos · ${preview!.headCount} versiones actuales\n'
                  '${preview!.revisionCount} revisiones · ${preview!.folderCount} carpetas\n'
                  '${preview!.assetCount} recursos, incluidas imágenes y grabaciones\n'
                  '${preview!.templateCount} plantillas · ${preview!.elementCount} elementos',
                ),
                const SizedBox(height: 12),
                const Text(
                  'La recuperación crea copias en una carpeta nueva y conserva los apuntes actuales. Los enlaces internos apuntarán a las copias.',
                ),
                if (preview!.preferenceCount > 0) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Recuperar ajustes y favoritos'),
                    value: preferences,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => preferences = value!),
                  ),
                  const Text(
                    'La apariencia se aplica al volver a abrir Nala. Los ajustes anteriores se guardan en la biblioteca.',
                  ),
                ],
                for (final warning in preview!.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(warning),
                  ),
              ] else ...[
                const Text(
                  'Un archivo .nala.zip guarda todos los cuadernos y su historial, versiones en conflicto, carpetas, imágenes, grabaciones, plantillas, elementos y ajustes locales.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'No incluye credenciales ni la identidad de este dispositivo. Podés guardarlo fuera de Nala y recuperarlo en otro dispositivo.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Límites: 128 MB por backup, 64 MB por recurso y 256 MB de contenido total.',
                ),
              ],
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(message!),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, result),
          child: Text(result == null ? 'Cerrar' : 'Abrir carpeta recuperada'),
        ),
        if (result == null && preview == null) ...[
          TextButton(
            onPressed: busy ? null : _open,
            child: const Text('Abrir backup'),
          ),
          FilledButton(
            onPressed: busy ? null : _export,
            child: const Text('Guardar backup'),
          ),
        ] else if (result == null) ...[
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    preview = null;
                    bytes = null;
                    message = null;
                  }),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: busy ? null : _restore,
            child: const Text('Recuperar copias'),
          ),
        ],
      ],
    ),
  );
}
