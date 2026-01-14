import 'package:flutter/material.dart';
import 'package:flutter_application_2/models.dart';

enum ReportMode { aggregate, history }

class ReportScreen extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final ReportMode mode;

  const ReportScreen({Key? key, required this.start, required this.end, required this.mode}) : super(key: key);

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    // date range filter (inclusive)
    final entries = inventoryEntries.where((e) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      final s = DateTime(start.year, start.month, start.day);
      final ed = DateTime(end.year, end.month, end.day);
      return (d.isAtSameMomentAs(s) || d.isAfter(s)) && (d.isAtSameMomentAs(ed) || d.isBefore(ed));
    }).toList();

    Widget body;

    if (mode == ReportMode.aggregate) {
      final Map<int, int> totals = {};
      for (var e in entries) {
        totals[e.itemId] = (totals[e.itemId] ?? 0) + e.quantity;
      }
      final rows = totals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      body = rows.isEmpty
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
            );
    } else {
      // history
      entries.sort((a, b) => b.date.compareTo(a.date));
      body = entries.isEmpty
          ? const Center(child: Text('該当データがありません'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, idx) {
                final e = entries[idx];
                final name = masterItems.firstWhere((m) => m.id == e.itemId, orElse: () => Item(id: e.itemId, name: '不明')).name;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?')),
                    title: Text(name),
                    subtitle: Text(_fmt(e.date)),
                    trailing: Chip(label: Text('${e.quantity}')),
                  ),
                );
              },
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(mode == ReportMode.aggregate ? '集計結果' : '履歴'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text('期間: ${_fmt(start)} 〜 ${_fmt(end)}'),
            const SizedBox(height: 8),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
