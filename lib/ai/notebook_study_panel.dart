import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../document/notebook.dart';
import '../editor/markdown_sheet.dart';
import '../pdf/pdf_service.dart';
import 'chat_gpt_client.dart';
import 'chat_gpt_logo.dart';
import 'chat_gpt_settings_dialog.dart';
import 'notebook_chat_store.dart';
import 'notebook_study_service.dart';
import 'study_page_picker.dart';

class NotebookStudyPanel extends StatefulWidget {
  const NotebookStudyPanel({
    super.key,
    required this.notebook,
    required this.client,
    required this.service,
    required this.store,
    required this.onClose,
    required this.onOpenPage,
    required this.unlockPdf,
    required this.onRequestChanged,
    this.pdf,
  });

  final Notebook notebook;
  final ChatGptClient client;
  final NotebookStudyService service;
  final NotebookChatStore store;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenPage;
  final Future<bool> Function(String assetId) unlockPdf;
  final ValueChanged<Future<void>?> onRequestChanged;
  final PdfService? pdf;

  @override
  State<NotebookStudyPanel> createState() => _NotebookStudyPanelState();
}

class _NotebookStudyPanelState extends State<NotebookStudyPanel> {
  final _question = TextEditingController();
  List<NotebookChat>? _chats;
  String? _chatId;
  NotebookChat? _unsaved;
  Set<String>? _sourceIds;
  bool _showHistory = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  List<String> get _pageIds => [
    for (final page in widget.notebook.pages)
      if (_sourceIds?.contains(page.id) ?? true) page.id,
  ];

