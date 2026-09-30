import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import 'package:intl/intl.dart';

class ParentCheckInsScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ParentCheckInsScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ParentCheckInsScreen> createState() => _ParentCheckInsScreenState();
}

class _ParentCheckInsScreenState extends State<ParentCheckInsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _checkIns = [];
  bool _isLoading = true;
  int _selectedDays = 7;

  @override
  void initState() {
    super.initState();
    _loadCheckIns();
  }

  Future<void> _loadCheckIns() async {
    setState(() => _isLoading = true);
    try {
      final checkIns = await _apiService.getChildCheckIns(
        widget.childId,
        days: _selectedDays,
      );
      setState(() {
        _checkIns = checkIns;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading check-ins: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dt);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('MMM d, h:mm a').format(dt);
      }
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Check-ins'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _selectedDays,
            onSelected: (days) {
              setState(() => _selectedDays = days);
              _loadCheckIns();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 1, child: Text('Last 24 hours')),
              const PopupMenuItem(value: 7, child: Text('Last 7 days')),
              const PopupMenuItem(value: 30, child: Text('Last 30 days')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Text(
                    _selectedDays == 1
                        ? '24h'
                        : _selectedDays == 7
                            ? '7d'
                            : '30d',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCheckIns,
              child: _checkIns.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No check-ins yet',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check-ins will appear here when ${widget.childName} sends them',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _checkIns.length,
                      itemBuilder: (context, index) {
                        final checkIn = _checkIns[index];
                        final message = checkIn['message'] ?? 'Safe check-in';
                        final timestamp = checkIn['timestamp'] ?? checkIn['created_at'] ?? '';
                        final latitude = checkIn['latitude'];
                        final longitude = checkIn['longitude'];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            title: Text(
                              message,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatTimestamp(timestamp),
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                                if (latitude != null && longitude != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 14,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
