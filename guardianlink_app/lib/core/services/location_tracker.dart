import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

/// Continuous location sharing for the child's phone.
///
/// Uses geolocator's built-in Android foreground service: while sharing is on,
/// a permanent notification ("GuardianLink is sharing your location") is shown
/// and updates keep flowing with the screen off or the app in the background.
/// Only "while using the app" permission is needed.
///
/// Uploads are throttled: at most one per [minUploadInterval] unless the child
/// moved more than [forceUploadDistance] meters, plus a [heartbeat] upload so
/// the parent sees a fresh "last updated" time when the child is stationary.
class LocationTracker extends ChangeNotifier {
  static final LocationTracker _instance = LocationTracker._internal();
  factory LocationTracker() => _instance;
  LocationTracker._internal();

  static const Duration minUploadInterval = Duration(minutes: 1);
  static const Duration heartbeat = Duration(minutes: 5);
  static const double forceUploadDistance = 100;

  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _subscription;
  Timer? _heartbeatTimer;
  Position? _lastPosition;
  Position? _lastUploadedPosition;
  DateTime? _lastUploadAt;
  String? _lastError;
  bool _uploading = false;

  bool get isTracking => _subscription != null;
  DateTime? get lastUploadAt => _lastUploadAt;
  Position? get lastPosition => _lastPosition;
  String? get lastError => _lastError;

  /// Start sharing. Returns false if permission or location services are off.
  Future<bool> start() async {
    if (_subscription != null) return true;

    if (!await _locationService.hasPermissions()) {
      _lastError = 'Location permission not granted';
      notifyListeners();
      return false;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _lastError = 'Location is turned off on this phone';
      notifyListeners();
      return false;
    }

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
      intervalDuration: const Duration(seconds: 30),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'GuardianLink is sharing your location',
        notificationText: 'Your parent can see where you are and gets safe zone alerts.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e) {
        _lastError = e.toString();
        notifyListeners();
      },
    );
    _heartbeatTimer = Timer.periodic(heartbeat, (_) => _onHeartbeat());
    _lastError = null;
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    notifyListeners();
  }

  void _onPosition(Position position) {
    _lastPosition = position;
    final due = _lastUploadAt == null ||
        DateTime.now().difference(_lastUploadAt!) >= minUploadInterval;
    final movedFar = _lastUploadedPosition != null &&
        Geolocator.distanceBetween(
              _lastUploadedPosition!.latitude,
              _lastUploadedPosition!.longitude,
              position.latitude,
              position.longitude,
            ) >=
            forceUploadDistance;
    if (due || movedFar) _upload(position);
  }

  Future<void> _onHeartbeat() async {
    if (_lastUploadAt != null && DateTime.now().difference(_lastUploadAt!) < heartbeat) return;
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
    } catch (_) {
      position = _lastPosition;
    }
    if (position != null) await _upload(position);
  }

  /// Upload a position right away (also used after SOS / screen refresh).
  Future<bool> uploadNow(Position position) async {
    _lastPosition = position;
    return _upload(position);
  }

  Future<bool> _upload(Position position) async {
    if (_uploading) return false;
    _uploading = true;
    try {
      final ok = await _locationService.updateLocation(position);
      if (ok) {
        _lastUploadAt = DateTime.now();
        _lastUploadedPosition = position;
        _lastError = null;
      } else {
        _lastError = 'Could not reach the server';
      }
      notifyListeners();
      return ok;
    } finally {
      _uploading = false;
    }
  }
}
