import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/location_tracker.dart';
import '../../../core/widgets/safety_map.dart';

class ChildLocationScreen extends StatefulWidget {
  const ChildLocationScreen({Key? key}) : super(key: key);

  @override
  State<ChildLocationScreen> createState() => _ChildLocationScreenState();
}

class _ChildLocationScreenState extends State<ChildLocationScreen> {
  final LocationService _locationService = LocationService();
  final LocationTracker _tracker = LocationTracker();

  bool _isLoading = true;
  bool _hasPermission = false;
  Position? _currentPosition;
  List<Map<String, dynamic>> _safeZones = [];
  DateTime? _lastCheckIn;

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_onTrackerChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tracker.removeListener(_onTrackerChanged);
    super.dispose();
  }

  void _onTrackerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);
    await _locationService.requestPermissions();
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final hasPermission = await _locationService.hasPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = hasPermission);
    if (!hasPermission) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      await _tracker.start();
      final position = await _locationService.getCurrentLocation();
      final geofences = await _locationService.getGeofences();
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _safeZones = geofences;
      });
      if (position != null) await _tracker.uploadNow(position);
    } catch (e) {
      print('Error loading location data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkIn() async {
    final success = await _locationService.checkIn("I'm safe!");
    if (!mounted) return;
    if (success) setState(() => _lastCheckIn = DateTime.now());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '✅ Check-in sent to your parent.' : '❌ Check-in failed. Please try again.'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Location')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Location')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.share_location, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Share your location with your parent',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const _ExplainRow(Icons.visibility, 'Your parent can see where you are on a map.'),
            const _ExplainRow(Icons.place, 'Your parent is told when you arrive at or leave places like Home or School.'),
            const _ExplainRow(Icons.sos, 'If you press SOS, your location is sent with the alert.'),
            const _ExplainRow(Icons.notifications,
                'While sharing, a notification is always shown on your phone, so you know it is on.'),
            const _ExplainRow(Icons.lock, 'Only your linked parent can see your location.'),
            const SizedBox(height: 16),
            const Text(
              'On the next screen choose "While using the app". "Allow all the time" is not needed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.location_on),
              label: const Text('Allow location'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      );
    }

    final me = _currentPosition != null ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Location'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SafetyMap(person: me, zones: _safeZones, height: 260),
            const SizedBox(height: 12),

            // Sharing status
            Card(
              child: ListTile(
                leading: Icon(
                  _tracker.isTracking ? Icons.share_location : Icons.location_disabled,
                  color: _tracker.isTracking ? Colors.green : Colors.orange,
                ),
                title: Text(_tracker.isTracking ? 'Location sharing is on' : 'Location sharing is off'),
                subtitle: Text(
                  _tracker.isTracking
                      ? 'Your parent sees your location. It keeps working with the screen off.'
                      : (_tracker.lastError ?? 'Pull down to retry'),
                ),
              ),
            ),
            if (me == null)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.gps_off),
                  title: Text('Location not available'),
                  subtitle: Text('Make sure location (GPS) is turned on.'),
                ),
              ),
            const SizedBox(height: 12),

            // Safety Check-in Button
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.shield, size: 48, color: Colors.green),
                    const SizedBox(height: 12),
                    const Text('Safety Check-In',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    const Text("Let your parent know you're safe",
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _checkIn,
                      icon: const Icon(Icons.check_circle),
                      label: const Text("I'm Safe!"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                    ),
                    if (_lastCheckIn != null) ...[
                      const SizedBox(height: 12),
                      Text('Last check-in: ${_formatTime(_lastCheckIn!)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Safe Zones
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.place, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Safe Zones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_safeZones.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No safe zones yet')))
                    else
                      ..._safeZones.map((zone) {
                        final lat = (zone['latitude'] as num?)?.toDouble();
                        final lng = (zone['longitude'] as num?)?.toDouble();
                        final radius = (zone['radius'] as num?)?.toDouble() ?? 0;
                        final distance = _currentPosition != null && lat != null && lng != null
                            ? _locationService.calculateDistance(
                                _currentPosition!.latitude, _currentPosition!.longitude, lat, lng)
                            : null;
                        final inside = distance != null && distance <= radius;
                        return ListTile(
                          leading: const Icon(Icons.location_city, color: Colors.orange),
                          title: Text(zone['name'] ?? 'Unknown'),
                          subtitle: distance != null
                              ? Text(inside ? 'You are here' : '${distance.toStringAsFixed(0)} m away')
                              : null,
                          trailing: Icon(
                            inside ? Icons.check_circle : Icons.circle_outlined,
                            color: inside ? Colors.green : Colors.grey,
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ExplainRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ExplainRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
