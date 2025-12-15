import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
  
  // Validate configuration
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
  
  // Initialize Sentry for error tracking
  await SentryFlutter.init(
    (options) {
      options.dsn = AppConfig.sentryDsn.isNotEmpty 
          ? AppConfig.sentryDsn 
          : null;
      options.environment = AppConfig.isProduction ? 'production' : 'development';
      options.release = '${AppInfo.appName}@${AppInfo.versionString}';
      options.tracesSampleRate = AppConfig.isProduction ? 0.1 : 1.0;
      options.enableAutoSessionTracking = true;
    },
    appRunner: () => _initializeApp(),
  );
}

Future<void> _initializeApp() async {
  try {
    // Setup error handling
    ErrorHandler.setupErrorHandling();
    
    // Initialize Supabase
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    
    LoggerService.info('App initialized successfully');
    
    // Run the app
    runApp(const SportsDugApp());
  } catch (e, stackTrace) {
    LoggerService.fatal('Failed to initialize app', e, stackTrace);
    AnalyticsService.recordFatalError(e, stackTrace, reason: 'App initialization');
    rethrow;
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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
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
