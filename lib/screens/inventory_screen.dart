import 'package:flutter/material.dart';
import 'package:flutter_application_2/models.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 0, 0);
  int? _selectedItemId;
  final TextEditingController _qtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 画面表示時に GitHub から最新データを取得
    _loadLatestData();
  }

  Future<void> _loadLatestData() async {
    await loadData();
    setState(() {});
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  void _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _selectedDate = DateTime(d.year, d.month, d.day, 0, 0));
  }

  void _saveEntry() async {
    if (_selectedItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('アイテムを選択してください')));
      return;
    }
    final q = int.tryParse(_qtyController.text);
    if (q == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数量は整数で入力してください')));
      return;
    }
    final now = DateTime.now();
    final entryDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, now.hour, now.minute, now.second);
    final itemName = masterItems.firstWhere((e) => e.id == _selectedItemId).name;
    inventoryEntries.add(InventoryEntry(date: entryDate, itemId: _selectedItemId!, itemName: itemName, quantity: q));
    await saveData();
    // 保存後、GitHub から最新データを再取得
    await _loadLatestData();
    _qtyController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('在庫を登録しました')));
  }

  String _findItemName(InventoryEntry entry) => entry.itemName;

  @override
  Widget build(BuildContext context) {
    final entries = List<InventoryEntry>.from(inventoryEntries)..sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(title: const Text('在庫入力')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '日付',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text('${_selectedDate.toLocal().toString().split(' ')[0]}'),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'アイテム'),
              items: masterItems.map((i) => DropdownMenuItem(value: i.id, child: Text(i.name))).toList(),
              onChanged: (v) => setState(() => _selectedItemId = v),
              value: _selectedItemId,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '数量'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _saveEntry, child: const Text('登録')),

            const Divider(height: 24),
            const Text('入力済みデータ：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: entries.isEmpty
                  ? const Text('まだデータがありません')
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        final name = _findItemName(e);
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
                    ),
            ),
          ],
        ),
      ),
    );
  }
}