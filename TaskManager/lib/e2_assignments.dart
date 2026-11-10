part of 'main.dart';

/// E2 - Thong ke cong viec duoc giao va dang phu trach.
/// Data is fetched from a user-scoped, authenticated backend endpoint.
class E2AssignmentsSection extends StatefulWidget {
  const E2AssignmentsSection({super.key});

  @override
  State<E2AssignmentsSection> createState() => _E2AssignmentsSectionState();
}

class _E2AssignmentsSectionState extends State<E2AssignmentsSection> {
  bool _loading = true;
  String? _error;
  int _assignedToMe = 0;
  int _primaryResponsible = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await Api.request('GET', '/api/statistics/assignments');
      final assigned = data['assignedToMe'];
      final primary = data['primaryResponsible'];
      if (assigned is! int || primary is! int || assigned < 0 || primary < 0) {
        throw Exception('Du lieu thong ke phan cong khong hop le.');
      }
      if (!mounted) return;
      setState(() {
        _assignedToMe = assigned;
        _primaryResponsible = primary;
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

  Widget _countRow(String label, String subtitle, int count, IconData icon,
      Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 23),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 14,
          )),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(
            fontSize: 12, color: Color(0xFF718096),
          )),
        ],
      )),
      const SizedBox(width: 8),
      Text('$count', style: TextStyle(
        fontSize: 25, fontWeight: FontWeight.w800, color: color,
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(child: Text(
            'CÔNG VIỆC ĐƯỢC GIAO VÀ PHỤ TRÁCH',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
              color: Color(0xFF70809C)),
          )),
          IconButton(
            tooltip: 'Làm mới thống kê phân công',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
        ]),
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
                  ? Column(children: [
                      const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 32),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Thử lại'),
                      ),
                    ])
                  : Column(children: [
                      _countRow('Được giao cho tôi',
                        'Tôi thuộc danh sách người được giao',
                        _assignedToMe, Icons.assignment_ind_outlined,
                        const Color(0xFF3867D6)),
                      const Divider(height: 32),
                      _countRow('Phụ trách chính',
                        'Tôi là người phụ trách chính',
                        _primaryResponsible, Icons.supervisor_account_outlined,
                        const Color(0xFF249F72)),
                      const SizedBox(height: 16),
                      const Text(
                        'Một công việc có thể thuộc cả hai nhóm; không cộng hai số này thành tổng.',
                        style: TextStyle(fontSize: 12,
                          color: Color(0xFF718096)),
                      ),
                    ]),
        )),
      ],
    );
  }
}
