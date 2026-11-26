import 'dart:io';

import 'package:flutter/material.dart';

import '../account/cloud_controller.dart';
import '../account/cloud_panel.dart';
import '../ai/chat_gpt_settings_dialog.dart';
import '../backup/backup_dialog.dart';
import '../backup/backup_files.dart';
import '../backup/backup_service.dart';
import '../bootstrap.dart';
import '../ui/appearance.dart';
import '../ui/fullscreen.dart';
import '../update/app_updates.dart';
import '../update/update_dialog.dart';

class LibrarySettingsScreen extends StatefulWidget {
  const LibrarySettingsScreen({
    super.key,
    required this.services,
    this.cloud,
    this.backupFiles,
    this.readInstalledVersion = NativeAppUpdates.installedVersion,
  });

  final AppServices services;
  final CloudController? cloud;
  final BackupFiles? backupFiles;
  final Future<String> Function() readInstalledVersion;

  @override
  State<LibrarySettingsScreen> createState() => _LibrarySettingsScreenState();
}

class _LibrarySettingsScreenState extends State<LibrarySettingsScreen> {
  late final _installedVersion = widget.readInstalledVersion();

  Future<void> _openBackup(BuildContext context) async {
    final active = widget.cloud?.services ?? widget.services;
    final result = await showBackupDialog(
      context,
      service: BackupService(
        root: active.root,
        repository: active.repository,
        assets: active.assets,
        deviceId: active.deviceId,
        appearanceFile: AppearanceScope.of(context)?.file,
      ),
      files: widget.backupFiles ?? NativeBackupFiles(),
      onRestored: (result) async {
        await active.library.refresh();
        if (result.preferencesRestored) {
          await active.toolbarPreferences?.reload();
          await active.penPreferences?.reload();
        }
      },
    );
    if (result != null && context.mounted) {
      Navigator.of(context).pop(result.recoveryFolderId);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ajustes')),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card.outlined(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ListTileTheme(
                minVerticalPadding: 12,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppearanceButton(asTile: true),
                    if (FullscreenScope.of(context) case final mode?
                        when mode.available) ...[
                      const Divider(indent: 56, endIndent: 16),
                      SwitchListTile(
                        secondary: const Icon(Icons.fullscreen),
                        title: const Text('Pantalla completa'),
                        subtitle: Platform.isLinux ? const Text('F11') : null,
                        value: mode.enabled,
                        onChanged: mode.changing
                            ? null
                            : (_) => toggleFullscreen(context, mode),
                      ),
                    ],
                    const Divider(indent: 56, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Backup de la biblioteca'),
                      subtitle: const Text('Guardá o restaurá una copia.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openBackup(context),
                    ),
                    if (widget.cloud case final controller?) ...[
                      const Divider(indent: 56, endIndent: 16),
                      ServerSettingsTile(cloud: controller),
                    ],
                    const Divider(indent: 56, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('ChatGPT'),
                      subtitle: const Text('Gestioná tu cuenta y tu plan.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          showChatGptSettings(context, widget.services.chatGpt),
                    ),
                    if (NativeAppUpdates.isSupported) ...[
                      const Divider(indent: 56, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.system_update_outlined),
                        title: const Text('Buscar actualizaciones'),
                        subtitle: FutureBuilder<String>(
                          future: _installedVersion,
                          builder: (context, snapshot) => switch (snapshot) {
                            AsyncSnapshot(data: final String version) => Text(
                              'Versión instalada $version',
                            ),
                            AsyncSnapshot(hasError: true) => const Text(
                              'Versión no disponible',
                            ),
                            _ => const SizedBox.shrink(),
                          },
                        ),
                        onTap: () {
                          final updates = NativeAppUpdates();
                          showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => UpdateDialog(updates: updates),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
