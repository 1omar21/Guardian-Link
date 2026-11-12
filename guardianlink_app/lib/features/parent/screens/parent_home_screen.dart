import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../models/task_model.dart';
import '../../../models/user_model.dart';
import 'family_management_screen.dart';
import 'parent_location_screen.dart';
import 'parent_checkins_screen.dart';
import 'parent_alerts_screen.dart';
import 'browsing_history_screen.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  final ApiService _apiService = ApiService();
  List<Task> _tasks = [];
  List<Map<String, dynamic>> _children = [];
  bool _isLoading = true;
  int _activeSos = 0;
  int _recentZoneEvents = 0;
  Timer? _alertsTimer;
  StreamSubscription? _pushSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Keep the SOS banner current even if a push is missed.
    _alertsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadAlerts());
    // Any push (SOS, zone, task update) -> refresh the dashboard.
    _pushSubscription = FCMService().messages.listen((_) => _loadData());
    // App opened by tapping a notification while it was closed.
    WidgetsBinding.instance.addPostFrameCallback((_) => FCMService().consumePendingOpen());
  }

  @override
  void dispose() {
    _alertsTimer?.cancel();
    _pushSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadTasks(),
      _loadChildren(),
      _loadAlerts(),
    ]);
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await _apiService.getTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      print('Load tasks error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadChildren() async {
    try {
      final children = await _apiService.getChildren();
      if (mounted) setState(() => _children = children);
    } catch (e) {
      print('Load children error: $e');
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await _apiService.getAlerts(days: 1);
      if (!mounted) return;
      setState(() {
        _activeSos = (alerts['active_sos_count'] as num?)?.toInt() ?? 0;
        _recentZoneEvents = (alerts['geofence_events'] as List?)?.length ?? 0;
      });
    } catch (e) {
      print('Load alerts error: $e');
    }
  }

  Future<void> _openAlerts() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentAlertsScreen()));
    _loadAlerts();
  }

  void _openBrowsing(Map<String, dynamic> child) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrowsingHistoryScreen(
          childId: child['id'],
          childName: child['full_name'] ?? child['email'],
        ),
      ),
    );
  }

  Future<void> _reviewTask(Task task, bool approve) async {
    String? feedback;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Not approve this task?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('The ${task.rewardCoins} coins (and the sticker) given for "${task.title}" will be taken back.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Not approve'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      feedback = controller.text;
    }
    try {
      await _apiService.verifyTask(task.id, approved: approve, feedback: feedback);
      _loadTasks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? '✅ Task approved' : 'Task not approved - coins taken back'),
          backgroundColor: approve ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
      );
    }
  }

  void _showCreateTaskDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    int rewardCoins = 10;
    String? selectedChildId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Task Title'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // Child Selection Dropdown
                if (_children.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value: selectedChildId,
                    decoration: const InputDecoration(
                      labelText: 'Assign to Child',
                      border: OutlineInputBorder(),
                    ),
                    items: _children.map((child) {
                      return DropdownMenuItem<String>(
                        value: child['id'],
                        child: Text(child['full_name'] ?? child['email']),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedChildId = value);
                    },
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'No children linked. Link a child first!',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Reward Slider
                Row(
                  children: [
                    const Text('Reward: '),
                    Expanded(
                      child: Slider(
                        value: rewardCoins.toDouble(),
                        min: 5,
                        max: 50,
                        divisions: 9,
                        label: '$rewardCoins coins',
                        onChanged: (value) {
                          setDialogState(() => rewardCoins = value.toInt());
                        },
                      ),
                    ),
                    Text('$rewardCoins'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a title')),
                  );
                  return;
                }

                if (_children.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please link a child first')),
                  );
                  return;
                }

                if (selectedChildId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a child')),
                  );
                  return;
                }

                try {
                  await _apiService.createTask(
                    title: titleController.text,
                    description: descController.text,
                    assignedTo: selectedChildId!,
                    rewardCoins: rewardCoins,
                  );
                  Navigator.pop(context);
                  _loadTasks();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Task created successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _apiService.deleteTask(task.id);
        _loadTasks();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Task deleted. Your child will be notified.'),
            backgroundColor: Colors.grey,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatusBadge(String status) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    switch (status.toLowerCase()) {
      case 'pending':
        badgeColor = Colors.orange;
        badgeIcon = Icons.pending;
        badgeText = 'Pending';
        break;
      case 'accepted':
        badgeColor = Colors.blue;
        badgeIcon = Icons.check_circle_outline;
        badgeText = 'Accepted';
        break;
      case 'rejected':
        badgeColor = Colors.red;
        badgeIcon = Icons.cancel;
        badgeText = 'Rejected';
        break;
      case 'scheduled':
        badgeColor = Colors.purple;
        badgeIcon = Icons.schedule;
        badgeText = 'Scheduled';
        break;
      case 'completed':
        badgeColor = Colors.teal;
        badgeIcon = Icons.hourglass_top;
        badgeText = 'To review';
        break;
      case 'verified':
        badgeColor = Colors.green;
        badgeIcon = Icons.verified;
        badgeText = 'Approved';
        break;
      default:
        badgeColor = Colors.grey;
        badgeIcon = Icons.help_outline;
        badgeText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 14, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showChildSelectionDialog(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Child'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _children.map((child) {
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  (child['full_name'] ?? child['email'])
                      .toString()
                      .substring(0, 1)
                      .toUpperCase(),
                  style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                ),
              ),
              title: Text(child['full_name'] ?? child['email']),
              subtitle: Text(child['email'] ?? ''),
              onTap: () {
                Navigator.pop(context);
                if (feature == 'browsing') {
                  _openBrowsing(child);
                } else if (feature == 'check-ins') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ParentCheckInsScreen(
                        childId: child['id'],
                        childName: child['full_name'] ?? child['email'],
                      ),
                    ),
                  );
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        backgroundColor: Colors.purple,
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme();
            },
          ),
          IconButton(
            icon: const Icon(Icons.family_restroom),
            tooltip: 'Manage Family',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FamilyManagementScreen(),
                ),
              );
              _loadChildren(); // Reload children after returning
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await authProvider.logout();
                if (mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                    (route) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome Card
                    Card(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Theme.of(context).colorScheme.tertiary,
                              child: Text(
                                user?.fullName[0].toUpperCase() ?? 'P',
                                style: TextStyle(
                                  fontSize: 24,
                                  color: Theme.of(context).colorScheme.onTertiary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome, ${user?.fullName ?? "Parent"}!',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_children.length} ${_children.length == 1 ? "child" : "children"} linked',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onTertiaryContainer.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Safety alerts banner
                    Card(
                      color: _activeSos > 0 ? Colors.red : Theme.of(context).colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: Icon(
                          _activeSos > 0 ? Icons.sos : Icons.notifications_active,
                          color: _activeSos > 0 ? Colors.white : null,
                          size: 32,
                        ),
                        title: Text(
                          _activeSos > 0
                              ? '$_activeSos active SOS ${_activeSos == 1 ? "alert" : "alerts"}!'
                              : 'Safety alerts',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _activeSos > 0 ? Colors.white : null,
                          ),
                        ),
                        subtitle: Text(
                          _activeSos > 0
                              ? 'Tap to see where and mark as handled'
                              : '$_recentZoneEvents safe zone ${_recentZoneEvents == 1 ? "event" : "events"} in the last 24 hours',
                          style: TextStyle(color: _activeSos > 0 ? Colors.white70 : null),
                        ),
                        trailing: Icon(Icons.chevron_right, color: _activeSos > 0 ? Colors.white : null),
                        onTap: _openAlerts,
                      ),
                    ),
                    const SizedBox(height: 24),

                  // Children List with Location Access
                  if (_children.isNotEmpty) ...[
                    const Text(
                      'My Children',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._children.map((child) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple,
                            child: Text(
                              (child['full_name'] ?? child['email'])
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            child['full_name'] ?? child['email'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(child['email'] ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Browsing history',
                                icon: const Icon(Icons.public),
                                onPressed: () => _openBrowsing(child),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ParentLocationScreen(
                                        childId: child['id'],
                                        childName: child['full_name'] ?? child['email'],
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.map, size: 18),
                                label: const Text('Map'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 24),

                    // Monitoring Features Section
                    if (_children.isNotEmpty) ...[ 
                      Text(
                        'Monitoring',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Card(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              child: InkWell(
                                onTap: () {
                                  if (_children.length == 1) {
                                    // If only one child, go directly to their check-ins
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ParentCheckInsScreen(
                                          childId: _children[0]['id'],
                                          childName: _children[0]['full_name'] ?? _children[0]['email'],
                                        ),
                                      ),
                                    );
                                  } else {
                                    // Show child selection dialog
                                    _showChildSelectionDialog('check-ins');
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 32,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Check-ins',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Card(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              child: InkWell(
                                onTap: () {
                                  if (_children.length == 1) {
                                    _openBrowsing(_children[0]);
                                  } else {
                                    _showChildSelectionDialog('browsing');
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Icon(Icons.public, size: 32, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Web history',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],

                  // Quick Actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showCreateTaskDialog,
                            icon: const Icon(Icons.add_task),
                            label: const Text('Create Task'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const FamilyManagementScreen(),
                                ),
                              ).then((_) => _loadChildren());
                            },
                            icon: const Icon(Icons.family_restroom),
                            label: const Text('Manage Family'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Tasks Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tasks',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_tasks.length} total',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _tasks.where((t) => t.status != 'deleted').isEmpty
                        ? Card(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.task_alt,
                                      size: 64,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No tasks yet',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Create a task to get started!',
                                      style: TextStyle(color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _tasks.where((t) => t.status != 'deleted').length,
                             itemBuilder: (context, index) {
                              final activeTasks = _tasks.where((t) => t.status != 'deleted').toList();
                              final task = activeTasks[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: task.isCompleted
                                        ? Colors.green
                                        : task.status == 'rejected'
                                            ? Colors.red
                                            : task.status == 'accepted'
                                                ? Colors.blue
                                                : Colors.orange,
                                    child: Icon(
                                      task.isCompleted
                                          ? Icons.check
                                          : task.status == 'rejected'
                                              ? Icons.close
                                              : task.status == 'accepted'
                                                  ? Icons.thumb_up
                                                  : Icons.pending,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          task.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      _buildStatusBadge(task.status),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(task.description),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.stars, size: 16, color: Colors.amber),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${task.rewardCoins} coins',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (task.status == 'rejected' && task.rejectedBy != null)
                                        Text(
                                          task.rejectedBy == 'child' ? 'Rejected by your child' : 'Not approved by you',
                                          style: const TextStyle(fontSize: 12, color: Colors.red),
                                        ),
                                      if (task.status == 'completed')
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Wrap(
                                            spacing: 8,
                                            children: [
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  foregroundColor: Colors.white,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                onPressed: () => _reviewTask(task, true),
                                                icon: const Icon(Icons.thumb_up, size: 16),
                                                label: const Text('Approve'),
                                              ),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.red,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                onPressed: () => _reviewTask(task, false),
                                                icon: const Icon(Icons.thumb_down, size: 16),
                                                label: const Text('Not done'),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.grey),
                                    onPressed: () => _deleteTask(task),
                                    tooltip: 'Delete task',
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateTaskDialog,
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }
}
