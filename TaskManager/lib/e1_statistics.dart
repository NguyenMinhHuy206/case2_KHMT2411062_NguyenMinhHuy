part of 'main.dart';

/// E1 - Thong ke tong so cong viec theo trang thai.
/// API values come from MongoDB, filtered by server-side authorization.
class E1StatisticsScreen extends StatefulWidget {
  const E1StatisticsScreen({super.key});

  @override
  State<E1StatisticsScreen> createState() => _E1StatisticsScreenState();
}

class _E1StatisticsScreenState extends State<E1StatisticsScreen> {
  bool _loading = true;
  String? _error;
  int _total = 0;
  Map<String, int> _byStatus = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await Api.request('GET', '/api/statistics/tasks');
      final raw = data['byStatus'];
      if (raw is! Map || data['total'] is! num) {
        throw Exception('Du lieu thong ke tu Backend khong hop le.');
      }
      final values = <String, int>{};
      for (final key in ['pending', 'in_progress', 'completed', 'other']) {
        final value = raw[key];
        if (value is! num || value.toInt() < 0) {
          throw Exception('So lieu thong ke khong hop le.');
        }
        values[key] = value.toInt();
      }
      final total = (data['total'] as num).toInt();
      if (total < 0 || values.values.fold<int>(0, (a, b) => a + b) != total) {
        throw Exception('Tong so cong viec khong khop voi tung trang thai.');
      }
      if (!mounted) return;
      setState(() { _total = total; _byStatus = values; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statusCard(String label, String key, Color color, IconData icon) {
    final count = _byStatus[key] ?? 0;
    final ratio = _total > 0 ? count / _total : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700))),
            Text('$count', style: const TextStyle(fontSize: 21,
              fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(
              value: ratio, minHeight: 9, color: color,
              backgroundColor: const Color(0xFFE8ECF5),
            ),
          ),
          const SizedBox(height: 8),
          Text('${(ratio * 100).toStringAsFixed(1)}% tổng công việc',
            style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê và tiện ích'),
        actions: [
          IconButton(
            tooltip: 'Làm mới thống kê',
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Thử lại')),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
                    children: [
                      Card(child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('TỔNG CÔNG VIỆC CÓ QUYỀN TRUY CẬP',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: Color(0xFF70809C))),
                          const SizedBox(height: 8),
                          Text('$_total', style: const TextStyle(
                            fontSize: 39, fontWeight: FontWeight.w800,
                            color: Color(0xFF3867D6))),
                          const SizedBox(height: 6),
                          const Text('Mỗi công việc chỉ được tính một lần.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
                        ]),
                      )),
                      const SizedBox(height: 16),
                      _statusCard('Chưa thực hiện', 'pending',
                        const Color(0xFF64748B), Icons.pending_actions_outlined),
                      _statusCard('Đang thực hiện', 'in_progress',
                        const Color(0xFFF0A03B), Icons.hourglass_top_rounded),
                      _statusCard('Đã hoàn thành', 'completed',
                        const Color(0xFF249F72), Icons.check_circle_outline),
                      if ((_byStatus['other'] ?? 0) > 0)
                        _statusCard('Trạng thái khác', 'other',
                          const Color(0xFFB05ABB), Icons.help_outline_rounded),
                      const SizedBox(height: 18),
                      const E2AssignmentsSection(),
                      const SizedBox(height: 18),
                      const E3DeadlinesSection(),
                      if (_total == 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text('Chưa có công việc để thống kê.',
                            textAlign: TextAlign.center),
                        ),
                    ],
                  ),
                ),
    );
  }
}
