import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_provider.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/enrich_popup.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await ref.read(chatControllerProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= AppConfig.desktopBreakpoint;

    return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
  }

  // ---------------------------------------------------------------------------
  // Desktop: split-screen (message list | input)
  // ---------------------------------------------------------------------------

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left: session list sidebar
        SizedBox(
          width: 260,
          child: _SessionListPanel(
            onNewSession: () {
              ref.read(activeSessionIdProvider.notifier).state = null;
            },
            onEndSession: () =>
                ref.read(chatControllerProvider.notifier).endSession(),
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: chat area
        Expanded(child: _buildChatArea()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile: full-screen chat
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout() {
    return _buildChatArea();
  }

  // ---------------------------------------------------------------------------
  // Chat area (shared)
  // ---------------------------------------------------------------------------

  Widget _buildChatArea() {
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final controller = ref.watch(chatControllerProvider);
    final isLoading = controller is AsyncLoading;

    // Show snackbar on error
    ref.listen(chatControllerProvider, (_, next) {
      if (next is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${next.error}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(activeSessionId != null ? 'Chat' : 'New Chat'),
        actions: [
          if (activeSessionId != null)
            TextButton.icon(
              onPressed: isLoading
                  ? null
                  : () => ref
                      .read(chatControllerProvider.notifier)
                      .endSession(),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End & Analyse'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(activeSessionId)),
          _buildInputArea(isLoading),
        ],
      ),
    );
  }

  Widget _buildMessageList(String? sessionId) {
    if (sessionId == null) {
      return const Center(
        child: Text(
          'Start typing to begin a new session',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final messagesAsync = ref.watch(chatMessagesProvider(sessionId));
    final streamingMsg = ref.watch(streamingMessageProvider);

    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (messages) {
        _scrollToBottom();
        return SelectionArea(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: messages.length + (streamingMsg != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == messages.length && streamingMsg != null) {
                // Streaming placeholder
                return _ChatBubble(
                  role: 'assistant',
                  content: streamingMsg['content'] ?? '',
                  isStreaming: true,
                  sessionId: sessionId,
                );
              }
              final msg = messages[index];
              return _ChatBubble(
                role: msg.role,
                content: msg.content,
                isStreaming: false,
                sessionId: sessionId,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildInputArea(bool isLoading) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              maxLines: 5,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Write in English…',
              ),
              onSubmitted: isLoading ? null : (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: isLoading ? null : _sendMessage,
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat bubble with long-press to save card
// ---------------------------------------------------------------------------

class _ChatBubble extends ConsumerWidget {
  const _ChatBubble({
    required this.role,
    required this.content,
    required this.isStreaming,
    required this.sessionId,
  });

  final String role;
  final String content;
  final bool isStreaming;
  final String sessionId;

  bool get _isUser => role == 'user';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
          ),
          child: GestureDetector(
            onLongPress: () => _showEnrichOptions(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(_isUser ? 18 : 4),
                  bottomRight: Radius.circular(_isUser ? 4 : 18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      content,
                      style: TextStyle(
                        color: _isUser
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                  if (isStreaming) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onSurface.withAlpha(128),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEnrichOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _EnrichOptionSheet(
        text: content,
        sessionId: sessionId,
        contextSnippet: content,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet: select word or phrase to save
// ---------------------------------------------------------------------------

class _EnrichOptionSheet extends StatelessWidget {
  const _EnrichOptionSheet({
    required this.text,
    required this.sessionId,
    required this.contextSnippet,
  });

  final String text;
  final String sessionId;
  final String contextSnippet;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save as card',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('Save full message'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => EnrichPopup(
                    selectedText: text,
                    contextSnippet: contextSnippet,
                    sessionId: sessionId,
                    cardType: 'sentence',
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Select a word / phrase to save'),
              subtitle: const Text(
                'Highlight the specific text you want to save',
              ),
              onTap: () {
                Navigator.pop(context);
                // SelectionArea handles this — user can select text and use context menu
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Select the word or phrase, then choose "Save card" from the menu',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session list panel (desktop sidebar)
// ---------------------------------------------------------------------------

class _SessionListPanel extends ConsumerWidget {
  const _SessionListPanel({
    required this.onNewSession,
    required this.onEndSession,
  });

  final VoidCallback onNewSession;
  final VoidCallback onEndSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(chatSessionsProvider);
    final activeId = ref.watch(activeSessionIdProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNewSession,
                  icon: const Icon(Icons.add),
                  label: const Text('New Chat'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (sessions) => ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isActive = session.id == activeId;
                return ListTile(
                  selected: isActive,
                  title: Text(
                    session.title ?? 'Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_statusLabel(session.status)),
                  leading: Icon(_statusIcon(session.status)),
                  onTap: () {
                    ref.read(activeSessionIdProvider.notifier).state =
                        session.id;
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'analyzing':
        return 'Analysing…';
      case 'analyzed':
        return 'Analysed';
      case 'error':
        return 'Error';
      case 'ended':
        return 'Ended';
      default:
        return 'Active';
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'analyzing':
        return Icons.hourglass_bottom;
      case 'analyzed':
        return Icons.check_circle_outline;
      case 'error':
        return Icons.error_outline;
      case 'ended':
        return Icons.stop_circle_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }
}
