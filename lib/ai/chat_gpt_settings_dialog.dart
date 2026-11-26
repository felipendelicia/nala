import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_gpt_client.dart';

Future<void> showChatGptSettings(BuildContext context, ChatGptClient client) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChatGptSettingsDialog(client: client),
    );

class _ChatGptSettingsDialog extends StatefulWidget {
  const _ChatGptSettingsDialog({required this.client});
  final ChatGptClient client;

  @override
  State<_ChatGptSettingsDialog> createState() => _ChatGptSettingsDialogState();
}

class _ChatGptSettingsDialogState extends State<_ChatGptSettingsDialog>
    with WidgetsBindingObserver {
  bool _busy = true;
  bool _authorizing = false;
  bool _waitingForBrowser = false;
  Completer<void>? _foreground;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run(widget.client.load));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on ChatGptException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'No se pudo completar la conexión con ChatGPT.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _browser(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _signIn({String? accountId}) => _run(() async {
    setState(() {
      _authorizing = true;
      _waitingForBrowser = true;
      _message = 'Continuá en el navegador.';
    });
    try {
      await widget.client.signIn(
        _browser,
        accountId: accountId,
        onBrowserReturn: _finishInNala,
      );
      if (mounted) {
        setState(() {
          _message = widget.client.connected
              ? 'Uso del plan habilitado.'
              : 'Habilitá el uso de tu plan en Nala.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _authorizing = false;
          _waitingForBrowser = false;
        });
      }
    }
  });

  Future<void> _finishInNala() async {
    if (!mounted) throw const ChatGptException('Se canceló la conexión.');
    setState(() {
      _waitingForBrowser = false;
      _message = 'Autorización recibida. Verificando la conexión…';
    });
    final state = WidgetsBinding.instance.lifecycleState;
    if (!Platform.isAndroid ||
        state == null ||
        state == AppLifecycleState.resumed) {
      return;
    }
    final foreground = _foreground = Completer<void>();
    try {
      await foreground.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      throw const ChatGptException(
        'Venció el tiempo para volver a Nala. Iniciá sesión otra vez.',
      );
    } finally {
      _foreground = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = _foreground;
    if (state == AppLifecycleState.resumed &&
        foreground != null &&
        !foreground.isCompleted) {
      foreground.complete();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_authorizing) widget.client.cancelSignIn();
    final foreground = _foreground;
    if (foreground != null && !foreground.isCompleted) {
      foreground.completeError(
        const ChatGptException('Se canceló la conexión.'),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.client,
    builder: (context, _) {
      final client = widget.client;
      return PopScope(
        canPop: !_authorizing,
        child: AlertDialog(
          title: const Text('Conectar tu plan de ChatGPT'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (client.accounts.isEmpty)
                  const Text(
                    'Vinculá tu cuenta de ChatGPT para usar tu plan en Nala.',
                  ),
                for (final account in client.accounts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      client.activeAccount?.id == account.id && client.connected
                          ? Icons.check_circle_outline
                          : Icons.person_outline,
                    ),
                    title: Text(account.email),
                    trailing: account.connected
                        ? IconButton(
                            tooltip: 'Volver a iniciar sesión',
                            onPressed: _busy
                                ? null
                                : () => _signIn(accountId: account.id),
                            icon: const Icon(Icons.refresh),
                          )
                        : null,
                    subtitle: account.connected
                        ? Text(
                            client.activeAccount?.id == account.id
                                ? 'Plan conectado'
                                : 'Cuenta guardada',
                          )
                        : const Text('Requiere autorización'),
                    onTap: _busy
                        ? null
                        : account.connected
                        ? () => _run(() => client.useAccount(account.id))
                        : () => _signIn(accountId: account.id),
                  ),
                if (_message case final message?) ...[
                  const SizedBox(height: 12),
                  Text(message),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (client.activeAccount != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final opened = await _browser(
                              Uri.https('chatgpt.com', '/settings/usage'),
                            );
                            if (!opened) {
                              throw const ChatGptException(
                                'No se pudo abrir el navegador.',
                              );
                            }
                          }),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Uso y límites en ChatGPT'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _waitingForBrowser
                  ? widget.client.cancelSignIn
                  : _authorizing
                  ? null
                  : () => Navigator.pop(context),
              child: Text(_waitingForBrowser ? 'Cancelar conexión' : 'Cerrar'),
            ),
            if (client.activeAccount != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final revoked = await client.signOut();
                        if (!revoked && mounted) {
                          setState(
                            () => _message =
                                'Sesión cerrada en Nala. Revisá el acceso en la configuración de ChatGPT.',
                          );
                        }
                      }),
                child: const Text('Cerrar sesión'),
              ),
            FilledButton(
              onPressed: _busy ? null : () => _signIn(),
              child: Text(
                client.accounts.isEmpty
                    ? 'Continuar con ChatGPT'
                    : 'Agregar cuenta',
              ),
            ),
          ],
        ),
      );
    },
  );
}
