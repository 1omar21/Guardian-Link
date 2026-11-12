import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../models/task_model.dart';
import '../../../models/user_model.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/location_tracker.dart';
import '../../../core/services/native_bridge.dart';
import 'invitations_screen.dart';
import 'child_location_screen.dart';
import 'sticker_gallery_screen.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final LocationTracker _tracker = LocationTracker();
  List<Task> _tasks = [];
  bool _isLoading = true;
  int _focusCoins = 0;
  bool _coinsInitialized = false;
  bool _browsingMonitorOn = false;
  bool _sendingSos = false;
  StreamSubscription? _pushSubscription;

  @override
  void initState() {
    super.initState();
    // Initialize coins from current provider state immediately if available
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser != null) {
      _focusCoins = authProvider.currentUser!.focusCoins;
      _coinsInitialized = true;
    }
    
    _loadTasksAndCoins();

    WidgetsBinding.instance.addObserver(this);
    _tracker.addListener(_onTrackerChanged);
    _startLocationSharing();
    _checkBrowsingMonitor();
    // Task updates / SOS answered by the parent -> refresh.
    _pushSubscription = FCMService().messages.listen((_) => _loadTasksAndCoins());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tracker.removeListener(_onTrackerChanged);
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Settings (accessibility / location permission).
    if (state == AppLifecycleState.resumed) {
      _checkBrowsingMonitor();
      _startLocationSharing();
    }
  }

  void _onTrackerChanged() {
    if (mounted) setState(() {});
  }

  /// Location sharing starts automatically once permission is granted
  /// (asked on the "My Location" screen with an explanation).
  Future<void> _startLocationSharing() async {
    await _tracker.start();
  }

  Future<void> _checkBrowsingMonitor() async {
    final on = await NativeBridge.isBrowsingMonitorEnabled();
    if (on) NativeBridge.flushBrowsingHistory();
    if (mounted) setState(() => _browsingMonitorOn = on);
  }

  Future<void> _explainBrowsingMonitor() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Turn on browsing monitor'),
        content: const Text(
          'Your parent can see the addresses of websites you open in your web browser '
          '(Chrome, Firefox, Edge, Samsung Internet and others). Other apps and anything you type are not read.\n\n'
          'On the next screen open "Installed apps" (or "Downloaded apps"), tap "GuardianLink browsing monitor" '
          'and switch it on.\n\n'
          'If the switch is greyed out: open Settings > Apps > GuardianLink, tap the ⋮ menu and choose '
          '"Allow restricted settings", then try again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Open settings')),
        ],
      ),
    );
    if (go == true) await NativeBridge.openAccessibilitySettings();
  }

  // ------------------------------------------------------------------ //
  // SOS
  // ------------------------------------------------------------------ //
  Future<void> _sendSOS() async {
    if (_sendingSos) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.sos, color: Colors.red, size: 48),
        title: const Text('Send SOS?'),
        content: const Text('Your parent will get an emergency alert with your location right away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _sendingSos = true);
    try {
      // Best effort location: fresh fix (10 s max), else the last known one,
      // else the backend uses the last location it has.
      Position? position;
      try {
        position = await LocationService().getCurrentLocation().timeout(const Duration(seconds: 10));
      } catch (_) {}
      if (position == null) {
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      final result = await _apiService.triggerSOS(
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracy: position?.accuracy,
      );
      if (!mounted) return;
      final notified = result['parent_notified'] == true;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(notified ? Icons.check_circle : Icons.warning_amber,
              color: notified ? Colors.green : Colors.orange, size: 48),
          title: Text(notified ? 'SOS sent' : 'SOS saved'),
          content: Text(
            notified
                ? 'Your parent has been alerted${result['location_included'] == true ? ' with your location' : ''}. Stay where you are if it is safe.'
                : "Your SOS was saved, but your parent's phone could not be reached right now. "
                    'If you can, call your parent or an emergency number.',
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.error, color: Colors.red, size: 48),
          title: const Text('SOS could not be sent'),
          content: Text(
            '${e.toString().replaceFirst('Exception: ', '')}\n\n'
            'Check your internet connection and try again, or call your parent or an emergency number.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _sendSOS();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingSos = false);
    }
  }

  // New method: Fetch coins directly from API (Single Source of Truth)
  Future<void> _refreshCoins() async {
    if (!mounted) return;
    try {
      final user = await _apiService.getCurrentUser();
      if (mounted) {
        setState(() {
          _focusCoins = user.focusCoins;
          _coinsInitialized = true;
        });
      }
    } catch (e) {
      // Silent error
    }
  }

  Future<void> _loadTasksAndCoins() async {
    try {
      // Load tasks and fresh user data in parallel
      final results = await Future.wait([
        _apiService.getTasks(),
        _apiService.getCurrentUser(),
      ]);
      
      if (!mounted) return;

      final tasks = results[0] as List<Task>;
      final user = results[1] as User;
      
      setState(() {
        _tasks = tasks;
        _focusCoins = user.focusCoins; // Set coins directly from API load
        _coinsInitialized = true;
        _isLoading = false;
      });
      
      print('✅ Inital load complete. Coins: $_focusCoins');
      
      // Update AuthProvider with fresh user data (including new stickers)
      if (mounted) {
        Provider.of<AuthProvider>(context, listen: false).updateUser(user);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showTaskActionDialog(Task task) async {
    // Check if task can be completed
    final canComplete = task.status != 'rejected' && task.status != 'completed';
    
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.description),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.stars, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'Reward: ${task.rewardCoins} coins',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            if (task.status == 'rejected') ...[ 
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.rejectedBy == 'parent'
                            ? 'Your parent did not approve this task${task.feedback != null && task.feedback!.isNotEmpty ? ': ${task.feedback}' : ''}'
                            : 'You rejected this task',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, 'delete'),
            icon: const Icon(Icons.delete, color: Colors.grey),
            label: const Text('Delete', style: TextStyle(color: Colors.grey)),
          ),
          if (task.status != 'rejected') ...[
            TextButton.icon(
              onPressed: () => Navigator.pop(context, 'reject'),
              icon: const Icon(Icons.close, color: Colors.red),
              label: const Text('Reject', style: TextStyle(color: Colors.red)),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, 'later'),
              icon: const Icon(Icons.schedule, color: Colors.orange),
              label: const Text('Later', style: TextStyle(color: Colors.orange)),
            ),
          ],
          if (canComplete)
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'complete'),
              icon: const Icon(Icons.check),
              label: const Text('Complete'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
        ],
      ),
    );

    if (action == null) return;

    if (action == 'complete') {
      if (!canComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot complete a rejected task'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await _completeTask(task);
    } else if (action == 'later') {
      await _scheduleTaskLater(task);
    } else if (action == 'reject') {
      await _rejectTask(task);
    } else if (action == 'delete') {
      await _deleteTask(task);
    }
  }

  Future<void> _completeTask(Task task) async {
    try {
      final response = await _apiService.completeTask(task.id);
      
      // Get new coin total from response if available
      final coinsAwarded = response['coins_awarded'] ?? task.rewardCoins;
      final newTotal = response['new_coin_total'];
      
      if (newTotal != null) {
        setState(() {
          _focusCoins = newTotal;
        });
      }
      
      // Refresh tasks list and coins to ensure sync
      _loadTasksAndCoins();
      
      // Show success message with sticker if awarded
      if (mounted) {
        final stickerAwarded = response['sticker_awarded'];
        String message = '🎉 Task completed! +$coinsAwarded coins (your parent will check it)';
        if (stickerAwarded != null) {
          message += '\n$stickerAwarded Sticker earned!';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Refresh both tasks and coins to keep UI in sync even on error
      _loadTasksAndCoins();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete task. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _scheduleTaskLater(Task task) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null && mounted) {
      try {
        // Call API to schedule task
        final now = DateTime.now();
        final scheduledTime = DateTime(
          now.year, now.month, now.day,
          time.hour, time.minute
        );
        
        print('🔄 Scheduling task ${task.id} for $scheduledTime');
        await _apiService.scheduleTask(task.id, scheduledTime);
        print('✅ Task scheduled successfully');
        
        _loadTasksAndCoins(); // Refresh tasks
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏰ Task scheduled for ${time.format(context)}'),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        print('❌ Schedule task error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to schedule task: ${e.toString().contains('Exception:') ? e.toString().split('Exception:')[1].trim() : e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _rejectTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Task'),
        content: const Text('Are you sure you want to reject this task? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        print('🔄 Rejecting task: ${task.id}');
        await _apiService.rejectTask(task.id);
        print('✅ Task rejected successfully');
        
        _loadTasksAndCoins(); // Refresh tasks
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Task rejected. Your parent will be notified.'),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        print('❌ Reject task error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject task: ${e.toString().contains('Exception:') ? e.toString().split('Exception:')[1].trim() : e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task? This cannot be undone.'),
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
        print('🔄 Deleting task: ${task.id}');
        await _apiService.deleteTask(task.id);
        print('✅ Task deleted successfully');
        
        _loadTasksAndCoins(); // Refresh tasks
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Task deleted. Your parent will be notified.'),
            backgroundColor: Colors.grey,
          ),
        );
      } catch (e) {
        print('❌ Delete task error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete task: ${e.toString().contains('Exception:') ? e.toString().split('Exception:')[1].trim() : e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dashboard'),
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
            icon: const Icon(Icons.mail),
            tooltip: 'Family Invitations',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InvitationsScreen(),
                ),
              );
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
                await context.read<AuthProvider>().logout();
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
              onRefresh: _loadTasksAndCoins,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Welcome Card with Coins
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade400, Colors.purple.shade700],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Hi, ${user?.fullName ?? "there"}!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.stars,
                              color: Colors.amber,
                              size: 32,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$_focusCoins',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Focus Coins',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // SOS button
                  SizedBox(
                    height: 72,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _sendingSos ? null : _sendSOS,
                      icon: _sendingSos
                          ? const SizedBox(
                              width: 28, height: 28,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                          : const Icon(Icons.sos, size: 36),
                      label: Text(_sendingSos ? 'Sending...' : 'SOS - I need help'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location sharing + browsing monitor status
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            _tracker.isTracking ? Icons.share_location : Icons.location_disabled,
                            color: _tracker.isTracking ? Colors.green : Colors.orange,
                          ),
                          title: Text(_tracker.isTracking ? 'Sharing location with your parent' : 'Location sharing is off'),
                          subtitle: Text(
                            _tracker.isTracking
                                ? (_tracker.lastUploadAt != null
                                    ? 'Last sent ${_formatAgo(_tracker.lastUploadAt!)}'
                                    : 'Waiting for GPS...')
                                : (_tracker.lastError ?? 'Open "My Location" to allow location'),
                          ),
                          onTap: _tracker.isTracking
                              ? null
                              : () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const ChildLocationScreen()),
                                  );
                                  _startLocationSharing();
                                },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            _browsingMonitorOn ? Icons.public : Icons.public_off,
                            color: _browsingMonitorOn ? Colors.green : Colors.orange,
                          ),
                          title: Text(_browsingMonitorOn ? 'Browsing monitor is on' : 'Browsing monitor is off'),
                          subtitle: Text(_browsingMonitorOn
                              ? 'Websites you open in browsers are shared with your parent'
                              : 'Tap to turn it on'),
                          onTap: _browsingMonitorOn ? null : _explainBrowsingMonitor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quick Actions
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.location_on,
                          title: 'My Location',
                          color: Colors.green,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChildLocationScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.star,
                          title: 'My Stickers',
                          color: Colors.purple,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const StickerGalleryScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Tasks Section
                  Text(
                    'My Tasks',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),

                  if (_tasks.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No tasks yet!'),
                      ),
                    )
                  else
                    // Active tasks (pending, accepted, scheduled) - exclude deleted
                    ..._tasks.where((t) => !t.isCompleted && t.status != 'rejected' && t.status != 'deleted').map((task) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Checkbox(
                              value: false,
                              onChanged: (_) => _showTaskActionDialog(task),
                            ),
                            title: Text(task.title),
                            subtitle: Text(task.description),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.stars,
                                    size: 16,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${task.rewardCoins}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )),

                  // Rejected Tasks - exclude deleted
                  if (_tasks.any((t) => t.status == 'rejected' && t.status != 'deleted')) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Rejected',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.red,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ..._tasks.where((t) => t.status == 'rejected' && t.status != 'deleted').map((task) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: Colors.red.shade50,
                          child: ListTile(
                            leading: const Icon(
                              Icons.cancel,
                              color: Colors.red,
                            ),
                            title: Text(
                              task.title,
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey,
                              ),
                            ),
                            subtitle: Text(
                              task.description,
                              style: const TextStyle(color: Colors.grey),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.grey),
                              onPressed: () => _deleteTask(task),
                              tooltip: 'Delete task',
                            ),
                          ),
                        )),
                  ],

                  // Completed Tasks - exclude deleted
                  if (_tasks.any((t) => t.isCompleted && t.status != 'deleted')) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Completed',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.green,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ..._tasks.where((t) => t.isCompleted && t.status != 'deleted').map((task) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: Colors.grey.shade100,
                          child: ListTile(
                            leading: const Icon(
                              Icons.check_circle,
                            ),
                            title: Text(
                              task.title,
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            subtitle: Text(
                              task.status == 'verified' ? 'Approved by your parent' : 'Waiting for your parent to check',
                              style: TextStyle(
                                fontSize: 12,
                                color: task.status == 'verified' ? Colors.green : Colors.grey,
                              ),
                            ),
                            trailing: Text(
                              '+${task.rewardCoins}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )),
                  ],
                ],
              ),
            ),
    );
  }
}

String _formatAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  return '${diff.inHours} h ago';
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
