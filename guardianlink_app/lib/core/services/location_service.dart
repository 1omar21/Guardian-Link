import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/api_constants.dart';
import '../utils/json_parser.dart';
import 'api_service.dart';

class LocationService {
  /// Request location permissions
  Future<bool> requestPermissions() async {
    // Check current status
    var status = await Permission.location.status;
    
    if (status.isDenied) {
      // Request permission
      status = await Permission.location.request();
    }
    
    if (status.isPermanentlyDenied) {
      // Open app settings
      await openAppSettings();
      return false;
    }
    
    // "While using the app" is enough: background sharing runs as a visible
    // foreground service (see LocationTracker), so "Allow all the time" is
    // never requested.
    return status.isGranted;
  }

  /// Check if location permissions are granted
  Future<bool> hasPermissions() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await hasPermissions();
      if (!hasPermission) {
        print('Location permission not granted');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      return position;
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  /// Send location update to backend. Returns true on success.
  Future<bool> updateLocation(Position position) async {
    try {
      final token = await ApiService().getToken();
      
      if (token == null) {
        print('❌ Location update failed: Not authenticated');
        throw Exception('Not authenticated');
      }

      print('📍 Sending location update: ${position.latitude}, ${position.longitude}');

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/location/update'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      if (response.statusCode == 201) {
        print('✅ Location updated successfully');
        return true;
      }
      print('❌ Location update failed: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      print('❌ Error updating location: $e');
      return false;
    }
  }

  /// Send safety check-in
  Future<bool> checkIn(String message) async {
    try {
      print('🔔 Starting check-in...');
      
      final position = await getCurrentLocation();
      if (position == null) {
        print('❌ Check-in failed: Could not get location');
        throw Exception('Could not get location');
      }
      
      print('📍 Got location: ${position.latitude}, ${position.longitude}');

      final token = await ApiService().getToken();
      
      if (token == null) {
        print('❌ Check-in failed: Not authenticated');
        throw Exception('Not authenticated');
      }
      
      print('🔑 Token found, sending check-in request...');

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/location/check-in'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'message': message,
          'latitude': position.latitude,
          'longitude': position.longitude,
        }),
      );

      print('📡 Check-in response: ${response.statusCode}');
      
      if (response.statusCode == 201) {
        print('✅ Check-in successful');
        return true;
      } else {
        print('❌ Check-in failed: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to check in: ${response.body}');
      }
    } catch (e) {
      print('❌ Error checking in: $e');
      return false;
    }
  }

  /// Get child's current location (parent only)
  Future<Map<String, dynamic>?> getChildLocation(String childId) async {
    try {
      final token = await ApiService().getToken();
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/location/current/$childId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e) {
      print('Error getting child location: $e');
      return null;
    }
  }

  /// Get geofences for family
  Future<List<Map<String, dynamic>>> getGeofences() async {
    try {
      final token = await ApiService().getToken();
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/location/geofences'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = await JsonParser.parseJson(response.body);
        return data.map((item) => Map<String, dynamic>.from(item)).toList();
      } else {
        return [];
      }
    } catch (e) {
      print('Error getting geofences: $e');
      return [];
    }
  }

  /// Create geofence (parent only)
  Future<bool> createGeofence({
    required String name,
    required double latitude,
    required double longitude,
    required int radius,
  }) async {
    try {
      final token = await ApiService().getToken();
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/location/geofence'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'latitude': latitude,
          'longitude': longitude,
          'radius': radius,
        }),
      );

      return response.statusCode == 201;
    } catch (e) {
      print('Error creating geofence: $e');
      return false;
    }
  }

  /// Delete a safe zone (parent only)
  Future<bool> deleteGeofence(String geofenceId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) throw Exception('Not authenticated');
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/api/location/geofence/$geofenceId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting geofence: $e');
      return false;
    }
  }

  /// Get child's check-in history (parent only)
  Future<List<Map<String, dynamic>>> getCheckIns(String childId, {int days = 7}) async {
    try {
      final token = await ApiService().getToken();
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/location/check-ins/$childId?days=$days'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = await JsonParser.parseJson(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        print('Get check-ins error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error getting check-ins: $e');
      return [];
    }
  }

  /// Calculate distance between two points in meters
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }
}
