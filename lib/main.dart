import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// Inter font is now configured via pubspec.yaml and ThemeData
// Do NOT use google_fonts package for Inter

import 'core/app_config.dart';
import 'core/error_handler.dart';
import 'core/logger_service.dart';
import 'core/analytics_service.dart';
import 'core/app_info.dart';
import 'core/sentry_navigator_observer.dart';
import 'screens/auth_sign_in_screen.dart';
import 'screens/home_tabs/home_tabs_screen.dart';

Future<void> main() async {
  // Initialize Flutter binding first
  WidgetsFlutterBinding.ensureInitialized();
  
  // Validate configuration (only strict in production)
  AppConfig.validate();
  
  // Initialize app info
  await AppInfo.initialize();
  
  // Initialize Firebase if enabled
  if (AppConfig.enableFirebase) {
    try {
      await Firebase.initializeApp();
      await AnalyticsService.initialize();
      LoggerService.info('Firebase initialized');
    } catch (e) {
      LoggerService.error('Firebase initialization failed', e);
    }
  }
  
  // Initialize Sentry for error tracking (only if DSN is provided)
  if (AppConfig.sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.isProduction ? 'production' : 'development';
        options.release = '${AppInfo.appName}@${AppInfo.versionString}';
        options.tracesSampleRate = AppConfig.isProduction ? 0.1 : 1.0;
        options.enableAutoSessionTracking = true;
      },
      appRunner: () => _initializeApp(),
    );
  } else {
    // Skip Sentry initialization and run app directly
    await _initializeApp();
  }
}

Future<void> _initializeApp() async {
  try {
    // Setup error handling
    ErrorHandler.setupErrorHandling();
    
    // Initialize Supabase only if credentials are provided
    if (AppConfig.supabaseUrl.isNotEmpty && AppConfig.supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      LoggerService.info('Supabase initialized successfully');
    } else {
      LoggerService.warning('Supabase credentials not provided - app will run in demo mode');
    }
    
    LoggerService.info('App initialized successfully');
    
    // Run the app
    runApp(const SportsDugApp());
  } catch (e, stackTrace) {
    LoggerService.fatal('Failed to initialize app', e, stackTrace);
    AnalyticsService.recordFatalError(e, stackTrace, reason: 'App initialization');
    // Show error screen instead of crashing
    runApp(const ErrorApp());
  }
}

class SportsDugApp extends StatelessWidget {
  const SportsDugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false, // DISABLED - Material 3 changes spacing and styling
        brightness: Brightness.light,
        // Inter font family (MANDATORY - do not use Roboto or default Material font)
        fontFamily: 'Inter',
        // SPORTSDUG logo colors - dark teal and orange
        colorScheme: ColorScheme.light(
          primary: Color(0xFFFF6B35),           // Orange (from logo)
          secondary: Color(0xFF0D7377),         // Dark teal (from logo)
          surface: Colors.white,                // Pure white surfaces
          background: Color(0xFFFAFAFA),        // Cool white background
          onPrimary: Colors.white,              // White text on orange
          onSecondary: Colors.white,            // White text on teal
          onSurface: Color(0xFF0D7377),         // Dark teal text on white
          onBackground: Color(0xFF323E48),      // Dark grey text
        ),
        scaffoldBackgroundColor: Color(0xFFFAFAFA), // Cool white background
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,        // Pure white app bar
          foregroundColor: Color(0xFF0D7377),   // Dark teal text
          elevation: 0.5,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0D7377),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,                  // Pure white cards
          elevation: 1,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        // Apply Inter font with dark teal text for light theme
        textTheme: TextTheme(
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF0D7377),           // Dark teal text for body
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Color(0xFF0D7377),
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0D7377),
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0D7377),
          ),
        ),
        // Keep primary text theme clean
        primaryTextTheme: TextTheme(
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        // Button theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFFF6B35),   // Orange buttons (logo color)
            foregroundColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Color(0xFF0D7377),  // Dark teal outline
            side: BorderSide(color: Color(0xFF0D7377)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        // Tab bar theme
        tabBarTheme: TabBarThemeData(
          labelColor: Color(0xFFFF6B35),         // Orange for active tab (logo color)
          unselectedLabelColor: Color(0xFF757575), // Grey for inactive
          indicatorColor: Color(0xFFFF6B35),     // Orange indicator
          labelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        // Input decoration theme for text fields
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFF5F5F5),          // Light grey for inputs
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFFFF6B35), width: 2), // Orange focus
          ),
          labelStyle: TextStyle(color: Color(0xFF0D7377)),  // Dark teal label
          hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
        ),
        // Dialog theme
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,         // White dialogs
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0D7377),            // Dark teal title
          ),
          contentTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF757575),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const AuthGate(),
      navigatorObservers: [
        // Track screen views for analytics
        if (AppConfig.enableFirebase)
          AnalyticsNavigatorObserver(),
      ],
      builder: (context, child) {
        return child!;
      },
    );
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'App Initialization Error',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'The app failed to initialize. Please check:\n'
                  '1. Supabase credentials are set\n'
                  '2. Network connection is available\n'
                  '3. Check console for detailed errors',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Try to reload
                    main();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if Supabase is initialized
    if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseAnonKey.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Configuration Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please set your Supabase credentials:\n\n'
                  'Run the app with:\n'
                  'flutter run --dart-define=SUPABASE_URL=your_url '
                  '--dart-define=SUPABASE_ANON_KEY=your_key',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final supa = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supa.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? supa.auth.currentSession;

        // ⏳ Waiting for auth state
        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 🔓 Not logged in
        if (session == null) {
          return const AuthSignInScreen();
        }

        // ✅ Logged in
        return const HomeTabsScreen();
      },
    );
  }
}
