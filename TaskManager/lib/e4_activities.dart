part of 'main.dart';

/// E4 - Read-only activity timeline. All authorization is enforced by Backend.
class E4ActivitiesScreen extends StatefulWidget {
  final String taskId;
  final String taskTitle;
  const E4ActivitiesScreen({
    super.key,
    required this.taskId,
    required this.taskTitle,
  });

  @override
  State<E4ActivitiesScreen> createState() => _E4ActivitiesScreenState();
}

class _E4ActivitiesScreenState extends State<E4ActivitiesScreen> {
  static const int _pageSize = 30;
  final List<Map<String, dynamic>> _activities = [];
  bool _loading = false;
  bool _hasMore = false;
  String? _error;
  int _page = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final nextPage = reset ? 1 : _page + 1;
      final data = await Api.request('GET',
        '/api/tasks/${Uri.encodeComponent(widget.taskId)}/activities?page=$nextPage&limit=$_pageSize');
      if (data['activities'] is! List || data['total'] is! int || data['hasMore'] is! bool) {
        throw Exception('Dữ liệu lịch sử không hợp lệ.');
      }
      final items = (data['activities'] as List).whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)).toList();
      if (!mounted) return;
      setState(() {
        if (reset) _activities.clear();
        _activities.addAll(items);
        _page = nextPage;
        _total = data['total'] as int;
        _hasMore = data['hasMore'] as bool;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timestamp(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return 'Chưa rõ thời gian';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  IconData _iconFor(String action) {
    switch (action) {
      case 'created': return Icons.add_circle_outline;
      case 'status_changed': return Icons.sync_alt;
      case 'priority_changed': return Icons.flag_outlined;
      case 'dates_changed': return Icons.event_outlined;
      case 'assignees_changed': return Icons.group_add_outlined;
      case 'primary_changed': return Icons.verified_user_outlined;
      case 'share_added': return Icons.share_outlined;
      case 'share_permission_changed': return Icons.admin_panel_settings_outlined;
      case 'share_revoked': return Icons.person_remove_outlined;
      case 'deleted': return Icons.delete_outline;
      default: return Icons.edit_note_outlined;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('E4 - Lịch sử hoạt động'),
      actions: [
        IconButton(
          tooltip: 'Làm mới lịch sử',
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.taskTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Đã ghi nhận $_total hoạt động', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (_loading && _activities.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton(onPressed: _loading ? null : () => _load(reset: _page == 0),
                  child: const Text('Thử lại')),
              ],
            ))),
          if (!_loading && _error == null && _activities.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(24),
              child: Text('Chưa có hoạt động nào được ghi nhận. Lịch sử bắt đầu từ khi triển khai E4.',
                textAlign: TextAlign.center))),
          for (final activity in _activities)
            Card(child: ListTile(
              leading: CircleAvatar(child: Icon(_iconFor((activity['action'] ?? '').toString()), size: 20)),
              title: Text((activity['summary'] ?? 'Đã cập nhật công việc').toString()),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${(activity['actorName'] ?? 'Không rõ').toString()} · ${_timestamp(activity['createdAt'])}'),
              ),
              isThreeLine: true,
            )),
          if (_hasMore && _error == null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: OutlinedButton.icon(
              onPressed: _loading ? null : () => _load(),
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more),
              label: const Text('Xem thêm hoạt động'),
            )),
        ],
      ),
    ),
  );
}
