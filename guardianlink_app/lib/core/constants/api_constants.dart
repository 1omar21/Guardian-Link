class ApiConstants {
  // Backend API base URL
  // For physical device: use your computer's IP address
  static const String baseUrl = 'http://192.168.100.41:8000';
  // For Android emulator: use 'http://10.0.2.2:8000'
  
  // API Endpoints
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String me = '/api/auth/me';
  
  // Tasks
  static const String tasks = '/api/tasks/';
  static const String completeTask = '/api/tasks/complete';
  static const String verifyTask = '/api/tasks/verify';
}
