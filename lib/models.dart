class Item {
  final int id;
  String name;
  Item({required this.id, required this.name});
}

class InventoryEntry {
  final DateTime date;
  final int itemId;
  final int quantity;
  InventoryEntry({required this.date, required this.itemId, required this.quantity});
}

// 初期マスタデータ（5つ）
final List<Item> masterItems = [
  Item(id: 1, name: 'りんご'),
  Item(id: 2, name: 'バナナ'),
  Item(id: 3, name: 'みかん'),
  Item(id: 4, name: 'ぶどう'),
  Item(id: 5, name: 'もも'),
];
int _nextItemId = 6;

int getNextItemId() => _nextItemId++;

// 在庫入力で登録したデータ（起動中は保持）
// サンプルデータを10件追加（時間は00:00）
final now = DateTime.now();
final List<InventoryEntry> inventoryEntries = [
  InventoryEntry(date: DateTime(now.year, now.month, now.day, 0, 0), itemId: 1, quantity: 10),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 1, 0, 0), itemId: 2, quantity: 3),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 2, 0, 0), itemId: 3, quantity: 8),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 3, 0, 0), itemId: 1, quantity: 2),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 4, 0, 0), itemId: 4, quantity: 6),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 5, 0, 0), itemId: 5, quantity: 1),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 6, 0, 0), itemId: 2, quantity: 7),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 7, 0, 0), itemId: 3, quantity: 4),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 8, 0, 0), itemId: 4, quantity: 9),
  InventoryEntry(date: DateTime(now.year, now.month, now.day - 9, 0, 0), itemId: 5, quantity: 5),
];