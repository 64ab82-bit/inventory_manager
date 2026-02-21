import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class DatabaseService {
  DatabaseService({
    required this.workspaceRoot,
    String? dbPath,
    String? masterDataPath,
    String? inventoryEntriesPath,
  })  : _dbPathOverride = dbPath,
        _masterDataPathOverride = masterDataPath,
        _inventoryEntriesPathOverride = inventoryEntriesPath;

  final String workspaceRoot;
  final String? _dbPathOverride;
  final String? _masterDataPathOverride;
  final String? _inventoryEntriesPathOverride;
  late final Database db;

  String get _dbPath => _dbPathOverride ?? p.join(workspaceRoot, 'backend', 'inventory.db');
  String get _masterDataPath => _masterDataPathOverride ?? p.join(workspaceRoot, 'master_data.json');
  String get _inventoryEntriesPath =>
      _inventoryEntriesPathOverride ?? p.join(workspaceRoot, 'inventory_entries.json');

  void initialize() {
    db = sqlite3.open(_dbPath);
    db.execute('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        remarks TEXT,
        FOREIGN KEY(item_id) REFERENCES items(id)
      );
    ''');
    _seedFromJsonIfEmpty();
  }

  void dispose() {
    db.dispose();
  }

  List<Map<String, Object?>> getItems() {
    final result = db.select('SELECT id, name FROM items ORDER BY id');
    return result
        .map((row) => {'id': row['id'], 'name': row['name']})
        .toList();
  }

  Map<String, Object?> createItem(String name) {
    final row = db.select('SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM items').first;
    final id = row['next_id'] as int;
    db.execute(
      'INSERT INTO items (id, name) VALUES (?, ?)',
      [id, name],
    );
    return {'id': id, 'name': name};
  }

  List<Map<String, Object?>> getEntries({int? itemId}) {
    final query = StringBuffer(
      'SELECT id, date, item_id, item_name, quantity, remarks FROM inventory_entries',
    );
    final params = <Object?>[];
    if (itemId != null) {
      query.write(' WHERE item_id = ?');
      params.add(itemId);
    }
    query.write(' ORDER BY datetime(date) DESC, id DESC');

    final result = db.select(query.toString(), params);
    return result
        .map(
          (row) => {
            'id': row['id'],
            'date': row['date'],
            'itemId': row['item_id'],
            'itemName': row['item_name'],
            'quantity': row['quantity'],
            'remarks': row['remarks'],
          },
        )
        .toList();
  }

  Map<String, Object?> createEntry({
    required int itemId,
    required int quantity,
    String? remarks,
    String? date,
  }) {
    final itemRow = db.select('SELECT id, name FROM items WHERE id = ?', [itemId]);
    if (itemRow.isEmpty) {
      throw StateError('指定したitemIdが存在しません: $itemId');
    }

    final itemName = itemRow.first['name'] as String;
    final entryDate = date ?? DateTime.now().toIso8601String();

    db.execute(
      '''
      INSERT INTO inventory_entries (date, item_id, item_name, quantity, remarks)
      VALUES (?, ?, ?, ?, ?)
      ''',
      [entryDate, itemId, itemName, quantity, remarks],
    );

    final insertedId = db.select('SELECT last_insert_rowid() AS id').first['id'] as int;
    return {
      'id': insertedId,
      'date': entryDate,
      'itemId': itemId,
      'itemName': itemName,
      'quantity': quantity,
      'remarks': remarks,
    };
  }

  List<Map<String, Object?>> aggregateStock() {
    final result = db.select('''
      SELECT item_id AS itemId, item_name AS itemName, SUM(quantity) AS totalQuantity
      FROM inventory_entries
      GROUP BY item_id, item_name
      ORDER BY item_id
    ''');

    return result
        .map(
          (row) => {
            'itemId': row['itemId'],
            'itemName': row['itemName'],
            'totalQuantity': row['totalQuantity'],
          },
        )
        .toList();
  }

  void replaceAllData({
    required List<dynamic> items,
    required List<dynamic> entries,
  }) {
    db.execute('BEGIN TRANSACTION');
    try {
      db.execute('DELETE FROM inventory_entries');
      db.execute('DELETE FROM items');

      for (final item in items) {
        final map = item as Map<String, dynamic>;
        db.execute(
          'INSERT INTO items (id, name) VALUES (?, ?)',
          [map['id'], map['name']],
        );
      }

      for (final entry in entries) {
        final map = entry as Map<String, dynamic>;
        db.execute(
          '''
          INSERT INTO inventory_entries (date, item_id, item_name, quantity, remarks)
          VALUES (?, ?, ?, ?, ?)
          ''',
          [
            map['date'],
            map['itemId'],
            map['itemName'],
            map['quantity'],
            map['remarks'],
          ],
        );
      }

      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _seedFromJsonIfEmpty() {
    final itemCount = db.select('SELECT COUNT(*) AS count FROM items').first['count'] as int;
    final entryCount =
        db.select('SELECT COUNT(*) AS count FROM inventory_entries').first['count'] as int;

    if (itemCount > 0 || entryCount > 0) {
      return;
    }

    final masterPath = _masterDataPath;
    final entriesPath = _inventoryEntriesPath;

    if (!File(masterPath).existsSync() || !File(entriesPath).existsSync()) {
      return;
    }

    final masterJson =
        jsonDecode(File(masterPath).readAsStringSync()) as Map<String, dynamic>;
    final entriesJson =
        jsonDecode(File(entriesPath).readAsStringSync()) as Map<String, dynamic>;

    final masterItems = (masterJson['masterItems'] as List?) ?? const [];
    final inventoryEntries = (entriesJson['inventoryEntries'] as List?) ?? const [];

    db.execute('BEGIN TRANSACTION');
    try {
      for (final item in masterItems) {
        final map = item as Map<String, dynamic>;
        db.execute(
          'INSERT INTO items (id, name) VALUES (?, ?)',
          [map['id'], map['name']],
        );
      }

      for (final entry in inventoryEntries) {
        final map = entry as Map<String, dynamic>;
        db.execute(
          '''
          INSERT INTO inventory_entries (date, item_id, item_name, quantity, remarks)
          VALUES (?, ?, ?, ?, ?)
          ''',
          [
            map['date'],
            map['itemId'],
            map['itemName'],
            map['quantity'],
            map['remarks'],
          ],
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
