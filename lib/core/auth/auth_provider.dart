import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../database/powersync_database.dart' as ps_db;

// ---------------------------------------------------------------------------
// Supabase client provider
// ---------------------------------------------------------------------------

/// Direct access to the Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// ---------------------------------------------------------------------------
// Auth state provider
// ---------------------------------------------------------------------------

/// Streams the current Supabase [Session].
/// null means the user is signed out.
final authStateProvider = StreamProvider<Session?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map((event) {
    final session = event.session;

    if (session != null) {
      // Connect PowerSync when user signs in
      ps_db.connectPowerSync().catchError((_) {});
    } else {
      // Disconnect on sign-out
      ps_db.disconnectPowerSync().catchError((_) {});
    }

    return session;
  });
});

/// Convenience provider: true when user is authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull != null;
});

// ---------------------------------------------------------------------------
// Auth notifier (sign-in / sign-up / sign-out actions)
// ---------------------------------------------------------------------------

class AuthNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _client.auth.signInWithPassword(
        email: email,
        password: password,
      ),
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _client.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      ),
    );
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _client.auth.signOut());
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AsyncValue<void>>(AuthNotifier.new);

// ---------------------------------------------------------------------------
// App initialisation
// ---------------------------------------------------------------------------

/// Call once in main() before runApp().
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );
}

// ---------------------------------------------------------------------------
// Auth helper widget
// ---------------------------------------------------------------------------

/// Listens to auth state and navigates accordingly.
/// Wrap your MaterialApp or use in a ProviderScope observer.
class AuthStateListener extends ConsumerWidget {
  const AuthStateListener({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<Session?>>(authStateProvider, (prev, next) {
      // Navigation handled by go_router redirect — no explicit push here.
    });
    return child;
  }
}
