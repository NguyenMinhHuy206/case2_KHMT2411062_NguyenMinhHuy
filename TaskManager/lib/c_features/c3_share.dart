part of '../main.dart';

// C3 - Chia se cong viec theo email.
// Chi nguoi tao cong viec duoc chia se.
// Viewer/Editor duoc cap theo C4; C6 cho phep doi va thu hoi quyen.
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
  String _newPermission = 'viewer';

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
        {'email': email, 'permission': _newPermission},
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

  // C6: Only the task creator may change an existing share.
  Future<void> _changePermission(Map<String, dynamic> share) async {
    if (!_canShare || _saving || _loading) return;
    final shareId = (share['id'] ?? '').toString();
    final current = (share['permission'] ?? 'viewer').toString();
    if (shareId.isEmpty) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Đổi quyền: ${_personName(share)}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'viewer'),
            child: Row(
              children: [
                Icon(current == 'viewer' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                const SizedBox(width: 12),
                const Expanded(child: Text('Viewer - Chỉ xem')),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'editor'),
            child: Row(
              children: [
                Icon(current == 'editor' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                const SizedBox(width: 12),
                const Expanded(child: Text('Editor - Được chỉnh sửa')),
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == current) return;

    setState(() => _saving = true);
    try {
      await Api.request(
        'PATCH',
        '/api/tasks/${widget.taskId}/shares/$shareId',
        {'permission': selected},
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật quyền chia sẻ.')),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // C6: Revoke share with explicit confirmation. Assignment C1 is preserved.
  Future<void> _revokeShare(Map<String, dynamic> share) async {
    if (!_canShare || _saving || _loading) return;
    final shareId = (share['id'] ?? '').toString();
    if (shareId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thu hồi quyền chia sẻ?'),
        content: Text(
          'Bạn muốn thu hồi quyền chia sẻ của ${_personName(share)}? '
          'Nếu tài khoản này còn được giao công việc, quyền được giao vẫn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _saving = true);
    try {
      await Api.request(
        'DELETE',
        '/api/tasks/${widget.taskId}/shares/$shareId',
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã thu hồi quyền chia sẻ.')),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
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
                      DropdownButtonFormField<String>(
                        key: ValueKey('c4_share_permission_$_newPermission'),
                        initialValue: _newPermission,
                        decoration: const InputDecoration(
                          labelText: 'C4 - Quyền truy cập',
                          prefixIcon: Icon(Icons.security_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'viewer',
                            child: Text('Viewer - Chỉ xem'),
                          ),
                          DropdownMenuItem(
                            value: 'editor',
                            child: Text('Editor - Được chỉnh sửa'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _newPermission = value);
                                }
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
                        'Viewer: chỉ xem. Editor: được chỉnh sửa công việc, '
                        'nhưng không được xóa, giao việc hay quản lý chia sẻ.',
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(
                                  (share['permission'] ?? '').toString() == 'editor'
                                      ? 'Editor'
                                      : 'Viewer',
                                ),
                              ),
                              if (_canShare)
                                PopupMenuButton<String>(
                                  tooltip: 'C6 - Quản lý quyền',
                                  enabled: !_saving,
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (action) {
                                    if (action == 'change') {
                                      _changePermission(share);
                                    } else if (action == 'revoke') {
                                      _revokeShare(share);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'change',
                                      child: ListTile(
                                        leading: Icon(Icons.manage_accounts_outlined),
                                        title: Text('Đổi quyền Viewer / Editor'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'revoke',
                                      child: ListTile(
                                        leading: Icon(Icons.person_remove_outlined, color: Colors.red),
                                        title: Text('Thu hồi quyền chia sẻ'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}