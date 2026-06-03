import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_provider.dart';
import 'core/config/router.dart';
import 'core/database/powersync_database.dart' as ps_db;
import 'shared/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open local SQLite DB first (no network required)
  await ps_db.openDatabase();

  // Initialise Supabase
  await initSupabase();

  runApp(
    const ProviderScope(
      child: PersonalEnglishOs(),
    ),
  );
}

class PersonalEnglishOs extends ConsumerWidget {
  const PersonalEnglishOs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Personal English OS',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
