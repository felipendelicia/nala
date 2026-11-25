import 'dart:async';

import 'package:flutter/material.dart';

import '../account/cloud_controller.dart';
import '../bootstrap.dart';
import '../document/revision.dart';
import 'document_workspace.dart';

/// Respond to navigation while the exact revision is loaded for the editor.
class WorkspaceOpeningScreen extends StatefulWidget {
  const WorkspaceOpeningScreen({
    super.key,
    required this.services,
    required this.title,
    required this.loadEntry,
    required this.initialPageIndex,
    this.cloud,
  });

  final AppServices services;
  final String title;
  final Future<DocumentEntry?> Function() loadEntry;
  final int initialPageIndex;
  final CloudController? cloud;

  @override
  State<WorkspaceOpeningScreen> createState() => _WorkspaceOpeningScreenState();
}

class _WorkspaceOpeningScreenState extends State<WorkspaceOpeningScreen> {
  DocumentEntry? _entry;
  bool _loaded = false;
  bool _showHint = false;
  bool _popped = false;
  late final Timer _hint;

  @override
  void initState() {
    super.initState();
    _hint = Timer(const Duration(milliseconds: 140), () {
      if (mounted && !_popped) setState(() => _showHint = true);
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    DocumentEntry? entry;
    try {
      entry = await widget.loadEntry();
    } catch (_) {
      // Unavailable revisions use the same recoverable state and back action.
    }
    _hint.cancel();
    if (!mounted || _popped) return;
    setState(() {
      _entry = entry;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _hint.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final message = _loaded
        ? 'El apunte ya no está disponible.'
        : _showHint
        ? 'Cargando apunte…'
        : null;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _popped = true;
          _hint.cancel();
        }
      },
      child: entry != null
          ? WorkspaceScreen(
              services: widget.services,
              initialEntry: entry,
              initialPageIndex: widget.initialPageIndex,
              cloud: widget.cloud,
            )
          : Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Volver a mis apuntes',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                toolbarHeight: 56,
                leadingWidth: 48,
                titleSpacing: 8,
                title: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              body: ColoredBox(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black
                    : const Color(0xffeeeeee),
                child: Center(
                  child: message == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(message, textAlign: TextAlign.center),
                          ),
                        ),
                ),
              ),
            ),
    );
  }
}
