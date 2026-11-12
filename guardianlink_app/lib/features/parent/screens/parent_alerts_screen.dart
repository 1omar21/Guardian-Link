import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/safety_map.dart';

/// Parent's safety alerts: SOS alerts (with "mark as handled") and safe zone
/// arrivals/departures for all linked children.
class ParentAlertsScreen extends StatefulWidget {
  const ParentAlertsScreen({super.key});

  @override
  State<ParentAlertsScreen> createState() => _ParentAlertsScreenState();
}

class _ParentAlertsScreenState extends State<ParentAlertsScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _sos = [];
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;
  int _days = 7;
  Timer? _refreshTimer;
  StreamSubscription? _pushSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    _pushSubscription = FCMService().messages.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pushSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await _api.getAlerts(days: _days);
      if (!mounted) return;
      setState(() {
        _sos = List<Map<String, dynamic>>.from((data['sos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
        _events = List<Map<String, dynamic>>.from(
            (data['geofence_events'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> alert) async {
    try {
      await _api.resolveSOS(alert['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as handled. Your child has been told.'), backgroundColor: Colors.green),
      );
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
      );
    }
  }

  void _showOnMap(String title, double lat, double lng, {bool sos = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SafetyMap(
                  person: LatLng(lat, lng),
                  personIcon: sos ? Icons.sos : Icons.person_pin_circle,
                  personColor: sos ? Colors.red : Colors.blue,
                  height: MediaQuery.of(context).size.height * 0.6,
                ),
                const SizedBox(height: 12),
                SelectableText('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _sos.where((a) => a['status'] == 'active').toList();
    final resolved = _sos.where((a) => a['status'] != 'active').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Alerts'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.filter_list),
            initialValue: _days,
            onSelected: (d) {
              setState(() => _days = d);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('Last 24 hours')),
              PopupMenuItem(value: 7, child: Text('Last 7 days')),
              PopupMenuItem(value: 30, child: Text('Last 30 days')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline, color: Colors.red),
                        title: Text(_error!),
                      ),
                    ),
                  _sectionTitle('SOS alerts', Icons.sos, Colors.red),
                  if (_sos.isEmpty) _empty('No SOS alerts'),
                  ...active.map((a) => _sosCard(a, active: true)),
                  ...resolved.map((a) => _sosCard(a, active: false)),
                  const SizedBox(height: 24),
                  _sectionTitle('Safe zone activity', Icons.place, Colors.green),
                  if (_events.isEmpty) _empty('No arrivals or departures yet'),
                  ..._events.map(_eventTile),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text(text, style: TextStyle(color: Colors.grey.shade600))),
      );

  Widget _sosCard(Map<String, dynamic> alert, {required bool active}) {
    final lat = toDouble(alert['latitude']);
    final lng = toDouble(alert['longitude']);
    final name = (alert['child_name'] ?? '').toString().isEmpty ? 'Your child' : alert['child_name'];
    return Card(
      color: active ? Colors.red.shade50 : null,
      shape: active
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.red, width: 2))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.sos, color: active ? Colors.red : Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  active ? 'SOS from $name' : 'SOS from $name (handled)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: active ? Colors.red.shade800 : null),
                ),
              ),
              Text(timeAgo(alert['timestamp']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
            const SizedBox(height: 6),
            Text(alert['message']?.toString() ?? ''),
            Text(formatDateTime(alert['timestamp']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (lat == null || lng == null)
              const Text('No location available', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (lat != null && lng != null)
                OutlinedButton.icon(
                  onPressed: () => _showOnMap('SOS location', lat, lng, sos: true),
                  icon: const Icon(Icons.map),
                  label: const Text('View on map'),
                ),
              if (active)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: () => _resolve(alert),
                  icon: const Icon(Icons.check),
                  label: const Text('Mark as handled'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(Map<String, dynamic> event) {
    final entered = event['event'] == 'enter';
    final lat = toDouble(event['latitude']);
    final lng = toDouble(event['longitude']);
    final name = (event['child_name'] ?? '').toString().isEmpty ? 'Your child' : event['child_name'];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: entered ? Colors.green : Colors.orange,
          child: Icon(entered ? Icons.login : Icons.logout, color: Colors.white),
        ),
        title: Text('$name ${entered ? 'arrived at' : 'left'} ${event['geofence_name'] ?? 'a safe zone'}'),
        subtitle: Text('${formatDateTime(event['timestamp'])} · ${timeAgo(event['timestamp'])}'),
        trailing: lat != null && lng != null ? const Icon(Icons.map, size: 20) : null,
        onTap: lat != null && lng != null ? () => _showOnMap(event['geofence_name'] ?? 'Location', lat, lng) : null,
      ),
    );
  }
}
