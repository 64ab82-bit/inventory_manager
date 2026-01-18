import 'package:flutter/material.dart';
import 'package:flutter_application_2/models.dart';

class MasterMaintenanceScreen extends StatefulWidget {
  const MasterMaintenanceScreen({Key? key}) : super(key: key);

  @override
  State<MasterMaintenanceScreen> createState() => _MasterMaintenanceScreenState();
}

class _MasterMaintenanceScreenState extends State<MasterMaintenanceScreen> {
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

  void _showEditDialog({Item? item}) {
    final TextEditingController c = TextEditingController(text: item?.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? '新規アイテム' : 'アイテム編集'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'アイテム名')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              final name = c.text.trim();
              if (name.isEmpty) return;
              
              // 編集時に排他チェック
              if (item != null) {
                // GitHub から最新データを取得
                await loadData();
                
                // 編集しようとしているアイテムがまだ存在するか確認
                final stillExists = masterItems.any((e) => e.id == item.id);
                if (!stillExists) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚠️ このアイテムは別の PC で削除されました')),
                    );
                    Navigator.of(context).pop();
                    await _loadLatestData();
                  }
                  return;
                }
                
                // 存在する場合は更新
                final existingItem = masterItems.firstWhere((e) => e.id == item.id);
                existingItem.name = name;
              } else {
                // 新規作成
                masterItems.add(Item(id: getNextItemId(), name: name));
              }
              
              await saveData();
              // 保存後、GitHub から最新データを再取得
              await _loadLatestData();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deleteItem(Item item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${item.name}」を削除してよいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              masterItems.removeWhere((e) => e.id == item.id);
              await saveData();
              // 保存後、GitHub から最新データを再取得
              await _loadLatestData();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('マスタメンテナンス')),
      body: ListView.builder(
        itemCount: masterItems.length,
        itemBuilder: (context, index) {
          final item = masterItems[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: ListTile(
              leading: CircleAvatar(child: Text(item.name.isNotEmpty ? item.name[0] : '?')),
              title: Text(item.name),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => _showEditDialog(item: item)),
                IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteItem(item)),
              ]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),
        icon: const Icon(Icons.add),
        label: const Text('新規追加'),
      ),
    );
  }
}