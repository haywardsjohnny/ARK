import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'logger_service.dart';

/// Global error handler for Flutter framework errors
class ErrorHandler {
  static void setupErrorHandling() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      
      // Log to console
      LoggerService.error(
        'Flutter Error: ${details.exception}',
        details.exception,
        details.stack,
      );
      
      // Send to Sentry in production
      if (kReleaseMode) {
        Sentry.captureException(
          details.exception,
          stackTrace: details.stack,
          hint: Hint.withMap({
            'library': details.library,
            'context': details.context?.toString(),
          }),
        );
      }
    };
    
    // Handle async errors outside Flutter framework
    PlatformDispatcher.instance.onError = (error, stack) {
      LoggerService.fatal(
        'Unhandled Error: $error',
        error,
        stack,
      );
      
      if (kReleaseMode) {
        Sentry.captureException(error, stackTrace: stack);
      }
      
      return true; // Handled
    };
  }
  
  /// Wrap async operations with error handling
  static Future<T?> safeAsync<T>(
    Future<T> Function() operation, {
    String? context,
    T? defaultValue,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      LoggerService.error(
        'Error in ${context ?? "operation"}: $e',
        e,
        stackTrace,
      );
      
      if (kReleaseMode) {
        Sentry.captureException(
          e,
          stackTrace: stackTrace,
          hint: Hint.withMap({'context': context}),
        );
      }
      
      return defaultValue;
    }
  }
  
  /// Show user-friendly error message
  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

