// Flutter UIフレームワークのコアライブラリ
import 'package:flutter/material.dart';
// データモデル（アイテムや在庫情報）をインポート
import 'package:inventory_manager/models.dart';

// ==== マスタメンテナンス画面 ====
// アイテムの新規追加、編集、削除を行う画面
class MasterMaintenanceScreen extends StatefulWidget {
  const MasterMaintenanceScreen({super.key});

  @override
  State<MasterMaintenanceScreen> createState() => _MasterMaintenanceScreenState();
}

// マスタメンテナンス画面の状態を管理するクラス
class _MasterMaintenanceScreenState extends State<MasterMaintenanceScreen> {
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
    setState(() {});   // 画面を再構築して最新データを表示
  }

  // アイテムの新規追加または編集ダイアログを表示する関数
  void _showEditDialog({Item? item}) {
    // テキスト入力用のコントローラを作成（編集時は現在の名前を初期値に）
    final TextEditingController c = TextEditingController(text: item?.name ?? '');
    // ダイアログを表示
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? '新規アイテム' : 'アイテム編集'),  // 新規/編集でタイトル変更
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'アイテム名')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              // 入力された名前を取得（前後の空白を除去）
              final name = c.text.trim();
              if (name.isEmpty) return;  // 空欄の場合は何もしない
              
              // ==== 編集時の排他チェック ====
              // 他のユーザーが同時に削除していないか確認
              if (item != null) {
                // GitHub から最新データを取得
                await loadData();
                
                // 編集しようとしているアイテムがまだ存在するか確認
                final stillExists = masterItems.any((e) => e.id == item.id);
                if (!stillExists) {
                  // 削除されていた場合はエラーメッセージを表示
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚠️ このアイテムは別の PC で削除されました')),
                    );
                    Navigator.of(context).pop();
                    await _loadLatestData();
                  }
                  return;
                }
                
                // 存在する場合は名前を更新
                final existingItem = masterItems.firstWhere((e) => e.id == item.id);
                existingItem.name = name;
              } else {
                // ==== 新規作成 ====
                // 新しいIDを取得してアイテムを追加
                masterItems.add(Item(id: getNextItemId(), name: name));
              }
              
              // ==== データを保存 ====
              await saveData();
              // 保存後、GitHub から最新データを再取得
              await _loadLatestData();
              if (mounted) {
                Navigator.of(context).pop();  // ダイアログを閉じる
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // アイテムを削除する関数
  void _deleteItem(Item item) {
    // 削除確認ダイアログを表示
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${item.name}」を削除してよいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              // リストから該当アイテムを削除
              masterItems.removeWhere((e) => e.id == item.id);
              // データを保存
              await saveData();
              // 保存後、GitHub から最新データを再取得
              await _loadLatestData();
              if (mounted) {
                Navigator.of(context).pop();  // ダイアログを閉じる
              }
            },
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // UI構築関数
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('マスタメンテナンス')),
      // アイテム一覧をリスト表示
      body: ListView.builder(
        itemCount: masterItems.length,  // アイテムの総数
        itemBuilder: (context, index) {
          final item = masterItems[index];  // 各アイテムを取得
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: ListTile(
              // アイテム名の頭文字をアイコンに表示
              leading: CircleAvatar(child: Text(item.name.isNotEmpty ? item.name[0] : '?')),
              title: Text(item.name),  // アイテム名
              // 編集と削除ボタン
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => _showEditDialog(item: item)),
                IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteItem(item)),
              ]),
            ),
          );
        },
      ),
      // 画面右下の新規追加ボタン
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),  // itemはnull = 新規追加モード
        icon: const Icon(Icons.add),
        label: const Text('新規追加'),
      ),
    );
  }
}