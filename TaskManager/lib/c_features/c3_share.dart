part of '../main.dart';

// C3 - Chia se cong viec theo email.
// Chi nguoi tao cong viec duoc chia se.
// Nguoi nhan duoc cap quyen viewer.
class C3ShareScreen extends StatefulWidget {
  final String taskId;
  final bool canManage;

  const C3ShareScreen({
    super.key,
    required this.taskId,
    required this.canManage,
  });

  @override
  State<C3ShareScreen> createState() => _C3ShareScreenState();
}

class _C3ShareScreenState extends State<C3ShareScreen> {
  final TextEditingController _email = TextEditingController();

  List<Map<String, dynamic>> _shares = [];
  bool _loading = true;
  bool _saving = false;
  bool _canManageFromServer = false;
  String? _error;

  bool get _canShare =>
      widget.canManage && _canManageFromServer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await Api.request(
        'GET',
        '/api/tasks/${widget.taskId}/shares',
      );

      final raw = data['shares'] as List? ?? [];

      final shares = raw
          .whereType<Map>()
          .map((item) =>
              Map<String, dynamic>.from(item))
          .toList();

      if (!mounted) return;

      setState(() {
        _shares = shares;
        _canManageFromServer =
            data['canManage'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString()
            .replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _share() async {
    if (!_canShare || _saving || _loading) return;

    final email = _email.text.trim().toLowerCase();

    final emailRegex =
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (email.isEmpty ||
        email.length > 254 ||
        !emailRegex.hasMatch(email)) {
      showError(
        context,
        'Vui lòng nhập địa chỉ email hợp lệ.',
      );
      return;
    }

    final alreadyShared = _shares.any(
      (item) =>
          (item['email'] ?? '')
              .toString()
              .toLowerCase() == email,
    );

    if (alreadyShared) {
      showError(
        context,
        'Công việc đã được chia sẻ cho tài khoản này.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await Api.request(
        'POST',
        '/api/tasks/${widget.taskId}/shares',
        {'email': email},
      );

      if (!mounted) return;

      _email.clear();

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chia sẻ công việc thành công.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _personName(Map<String, dynamic> share) {
    final name =
        (share['name'] ?? '').toString().trim();

    if (name.isNotEmpty) return name;

    return (share['email'] ?? 'Tài khoản')
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('C3 - Chia sẻ công việc'),
        actions: [
          IconButton(
            onPressed:
                (_loading || _saving) ? null : _load,
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.people_outline,
                        ),
                        title: const Text(
                          'Danh sách người được chia sẻ',
                        ),
                        subtitle: Text(
                          '${_shares.length} tài khoản',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_canShare) ...[
                      Text(
                        'Chia sẻ theo email',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _email,
                        keyboardType:
                            TextInputType.emailAddress,
                        textInputAction:
                            TextInputAction.done,
                        enabled: !_saving,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email người nhận',
                          hintText:
                              'nguoidung@example.com',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.alternate_email,
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_saving) _share();
                        },
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _share,
                        icon: const Icon(
                          Icons.person_add_alt_1_outlined,
                        ),
                        label: Text(
                          _saving
                              ? 'Đang chia sẻ...'
                              : 'Chia sẻ công việc',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'C3 chỉ cấp quyền xem (viewer). '
                        'Quyền chỉnh sửa sẽ được triển khai ở C4.',
                      ),
                      const SizedBox(height: 22),
                    ] else ...[
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text(
                            'Chỉ người tạo công việc được chia sẻ',
                          ),
                          subtitle: Text(
                            'Bạn có thể xem danh sách, '
                            'nhưng không được thêm người nhận.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'Người nhận chia sẻ (${_shares.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_shares.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 18,
                        ),
                        child: Text(
                          'Công việc này chưa được chia sẻ cho ai.',
                        ),
                      ),
                    for (final share in _shares)
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.person_outline,
                          ),
                          title: Text(
                            _personName(share),
                          ),
                          subtitle: Text(
                            (share['email'] ?? '')
                                .toString(),
                          ),
                          trailing: const Chip(
                            label: Text('Viewer'),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}