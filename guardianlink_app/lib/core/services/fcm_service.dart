import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../features/parent/screens/parent_alerts_screen.dart';
import '../navigation.dart';
import 'api_service.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  String? _fcmToken;
  bool _initialized = false;
  RemoteMessage? _pendingOpen;
  final StreamController<RemoteMessage> _messages = StreamController<RemoteMessage>.broadcast();

  /// Every push received while the app is running (foreground or tapped).
  /// Screens listen to this to refresh their data.
  Stream<RemoteMessage> get messages => _messages.stream;

  /// Firebase is optional at runtime: if it failed to initialise, every
  /// method here becomes a no-op instead of throwing.
  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  /// Initialize FCM: permissions, token and listeners. Safe to call before login.
  Future<void> initialize() async {
    if (_initialized || !_firebaseReady) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      debugPrint('FCM permission: ${settings.authorizationStatus}');

      _fcmToken = await messaging.getToken();

      // Only uploads if a user is logged in; otherwise done after login.
      await syncTokenWithBackend();

      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        syncTokenWithBackend();
      });

      // App open: Android does not show the system notification, so show it in-app.
      FirebaseMessaging.onMessage.listen((message) {
        _messages.add(message);
        _showInApp(message);
      });

      // Notification tapped while the app was in the background.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _messages.add(message);
        _openFromNotification(message);
      });

      // Notification tapped while the app was closed: handled once the
      // parent dashboard is on screen (see consumePendingOpen).
      _pendingOpen = await messaging.getInitialMessage();
    } catch (e) {
      debugPrint('❌ FCM initialization error: $e');
    }
  }

  /// Send the current FCM token to the backend for the logged-in user.
  /// Call after login/register. Never throws.
  Future<void> syncTokenWithBackend() async {
    try {
      if (!_firebaseReady) return;

      final apiService = ApiService();
      if (await apiService.getToken() == null) return; // not logged in yet

      _fcmToken ??= await FirebaseMessaging.instance.getToken();
      final token = _fcmToken;
      if (token == null) return;

      await apiService.saveFCMToken(token);
    } catch (e) {
      debugPrint('❌ Failed to send FCM token to backend: $e');
    }
  }

  /// Stop this device from receiving the current user's notifications.
  /// Call on logout, BEFORE the auth token is cleared. Never throws.
  Future<void> unregisterFromBackend() async {
    try {
      if (!_firebaseReady) return;
      final token = _fcmToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null) await ApiService().removeFCMToken(token);
    } catch (e) {
      debugPrint('❌ Failed to unregister FCM token: $e');
    }
  }

  /// Called by the parent dashboard once it is visible: opens the screen for
  /// a notification that launched the app.
  void consumePendingOpen() {
    final message = _pendingOpen;
    _pendingOpen = null;
    if (message != null) _openFromNotification(message);
  }

  /// Get current FCM token
  String? get token => _fcmToken;

  // ------------------------------------------------------------------ //

  static const _parentAlertTypes = {'sos', 'geofence', 'check_in'};

  void _openFromNotification(RemoteMessage message) {
    final type = message.data['type'];
    if (!_parentAlertTypes.contains(type)) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const ParentAlertsScreen()),
    );
  }

  void _showInApp(RemoteMessage message) {
    final title = message.notification?.title ?? 'GuardianLink';
    final body = message.notification?.body ?? '';
    final type = message.data['type'];

    if (type == 'sos') {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.red.shade50,
          icon: const Icon(Icons.sos, color: Colors.red, size: 56),
          title: Text(title, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(dialogContext);
                _openFromNotification(message);
              },
              icon: const Icon(Icons.map),
              label: const Text('View alert'),
            ),
          ],
        ),
      );
      return;
    }

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title\n$body'),
        duration: const Duration(seconds: 5),
        action: _parentAlertTypes.contains(type)
            ? SnackBarAction(label: 'View', onPressed: () => _openFromNotification(message))
            : null,
      ),
    );
  }
}
