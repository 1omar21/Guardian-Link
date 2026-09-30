import 'package:flutter/material.dart';
import '../../../core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

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
  final LocationService _locationService = LocationService();
  
  bool _isLoading = true;
  Map<String, dynamic>? _childLocation;
  List<Map<String, dynamic>> _geofences = [];
  List<Map<String, dynamic>> _locationHistory = [];
  List<Map<String, dynamic>> _checkIns = [];
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final location = await _locationService.getChildLocation(widget.childId);
      final geofences = await _locationService.getGeofences();
      final checkIns = await _locationService.getCheckIns(widget.childId);
      
      setState(() {
        _childLocation = location;
        _geofences = geofences;
        _checkIns = checkIns;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading location data: $e');
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _createGeofence() async {
    if (_childLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location available')),
      );
      return;
    }
    
    final nameController = TextEditingController();
    final radiusController = TextEditingController(text: '500');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Safe Zone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Zone Name',
                hintText: 'e.g., Home, School',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: radiusController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Radius (meters)',
                hintText: '500',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              
              final success = await _locationService.createGeofence(
                name: nameController.text,
                latitude: _childLocation!['latitude'],
                longitude: _childLocation!['longitude'],
                radius: int.tryParse(radiusController.text) ?? 500,
              );
              
              Navigator.pop(context, success);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Safe zone created successfully'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Child's Current Location
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_pin_circle, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                '${widget.childName}\'s Location',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_childLocation != null) ...[
                            _buildInfoRow('Latitude', _childLocation!['latitude'].toStringAsFixed(6)),
                            const SizedBox(height: 8),
                            _buildInfoRow('Longitude', _childLocation!['longitude'].toStringAsFixed(6)),
                            const SizedBox(height: 8),
                            _buildInfoRow('Accuracy', '${_childLocation!['accuracy']?.toStringAsFixed(1) ?? 'N/A'}m'),
                            const SizedBox(height: 8),
                            _buildInfoRow('Last Updated', _formatTimestamp(_childLocation!['timestamp'])),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _createGeofence,
                              icon: const Icon(Icons.add_location),
                              label: const Text('Create Safe Zone Here'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                          ] else
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No location data available'),
                              ),
                            ),
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
                              TextButton.icon(
                                onPressed: _createGeofence,
                                icon: const Icon(Icons.add),
                                label: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_geofences.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No safe zones yet'),
                              ),
                            )
                          else
                            ..._geofences.map((zone) {
                              final distance = _childLocation != null
                                  ? _locationService.calculateDistance(
                                      _childLocation!['latitude'],
                                      _childLocation!['longitude'],
                                      zone['latitude'],
                                      zone['longitude'],
                                    )
                                  : null;
                              
                              final isInside = distance != null && distance <= zone['radius'];
                              
                              return Card(
                                color: isInside ? Colors.green[50] : null,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.location_city,
                                    color: isInside ? Colors.green : Colors.orange,
                                  ),
                                  title: Text(zone['name'] ?? 'Unknown'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Radius: ${zone['radius']}m'),
                                      if (distance != null)
                                        Text(
                                          isInside
                                              ? '✅ Child is inside'
                                              : '${distance.toStringAsFixed(0)}m away',
                                          style: TextStyle(
                                            color: isInside ? Colors.green : Colors.grey,
                                            fontWeight: isInside ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Icon(
                                    isInside ? Icons.check_circle : Icons.circle_outlined,
                                    color: isInside ? Colors.green : Colors.grey,
                                  ),
                                ),
                              );
                            }).toList(),
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
                          Row(
                            children: const [
                              Icon(Icons.verified_user, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'Safety Check-Ins',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_checkIns.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No check-ins yet'),
                              ),
                            )
                          else
                            ..._checkIns.take(5).map((checkIn) {
                              return Card(
                                color: Colors.green[50],
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.green,
                                    child: Icon(Icons.check, color: Colors.white),
                                  ),
                                  title: Text(checkIn['message'] ?? 'Check-in'),
                                  subtitle: Text(
                                    _formatTimestamp(checkIn['timestamp']),
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            }).toList(),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Info Card
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                          SizedBox(height: 8),
                          Text(
                            'Location updates automatically when your child uses the app',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
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
  
  String _formatTimestamp(dynamic timestamp) {
    try {
      final DateTime time = DateTime.parse(timestamp.toString());
      final now = DateTime.now();
      final diff = now.difference(time);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      return 'Unknown';
    }
  }
}
