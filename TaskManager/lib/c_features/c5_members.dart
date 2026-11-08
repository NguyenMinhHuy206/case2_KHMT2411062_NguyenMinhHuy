part of '../main.dart';

// C5: Unified, read-only lists of assignees and shared users.
// All data is fetched from the authenticated Backend APIs.
class C5MembersScreen extends StatefulWidget {
  final String taskId;

  const C5MembersScreen({super.key, required this.taskId});

  @override
  State<C5MembersScreen> createState() => _C5MembersScreenState();
}

class _C5MembersScreenState extends State<C5MembersScreen> {
  List<Map<String, dynamic>> _assignees = [];
  List<Map<String, dynamic>> _shares = [];
  String? _primaryAssigneeId;
  String? _error;
  bool _loading = true;

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
      final assignmentData = await Api.request(
        'GET',
        '/api/tasks/${widget.taskId}/assignees',
      );
      final shareData = await Api.request(
        'GET',
        '/api/tasks/${widget.taskId}/shares',
      );

      final assignees = (assignmentData['assignees'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final shares = (shareData['shares'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final primaryId = assignmentData['primaryAssigneeId']?.toString();

      if (!mounted) return;
      setState(() {
        _assignees = assignees;
        _shares = shares;
        _primaryAssigneeId = primaryId;
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

  String _name(Map<String, dynamic> user) {
    final name = (user['name'] ?? '').toString().trim();
    final email = (user['email'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return email.isNotEmpty ? email : 'Tài khoản';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('C5 - Danh sách thành viên'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Làm mới',
          onPressed: _loading ? null : _load,
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(18),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: const Text('Thành viên liên quan'),
                        subtitle: Text(
                          '${_assignees.length} người được giao · '
                          '${_shares.length} người được chia sẻ',
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Người được giao (${_assignees.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_assignees.isEmpty)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Chưa có người được giao'),
                        ),
                      ),
                    for (final user in _assignees)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(_name(user)),
                          subtitle: Text((user['email'] ?? '').toString()),
                          trailing: user['id']?.toString() ==
                                  _primaryAssigneeId
                              ? const Chip(label: Text('Phụ trách chính'))
                              : null,
                        ),
                      ),
                    const SizedBox(height: 22),
                    Text(
                      'Người được chia sẻ (${_shares.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_shares.isEmpty)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Chưa có người được chia sẻ'),
                        ),
                      ),
                    for (final share in _shares)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(_name(share)),
                          subtitle: Text((share['email'] ?? '').toString()),
                          trailing: Chip(
                            label: Text(
                              share['permission'] == 'editor'
                                  ? 'Editor'
                                  : 'Viewer',
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      'Danh sách chỉ để xem. Việc phân công và thay đổi '
                      'quyền được thực hiện ở màn hình quản lý tương ứng.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
  );
}
