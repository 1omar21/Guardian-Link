import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/safety_map.dart';
import 'browsing_history_screen.dart';
import 'parent_alerts_screen.dart';

class ParentLocationScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ParentLocationScreen({
    Key? key,
    required this.childId,
    required this.childName,
  }) : super(key: key);

  @override
  State<ParentLocationScreen> createState() => _ParentLocationScreenState();
}

class _ParentLocationScreenState extends State<ParentLocationScreen> {
  static const Duration _refreshEvery = Duration(seconds: 20);

  final LocationService _locationService = LocationService();

  bool _isLoading = true;
  Map<String, dynamic>? _childLocation;
  List<Map<String, dynamic>> _geofences = [];
  List<Map<String, dynamic>> _checkIns = [];
  Timer? _refreshTimer;

  // Placing a new safe zone on the map
  bool _placingZone = false;
  LatLng? _draftCenter;
  double _draftRadius = 200;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Near real-time: the child's phone uploads about once a minute while moving.
    _refreshTimer = Timer.periodic(_refreshEvery, (_) {
      if (!_placingZone) _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  LatLng? get _childLatLng {
    final lat = toDouble(_childLocation?['latitude']);
    final lng = toDouble(_childLocation?['longitude']);
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _locationService.getChildLocation(widget.childId),
        _locationService.getGeofences(),
        _locationService.getCheckIns(widget.childId),
      ]);
      if (!mounted) return;
      setState(() {
        _childLocation = results[0] as Map<String, dynamic>?;
        _geofences = results[1] as List<Map<String, dynamic>>;
        _checkIns = results[2] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading location data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startPlacingZone() {
    setState(() {
      _placingZone = true;
      _draftCenter = _childLatLng;
      _draftRadius = 200;
    });
  }

  void _cancelPlacingZone() {
    setState(() {
      _placingZone = false;
      _draftCenter = null;
    });
  }

  Future<void> _saveZone() async {
    final center = _draftCenter;
    if (center == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map to choose the centre of the safe zone')),
      );
      return;
    }
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this safe zone'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Zone name', hintText: 'e.g. Home, School'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final success = await _locationService.createGeofence(
      name: name,
      latitude: center.latitude,
      longitude: center.longitude,
      radius: _draftRadius.round(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? '✅ Safe zone "$name" created. You will be alerted when ${widget.childName} arrives or leaves.'
            : '❌ Could not create the safe zone'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    if (success) {
      _cancelPlacingZone();
      _loadData(silent: true);
    }
  }

  Future<void> _deleteZone(Map<String, dynamic> zone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete safe zone'),
        content: Text('Delete "${zone['name']}"? You will no longer get alerts for it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _locationService.deleteGeofence(zone['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Safe zone deleted' : 'Could not delete the safe zone')),
    );
    if (ok) _loadData(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final child = _childLatLng;
    final updatedAt = parseTime(_childLocation?['timestamp']);
    final isStale = updatedAt == null || DateTime.now().difference(updatedAt) > const Duration(minutes: 15);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Safety alerts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ParentAlertsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Browsing history',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BrowsingHistoryScreen(childId: widget.childId, childName: widget.childName),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: _placingZone ? const NeverScrollableScrollPhysics() : null,
                children: [
                  if (_placingZone)
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tap the map to place the safe zone',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Row(children: [
                              const Text('Radius'),
                              Expanded(
                                child: Slider(
                                  value: _draftRadius,
                                  min: 50,
                                  max: 2000,
                                  divisions: 39,
                                  label: '${_draftRadius.round()} m',
                                  onChanged: (v) => setState(() => _draftRadius = v),
                                ),
                              ),
                              Text('${_draftRadius.round()} m'),
                            ]),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(onPressed: _cancelPlacingZone, child: const Text('Cancel')),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _saveZone,
                                  icon: const Icon(Icons.check),
                                  label: const Text('Save zone'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Map
                  SafetyMap(
                    person: child,
                    zones: _geofences,
                    draftCenter: _placingZone ? _draftCenter : null,
                    draftRadius: _draftRadius,
                    onTap: _placingZone ? (point) => setState(() => _draftCenter = point) : null,
                    height: 320,
                  ),
                  const SizedBox(height: 12),

                  // Child's Current Location
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_pin_circle, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${widget.childName}\'s Location',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_childLocation != null) ...[
                            _buildInfoRow('Last updated', timeAgo(_childLocation!['timestamp'])),
                            const SizedBox(height: 6),
                            _buildInfoRow('Accuracy',
                                '${toDouble(_childLocation!['accuracy'])?.toStringAsFixed(0) ?? 'N/A'} m'),
                            const SizedBox(height: 6),
                            _buildInfoRow('Coordinates',
                                '${child!.latitude.toStringAsFixed(5)}, ${child.longitude.toStringAsFixed(5)}'),
                            if (isStale) ...[
                              const SizedBox(height: 8),
                              Text(
                                'This location is more than 15 minutes old. ${widget.childName}\'s phone may be '
                                'offline, have location turned off, or location sharing stopped.',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                              ),
                            ],
                          ] else
                            const Text('No location yet. Ask your child to open GuardianLink and allow location.'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Safe Zones
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.place, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text('Safe Zones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              if (!_placingZone)
                                TextButton.icon(
                                  onPressed: _startPlacingZone,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add'),
                                ),
                            ],
                          ),
                          const Text(
                            'You get a notification when your child arrives at or leaves a safe zone.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          if (_geofences.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No safe zones yet. Tap "Add" and pick a place on the map.'),
                              ),
                            )
                          else
                            ..._geofences.map((zone) {
                              final zoneLat = toDouble(zone['latitude']);
                              final zoneLng = toDouble(zone['longitude']);
                              final radius = toDouble(zone['radius']) ?? 0;
                              final distance = child != null && zoneLat != null && zoneLng != null
                                  ? _locationService.calculateDistance(
                                      child.latitude, child.longitude, zoneLat, zoneLng)
                                  : null;
                              final isInside = distance != null && distance <= radius;

                              return Card(
                                color: isInside ? Colors.green[50] : null,
                                child: ListTile(
                                  leading: Icon(
                                    isInside ? Icons.check_circle : Icons.location_city,
                                    color: isInside ? Colors.green : Colors.orange,
                                  ),
                                  title: Text(zone['name'] ?? 'Unknown'),
                                  subtitle: Text(
                                    'Radius ${radius.round()} m · '
                                    '${distance == null ? 'distance unknown' : isInside ? 'child is inside' : '${distance.toStringAsFixed(0)} m away'}',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Delete zone',
                                    onPressed: () => _deleteZone(zone),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Check-In History
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.verified_user, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Safety Check-Ins', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_checkIns.isEmpty)
                            const Center(
                              child: Padding(padding: EdgeInsets.all(16), child: Text('No check-ins yet')),
                            )
                          else
                            ..._checkIns.take(5).map((checkIn) => ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.green,
                                    child: Icon(Icons.check, color: Colors.white),
                                  ),
                                  title: Text(checkIn['message'] ?? 'Check-in'),
                                  subtitle: Text(timeAgo(checkIn['timestamp'])),
                                )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Updates automatically every ${_refreshEvery.inSeconds} seconds while this screen is open.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w500))),
      ],
    );
  }
}
