import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/powersync_database.dart' as ps_db;

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Domain models
// ---------------------------------------------------------------------------

class ChatSession {
  const ChatSession({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.createdAt,
    this.endedAt,
  });

  final String id;
  final String userId;
  final String? title;
  final String status;
  final DateTime createdAt;
  final DateTime? endedAt;

  factory ChatSession.fromRow(Map<String, dynamic> row) => ChatSession(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        title: row['title'] as String?,
        status: row['status'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        endedAt: row['ended_at'] != null
            ? DateTime.parse(row['ended_at'] as String)
            : null,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String userId;
  final String role; // user | assistant
  final String content;
  final DateTime createdAt;

  factory ChatMessage.fromRow(Map<String, dynamic> row) => ChatMessage(
        id: row['id'] as String,
        sessionId: row['session_id'] as String,
        userId: row['user_id'] as String,
        role: row['role'] as String,
        content: row['content'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class ChatRepository {
  // ---- Sessions ----

  Stream<List<ChatSession>> watchSessions(String userId) {
    return ps_db.db
        .watch(
          'SELECT * FROM sessions WHERE user_id = ? AND source_type = ? ORDER BY created_at DESC',
          parameters: [userId, 'chat'],
        )
        .map((rows) => rows.map(ChatSession.fromRow).toList());
  }

  Future<ChatSession> createSession(String userId) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await ps_db.db.execute(
      '''INSERT INTO sessions (id, user_id, source_type, title, status, created_at)
         VALUES (?, ?, 'chat', 'New Chat', 'active', ?)''',
      [id, userId, now],
    );
    final rows = await ps_db.db.getAll(
      'SELECT * FROM sessions WHERE id = ?',
      [id],
    );
    return ChatSession.fromRow(rows.first);
  }

  Future<void> endSession(String sessionId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await ps_db.db.execute(
      '''UPDATE sessions SET status = 'ended', ended_at = ? WHERE id = ?''',
      [now, sessionId],
    );
  }

  Future<void> updateSessionStatus(String sessionId, String status) async {
    await ps_db.db.execute(
      'UPDATE sessions SET status = ? WHERE id = ?',
      [status, sessionId],
    );
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    await ps_db.db.execute(
      'UPDATE sessions SET title = ? WHERE id = ?',
      [title, sessionId],
    );
  }

  // ---- Messages ----

  Stream<List<ChatMessage>> watchMessages(String sessionId) {
    return ps_db.db
        .watch(
          'SELECT * FROM messages WHERE session_id = ? ORDER BY created_at ASC',
          parameters: [sessionId],
        )
        .map((rows) => rows.map(ChatMessage.fromRow).toList());
  }

  Future<void> insertMessage({
    required String sessionId,
    required String userId,
    required String role,
    required String content,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await ps_db.db.execute(
      '''INSERT INTO messages (id, session_id, user_id, role, content, created_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [id, sessionId, userId, role, content, now],
    );
  }

  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final rows = await ps_db.db.getAll(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY created_at ASC',
      [sessionId],
    );
    return rows.map(ChatMessage.fromRow).toList();
  }
}

// ---------------------------------------------------------------------------
// AI Streaming service (calls Supabase Edge Function)
// ---------------------------------------------------------------------------

class ChatAiService {
  final _supabase = Supabase.instance.client;

  /// Streams tokens from the `chat` Edge Function via direct HTTP SSE.
  Stream<String> streamResponse({
    required String sessionId,
    required List<ChatMessage> history,
    required String userMessage,
  }) async* {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final messages = [
      ...history.map((m) => {'role': m.role, 'content': m.content}),
      {'role': 'user', 'content': userMessage},
    ];

    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/functions/v1/chat',
    );

    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
        'apikey': AppConfig.supabaseAnonKey,
      })
      ..body = json.encode({
        'session_id': sessionId,
        'messages': messages,
      });

    final httpClient = http.Client();
    try {
      final streamedResponse = await httpClient.send(request);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception('Edge Function error ${streamedResponse.statusCode}: $body');
      }

      var accumulated = '';
      var buffer = '';

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // keep incomplete line

        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') return;
          try {
            final parsed = json.decode(data) as Map<String, dynamic>;
            final delta = parsed['delta'] as String? ?? '';
            if (delta.isEmpty) continue;
            accumulated += delta;
            yield accumulated;
          } catch (_) {
            continue;
          }
        }
      }
    } finally {
      httpClient.close();
    }
  }

  /// Triggers background session analysis after the session ends.
  Future<void> analyzeSession(String sessionId) async {
    await _supabase.functions.invoke(
      'analyze-session',
      body: json.encode({'session_id': sessionId}),
    );
  }
}
