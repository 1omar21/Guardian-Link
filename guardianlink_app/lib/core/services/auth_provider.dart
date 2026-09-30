import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  User? _currentUser;
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;

  // Extract clean error message from exception
  String _extractErrorMessage(dynamic error) {
    final errorStr = error.toString();
    
    // Remove "Exception: " prefix if present
    if (errorStr.startsWith('Exception: ')) {
      return errorStr.substring('Exception: '.length);
    }
    
    return errorStr;
  }

  // Update local user state manually (e.g. after earning coins/stickers)
  void updateUser(User user) {
    _currentUser = user;
    notifyListeners();
    debugPrint('🔄 AuthProvider: User state manually updated (Stickers: ${_currentUser?.stickers?.length})');
  }

  // Register
  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('📝 AuthProvider: Starting registration for $email, role: $role');
      final response = await _apiService.register(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
      );
      
      debugPrint('📝 AuthProvider: Registration API response: $response');
      
      // Ensure we have a valid user in response
      if (response['user'] == null) {
        throw Exception('Registration failed: No user data received');
      }
      
      _currentUser = User.fromJson(response['user']);
      debugPrint('📝 AuthProvider: User created: ${_currentUser?.email}, isParent: ${_currentUser?.isParent}');
      
      // Clear any previous errors
      _error = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _extractErrorMessage(e);
      debugPrint('❌ AuthProvider: Registration error: $_error');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Login
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('🔑 AuthProvider: Starting login for $email');
      await _apiService.login(email: email, password: password);
      debugPrint('🔑 AuthProvider: Login API call successful');
      
      _currentUser = await _apiService.getCurrentUser();
      debugPrint('🔑 AuthProvider: Got current user: ${_currentUser?.email}, role: ${_currentUser?.role}');
      
      // Clear any previous errors
      _error = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _extractErrorMessage(e);
      debugPrint('❌ AuthProvider: Login error: $_error');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    await _apiService.clearToken();
    _currentUser = null;
    notifyListeners();
  }

  // Check if user is logged in
  Future<void> checkAuth() async {
    try {
      final token = await _apiService.getToken();
      if (token != null) {
        _currentUser = await _apiService.getCurrentUser();
      }
    } catch (e) {
      await _apiService.clearToken();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }
}
