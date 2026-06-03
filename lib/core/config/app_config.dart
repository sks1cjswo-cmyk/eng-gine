/// App configuration — replace values with your actual credentials.
/// Store secrets in a .env file or use --dart-define at build time.
/// Never commit real keys to version control.
class AppConfig {
  AppConfig._();

  // ---------------------------------------------------------------------------
  // Supabase
  // ---------------------------------------------------------------------------
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR_PROJECT_ID.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );

  // ---------------------------------------------------------------------------
  // PowerSync
  // ---------------------------------------------------------------------------
  static const String powersyncUrl = String.fromEnvironment(
    'POWERSYNC_URL',
    defaultValue: 'https://YOUR_INSTANCE_ID.powersync.journeyapps.com',
  );

  // ---------------------------------------------------------------------------
  // App constants
  // ---------------------------------------------------------------------------

  /// Maximum cards auto-extracted per chat session.
  static const int maxAutoCardsPerSession = 7;

  /// Desktop breakpoint — screens wider than this use split-screen layout.
  static const double desktopBreakpoint = 900.0;

  /// Tablet breakpoint — screens wider than this show the sidebar.
  static const double tabletBreakpoint = 600.0;
}
