import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'logger_service.dart';

/// App and device information service
class AppInfo {
  static PackageInfo? _packageInfo;
  static DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  static Future<void> initialize() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      LoggerService.info('App Info initialized: ${_packageInfo!.version}');
    } catch (e) {
      LoggerService.error('Failed to initialize app info', e);
    }
  }
  
  static String get version => _packageInfo?.version ?? 'unknown';
  static String get buildNumber => _packageInfo?.buildNumber ?? 'unknown';
  static String get appName => _packageInfo?.appName ?? 'SPORTSDUG';
  static String get packageName => _packageInfo?.packageName ?? 'unknown';
  
  static String get versionString => '$version+$buildNumber';
  
  /// Get device information for analytics
  static Future<Map<String, String>> getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'platform': 'android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'version': androidInfo.version.release,
          'sdk': androidInfo.version.sdkInt.toString(),
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return {
          'platform': 'ios',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'systemVersion': iosInfo.systemVersion,
          'identifierForVendor': iosInfo.identifierForVendor ?? 'unknown',
        };
      }
    } catch (e) {
      LoggerService.error('Failed to get device info', e);
    }
    
    return {'platform': Platform.operatingSystem};
  }
}

