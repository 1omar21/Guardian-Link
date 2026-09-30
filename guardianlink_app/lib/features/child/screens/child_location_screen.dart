import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_service.dart';

class ChildLocationScreen extends StatefulWidget {
  const ChildLocationScreen({Key? key}) : super(key: key);

  @override
  State<ChildLocationScreen> createState() => _ChildLocationScreenState();
}

class _ChildLocationScreenState extends State<ChildLocationScreen> {
  final LocationService _locationService = LocationService();
  
  bool _isLoading = true;
  bool _hasPermission = false;
  Position? _currentPosition;
  List<Map<String, dynamic>> _safeZones = [];
  DateTime? _lastCheckIn;
  
  @override
  void initState() {
    super.initState();
    _loadData(); // Changed from _initialize()
  }
  
  // The _initialize method is no longer needed as its logic is integrated into _loadData
  // Future<void> _initialize() async {
  //   await _checkPermission();
  //   if (_hasPermission) {
  //     await _loadData();
  //   }
  //   setState(() => _isLoading = false);
  // }
  
  Future<void> _checkPermission() async {
    final hasPermission = await _locationService.hasPermissions();
    setState(() => _hasPermission = hasPermission);
  }
  
  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);
    await _locationService.requestPermissions();
    await Future.delayed(const Duration(seconds: 1));
    await _checkPermission();
    if (_hasPermission) {
      await _loadData();
    }
    setState(() => _isLoading = false);
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // Check permission first
    await _checkPermission();
    
    if (!_hasPermission) {
      setState(() => _isLoading = false);
      return;
    }
    
    try {
      final position = await _locationService.getCurrentLocation();
      final geofences = await _locationService.getGeofences();
      
      setState(() {
        _currentPosition = position;
        _safeZones = geofences;
      });
      
      // Update location on backend
      if (position != null) {
        await _locationService.updateLocation(position);
      }
    } catch (e) {
      print('Error loading location data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _checkIn() async {
    final success = await _locationService.checkIn("I'm safe!");
    
    if (success && mounted) {
      setState(() => _lastCheckIn = DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Check-in successful! Parent notified.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Check-in failed. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_off, size: 80, color: Colors.grey),
                const SizedBox(height: 24),
                const Text(
                  'Location Permission Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'To use location features and safety check-in, we need your location permission.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _requestPermission,
                  icon: const Icon(Icons.location_on),
                  label: const Text('Grant Permission'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Current Location Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.my_location, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'Current Location',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_currentPosition != null) ...[
                      _buildInfoRow('Latitude', _currentPosition!.latitude.toStringAsFixed(6)),
                      const SizedBox(height: 8),
                      _buildInfoRow('Longitude', _currentPosition!.longitude.toStringAsFixed(6)),
                      const SizedBox(height: 8),
                      _buildInfoRow('Accuracy', '${_currentPosition!.accuracy.toStringAsFixed(1)}m'),
                    ] else
                      const Text('Location not available'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Safety Check-in Button
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.shield, size: 48, color: Colors.green),
                    const SizedBox(height: 12),
                    const Text(
                      'Safety Check-In',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Let your parent know you\'re safe',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _checkIn,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('I\'m Safe!'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                    ),
                    if (_lastCheckIn != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Last check-in: ${_formatTime(_lastCheckIn!)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
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
                      children: const [
                        Icon(Icons.place, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Safe Zones',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_safeZones.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No safe zones yet'),
                        ),
                      )
                    else
                      ..._safeZones.map((zone) {
                        final distance = _currentPosition != null
                            ? _locationService.calculateDistance(
                                _currentPosition!.latitude,
                                _currentPosition!.longitude,
                                zone['latitude'],
                                zone['longitude'],
                              )
                            : null;
                        
                        return ListTile(
                          leading: const Icon(Icons.location_city, color: Colors.orange),
                          title: Text(zone['name'] ?? 'Unknown'),
                          subtitle: distance != null
                              ? Text('${distance.toStringAsFixed(0)}m away')
                              : null,
                          trailing: Icon(
                            distance != null && distance <= zone['radius']
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: distance != null && distance <= zone['radius']
                                ? Colors.green
                                : Colors.grey,
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
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
        Text(
          label,
          style: const TextStyle(color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
