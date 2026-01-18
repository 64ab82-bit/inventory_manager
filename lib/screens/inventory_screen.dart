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
  int? _selectedQuantity;
  final TextEditingController _remarksController = TextEditingController();

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
    if (_selectedQuantity == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数量を選択してください')));
      return;
    }
    final now = DateTime.now();
    final entryDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, now.hour, now.minute, now.second);
    final itemName = masterItems.firstWhere((e) => e.id == _selectedItemId).name;
    final remarks = _remarksController.text.isEmpty ? null : _remarksController.text;
    
    print('📝 [在庫登録] 保存前の在庫データ件数: ${inventoryEntries.length}');
    inventoryEntries.add(InventoryEntry(date: entryDate, itemId: _selectedItemId!, itemName: itemName, quantity: _selectedQuantity!, remarks: remarks));
    print('📝 [在庫登録] 保存後の在庫データ件数: ${inventoryEntries.length}');
    
    await saveData();
    print('✅ [在庫登録] saveData完了');
    
    // 保存後、GitHub から最新データを再取得
    await _loadLatestData();
    print('✅ [在庫登録] _loadLatestData完了 - 在庫データ件数: ${inventoryEntries.length}');
    
    _selectedQuantity = null;
    _remarksController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('在庫を登録しました')));
  }

  void _deleteEntry(InventoryEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('この履歴を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );

    if (confirm == true) {
      inventoryEntries.removeWhere((e) => e.date == entry.date && e.itemId == entry.itemId);
      await saveData();
      await _loadLatestData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
    }
  }

  void _editEntry(InventoryEntry entry) async {
    final qtyController = TextEditingController(text: entry.quantity.toString());
    final remarksController = TextEditingController(text: entry.remarks ?? '');
    DateTime selectedDate = entry.date;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('履歴編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      setDialogState(() {
                        selectedDate = DateTime(d.year, d.month, d.day, selectedDate.hour, selectedDate.minute, selectedDate.second);
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '日付',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(_fmt(selectedDate)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '数量'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: remarksController,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            TextButton(
              onPressed: () async {
                final q = int.tryParse(qtyController.text);
                if (q == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数量は整数で入力してください')));
                  return;
                }

                final index = inventoryEntries.indexWhere((e) => e.date == entry.date && e.itemId == entry.itemId);
                if (index != -1) {
                  inventoryEntries[index] = InventoryEntry(
                    date: selectedDate,
                    itemId: entry.itemId,
                    itemName: entry.itemName,
                    quantity: q,
                    remarks: remarksController.text.isEmpty ? null : remarksController.text,
                  );
                  await saveData();
                  await _loadLatestData();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新しました')));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  String _findItemName(InventoryEntry entry) => entry.itemName;

  @override
  Widget build(BuildContext context) {
    // 選択されたアイテムの履歴のみをフィルタリング
    final filteredEntries = _selectedItemId == null
        ? <InventoryEntry>[]
        : inventoryEntries.where((e) => e.itemId == _selectedItemId).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

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
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '数量'),
              items: List.generate(100, (i) => i + 1)
                  .map((q) => DropdownMenuItem(value: q, child: Text('$q')))
                  .toList(),
              onChanged: (v) => setState(() => _selectedQuantity = v),
              value: _selectedQuantity,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remarksController,
              decoration: const InputDecoration(labelText: '備考'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _saveEntry, child: const Text('登録')),

            const Divider(height: 24),
            Text(
              _selectedItemId == null 
                ? '← アイテムを選択すると履歴が表示されます'
                : '入力履歴：',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _selectedItemId == null
                  ? const Center(child: Text('アイテムを選択してください'))
                  : filteredEntries.isEmpty
                      ? const Center(child: Text('まだデータがありません'))
                      : ListView.builder(
                          itemCount: filteredEntries.length,
                          itemBuilder: (context, index) {
                            final e = filteredEntries[index];
                            final name = _findItemName(e);
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?')),
                                title: Text(name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_fmt(e.date)),
                                    if (e.remarks != null && e.remarks!.isNotEmpty)
                                      Text('備考: ${e.remarks}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(label: Text('${e.quantity}')),
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () => _editEntry(e),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                      onPressed: () => _deleteEntry(e),
                                    ),
                                  ],
                                ),
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