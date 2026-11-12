import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/utils/time_format.dart';

/// Websites the child opened in a web browser (browsers only).
class BrowsingHistoryScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const BrowsingHistoryScreen({super.key, required this.childId, required this.childName});

  @override
  State<BrowsingHistoryScreen> createState() => _BrowsingHistoryScreenState();
}

class _BrowsingHistoryScreenState extends State<BrowsingHistoryScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _visits = [];
  bool _loading = true;
  String? _error;
  int _days = 7;
  String _filter = '';

  static const _browserNames = {
    'com.android.chrome': 'Chrome',
    'com.chrome.beta': 'Chrome Beta',
    'com.microsoft.emmx': 'Edge',
    'com.brave.browser': 'Brave',
    'com.kiwibrowser.browser': 'Kiwi',
    'com.vivaldi.browser': 'Vivaldi',
    'com.opera.browser': 'Opera',
    'com.opera.mini.native': 'Opera Mini',
    'org.mozilla.firefox': 'Firefox',
    'com.sec.android.app.sbrowser': 'Samsung Internet',
    'com.duckduckgo.mobile.android': 'DuckDuckGo',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final visits = await _api.getBrowsingHistory(widget.childId, days: _days);
      if (!mounted) return;
      setState(() {
        _visits = visits;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _domain(String url) {
    final withScheme = url.contains('://') ? url : 'https://$url';
    final host = Uri.tryParse(withScheme)?.host ?? '';
    return host.isEmpty ? url : host.replaceFirst(RegExp(r'^www\.'), '');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? _visits
        : _visits.where((v) => (v['url'] ?? '').toString().toLowerCase().contains(_filter.toLowerCase())).toList();

    // Top sites summary
    final counts = <String, int>{};
    for (final v in _visits) {
      final d = _domain((v['url'] ?? '').toString());
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final topSites = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.childName}'s Browsing"),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.filter_list),
            initialValue: _days,
            onSelected: (d) {
              setState(() => _days = d);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('Last 24 hours')),
              PopupMenuItem(value: 7, child: Text('Last 7 days')),
              PopupMenuItem(value: 30, child: Text('Last 30 days')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Only websites opened in web browsers are recorded. '
                        "Your child must switch on \"GuardianLink browsing monitor\" in the phone's "
                        'Accessibility settings. They can see this in their app.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: ListTile(leading: const Icon(Icons.error_outline, color: Colors.red), title: Text(_error!)),
                    ),
                  if (topSites.isNotEmpty) ...[
                    const Text('Most visited', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: topSites
                          .take(8)
                          .map((e) => Chip(label: Text('${e.key} (${e.value})')))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search addresses',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _filter = v.trim()),
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          _visits.isEmpty ? 'No browsing history yet' : 'No matches',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ...filtered.map((v) {
                    final url = (v['url'] ?? '').toString();
                    final browser = _browserNames[v['browser']] ?? (v['browser'] ?? 'Browser').toString();
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.public),
                        title: Text(_domain(url), style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$url\n$browser · ${formatDateTime(v['timestamp'])}',
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
