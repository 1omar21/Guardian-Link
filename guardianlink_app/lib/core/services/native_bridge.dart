import 'package:flutter/services.dart';

/// Calls into MainActivity.kt (browsing monitor status and settings).
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('guardianlink/native');

  /// True if the child has switched on "GuardianLink browsing monitor"
  /// in Settings > Accessibility.
  static Future<bool> isBrowsingMonitorEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isBrowsingMonitorEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// Upload any browsing history waiting on the device (e.g. after login).
  static Future<void> flushBrowsingHistory() async {
    try {
      await _channel.invokeMethod('flushBrowsingHistory');
    } catch (_) {}
  }
}
