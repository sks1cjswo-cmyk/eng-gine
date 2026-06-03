import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/chat_repository.dart';

// ---------------------------------------------------------------------------
// Repository providers (singleton)
// ---------------------------------------------------------------------------

final chatRepositoryProvider = Provider<ChatRepository>(
  (_) => ChatRepository(),
);

final chatAiServiceProvider = Provider<ChatAiService>(
  (_) => ChatAiService(),
);

// ---------------------------------------------------------------------------
// Session list provider
// ---------------------------------------------------------------------------

final chatSessionsProvider = StreamProvider<List<ChatSession>>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return const Stream.empty();
  return ref.watch(chatRepositoryProvider).watchSessions(userId);
});

// ---------------------------------------------------------------------------
// Active session provider
// ---------------------------------------------------------------------------

final activeSessionIdProvider =
    StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Messages provider for the active session
// ---------------------------------------------------------------------------

final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, sessionId) {
  return ref.watch(chatRepositoryProvider).watchMessages(sessionId);
});

// ---------------------------------------------------------------------------
// Chat controller — manages send flow
// ---------------------------------------------------------------------------

class ChatController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  ChatAiService get _ai => ref.read(chatAiServiceProvider);

  String? get _userId =>
      Supabase.instance.client.auth.currentUser?.id;

  /// Sends a user message and streams the AI response.
  /// Creates a new session if none is active.
  Future<void> sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;

    state = const AsyncLoading();

    try {
      final userId = _userId;
      if (userId == null) throw Exception('Not authenticated');

      // Ensure we have an active session
      String sessionId = ref.read(activeSessionIdProvider) ?? '';
      if (sessionId.isEmpty) {
        final session = await _repo.createSession(userId);
        sessionId = session.id;
        ref.read(activeSessionIdProvider.notifier).state = sessionId;
      }

      // Save user message locally
      await _repo.insertMessage(
        sessionId: sessionId,
        userId: userId,
        role: 'user',
        content: userMessage.trim(),
      );

      // Get history for context
      final history = await _repo.getMessages(sessionId);

      // Stream AI response — accumulate and update a temporary message
      var assistantContent = '';
      final assistantId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';

      await for (final chunk in _ai.streamResponse(
        sessionId: sessionId,
        history: history.where((m) => m.role == 'user').toList(),
        userMessage: userMessage.trim(),
      )) {
        assistantContent = chunk;
        // Notify UI about streaming progress via a separate provider
        ref
            .read(_streamingMessageProvider.notifier)
            .update((s) => {'id': assistantId, 'content': assistantContent});
      }

      // Save final assistant message
      if (assistantContent.isNotEmpty) {
        await _repo.insertMessage(
          sessionId: sessionId,
          userId: userId,
          role: 'assistant',
          content: assistantContent,
        );
      }

      // Clear streaming state
      ref.read(_streamingMessageProvider.notifier).state = null;

      // Auto-name session from first user message
      final sessions = await _repo.watchSessions(userId).first;
      final session = sessions.firstWhere(
        (s) => s.id == sessionId,
        orElse: () => throw Exception('Session not found'),
      );
      if (session.title == 'New Chat') {
        final title = userMessage.trim().length > 40
            ? '${userMessage.trim().substring(0, 40)}…'
            : userMessage.trim();
        await _repo.updateSessionTitle(sessionId, title);
      }

      state = const AsyncData(null);
    } catch (e, st) {
      ref.read(_streamingMessageProvider.notifier).state = null;
      state = AsyncError(e, st);
    }
  }

  /// Ends the current session and triggers background analysis.
  Future<void> endSession() async {
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId == null) return;

    await _repo.endSession(sessionId);
    await _repo.updateSessionStatus(sessionId, 'analyzing');

    // Fire-and-forget analysis
    _ai.analyzeSession(sessionId).catchError((_) {});

    // Start new session
    ref.read(activeSessionIdProvider.notifier).state = null;
  }
}

/// Holds the in-progress streaming message (null when not streaming).
final _streamingMessageProvider =
    StateProvider<Map<String, String>?>((ref) => null);

/// Exposes the streaming message to the chat UI.
final streamingMessageProvider =
    Provider<Map<String, String>?>((ref) => ref.watch(_streamingMessageProvider));

final chatControllerProvider =
    AutoDisposeAsyncNotifierProvider<ChatController, void>(
  ChatController.new,
);