  NotebookChat? get _activeChat =>
      _chats?.where((chat) => chat.id == _chatId).firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chats = await widget.store.list(widget.notebook.id);
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _chatId = chats.firstOrNull?.id;
        _sourceIds = _pendingPages(chats.firstOrNull);
      });
      await widget.client.load();
    } on ChatGptException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo abrir el historial de este apunte.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final settled = Completer<void>();
    widget.onRequestChanged(settled.future);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ChatGptException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _unsaved == null
              ? 'No se pudo completar la solicitud.'
              : 'No se pudo guardar el chat en este dispositivo.';
        });
      }
    } finally {
      settled.complete();
      widget.onRequestChanged(null);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPages() async {
    final ids = await showStudyPagePicker(
      context,
      pages: widget.notebook.pages,
      selected: _pageIds.toSet(),
      pdf: widget.pdf,
    );
    if (mounted && ids != null) {
      setState(() {
        _sourceIds =
            widget.notebook.pages.every((page) => ids.contains(page.id))
            ? null
            : ids;
      });
    }
  }

  Set<String>? _pendingPages(NotebookChat? chat) {
    final message = chat?.messages.lastOrNull;
    return message != null && message.isUser ? message.pageIds.toSet() : null;
  }

  void _openChat(NotebookChat? chat) {
    _question.clear();
    setState(() {
      _chatId = chat?.id;
      _showHistory = false;
      _error = null;
      _sourceIds = _pendingPages(chat);
    });
  }

  Future<void> _persist(NotebookChat chat) async {
    _unsaved = chat;
    if (mounted) {
      setState(() {
        _chatId = chat.id;
        _chats = [chat, ...?_chats?.where((item) => item.id != chat.id)];
      });
    }
    await widget.store.save(widget.notebook.id, chat);
    _unsaved = null;
  }

  Future<void> _answer(Notebook notebook, NotebookChat chat) async {
    final pages = chat.messages.last.pageIds;
    final answer = await widget.service.ask(
      notebook: notebook,
      pageIds: pages,
      messages: chat.messages,
      unlock: widget.unlockPdf,
    );
    await _persist(
      chat.copyWith(
        updatedAt: DateTime.now(),
        messages: [
          ...chat.messages,
          NotebookChatMessage(isUser: false, text: answer, pageIds: pages),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final question = _question.text.trim();
    final pages = _pageIds;
    if (question.isEmpty || pages.isEmpty || !widget.client.connected) return;
    final notebook = widget.notebook;
    final chat = _activeChat;
    final pending = NotebookChat(
      id: chat?.id ?? const Uuid().v4(),
      title:
          chat?.title ?? question.split('\n').first.characters.take(64).join(),
      updatedAt: DateTime.now(),
      messages: [
        ...?chat?.messages,
        NotebookChatMessage(isUser: true, text: question, pageIds: pages),
      ],
    );
    _question.clear();
    await _run(() async {
      await _persist(pending);
      await _answer(notebook, pending);
    });
  }

  Future<void> _retryAnswer(NotebookChat chat) async {
    final pages = _pageIds;
    if (pages.isEmpty || !widget.client.connected) return;
    final notebook = widget.notebook;
    await _run(() async {
      final pending = chat.copyWith(
        messages: [
          ...chat.messages.take(chat.messages.length - 1),
          NotebookChatMessage(
            isUser: true,
            text: chat.messages.last.text,
            pageIds: pages,
          ),
        ],
      );
      await _persist(pending);
      await _answer(notebook, pending);
    });
  }

  void _openCitation(String destination) {
    const prefix = 'nala-page:';
    if (!destination.startsWith(prefix)) return;
    try {
      final id = Uri.decodeComponent(destination.substring(prefix.length));
      if (widget.notebook.pages.any((page) => page.id == id)) {
        widget.onOpenPage(id);
      }
    } on FormatException {
      return;
    }
  }

  Future<void> _showUsage() async {
    try {
      if (await launchUrl(
        Uri.https('chatgpt.com', '/settings/usage'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep the user in the current notebook if the browser cannot open.
    }
    if (mounted) {
      setState(() => _error = 'No se pudo abrir el navegador.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.client,
    builder: (context, _) {
      final theme = Theme.of(context);
      final chat = _activeChat;
      final canCompose =
          !_busy &&
          !_loading &&
          _chats != null &&
          _unsaved == null &&
          widget.client.connected &&
          _pageIds.isNotEmpty;
      final awaitingAnswer = chat?.messages.lastOrNull?.isUser ?? false;
      final content = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
            child: Row(
              children: [
                const ChatGptLogo(),
                Expanded(
                  child: Text(
                    'ChatGPT',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Historial de chats',
                  isSelected: _showHistory,
                  onPressed: _busy || _chats == null || _unsaved != null
                      ? null
                      : () => setState(() => _showHistory = !_showHistory),
                  icon: const Icon(Icons.history),
                ),
                IconButton(
                  tooltip: 'Nuevo chat',
                  onPressed: _busy || _chats == null || _unsaved != null
                      ? null
                      : () => _openChat(null),
                  icon: const Icon(Icons.add_comment_outlined),
                ),
                IconButton(
                  tooltip: 'Cerrar ChatGPT',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (_busy || _loading) const LinearProgressIndicator(minHeight: 2),
          if (_loading)
            const Expanded(child: SizedBox())
          else if (_chats == null)
            Expanded(
              child: Center(
                child: TextButton(
                  onPressed: _load,
                  child: const Text('Reintentar historial'),
                ),
              ),
            )
          else if (_showHistory)
            Expanded(child: _buildHistory()),
          if (!_loading && _chats != null && !_showHistory) ...[
            Expanded(child: _buildConversation(chat)),
            _buildSources(),
            _buildComposer(canCompose, awaitingAnswer),
            if (widget.client.connected)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Usando tu plan de ChatGPT',
                    style: theme.textTheme.labelSmall,
                  ),
                  TextButton(
                    onPressed: _showUsage,
                    child: const Text('Ver uso'),
                  ),
                ],
              )
            else
              TextButton(
                onPressed: () => showChatGptSettings(context, widget.client),
                child: const Text('Conectar con ChatGPT'),
              ),
          ],
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                error,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      );
      return Material(
        color: theme.colorScheme.surface,
        elevation: 4,
        child: SafeArea(
          top: false,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context);
              final minHeight =
                  360.0 + math.max(0.0, textScale.scale(120) - 120);
              return SingleChildScrollView(
                reverse: true,
                physics: constraints.maxHeight >= minHeight
                    ? const NeverScrollableScrollPhysics()
                    : null,
                child: SizedBox(
                  height: math.max(constraints.maxHeight, minHeight),
                  child: content,
                ),
              );
            },
          ),
        ),
      );
    },
  );

  Widget _buildHistory() {
    if (_chats!.isEmpty) {
      return const Center(child: Text('Todavía no hay chats.'));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final chat in _chats!)
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: Text(
              chat.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            selected: chat.id == _chatId,
            onTap: () => _openChat(chat),
          ),
      ],
    );
  }

  Widget _buildConversation(NotebookChat? chat) {
    final messages = chat?.messages ?? const <NotebookChatMessage>[];
    if (messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Hacé una pregunta sobre este apunte.'),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      key: ValueKey(chat?.id),
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: message.isUser
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: message.isUser
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(message.text),
                    ),
                  )
                : MarkdownContent(
                    markdown: message.text,
                    onLink: _openCitation,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSources() {
    final pages = _pageIds;
    final allPages = pages.length == widget.notebook.pages.length;
    final label = allPages
        ? 'Todas las hojas'
        : pages.isEmpty
        ? 'Elegir hojas'
        : pages.length == 1
        ? 'Hoja ${widget.notebook.pages.indexWhere((page) => page.id == pages.single) + 1}'
        : '${pages.length} hojas seleccionadas';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label),
          TextButton(
            onPressed: _busy ? null : _pickPages,
            child: const Text('Cambiar páginas'),
          ),
          if (!allPages)
            IconButton(
              tooltip: 'Seleccionar todas las hojas',
              onPressed: _busy ? null : () => setState(() => _sourceIds = null),
              icon: const Icon(Icons.select_all),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(bool canCompose, bool awaitingAnswer) {
    if (_unsaved case final chat?) {
      return TextButton(
        onPressed: _busy ? null : () => _run(() => _persist(chat)),
        child: const Text('Reintentar guardado'),
      );
    }
    if (awaitingAnswer) {
      return TextButton(
        onPressed: canCompose ? () => _retryAnswer(_activeChat!) : null,
        child: Text(_busy ? 'Generando respuesta…' : 'Reintentar respuesta'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _question,
              enabled: canCompose,
              minLines: 1,
              maxLines: 3,
              maxLength: 4000,
              decoration: const InputDecoration(
                hintText: 'Preguntale al apunte',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: _question,
            builder: (context, value, _) => IconButton(
              tooltip: 'Enviar pregunta',
              onPressed: canCompose && value.text.trim().isNotEmpty
                  ? _send
                  : null,
              icon: const Icon(Icons.send_outlined),
            ),
          ),
        ],
      ),
    );
  }
}
