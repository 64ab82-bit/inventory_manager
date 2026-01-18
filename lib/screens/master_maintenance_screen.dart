import 'package:flutter/material.dart';
import 'package:flutter_application_2/models.dart';

class MasterMaintenanceScreen extends StatefulWidget {
  const MasterMaintenanceScreen({Key? key}) : super(key: key);

  @override
  State<MasterMaintenanceScreen> createState() => _MasterMaintenanceScreenState();
}

class _MasterMaintenanceScreenState extends State<MasterMaintenanceScreen> {
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
              setState(() {
                if (item == null) {
                  masterItems.add(Item(id: getNextItemId(), name: name));
                } else {
                  item.name = name;
                }
              });
              await saveData();
              Navigator.of(context).pop();
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
              setState(() {
                masterItems.removeWhere((e) => e.id == item.id);
                // 在庫データに影響が出るが、ここではそのまま残す（要件通り起動中保持）
              });              await saveData();              Navigator.of(context).pop();
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