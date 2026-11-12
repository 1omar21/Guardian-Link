import 'package:intl/intl.dart';

/// "Just now", "5m ago", "3h ago", "2d ago" for an ISO-8601 string or DateTime.
String timeAgo(dynamic timestamp) {
  final time = parseTime(timestamp);
  if (time == null) return 'Unknown';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// "12 Nov, 14:05" in local time.
String formatDateTime(dynamic timestamp) {
  final time = parseTime(timestamp);
  if (time == null) return 'Unknown';
  return DateFormat('d MMM, HH:mm').format(time.toLocal());
}

DateTime? parseTime(dynamic timestamp) {
  if (timestamp == null) return null;
  if (timestamp is DateTime) return timestamp;
  return DateTime.tryParse(timestamp.toString());
}

double? toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
