part of '../main.dart';

// C1: Assign one or more registered accounts using their exact email.
class C1AssignScreen extends StatefulWidget {
  final String taskId;
  const C1AssignScreen({super.key, required this.taskId});
  @override
  State<C1AssignScreen> createState() => _C1AssignScreenState();
}

class _C1AssignScreenState extends State<C1AssignScreen> {
  final TextEditingController _email = TextEditingController();
  List<Map<String, dynamic>> _selected = [];
  Map<String, dynamic>? _found;
  bool _loading = true;
  bool _searching = false;
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _email.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final data = await Api.request('GET', '/api/tasks/${widget.taskId}/assignees');
      final raw = data['assignees'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        _selected = raw.map((u) => Map<String, dynamic>.from(u as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _searchUser() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) return;
    setState(() { _searching = true; _found = null; });
    try {
      final data = await Api.request('GET',
          '/api/tasks/members/search?email=${Uri.encodeQueryComponent(email)}');
      if (!mounted) return;
      setState(() => _found = Map<String, dynamic>.from(data['user'] as Map));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _add() {
    if (_found == null) return;
    if (_selected.any((u) => u['id'] == _found!['id'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Người này đã được giao công việc.')));
      return;
    }
    setState(() {
      _selected.add(_found!);
      _found = null;
      _email.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.request('PUT', '/api/tasks/${widget.taskId}/assignees', {
        'userIds': _selected.map((u) => u['id'].toString()).toList(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('C1 - Giao việc')),
    body: _loading ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Nhập email tài khoản đã đăng ký để giao công việc.',
        style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 15),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email người nhận',
          prefixIcon: Icon(Icons.email_outlined)),
        onSubmitted: (_) => _searchUser(),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _searching ? null : _searchUser,
        icon: const Icon(Icons.search),
        label: Text(_searching ? 'Đang tìm...' : 'Tìm tài khoản'),
      ),
      if (_found != null) Card(child: ListTile(
        title: Text((_found!['name'] ?? '').toString()),
        subtitle: Text((_found!['email'] ?? '').toString()),
        trailing: IconButton(onPressed: _add, icon: const Icon(Icons.person_add_alt_1),
          tooltip: 'Thêm người được giao'),
      )),
      const SizedBox(height: 18),
      Text('Người được giao (${_selected.length})',
        style: Theme.of(context).textTheme.titleMedium),
      if (_selected.isEmpty) const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text('Chưa có ai được giao.'),
      ),
      for (final user in _selected) Card(child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text((user['name'] ?? '').toString()),
        subtitle: Text((user['email'] ?? '').toString()),
        trailing: IconButton(
          tooltip: 'Bỏ khỏi danh sách giao',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => setState(() => _selected.removeWhere((u) => u['id'] == user['id'])),
        ),
      )),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Đang lưu...' : 'Lưu phân công'),
      ),
      const SizedBox(height: 12),
      const Text('Chỉ người tạo công việc được thay đổi danh sách phân công.',
        style: TextStyle(color: Colors.black54)),
    ]),
  );
}
