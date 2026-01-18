import 'package:flutter/material.dart';
import 'package:flutter_application_2/models.dart';
import 'package:flutter_application_2/screens/report_screen.dart';

class AggregateScreen extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  const AggregateScreen({Key? key, this.initialStart, this.initialEnd}) : super(key: key);

  @override
  State<AggregateScreen> createState() => _AggregateScreenState();
}

class _AggregateScreenState extends State<AggregateScreen> {
  late DateTime _start;
  late DateTime _end;
  Map<int, int> _totals = {};
  ReportMode _mode = ReportMode.aggregate;
  List<InventoryEntry> _filteredEntries = [];
  @override
  void initState() {
    super.initState();
    _end = widget.initialEnd ?? DateTime.now();
    _start = widget.initialStart ?? DateTime.now().subtract(const Duration(days: 7));
    // 画面表示時に GitHub から最新データを取得
    _loadLatestData();
  }

  Future<void> _loadLatestData() async {
    await loadData();
    _compute();
    setState(() {});
  }

  void _pickStart() async {
    final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _start = d);
  }

  void _pickEnd() async {
    final d = await showDatePicker(context: context, initialDate: _end, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _end = d);
  }

  void _compute() {
    if (_start.isAfter(_end)) {
      setState(() => _totals = {});
      setState(() => _filteredEntries = []);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('開始日が終了日より後です')));
      return;
    }
    final entries = inventoryEntries.where((e) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      final s = DateTime(_start.year, _start.month, _start.day);
      final ed = DateTime(_end.year, _end.month, _end.day);
      return (d.isAtSameMomentAs(s) || d.isAfter(s)) && (d.isAtSameMomentAs(ed) || d.isBefore(ed));
    }).toList();

    entries.sort((a, b) => b.date.compareTo(a.date));

    final Map<int, int> totals = {};
    for (var e in entries) {
      totals[e.itemId] = (totals[e.itemId] ?? 0) + e.quantity;
    }
    setState(() {
      _totals = totals;
      _filteredEntries = entries;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('集計')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: _pickStart,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: '開始日', suffixIcon: Icon(Icons.calendar_today)),
                    child: Text('${_start.toLocal().toString().split(' ')[0]}'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickEnd,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: '終了日', suffixIcon: Icon(Icons.calendar_today)),
                    child: Text('${_end.toLocal().toString().split(' ')[0]}'),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: () { _compute(); setState(() => _mode = ReportMode.aggregate); }, icon: const Icon(Icons.bar_chart), label: const Text('集計実行'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(onPressed: () { _compute(); setState(() => _mode = ReportMode.history); }, icon: const Icon(Icons.list), label: const Text('期間履歴表示'))),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: _mode == ReportMode.aggregate
                  ? (rows.isEmpty
                      ? const Center(child: Text('該当データがありません'))
                      : ListView(
                          children: rows.map((r) {
                            final name = masterItems.firstWhere((m) => m.id == r.key, orElse: () => Item(id: r.key, name: '不明')).name;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: const Icon(Icons.shopping_bag),
                                title: Text(name),
                                trailing: Chip(label: Text('${r.value}')),
                              ),
                            );
                          }).toList(),
                        ))
                  : (_filteredEntries.isEmpty
                      ? const Center(child: Text('該当データがありません'))
                      : ListView.builder(
                          itemCount: _filteredEntries.length,
                          itemBuilder: (context, idx) {
                            final e = _filteredEntries[idx];
                            final name = masterItems.firstWhere((m) => m.id == e.itemId, orElse: () => Item(id: e.itemId, name: '不明')).name;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?')),
                                title: Text(name),
                                subtitle: Text(e.date.toLocal().toString().split(' ')[0]),
                                trailing: Chip(label: Text('${e.quantity}')),
                              ),
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
    );
  }
}
