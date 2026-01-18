import 'package:flutter/material.dart';
import 'package:inventory_manager/models.dart';
import 'package:inventory_manager/screens/report_screen.dart';

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
  int? _selectedItemId; // null = すべての項目
  
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
    if (d != null) {
      setState(() => _start = d);
      _compute();
    }
  }

  void _pickEnd() async {
    final d = await showDatePicker(context: context, initialDate: _end, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) {
      setState(() => _end = d);
      _compute();
    }
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
    // 履歴から使われているアイテムIDを取得
    final usedItemIds = _filteredEntries.map((e) => e.itemId).toSet().toList();
    final availableItems = masterItems.where((item) => usedItemIds.contains(item.id)).toList();
    
    // 選択されたアイテムでフィルタリング
    final filteredRows = _totals.entries.where((r) {
      if (_selectedItemId == null) return true;
      return r.key == _selectedItemId;
    }).toList()..sort((a, b) => b.value.compareTo(a.value));
    
    final filteredHistoryEntries = _filteredEntries.where((e) {
      if (_selectedItemId == null) return true;
      return e.itemId == _selectedItemId;
    }).toList();

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
            DropdownButtonFormField<int?>(
              value: _selectedItemId,
              decoration: const InputDecoration(
                labelText: 'アイテムで絞り込み',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_list),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('すべての項目'),
                ),
                ...availableItems.map((item) => DropdownMenuItem<int?>(
                  value: item.id,
                  child: Text(item.name),
                )),
              ],
              onChanged: (value) {
                setState(() => _selectedItemId = value);
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: () { _compute(); setState(() => _mode = ReportMode.aggregate); }, icon: const Icon(Icons.bar_chart), label: const Text('集計実行'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(onPressed: () { _compute(); setState(() => _mode = ReportMode.history); }, icon: const Icon(Icons.list), label: const Text('期間履歴表示'))),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: _mode == ReportMode.aggregate
                  ? (filteredRows.isEmpty
                      ? const Center(child: Text('該当データがありません'))
                      : ListView(
                          children: filteredRows.map((r) {
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
                  : (filteredHistoryEntries.isEmpty
                      ? const Center(child: Text('該当データがありません'))
                      : ListView.builder(
                          itemCount: filteredHistoryEntries.length,
                          itemBuilder: (context, idx) {
                            final e = filteredHistoryEntries[idx];
                            final name = masterItems.firstWhere((m) => m.id == e.itemId, orElse: () => Item(id: e.itemId, name: '不明')).name;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?')),
                                title: Text(name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.date.toLocal().toString().split(' ')[0]),
                                    if (e.remarks != null && e.remarks!.isNotEmpty)
                                      Text('備考: ${e.remarks}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                  ],
                                ),
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
