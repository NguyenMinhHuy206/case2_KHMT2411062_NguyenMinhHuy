part of '../main.dart';

// C7: Read-only progress board for tasks related to the signed-in user.
// Role membership and status counts are computed by authenticated Backend API.
class C7ProgressScreen extends StatefulWidget {
  const C7ProgressScreen({super.key});

  @override
  State<C7ProgressScreen> createState() => _C7ProgressScreenState();
}

class _C7ProgressScreenState extends State<C7ProgressScreen> {
  bool _loading = true;
  String? _error;
  String _scope = 'all';
  Map<String, dynamic> _groups = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await Api.request('GET', '/api/tasks/progress');
      final rawGroups = response['groups'];
      if (rawGroups is! Map) {
        throw Exception('Máy chủ không trả về dữ liệu tiến độ hợp lệ.');
      }
      final groups = Map<String, dynamic>.from(rawGroups);
      for (final role in ['all', 'created', 'assigned', 'shared']) {
        if (groups[role] is! Map) {
          throw Exception('Thiếu dữ liệu tiến độ của nhóm $role.');
        }
      }
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _group(String key) {
    final value = _groups[key];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  int _number(dynamic value) => value is num ? value.toInt() : 0;

  String _scopeTitle(String scope) => switch (scope) {
    'created' => 'Tôi tạo',
    'assigned' => 'Được giao',
    'shared' => 'Được chia sẻ',
    _ => 'Tất cả',
  };

  String _statusTitle(String status) => switch (status) {
    'completed' => 'Đã hoàn thành',
    'in_progress' => 'Đang thực hiện',
    _ => 'Chưa thực hiện',
  };

  String _dateText(dynamic value) {
    final source = value?.toString() ?? '';
    if (source.isEmpty) return 'Chưa đặt hạn';
    final date = DateTime.tryParse(source);
    if (date == null) return 'Chưa đặt hạn';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  Widget _summaryCard(String title, Map<String, dynamic> group) {
    final total = _number(group['total']);
    final completedPercent = _number(group['completionPercent']).clamp(0, 100);
    final counts = group['counts'] is Map
        ? Map<String, dynamic>.from(group['counts'] as Map)
        : <String, dynamic>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('$total công việc liên quan', style: const TextStyle(color: Color(0xFF66748B))),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: completedPercent / 100.0,
              minHeight: 9,
              borderRadius: BorderRadius.circular(10),
              backgroundColor: const Color(0xFFE7ECF5),
            ),
            const SizedBox(height: 9),
            Text('$completedPercent% hoàn thành', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 9, runSpacing: 8, children: [
              Chip(label: Text('Chưa làm: ${_number(counts['pending'])}')),
              Chip(label: Text('Đang làm: ${_number(counts['in_progress'])}')),
              Chip(label: Text('Hoàn thành: ${_number(counts['completed'])}')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final id = (task['id'] ?? '').toString();
    final title = (task['title'] ?? 'Không có tiêu đề').toString();
    final status = (task['status'] ?? 'pending').toString();
    final roles = task['roles'] is Map
        ? Map<String, dynamic>.from(task['roles'] as Map)
        : <String, dynamic>{};
    final tags = <String>[];
    if (roles['created'] == true) tags.add('Tôi tạo');
    if (roles['assigned'] == true) tags.add('Được giao');
    if (roles['primaryAssignee'] == true) tags.add('Phụ trách chính');
    if (roles['shared'] == true) {
      final permission = task['sharePermission'] == 'editor' ? 'Editor' : 'Viewer';
      tags.add('Chia sẻ · $permission');
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: id.isEmpty ? null : () async {
          await Navigator.push<void>(context, MaterialPageRoute(
            builder: (_) => TaskDetailScreen(taskId: id),
          ));
          if (mounted) await _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 5, children: [
                for (final tag in tags) Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(tag, style: const TextStyle(fontSize: 11)),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text(_statusTitle(status),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF3867D6)))),
                const SizedBox(width: 8),
                Text('Hạn: ${_dateText(task['dueDate'])}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF66748B))),
                const Icon(Icons.chevron_right_rounded, size: 19),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = _group(_scope);
    final rawItems = selectedGroup['tasks'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiến độ theo vai trò'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Thử lại')),
                    ],
                  ),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      const Text('Theo dõi công việc theo vai trò',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      const Text('Một công việc có thể thuộc nhiều vai trò; tổng số không đếm trùng.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF66748B))),
                      const SizedBox(height: 14),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final scope in ['all', 'created', 'assigned', 'shared'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('${_scopeTitle(scope)} (${_number(_group(scope)['total'])})'),
                                selected: _scope == scope,
                                onSelected: (_) => setState(() => _scope = scope),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 13),
                      _summaryCard(_scopeTitle(_scope), selectedGroup),
                      const SizedBox(height: 20),
                      Text('Danh sách công việc (${items.length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        const Card(child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Chưa có công việc ở nhóm này'),
                        )),
                      for (final task in items) _taskCard(task),
                    ],
                  ),
                ),
    );
  }
}
