import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_updates.dart';
import 'github_updates.dart';
import 'linux_update.dart';

enum _UpdateState {
  checking,
  current,
  available,
  installing,
  permission,
  installer,
  restart,
  checkFailed,
  installFailed,
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.updates});

  final AppUpdates updates;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateState _state = _UpdateState.checking;
  UpdateRelease? _release;
  String? _installError;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _state = _UpdateState.checking);
    try {
      final release = await widget.updates.check();
      if (!mounted) return;
      setState(() {
        _release = release;
        _state = release == null
            ? _UpdateState.current
            : _UpdateState.available;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _UpdateState.checkFailed);
    }
  }

  Future<void> _install() async {
    final release = _release;
    if (release == null || _state == _UpdateState.installing) return;
    setState(() {
      _installError = null;
      _state = _UpdateState.installing;
    });
    try {
      final result = await widget.updates.install(release);
      if (!mounted) return;
      setState(() {
        _state = switch (result) {
          UpdateInstallResult.androidInstaller => _UpdateState.installer,
          UpdateInstallResult.androidPermission => _UpdateState.permission,
          UpdateInstallResult.linuxRestart => _UpdateState.restart,
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installError = switch (error) {
          PlatformException() => error.message,
          LinuxUpdateException() => error.message,
          _ => null,
        };
        _state = _UpdateState.installFailed;
      });
    }
  }

  @override
  void dispose() {
    widget.updates.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installing = _state == _UpdateState.installing;
    final message = switch (_state) {
      _UpdateState.checking => 'Buscando en GitHub…',
      _UpdateState.current => 'Ya tenés la última versión disponible.',
      _UpdateState.available => 'Nala ${_release!.version} está disponible.',
      _UpdateState.installing => 'Descargando y verificando Nala…',
      _UpdateState.permission =>
        'Permití que Nala instale aplicaciones en los ajustes de Android. Cuando vuelvas, tocá Instalar.',
      _UpdateState.installer => 'Seguí los pasos de Android para terminar.',
      _UpdateState.restart =>
        'La actualización se aplicará la próxima vez que abras Nala.',
      _UpdateState.checkFailed => 'No se pudieron buscar actualizaciones.',
      _UpdateState.installFailed =>
        _installError ?? 'No se pudo preparar la actualización.',
    };

    return PopScope(
      canPop: !installing,
      child: AlertDialog(
        title: const Text('Actualizaciones de Nala'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            if (installing || _state == _UpdateState.checking) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: installing ? null : () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          if (_state == _UpdateState.checkFailed)
            FilledButton(onPressed: _check, child: const Text('Reintentar')),
          if (_state == _UpdateState.available ||
              _state == _UpdateState.permission ||
              _state == _UpdateState.installFailed)
            FilledButton(onPressed: _install, child: const Text('Instalar')),
        ],
      ),
    );
  }
}
