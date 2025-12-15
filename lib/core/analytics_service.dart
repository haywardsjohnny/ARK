import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'app_config.dart';
import 'logger_service.dart';

/// Analytics and crash reporting service
class AnalyticsService {
  static FirebaseAnalytics? _analytics;
  static FirebaseCrashlytics? _crashlytics;
  static bool _initialized = false;
  
  static Future<void> initialize() async {
    if (!AppConfig.enableFirebase || _initialized) return;
    
    try {
      _analytics = FirebaseAnalytics.instance;
      _crashlytics = FirebaseCrashlytics.instance;
      
      // Enable crash collection
      await _crashlytics!.setCrashlyticsCollectionEnabled(true);
      
      // Set user identifier if available
      // _crashlytics!.setUserIdentifier(userId);
      
      _initialized = true;
      LoggerService.info('Analytics service initialized');
    } catch (e) {
      LoggerService.error('Failed to initialize analytics', e);
    }
  }
  
  // Event tracking
  static Future<void> logEvent(String name, [Map<String, dynamic>? parameters]) async {
    if (!_initialized || _analytics == null) return;
    
    try {
      await _analytics!.logEvent(
        name: name,
        parameters: parameters != null 
            ? Map<String, Object>.from(parameters) 
            : null,
      );
      LoggerService.debug('Analytics event: $name', parameters);
    } catch (e) {
      LoggerService.error('Failed to log event', e);
    }
  }
  
  // Screen tracking
  static Future<void> logScreenView(String screenName) async {
    if (!_initialized || _analytics == null) return;
    
    try {
      await _analytics!.logScreenView(screenName: screenName);
      LoggerService.debug('Screen view: $screenName');
    } catch (e) {
      LoggerService.error('Failed to log screen view', e);
    }
  }
  
  // User properties
  static Future<void> setUserProperty(String name, String? value) async {
    if (!_initialized || _analytics == null) return;
    
    try {
      await _analytics!.setUserProperty(name: name, value: value);
    } catch (e) {
      LoggerService.error('Failed to set user property', e);
    }
  }
  
  // Crash reporting
  static void recordError(dynamic error, StackTrace? stackTrace, {String? reason}) {
    if (!_initialized || _crashlytics == null) return;
    
    try {
      _crashlytics!.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: false,
      );
    } catch (e) {
      LoggerService.error('Failed to record error', e);
    }
  }
  
  static void recordFatalError(dynamic error, StackTrace? stackTrace, {String? reason}) {
    if (!_initialized || _crashlytics == null) return;
    
    try {
      _crashlytics!.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: true,
      );
    } catch (e) {
      LoggerService.error('Failed to record fatal error', e);
    }
  }
  
  // Log custom message
  static void log(String message) {
    if (!_initialized || _crashlytics == null) return;
    
    try {
      _crashlytics!.log(message);
    } catch (e) {
      LoggerService.error('Failed to log message', e);
    }
  }
}

