part of 'main.dart';

/// E3 – Cong viec sap den han va da qua han.
/// Today's date and classification come from the authenticated backend.
class E3DeadlinesSection extends StatefulWidget {
  const E3DeadlinesSection({super.key});

  @override
  State<E3DeadlinesSection> createState() => _E3DeadlinesSectionState();
}

class _E3DeadlinesSectionState extends State<E3DeadlinesSection> {
  bool _loading = true;
  String? _error;
  String _today = '';
  int _windowDays = 7;
  List<Map<String, dynamic>> _soon = const [];
  List<Map<String, dynamic>> _overdue = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _decodeTasks(dynamic raw, String key) {
    if (raw is! List) throw Exception('Danh sách $key không hợp lệ.');
    final values = <Map<String, dynamic>>[];
    for (final entry in raw) {
      if (entry is! Map) throw Exception('Công việc trong $key không hợp lệ.');
      final item = Map<String, dynamic>.from(entry);
      if (item['id'] is! String || (item['id'] as String).isEmpty ||
          item['title'] is! String || item['dueDate'] is! String ||
          item['daysRemaining'] is! int) {
        throw Exception('Thông tin thời hạn của công việc không hợp lệ.');
      }
      values.add(item);
    }
    return values;
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await Api.request('GET', '/api/statistics/deadlines');
      final soon = _decodeTasks(data['soon'], 'sắp hạn');
      final overdue = _decodeTasks(data['overdue'], 'quá hạn');
      if (data['today'] is! String || data['windowDays'] is! int ||
          data['soonCount'] is! int || data['overdueCount'] is! int ||
          data['soonCount'] != soon.length || data['overdueCount'] != overdue.length) {
        throw Exception('Số liệu công việc theo thời hạn không hợp lệ.');
      }
      if (!mounted) return;
      setState(() {
        _today = data['today'] as String;
        _windowDays = data['windowDays'] as int;
        _soon = soon;
        _overdue = overdue;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dateLabel(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(date.day)}/${pad(date.month)}/${date.year}';
  }

  Widget _summaryCard(String label, int count, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border.all(color: color.withValues(alpha: 0.17)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 10),
        Text('$count', style: TextStyle(fontSize: 27,
          fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w700)),
      ]),
    ));
  }

  Widget _taskList(String heading, List<Map<String, dynamic>> tasks,
      Color color, bool isOverdue) {
    return Card(child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(heading, style: TextStyle(fontSize: 14,
          fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Text('Không có công việc trong nhóm này.',
              style: TextStyle(color: Color(0xFF718096), fontSize: 12)),
          )
        else
          for (final task in tasks) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TaskDetailScreen(taskId: task['id'] as String),
                ));
                if (mounted) await _load();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Icon(isOverdue ? Icons.warning_amber_rounded
                    : Icons.calendar_today_outlined, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task['title'] as String, maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Hạn ${_dateLabel(task['dueDate'] as String)} • '
                        '${_relativeLabel(task['daysRemaining'] as int)}',
                        style: const TextStyle(fontSize: 12,
                          color: Color(0xFF718096))),
                    ],
                  )),
                  const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Color(0xFF9AA7BB)),
                ]),
              ),
            ),
            if (task != tasks.last) const Divider(height: 1),
          ],
      ]),
    ));
  }

  String _relativeLabel(int days) {
    if (days == 0) return 'đến hạn hôm nay';
    if (days < 0) return 'quá hạn ${-days} ngày';
    return 'còn $days ngày';
  }

  @override
  Widget build(BuildContext context) {
    const soonColor = Color(0xFF3867D6);
    const overdueColor = Color(0xFFD65B43);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('CÔNG VIỆC SẮP ĐẾN HẠN VÀ QUÁ HẠN',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
            color: Color(0xFF70809C)))),
        IconButton(
          tooltip: 'Làm mới công việc theo hạn',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, size: 21),
        ),
      ]),
      if (_loading)
        const Card(child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ))
      else if (_error != null)
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 29),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 9),
            OutlinedButton.icon(onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại')),
          ]),
        ))
      else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Tính từ ${_dateLabel(_today)} • '
            'Sắp hạn: hôm nay đến $_windowDays ngày tới',
            style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
        ),
        Row(children: [
          _summaryCard('Sắp đến hạn', _soon.length,
            Icons.calendar_month_outlined, soonColor),
          const SizedBox(width: 12),
          _summaryCard('Đã quá hạn', _overdue.length,
            Icons.warning_amber_rounded, overdueColor),
        ]),
        const SizedBox(height: 12),
        _taskList('Sắp đến hạn', _soon, soonColor, false),
        _taskList('Đã quá hạn', _overdue, overdueColor, true),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text('Chỉ tính công việc chưa hoàn thành mà bạn có quyền xem. '
            'Nhấn vào công việc để mở chi tiết.',
            style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
        ),
      ],
    ]);
  }
}
