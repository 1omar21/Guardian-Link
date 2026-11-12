import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../utils/time_format.dart';

/// Map with the child's position and the family's safe zones.
///
/// Uses free OpenStreetMap tiles through flutter_map (no API key, no billing).
/// OSM's tile policy asks apps to identify themselves (userAgentPackageName)
/// and to show the attribution, both done here.
class SafetyMap extends StatefulWidget {
  /// Child (or SOS) position to mark. Null = no marker.
  final LatLng? person;
  final IconData personIcon;
  final Color personColor;

  /// Safe zones as returned by the API: {id, name, latitude, longitude, radius}.
  final List<Map<String, dynamic>> zones;

  /// A zone being placed (shown dashed/orange before it is saved).
  final LatLng? draftCenter;
  final double? draftRadius;

  final void Function(LatLng point)? onTap;
  final double height;

  const SafetyMap({
    super.key,
    this.person,
    this.personIcon = Icons.person_pin_circle,
    this.personColor = Colors.blue,
    this.zones = const [],
    this.draftCenter,
    this.draftRadius,
    this.onTap,
    this.height = 280,
  });

  @override
  State<SafetyMap> createState() => _SafetyMapState();
}

class _SafetyMapState extends State<SafetyMap> {
  final MapController _controller = MapController();

  static LatLng? zoneCenter(Map<String, dynamic> zone) {
    final lat = toDouble(zone['latitude']);
    final lng = toDouble(zone['longitude']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng get _initialCenter {
    if (widget.person != null) return widget.person!;
    for (final zone in widget.zones) {
      final c = zoneCenter(zone);
      if (c != null) return c;
    }
    return const LatLng(20, 0); // world view until there is something to show
  }

  bool get _hasFocus => widget.person != null || widget.zones.isNotEmpty;

  void _recenter() {
    final target = widget.person ?? (_hasFocus ? _initialCenter : null);
    if (target == null) return;
    try {
      _controller.move(target, 16);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final circles = <CircleMarker>[
      for (final zone in widget.zones)
        if (zoneCenter(zone) != null)
          CircleMarker(
            point: zoneCenter(zone)!,
            radius: toDouble(zone['radius']) ?? 100,
            useRadiusInMeter: true,
            color: Colors.green.withOpacity(0.15),
            borderColor: Colors.green,
            borderStrokeWidth: 2,
          ),
      if (widget.draftCenter != null)
        CircleMarker(
          point: widget.draftCenter!,
          radius: widget.draftRadius ?? 200,
          useRadiusInMeter: true,
          color: Colors.orange.withOpacity(0.2),
          borderColor: Colors.orange,
          borderStrokeWidth: 2,
        ),
    ];

    final markers = <Marker>[
      for (final zone in widget.zones)
        if (zoneCenter(zone) != null)
          Marker(
            point: zoneCenter(zone)!,
            width: 120,
            height: 28,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Text(
                  zone['name']?.toString() ?? 'Safe zone',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      if (widget.person != null)
        Marker(
          point: widget.person!,
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: Icon(widget.personIcon, color: widget.personColor, size: 44),
        ),
    ];

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _hasFocus ? 16 : 2,
                onTap: widget.onTap == null ? null : (_, point) => widget.onTap!(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.guardianlink.app',
                ),
                CircleLayer(circles: circles),
                MarkerLayer(markers: markers),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
            if (_hasFocus)
              Positioned(
                right: 8,
                top: 8,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    tooltip: 'Re-center',
                    icon: const Icon(Icons.my_location, color: Colors.blue),
                    onPressed: _recenter,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
