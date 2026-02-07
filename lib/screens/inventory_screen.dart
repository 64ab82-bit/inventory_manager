// Flutter UIフレームワークのコアライブラリ
import 'package:flutter/material.dart';
// データモデル（アイテムや在庫情報）をインポート
import 'package:inventory_manager/models.dart';

// ==== 在庫入力画面 ====
// 日付、アイテム、数量を選択して在庫を登録する画面
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

// 在庫入力画面の状態を管理するクラス
class _InventoryScreenState extends State<InventoryScreen> {
  // 選択された日付（初期値は今日の0時）
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 0, 0);
  // 選択されたアイテムのID（null = 未選択）
  int? _selectedItemId;
  // 選択された数量（null = 未選択）
  int? _selectedQuantity;
  // 備考入力フィールドの制御用
  final TextEditingController _remarksController = TextEditingController();

  // 画面が表示されたときに一度だけ呼ばれる関数
  @override
  void initState() {
    super.initState();
    // 画面表示時に GitHub から最新データを取得
    _loadLatestData();
  }

  // GitHubから最新のデータを読み込んで画面を更新
  Future<void> _loadLatestData() async {
    await loadData();  // models.dart のデータ読み込み関数を呼ぶ
    setState(() {});  // 画面を再構築して最新データを表示
  }

  // 日時を「年/月/日 時:分:秒」形式に整形する関数
  String _fmt(DateTime dt) {
    final d = dt.toLocal();  // ローカルタイムゾーンに変換
    // 1桁の数字を2桁にする関数（例：1 → 01）
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  // 日付選択ダイアログを表示する関数
  void _pickDate() async {
    // カレンダーダイアログを表示して日付を選択
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,  // 初期表示日付
      firstDate: DateTime(2000),   // 選択可能な最初の日付
      lastDate: DateTime(2100),    // 選択可能な最後の日付
    );
    // 日付が選択されたら、0時に設定して保存
    if (d != null) setState(() => _selectedDate = DateTime(d.year, d.month, d.day, 0, 0));
  }

  // 在庫履歴を保存する関数
  void _saveEntry() async {
    // ==== 入力チェック ====
    if (_selectedItemId == null) {
      // アイテムが選択されていない場合はエラーメッセージを表示
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('アイテムを選択してください')));
      return;
    }
    if (_selectedQuantity == null) {
      // 数量が選択されていない場合はエラーメッセージを表示
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数量を選択してください')));
      return;
    }
    
    // ==== 履歴データを作成 ====
    final now = DateTime.now();
    // 選択した日付に現在の時刻を組み合わせる
    final entryDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, now.hour, now.minute, now.second);
    // 選択されたアイテムの名前を取得
    final itemName = masterItems.firstWhere((e) => e.id == _selectedItemId).name;
    // 備考が空の場合はnullにする
    final remarks = _remarksController.text.isEmpty ? null : _remarksController.text;
    
    debugPrint('📝 [在庫登録] 保存前の在庫データ件数: ${inventoryEntries.length}');
    // 在庫履歴をリストに追加
    inventoryEntries.add(InventoryEntry(date: entryDate, itemId: _selectedItemId!, itemName: itemName, quantity: _selectedQuantity!, remarks: remarks));
    debugPrint('📝 [在庫登録] 保存後の在庫データ件数: ${inventoryEntries.length}');
    
    // ==== GitHubとローカルに保存 ====
    await saveData();
    debugPrint('✅ [在庫登録] saveData完了');
    
    // 保存後、GitHub から最新データを再取得
    await _loadLatestData();
    debugPrint('✅ [在庫登録] _loadLatestData完了 - 在庫データ件数: ${inventoryEntries.length}');
    
    // ==== 入力フィールドをクリア ====
    _selectedQuantity = null;
    _remarksController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('在庫を登録しました')));
  }

  // 在庫履歴を削除する関数
  void _deleteEntry(InventoryEntry entry) async {
    // 削除確認ダイアログを表示
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

    // 「削除」ボタンが押された場合
    if (confirm == true) {
      // 該当する履歴をリストから削除
      inventoryEntries.removeWhere((e) => e.date == entry.date && e.itemId == entry.itemId);
      // データを保存
      await saveData();
      // 最新データを再取得
      await _loadLatestData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
    }
  }

  // 在庫履歴を編集する関数
  void _editEntry(InventoryEntry entry) async {
    // 編集用のコントローラを作成（現在の値を初期値に設定）
    final qtyController = TextEditingController(text: entry.quantity.toString());
    final remarksController = TextEditingController(text: entry.remarks ?? '');
    DateTime selectedDate = entry.date;  // 現在の日付を保持

    // 編集ダイアログを表示
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(  // ダイアログ内で状態を更新するため
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('履歴編集'),
          content: SingleChildScrollView(  // スクロール可能にする
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 日付選択フィールド（タップでカレンダー表示）
                InkWell(
                  onTap: () async {
                    // カレンダーを表示して日付を選択
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      // 日付を更新（時刻は保持）
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
                child: Text(_selectedDate.toLocal().toString().split(' ')[0]),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'アイテム'),
              items: masterItems.map((i) => DropdownMenuItem(value: i.id, child: Text(i.name))).toList(),
              onChanged: (v) => setState(() => _selectedItemId = v),
              initialValue: _selectedItemId,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '数量'),
              items: List.generate(100, (i) => i + 1)
                  .map((q) => DropdownMenuItem(value: q, child: Text('$q')))
                  .toList(),
              onChanged: (v) => setState(() => _selectedQuantity = v),
              initialValue: _selectedQuantity,
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
            const Text(
              '入力履歴：',
              style: TextStyle(fontWeight: FontWeight.bold),
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