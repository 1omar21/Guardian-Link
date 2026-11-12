class ApiConstants {
  // Backend API base URL.
  // Physical phone: your PC's Wi-Fi IPv4 address (run `ipconfig`), same Wi-Fi as the phone.
  // Android emulator: http://10.0.2.2:8000
  // Override without editing code:
  //   flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.41:8000',
  );

  // API Endpoints
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String me = '/api/auth/me';
  static const String fcmToken = '/api/auth/fcm-token';
  static const String fcmTokenRemove = '/api/auth/fcm-token/remove';

  // Tasks
  static const String tasks = '/api/tasks/';
  static const String completeTask = '/api/tasks/complete';
  static const String verifyTask = '/api/tasks/verify';

  // Safety alerts (SOS + safe zone events)
  static const String alerts = '/api/alerts/';
  static const String sos = '/api/alerts/sos';

  // Browsing history
  static const String browsingHistory = '/api/browsing/history';
}
