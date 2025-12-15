import 'package:logger/logger.dart';
import 'app_config.dart';

/// Centralized logging service
class LoggerService {
  static Logger? _logger;
  
  static Logger get instance {
    _logger ??= Logger(
      printer: PrettyPrinter(
        methodCount: AppConfig.enableVerboseLogging ? 2 : 0,
        errorMethodCount: 3,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        printTime: true,
      ),
      level: AppConfig.isProduction ? Level.warning : Level.debug,
    );
    return _logger!;
  }
  
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    instance.d(message, error: error, stackTrace: stackTrace);
  }
  
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    instance.i(message, error: error, stackTrace: stackTrace);
  }
  
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    instance.w(message, error: error, stackTrace: stackTrace);
  }
  
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    instance.e(message, error: error, stackTrace: stackTrace);
  }
  
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    instance.f(message, error: error, stackTrace: stackTrace);
  }
}

