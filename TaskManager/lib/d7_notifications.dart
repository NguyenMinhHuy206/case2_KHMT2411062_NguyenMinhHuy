part of 'main.dart';

// D7 – Notification inbox. Read/unread state is stored on the server.
class D7NotificationsScreen extends StatefulWidget {
  const D7NotificationsScreen({super.key});

  @override
  State<D7NotificationsScreen> createState() => _D7NotificationsScreenState();
}

class _D7NotificationsScreenState extends State<D7NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _onlyUnread = false;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await Api.request('GET', '/api/notifications');
      final raw = data['notifications'];
      if (raw is! List) throw Exception('Danh sách thông báo không hợp lệ.');
      final records = raw.whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)).toList();
      if (!mounted) return;
      setState(() { _items = records; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _setRead(Map<String, dynamic> item, bool value) async {
    final id = (item['id'] ?? '').toString();
    if (id.isEmpty || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await Api.request('PATCH', '/api/notifications/$id/read', {'isRead': value});
      if (!mounted) return;
      setState(() => item['isRead'] = value);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _openTask(Map<String, dynamic> item) async {
    final id = (item['taskId'] ?? '').toString();
    if (id.isEmpty) {
      showError(context, 'Thông báo không có mã công việc hợp lệ.');
      return;
    }
    try {
      // Check current rights, including C3 viewer/editor share, before navigation.
      await Api.request('GET', '/api/tasks/${Uri.encodeComponent(id)}');
      if (item['isRead'] != true) {
        await _setRead(item, true);
        if (item['isRead'] != true) return;
      }
      if (!mounted) return;
      await Navigator.push(context,
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)));
      if (mounted) await _load();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  String _when(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return 'Chưa có thời gian';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)} ${two(date.day)}/${two(date.month)}/${date.year}';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'task_assigned': return Icons.assignment_ind_outlined;
      case 'task_shared': return Icons.people_outline;
      case 'task_updated': return Icons.edit_notifications_outlined;
      case 'task_completed': return Icons.task_alt_outlined;
      case 'task_status_changed': return Icons.track_changes_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((item) => item['isRead'] != true).length;
    final visible = _onlyUnread
        ? _items.where((item) => item['isRead'] != true).toList()
        : _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo trong ứng dụng'),
        actions: [
          IconButton(
            tooltip: 'Làm mới thông báo',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Thử lại')),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      Row(children: [
                        Expanded(child: Text(
                          'Tổng ${_items.length} thông báo · $unread chưa đọc',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                        FilterChip(
                          selected: _onlyUnread,
                          label: const Text('Chưa đọc'),
                          onSelected: (selected) => setState(() => _onlyUnread = selected),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      if (visible.isEmpty)
                        const Card(child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Chưa có thông báo trong mục này.')),
                        )),
                      for (final item in visible)
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openTask(item),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 5, right: 12),
                                  child: Icon(
                                    _iconFor((item['type'] ?? '').toString()),
                                    color: item['isRead'] == true
                                        ? const Color(0xFF8895AA)
                                        : const Color(0xFF3867D6),
                                  ),
                                ),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(child: Text(
                                        (item['title'] ?? 'Thông báo').toString(),
                                        style: TextStyle(
                                          fontWeight: item['isRead'] == true
                                              ? FontWeight.w500 : FontWeight.w800,
                                        ),
                                      )),
                                      if (item['isRead'] != true)
                                        const Icon(Icons.circle, size: 9, color: Color(0xFF3867D6)),
                                    ]),
                                    const SizedBox(height: 6),
                                    Text((item['message'] ?? '').toString(),
                                      style: const TextStyle(color: Color(0xFF52617A))),
                                    const SizedBox(height: 9),
                                    Text(_when(item['createdAt']),
                                      style: const TextStyle(color: Color(0xFF8491A5), fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Wrap(spacing: 8, runSpacing: 4, children: [
                                      TextButton.icon(
                                        onPressed: _busy.contains((item['id'] ?? '').toString())
                                            ? null : () => _setRead(item, item['isRead'] == true ? false : true),
                                        icon: Icon(item['isRead'] == true
                                            ? Icons.mark_email_unread_outlined
                                            : Icons.mark_email_read_outlined, size: 18),
                                        label: Text(item['isRead'] == true
                                            ? 'Đánh dấu chưa đọc' : 'Đánh dấu đã đọc'),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _openTask(item),
                                        icon: const Icon(Icons.open_in_new, size: 17),
                                        label: const Text('Mở công việc'),
                                      ),
                                    ]),
                                  ],
                                )),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
