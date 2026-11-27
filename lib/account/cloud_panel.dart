import 'dart:async';
import 'package:flutter/material.dart';
import '../sync/sync_state.dart';
import 'cloud_controller.dart';

class CloudStatus extends StatelessWidget {
  const CloudStatus({super.key, this.cloud});

  final CloudController? cloud;

  @override
  Widget build(BuildContext context) {
    const local = SyncStatus(SyncPhase.localOnly);
    if (cloud == null) return _label(local.label);
    return ListenableBuilder(
      listenable: cloud!,
      builder: (context, _) => _label(cloud!.status.label),
    );
  }

  Widget _label(String label) =>
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
}

class ServerSettingsTile extends StatelessWidget {
  const ServerSettingsTile({super.key, required this.cloud});

  final CloudController cloud;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cloud,
    builder: (context, _) {
      final status = cloud.status;
      return ListTile(
        leading: Icon(switch (status.phase) {
          SyncPhase.synced => Icons.cloud_done_outlined,
          SyncPhase.error || SyncPhase.needsSignIn => Icons.cloud_off_outlined,
          _ => Icons.cloud_outlined,
        }),
        title: const Text('Servidor privado'),
        subtitle: Text(status.label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) => _CloudDialog(cloud: cloud),
          );
          await cloud.cancelConnection();
        },
      );
    },
  );
}

class _CloudDialog extends StatefulWidget {
  const _CloudDialog({required this.cloud});

  final CloudController cloud;

  @override
  State<_CloudDialog> createState() => _CloudDialogState();
}

class _CloudDialogState extends State<_CloudDialog> {
  CloudController get cloud => widget.cloud;
  late final _url = TextEditingController(
    text: cloud.destination?.url.toString(),
  );
  final _token = TextEditingController();
  bool _editing = false, _remember = true;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    await cloud.probe(_url.text, _token.text);
    if (mounted && cloud.pendingConnection != null) _token.clear();
  }

  Future<void> _confirm() async {
    await cloud.confirmConnection(remember: _remember);
    if (mounted && cloud.connected) setState(() => _editing = false);
  }

  Future<void> _select(LocalCatalog catalog) async {
    _token.clear();
    await cloud.selectCatalog(catalog);
    if (!mounted) return;
    _url.text = cloud.destination?.url.toString() ?? '';
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cloud,
    builder: (context, _) {
      final pending = cloud.pendingConnection;
      final status = cloud.status;
      final lastSuccessfulSync = cloud.lastSuccessfulSync;
      final needsReconnect = status.phase == SyncPhase.needsSignIn;
      final showForm = _editing || !cloud.connected || needsReconnect;
      final reconnectMessage = needsReconnect ? status.message : null;
      final message = reconnectMessage ?? cloud.message ?? status.message;
      return PopScope(
        canPop: !cloud.busy,
        child: AlertDialog(
          title: const Text('Servidor de Nala'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cloud.catalogs.length > 1 && pending == null) ...[
                  DropdownButtonFormField<LocalCatalog>(
                    key: ValueKey(cloud.activeCatalog),
                    initialValue: cloud.activeCatalog,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Biblioteca local',
                    ),
                    items: [
                      for (final catalog in cloud.catalogs)
                        DropdownMenuItem(
                          value: catalog,
                          child: Text(
                            catalog.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: cloud.busy
                        ? null
                        : (catalog) {
                            if (catalog != null) unawaited(_select(catalog));
                          },
                  ),
                  const SizedBox(height: 16),
                ],
                CloudStatus(cloud: cloud),
                if (status.pendingCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    status.pendingCount == 1
                        ? '1 cambio local pendiente'
                        : '${status.pendingCount} cambios locales pendientes',
                  ),
                ],
                if (lastSuccessfulSync != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Última sincronización completa: ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(lastSuccessfulSync.toLocal()), alwaysUse24HourFormat: true)}',
                  ),
                ],
                if (pending != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    pending.destination.url.toString(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pending.requiresUpload
                        ? 'Al confirmar, Nala enviará la biblioteca abierta a este servidor. Tus apuntes seguirán disponibles en este dispositivo.'
                        : pending.isNewDestination
                        ? 'Al conectar, Nala sincronizará esta biblioteca con el servidor.'
                        : 'Confirmá la conexión para retomar la sincronización con este servidor.',
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Recordar la credencial en este dispositivo',
                    ),
                    subtitle: const Text(
                      'Si el llavero no está disponible, la conexión durará esta sesión.',
                    ),
                    value: _remember,
                    onChanged: cloud.busy
                        ? null
                        : (remember) => setState(() => _remember = remember!),
                  ),
                ] else if (showForm) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    enabled: !cloud.busy,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'URL del servidor',
                      hintText: 'https://nala.ejemplo.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _token,
                    enabled: !cloud.busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => unawaited(_verify()),
                    decoration: const InputDecoration(
                      labelText: 'Credencial del dispositivo',
                    ),
                  ),
                ] else if (cloud.destination != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    cloud.destination!.url.toString(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(message),
                ],
                if (cloud.busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (pending == null &&
                    !cloud.busy &&
                    (cloud.connected || needsReconnect)) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (!showForm)
                        TextButton(
                          onPressed: status.phase == SyncPhase.syncing
                              ? null
                              : () => unawaited(cloud.synchronize()),
                          child: Text(
                            status.phase == SyncPhase.error
                                ? 'Reintentar sincronización'
                                : 'Sincronizar ahora',
                          ),
                        ),
                      TextButton(
                        onPressed: () => unawaited(cloud.disconnect()),
                        child: const Text('Desconectar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (pending != null || cloud.verifying)
              TextButton(
                onPressed: !cloud.busy || cloud.verifying
                    ? () => unawaited(cloud.cancelConnection())
                    : null,
                child: const Text('Cancelar conexión'),
              )
            else
              TextButton(
                onPressed: cloud.busy
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            if (pending != null)
              FilledButton(
                onPressed: cloud.busy ? null : () => unawaited(_confirm()),
                child: Text(
                  pending.requiresUpload ? 'Migrar y conectar' : 'Conectar',
                ),
              )
            else if (showForm)
              FilledButton(
                onPressed: cloud.busy ? null : () => unawaited(_verify()),
                child: const Text('Verificar conexión'),
              )
            else if (!cloud.busy)
              FilledButton(
                onPressed: () {
                  _url.text = cloud.destination?.url.toString() ?? '';
                  setState(() => _editing = true);
                },
                child: const Text('Configurar conexión'),
              ),
          ],
        ),
      );
    },
  );
}
