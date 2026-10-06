import 'dart:async';
import 'package:flutter/material.dart';
import '../sync/sync_state.dart';
import 'cloud_controller.dart';

class CloudStatus extends StatelessWidget {
  const CloudStatus({super.key, this.cloud});
  final CloudController? cloud;
  @override
  Widget build(BuildContext context) => cloud == null
      ? const Text(
          'Guardado en este dispositivo',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )
      : AnimatedBuilder(
          animation: cloud!,
          builder: (_, _) => Text(
            cloud!.status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
}

class CloudControls extends StatelessWidget {
  const CloudControls({super.key, required this.cloud});
  final CloudController cloud;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: cloud,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (MediaQuery.sizeOf(context).width >= 850)
          SizedBox(width: 270, child: CloudStatus(cloud: cloud)),
        IconButton(
          tooltip: 'Google Drive',
          icon: Icon(switch (cloud.status.phase) {
            SyncPhase.synced => Icons.cloud_done_outlined,
            SyncPhase.error ||
            SyncPhase.needsSignIn => Icons.cloud_off_outlined,
            _ => Icons.cloud_outlined,
          }),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _CloudDialog(cloud: cloud),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );
}

class _CloudDialog extends StatelessWidget {
  const _CloudDialog({required this.cloud});
  final CloudController cloud;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: cloud,
    builder: (context, _) => AlertDialog(
      title: const Text('Google Drive'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cloud.account != null) ...[
              Text(
                cloud.account!.email,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],
            CloudStatus(cloud: cloud),
            const SizedBox(height: 12),
            Text(
              !cloud.configured
                  ? 'Esta versión necesita configurar la conexión con Google Drive. Tus apuntes siguen guardados en este dispositivo.'
                  : cloud.busy
                  ? 'Completá la conexión en la ventana de Google.'
                  : 'Al conectar, los apuntes de esta cuenta se sincronizan automáticamente. Podés seguir escribiendo sin conexión.',
            ),
            if (cloud.account == null && cloud.configured && !cloud.busy) ...[
              const SizedBox(height: 12),
              const Text(
                'La primera cuenta incluirá tus apuntes locales. Cada cuenta mantiene su propia biblioteca.',
              ),
            ],
            if (cloud.message != null) ...[
              const SizedBox(height: 12),
              Text(cloud.message!),
            ],
            if (cloud.busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (cloud.configured && !cloud.busy) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.account_circle_outlined),
                label: Text(
                  cloud.status.phase == SyncPhase.needsSignIn
                      ? 'Reconectar con Google'
                      : cloud.connected
                      ? 'Cambiar cuenta'
                      : 'Conectar con Google',
                ),
                onPressed: () => unawaited(cloud.connect()),
              ),
              if (cloud.connected) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: cloud.status.phase == SyncPhase.syncing
                          ? null
                          : () => unawaited(cloud.synchronize()),
                      child: const Text('Sincronizar ahora'),
                    ),
                    TextButton(
                      onPressed: () => unawaited(cloud.disconnect()),
                      child: const Text('Desconectar'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (cloud.busy)
          TextButton(
            onPressed: () => unawaited(cloud.cancelConnection()),
            child: const Text('Cancelar conexión'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
