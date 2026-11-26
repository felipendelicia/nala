import 'package:flutter/material.dart';

import '../account/cloud_controller.dart';
import '../account/cloud_panel.dart';
import '../ai/chat_gpt_settings_dialog.dart';
import '../backup/backup_dialog.dart';
import '../backup/backup_files.dart';
import '../backup/backup_service.dart';
import '../bootstrap.dart';
import '../ui/appearance.dart';
import '../update/app_updates.dart';
import '../update/update_dialog.dart';

class LibrarySettingsScreen extends StatelessWidget {
  const LibrarySettingsScreen({
    super.key,
    required this.services,
    this.cloud,
    this.backupFiles,
  });

  final AppServices services;
  final CloudController? cloud;
  final BackupFiles? backupFiles;

  Future<void> _openBackup(BuildContext context) async {
    final active = cloud?.services ?? services;
    final result = await showBackupDialog(
      context,
      service: BackupService(
        root: active.root,
        repository: active.repository,
        assets: active.assets,
        deviceId: active.deviceId,
        appearanceFile: AppearanceScope.of(context)?.file,
      ),
      files: backupFiles ?? NativeBackupFiles(),
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
                    const Divider(indent: 56, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Backup de la biblioteca'),
                      subtitle: const Text('Guardá o restaurá una copia.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openBackup(context),
                    ),
                    if (cloud case final controller?) ...[
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
                          showChatGptSettings(context, services.chatGpt),
                    ),
                    if (NativeAppUpdates.isSupported) ...[
                      const Divider(indent: 56, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.system_update_outlined),
                        title: const Text('Buscar actualizaciones'),
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
