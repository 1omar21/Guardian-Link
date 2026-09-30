import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../utils/json_parser.dart';
import '../../models/user_model.dart';
import '../../models/task_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;

  // Get stored token
  Future<String?> getToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    return _token;
  }

  // Save token
  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  // Clear token
  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // Get headers with auth token
  Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Register user
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.register}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'full_name': fullName,
          'role': role,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = await JsonParser.parseJson(response.body);
        await saveToken(data['access_token']);
        return data;
      } else {
        throw Exception('Registration failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Registration error: $e');
    }
  }

  // Login user
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.login}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = await JsonParser.parseJson(response.body);
        await saveToken(data['access_token']);
        return data;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Invalid credentials');
      } else {
        throw Exception('Login failed: ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('Invalid credentials')) {
        rethrow;
      }
      throw Exception('Login error: $e');
    }
  }

  // Get current user
  Future<User> getCurrentUser() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.me}'),
        headers: headers,
      );

      print('🔍 API Response status: ${response.statusCode}');
      print('🔍 API Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = await JsonParser.parseJson(response.body);
        print('🔍 Decoded data: $data');
        print('🔍 focus_coins in response: ${data['focus_coins']}');
        final user = User.fromJson(data);
        print('🔍 User object created with focusCoins: ${user.focusCoins}');
        return user;
      } else {
        throw Exception('Failed to get user');
      }
    } catch (e) {
      print('❌ Get user error: $e');
      throw Exception('Get user error: $e');
    }
  }

  // Get tasks
  Future<List<Task>> getTasks() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.tasks}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = await JsonParser.parseJson(response.body);
        return data.map((json) => Task.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get tasks');
      }
    } catch (e) {
      throw Exception('Get tasks error: $e');
    }
  }

  // Create task
  Future<Task> createTask({
    required String title,
    required String description,
    required String assignedTo,
    String priority = 'medium',
    int rewardCoins = 10,
    DateTime? dueDate,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.tasks}'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'description': description,
          'assigned_to': assignedTo,
          'priority': priority,
          'reward_coins': rewardCoins,
          if (dueDate != null) 'due_date': dueDate.toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return Task.fromJson(jsonDecode(response.body));
      } else {
        print('Create task error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to create task: ${response.body}');
      }
    } catch (e) {
      print('Create task exception: $e');
      throw Exception('Create task error: $e');
    }
  }

  // Complete task
  Future<Map<String, dynamic>> completeTask(String taskId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.completeTask}'),
        headers: headers,
        body: jsonEncode({'task_id': taskId}),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to complete task');
      }
    } catch (e) {
      throw Exception('Complete task error: $e');
    }
  }

  // Reject task
  Future<void> rejectTask(String taskId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/tasks/reject/$taskId'),
        headers: headers,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to reject task');
      }
    } catch (e) {
      throw Exception('Reject task error: $e');
    }
  }

  // Schedule task
  Future<void> scheduleTask(String taskId, DateTime scheduledTime) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/tasks/schedule/$taskId'),
        headers: headers,
        body: jsonEncode({'scheduled_for': scheduledTime.toIso8601String()}),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to schedule task');
      }
    } catch (e) {
      throw Exception('Schedule task error: $e');
    }
  }

  // Delete task
  Future<void> deleteTask(String taskId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/api/tasks/$taskId'),
        headers: headers,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to delete task');
      }
    } catch (e) {
      throw Exception('Delete task error: $e');
    }
  }

  // Family Management - Invitation System
  Future<void> sendInvitation(String childEmail) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/family/invite'),
        headers: headers,
        body: jsonEncode({'child_email': childEmail}),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Failed to send invitation');
      }
    } catch (e) {
      print('Send invitation exception: $e');
      throw Exception('$e');
    }
  }

  Future<List<Map<String, dynamic>>> getInvitations() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/family/invitations'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        print('Get invitations error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Get invitations exception: $e');
      return [];
    }
  }

  Future<void> acceptInvitation(String invitationId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/family/accept/$invitationId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Failed to accept invitation');
      }
    } catch (e) {
      print('Accept invitation exception: $e');
      throw Exception('$e');
    }
  }

  Future<void> rejectInvitation(String invitationId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/family/reject/$invitationId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Failed to reject invitation');
      }
    } catch (e) {
      print('Reject invitation exception: $e');
      throw Exception('$e');
    }
  }

  Future<List<Map<String, dynamic>>> getChildren() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/family/children'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        print('Get children error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Get children exception: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFamilyMembers() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/family/members'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        print('Get family members error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Get family members exception: $e');
      return [];
    }
  }
  
  
  // FCM Token Management
  Future<void> saveFCMToken(String fcmToken) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/auth/fcm-token'),
        headers: headers,
        body: jsonEncode({'fcm_token': fcmToken}),
      );
      
      if (response.statusCode != 200) {
        print('Save FCM token error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Save FCM token exception: $e');
    }
  }

  // Location Monitoring - Get child's current location (parent only)
  Future<Map<String, dynamic>?> getChildLocation(String childId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/location/current/$childId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Get child location error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Get child location exception: $e');
      return null;
    }
  }

  // Get child's location history (parent only)
  Future<List<Map<String, dynamic>>> getChildLocationHistory(String childId, {int days = 7}) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/location/history/$childId?days=$days'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        print('Get location history error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Get location history exception: $e');
      return [];
    }
  }

  // Get child's check-in history (parent only)
  Future<List<Map<String, dynamic>>> getChildCheckIns(String childId, {int days = 7}) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/location/check-ins/$childId?days=$days'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        print('Get check-ins error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Get check-ins exception: $e');
      return [];
    }
  }
}
