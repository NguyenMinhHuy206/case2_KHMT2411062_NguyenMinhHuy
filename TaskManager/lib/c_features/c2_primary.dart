part of '../main.dart';

// C2: A task creator chooses one primary assignee from the C1 assignees.
// Other assigned users can view the selection but cannot modify it.
class C2PrimaryScreen extends StatefulWidget {
  final String taskId;
  final bool canManage;

  const C2PrimaryScreen({
    super.key,
    required this.taskId,
    required this.canManage,
  });

  @override
  State<C2PrimaryScreen> createState() => _C2PrimaryScreenState();
}

class _C2PrimaryScreenState extends State<C2PrimaryScreen> {
  List<Map<String, dynamic>> _assignees = [];
  String? _primaryUserId;
  String? _savedPrimaryUserId;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Api.request(
        'GET', '/api/tasks/${widget.taskId}/assignees',
      );
      final raw = data['assignees'] as List? ?? [];
      final users = raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final primary = data['primaryAssigneeId']?.toString();
      if (!mounted) return;
      setState(() {
        _assignees = users;
        // In case an assignee was removed by C1, do not show a stale primary.
        _primaryUserId = users.any((user) => user['id'].toString() == primary)
            ? primary
            : null;
        _savedPrimaryUserId = _primaryUserId;
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

  String _memberName(Map<String, dynamic> user) {
    final name = (user['name'] ?? '').toString().trim();
    return name.isEmpty ? (user['email'] ?? 'Tài khoản').toString() : name;
  }

  Future<void> _save() async {
    if (!widget.canManage || _saving || _primaryUserId == _savedPrimaryUserId) {
      return;
    }
    if (_primaryUserId != null &&
        !_assignees.any((user) => user['id'].toString() == _primaryUserId)) {
      showError(context, 'Người phụ trách chính phải thuộc danh sách được giao.');
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await Api.request(
        'PATCH',
        '/api/tasks/${widget.taskId}/primary-assignee',
        {'userId': _primaryUserId},
      );
      final task = result['task'];
      if (task is! Map ||
          task['primaryAssigneeId']?.toString() != _primaryUserId) {
        throw Exception('Máy chủ chưa xác nhận người phụ trách chính.');
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _assignees.where(
      (user) => user['id'].toString() == _savedPrimaryUserId,
    );
    final currentName = current.isEmpty
        ? 'Chưa chỉ định'
        : _memberName(current.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('C2 - Người phụ trách chính'),
        actions: [
          IconButton(
            onPressed: (_loading || _saving) ? null : _load,
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Thử lại'),
                      ),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text('Người phụ trách chính hiện tại'),
                        subtitle: Text(currentName),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.canManage
                          ? 'Chọn một người trong danh sách được giao ở C1.'
                          : 'Bạn có thể xem người phụ trách chính của công việc.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Người được giao (${_assignees.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_assignees.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'Chưa có người được giao. Người tạo cần giao việc ở C1 trước.',
                        ),
                      ),
                    for (final user in _assignees)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            user['id'].toString() == _primaryUserId
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(_memberName(user)),
                          subtitle: Text((user['email'] ?? '').toString()),
                          trailing: user['id'].toString() == _primaryUserId
                              ? const Icon(Icons.star_rounded,
                                  color: Color(0xFF3867D6))
                              : null,
                          onTap: (!widget.canManage || _saving)
                              ? null
                              : () => setState(() =>
                                  _primaryUserId = user['id'].toString()),
                        ),
                      ),
                    if (widget.canManage) ...[
                      const SizedBox(height: 10),
                      Card(
                        child: ListTile(
                          leading: Icon(
                            _primaryUserId == null
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: const Text('Không chỉ định người phụ trách chính'),
                          onTap: _saving
                              ? null
                              : () => setState(() => _primaryUserId = null),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: (_saving ||
                                _primaryUserId == _savedPrimaryUserId)
                            ? null
                            : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving
                            ? 'Đang lưu...'
                            : 'Lưu người phụ trách chính'),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Chỉ người tạo công việc được thay đổi người phụ trách chính.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Bạn không có quyền thay đổi người phụ trách chính.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ],
                ),
    );
  }
}
