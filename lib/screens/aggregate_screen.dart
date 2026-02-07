// Flutter UIフレームワークのコアライブラリ
import 'package:flutter/material.dart';
// データモデル（アイテムや在庫情報）をインポート
import 'package:inventory_manager/models.dart';
// レポート画面をインポート
import 'package:inventory_manager/screens/report_screen.dart';

// ==== 集計画面 ====
// 期間を指定して在庫データを集計し、結果を表示する画面
class AggregateScreen extends StatefulWidget {
  final DateTime? initialStart;  // 初期表示の開始日（オプション）
  final DateTime? initialEnd;    // 初期表示の終了日（オプション）
  
  const AggregateScreen({super.key, this.initialStart, this.initialEnd});

  @override
  State<AggregateScreen> createState() => _AggregateScreenState();
}

// 集計画面の状態を管理するクラス
class _AggregateScreenState extends State<AggregateScreen> {
  late DateTime _start;              // 集計期間の開始日
  late DateTime _end;                // 集計期間の終了日
  Map<int, int> _totals = {};        // アイテムごとの集計結果 {アイテムID: 合計数量}
  ReportMode _mode = ReportMode.aggregate;  // 表示モード（集計 or 履歴）
  List<InventoryEntry> _filteredEntries = [];  // フィルタリングされた在庫履歴
  int? _selectedItemId;              // 選択されたアイテムID (null = すべての項目)
  
  // 画面が表示されたときに一度だけ呼ばれる関数
  @override
  void initState() {
    super.initState();
    // 終了日：指定があればそれを、なければ今日
    _end = widget.initialEnd ?? DateTime.now();
    // 開始日：指定があればそれを、なければ7日前
    _start = widget.initialStart ?? DateTime.now().subtract(const Duration(days: 7));
    // 画面表示時に GitHub から最新データを取得
    _loadLatestData();
  }

  // GitHubから最新のデータを読み込んで集計を実行
  Future<void> _loadLatestData() async {
    await loadData();  // models.dart のデータ読み込み関数を呼ぶ
    _compute();        // 集計処理を実行
    setState(() {});   // 画面を再構築して最新データを表示
  }

  // 開始日選択ダイアログを表示する関数
  void _pickStart() async {
    final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) {
      setState(() => _start = d);  // 選択された日付を保存
      _compute();  // 日付が変わったので再集計
    }
  }

  // 終了日選択ダイアログを表示する関数
  void _pickEnd() async {
    final d = await showDatePicker(context: context, initialDate: _end, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) {
      setState(() => _end = d);  // 選択された日付を保存
      _compute();  // 日付が変わったので再集計
    }
  }

  // 期間内のデータを集計する関数
  void _compute() {
    // ==== 日付の妥当性チェック ====
    if (_start.isAfter(_end)) {
      // 開始日が終了日より後の場合はエラー
      setState(() => _totals = {});
      setState(() => _filteredEntries = []);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('開始日が終了日より後です')));
      return;
    }
    
    // ==== 期間内のデータをフィルタリング ====
    final entries = inventoryEntries.where((e) {
      // 日付部分のみを取り出す（時刻は無視）
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      final s = DateTime(_start.year, _start.month, _start.day);
      final ed = DateTime(_end.year, _end.month, _end.day);
      // 開始日以降かつ終了日以前のデータのみ
      return (d.isAtSameMomentAs(s) || d.isAfter(s)) && (d.isAtSameMomentAs(ed) || d.isBefore(ed));
    }).toList();

    // 新しい順にソート
    entries.sort((a, b) => b.date.compareTo(a.date));

    // ==== アイテムごとの合計数量を計算 ====
    final Map<int, int> totals = {};  // {アイテムID: 合計数量}
    for (var e in entries) {
      // 既存の合計に加算（初回は0として扱う）
      totals[e.itemId] = (totals[e.itemId] ?? 0) + e.quantity;
    }
    
    // 状態を更新
    setState(() {
      _totals = totals;
      _filteredEntries = entries;
    });
  }

  // UI構築関数
  @override
  Widget build(BuildContext context) {
    // ==== アイテム絞り込み用のリスト作成 ====
    // 履歴から使われているアイテムIDを取得
    final usedItemIds = _filteredEntries.map((e) => e.itemId).toSet().toList();
    // マスタから実際に使われているアイテムのみを抽出
    final availableItems = masterItems.where((item) => usedItemIds.contains(item.id)).toList();
    
    // ==== 選択されたアイテムでフィルタリング ====
    // 集計結果をフィルタリング
    final filteredRows = _totals.entries.where((r) {
      if (_selectedItemId == null) return true;  // 全て表示
      return r.key == _selectedItemId;  // 選択されたアイテムのみ
    }).toList()..sort((a, b) => b.value.compareTo(a.value));  // 数量の多い順にソート
    
    // 履歴をフィルタリング
    final filteredHistoryEntries = _filteredEntries.where((e) {
      if (_selectedItemId == null) return true;  // 全て表示
      return e.itemId == _selectedItemId;  // 選択されたアイテムのみ
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
                    child: Text(_start.toLocal().toString().split(' ')[0]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickEnd,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: '終了日', suffixIcon: Icon(Icons.calendar_today)),
                    child: Text(_end.toLocal().toString().split(' ')[0]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _selectedItemId,
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
