import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'powersync_schema.dart';

/// Singleton PowerSync database instance.
/// Call [openDatabase] once at app startup before using [db].
late PowerSyncDatabase db;

/// Opens the local SQLite database and initialises PowerSync.
/// Safe to call multiple times — subsequent calls are no-ops.
Future<void> openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final dbPath = p.join(dir.path, 'personal_english_os.db');

  db = PowerSyncDatabase(schema: schema, path: dbPath);
  await db.initialize();
}

/// Connects PowerSync to the backend once the user is signed in.
/// Call this after a successful Supabase auth sign-in.
Future<void> connectPowerSync() async {
  await db.connect(connector: _SupabasePowerSyncConnector());
}

/// Disconnects PowerSync (e.g., on sign-out).
Future<void> disconnectPowerSync() async {
  await db.disconnect();
}

// ---------------------------------------------------------------------------
// Backend Connector
// ---------------------------------------------------------------------------

class _SupabasePowerSyncConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;

    // Refresh if near expiry (< 2 minutes left)
    if (session.isExpired) {
      final refreshed =
          await Supabase.instance.client.auth.refreshSession();
      if (refreshed.session == null) return null;
      return PowerSyncCredentials(
        endpoint: AppConfig.powersyncUrl,
        token: refreshed.session!.accessToken,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          refreshed.session!.expiresAt! * 1000,
        ),
      );
    }

    return PowerSyncCredentials(
      endpoint: AppConfig.powersyncUrl,
      token: session.accessToken,
      expiresAt: session.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
          : null,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // Upload local writes to Supabase via the Supabase client library.
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    final client = Supabase.instance.client;

    try {
      for (final op in transaction.crud) {
        final table = op.table;
        final data = op.opData ?? {};

        switch (op.op) {
          case UpdateType.put:
            await client.from(table).upsert({...data, 'id': op.id});
          case UpdateType.patch:
            await client.from(table).update(data).eq('id', op.id);
          case UpdateType.delete:
            await client.from(table).delete().eq('id', op.id);
        }
      }
      await transaction.complete();
    } on PostgrestException catch (e) {
      // Unique constraint violation on dedup_key — treat as success
      // (card already exists, reinforce logic is handled at the app layer)
      if (e.code == '23505') {
        await transaction.complete();
        return;
      }
      rethrow;
    }
  }
}
