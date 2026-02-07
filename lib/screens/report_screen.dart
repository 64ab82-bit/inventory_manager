// Flutter UIフレームワークのコアライブラリ
import 'package:flutter/material.dart';
// データモデル（アイテムや在庫情報）をインポート
import 'package:inventory_manager/models.dart';

// レポートの表示モード（集計 or 履歴）
enum ReportMode { aggregate, history }

// ==== レポート表示画面 ====
// 期間を指定して集計結果または履歴を表示する画面
class ReportScreen extends StatelessWidget {
  final DateTime start;    // 開始日
  final DateTime end;      // 終了日
  final ReportMode mode;   // 表示モード（集計 or 履歴）

  // コンストラクタ：画面作成時に必要な情報を受け取る
  const ReportScreen({super.key, required this.start, required this.end, required this.mode});

  // 日時を「年/月/日 時:分:秒」形式に整形する関数
  String _fmt(DateTime dt) {
    final d = dt.toLocal();  // ローカルタイムゾーンに変換
    // 1桁の数字を2桁にする関数（例：1 → 01）
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  // UI構築関数
  @override
  Widget build(BuildContext context) {
    // ==== 指定期間内のデータをフィルタリング ====
    // 開始日と終了日の範囲内にある在庫履歴のみを抽出
    final entries = inventoryEntries.where((e) {
      // 日付部分のみを取り出す（時刻は無視）
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      final s = DateTime(start.year, start.month, start.day);
      final ed = DateTime(end.year, end.month, end.day);
      // 開始日以降かつ終了日以前のデータのみ
      return (d.isAtSameMomentAs(s) || d.isAfter(s)) && (d.isAtSameMomentAs(ed) || d.isBefore(ed));
    }).toList();

    Widget body;  // 表示する本体部分のウィジェット

    // ==== 集計モードの場合 ====
    if (mode == ReportMode.aggregate) {
      // アイテムごとの合計数量を計算
      final Map<int, int> totals = {};  // {アイテムID: 合計数量}
      for (var e in entries) {
        // 既存の合計に加算（初回は0として扱う）
        totals[e.itemId] = (totals[e.itemId] ?? 0) + e.quantity;
      }
      // 数量の多い順にソート
      final rows = totals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // 表示用のウィジェットを作成
      body = rows.isEmpty
          ? const Center(child: Text('該当データがありません'))  // データがない場合
          : ListView(  // リスト形式で表示
              children: rows.map((r) {
                // アイテム名を取得（存在しない場合は「不明」）
                final name = masterItems.firstWhere((m) => m.id == r.key, orElse: () => Item(id: r.key, name: '不明')).name;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.shopping_bag),  // アイコン
                    title: Text(name),                        // アイテム名
                    trailing: Chip(label: Text('${r.value}')),  // 数量
                  ),
                );
              }).toList(),
            );
    } else {
      // ==== 履歴モードの場合 ====
      // 新しい順にソート
      entries.sort((a, b) => b.date.compareTo(a.date));
      body = entries.isEmpty
          ? const Center(child: Text('該当データがありません'))  // データがない場合
          : ListView.builder(  // リスト形式で表示
              itemCount: entries.length,
              itemBuilder: (context, idx) {
                final e = entries[idx];
                // アイテム名を取得（存在しない場合は「不明」）
                final name = masterItems.firstWhere((m) => m.id == e.itemId, orElse: () => Item(id: e.itemId, name: '不明')).name;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?')),  // アイテム名の頭文字
                    title: Text(name),           // アイテム名
                    subtitle: Text(_fmt(e.date)),  // 日時
                    trailing: Chip(label: Text('${e.quantity}')),  // 数量
                  ),
                );
              },
            );
    }

    // ==== 画面全体の構築 ====
    return Scaffold(
      appBar: AppBar(
        title: Text(mode == ReportMode.aggregate ? '集計結果' : '履歴'),  // モードに応じてタイトル変更
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // 期間表示
            Text('期間: ${_fmt(start)} 〜 ${_fmt(end)}'),
            const SizedBox(height: 8),
            // 集計または履歴の本体部分
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
