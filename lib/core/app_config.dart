/// App configuration and environment management
class AppConfig {
  static const String appName = 'SPORTSDUG';
  static const String appVersion = '1.0.0';
  
  // Environment detection
  static bool get isProduction {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    return env == 'production' || env == 'prod';
  }
  
  static bool get isDevelopment {
    return !isProduction;
  }
  
  // Supabase configuration
  static String get supabaseUrl {
    return const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: '',
    );
  }
  
  static String get supabaseAnonKey {
    return const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );
  }
  
  // Sentry configuration
  static String get sentryDsn {
    return const String.fromEnvironment(
      'SENTRY_DSN',
      defaultValue: '',
    );
  }
  
  // Firebase configuration
  static bool get enableFirebase {
    const enabled = String.fromEnvironment('ENABLE_FIREBASE', defaultValue: 'false');
    return enabled == 'true';
  }
  
  // Logging configuration
  static bool get enableVerboseLogging {
    return isDevelopment;
  }
  
  // Validate configuration
  static void validate() {
    // Only validate in production - allow empty in dev for testing
    if (isProduction && (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty)) {
      throw Exception(
        'Missing Supabase configuration. '
        'Set SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define',
      );
    }
  }
}

