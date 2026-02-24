import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:mssql_connection/mssql_connection.dart';

class DatabaseService {
  DatabaseService({
    required this.workspaceRoot,
    required this.host,
    required this.port,
    required this.databaseName,
    required this.username,
    required this.password,
    String? masterDataPath,
    String? inventoryEntriesPath,
  })  : _masterDataPathOverride = masterDataPath,
        _inventoryEntriesPathOverride = inventoryEntriesPath;

  final String workspaceRoot;
  final String host;
  final String port;
  final String databaseName;
  final String username;
  final String password;
  final String? _masterDataPathOverride;
  final String? _inventoryEntriesPathOverride;
  final MssqlConnection _mssql = MssqlConnection.getInstance();

  String get _masterDataPath => _masterDataPathOverride ?? p.join(workspaceRoot, 'master_data.json');
  String get _inventoryEntriesPath =>
      _inventoryEntriesPathOverride ?? p.join(workspaceRoot, 'inventory_entries.json');

  Future<void> initialize() async {
    await _initializeMssql();
    await _seedFromJsonIfEmpty();
  }

  Future<void> _initializeMssql() async {
    final connected = await _mssql.connect(
      ip: host,
      port: port,
      databaseName: databaseName,
      username: username,
      password: password,
      timeoutInSeconds: 15,
    );

    if (!connected) {
      throw StateError('MSSQL接続に失敗しました: $host:$port / DB=$databaseName');
    }

    await _executeWrite('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL
      );
    ''');
    await _executeWrite('''
      CREATE TABLE IF NOT EXISTS inventory_entries (
        id INT IDENTITY(1,1) PRIMARY KEY,
        date TEXT NOT NULL,
        item_id INTEGER NOT NULL REFERENCES items(id),
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        remarks TEXT
      );
    ''');
  }

  Future<void> dispose() async {
    await _mssql.disconnect();
  }

  Future<List<Map<String, Object?>>> getItems() async {
    final rows = await _executeRead('SELECT id, name FROM items ORDER BY id');
    return rows
        .map(
          (row) => {
            'id': _asInt(_pick(row, ['id', 'ID'])),
            'name': '${_pick(row, ['name', 'NAME'])}',
          },
        )
        .toList();
  }

  Future<Map<String, Object?>> createItem(String name) async {
    final row = await _executeRead('SELECT ISNULL(MAX(id), 0) + 1 AS next_id FROM items');
    final id = _asInt(_pick(row.first, ['next_id', 'NEXT_ID']));
    await _executeWrite(
      "INSERT INTO items (id, name) VALUES ($id, N'${_escapeSql(name)}')",
    );

    return {'id': id, 'name': name};
  }

  Future<List<Map<String, Object?>>> getEntries({int? itemId}) async {
    final query = StringBuffer(
      'SELECT id, date, item_id, item_name, quantity, remarks FROM inventory_entries',
    );

    if (itemId != null) {
      query.write(' WHERE item_id = $itemId');
    }
    query.write(' ORDER BY date DESC, id DESC');

    final rows = await _executeRead(query.toString());
    return rows
        .map(
          (row) => {
            'id': _asInt(_pick(row, ['id', 'ID'])),
            'date': '${_pick(row, ['date', 'DATE'])}',
            'itemId': _asInt(_pick(row, ['item_id', 'ITEM_ID'])),
            'itemName': '${_pick(row, ['item_name', 'ITEM_NAME'])}',
            'quantity': _asInt(_pick(row, ['quantity', 'QUANTITY'])),
            'remarks': _pick(row, ['remarks', 'REMARKS']),
          },
        )
        .toList();
  }

  Future<Map<String, Object?>> createEntry({
    required int itemId,
    required int quantity,
    String? remarks,
    String? date,
  }) async {
    final itemName = await _getItemName(itemId);
    if (itemName == null) {
      throw StateError('指定したitemIdが存在しません: $itemId');
    }

    final entryDate = date ?? DateTime.now().toIso8601String();
    final remarksSql = remarks == null ? 'NULL' : "N'${_escapeSql(remarks)}'";
    await _executeWrite(
      "INSERT INTO inventory_entries ([date], item_id, item_name, quantity, remarks) VALUES (N'${_escapeSql(entryDate)}', $itemId, N'${_escapeSql(itemName)}', $quantity, $remarksSql)",
    );
    final insertedRows = await _executeRead('SELECT TOP 1 id FROM inventory_entries ORDER BY id DESC');
    final insertedId = _asInt(_pick(insertedRows.first, ['id', 'ID']));

    return {
      'id': insertedId,
      'date': entryDate,
      'itemId': itemId,
      'itemName': itemName,
      'quantity': quantity,
      'remarks': remarks,
    };
  }

  Future<String?> _getItemName(int itemId) async {
    final itemRow = await _executeRead('SELECT name FROM items WHERE id = $itemId');
    if (itemRow.isEmpty) {
      return null;
    }
    return '${_pick(itemRow.first, ['name', 'NAME'])}';
  }

  Future<List<Map<String, Object?>>> aggregateStock() async {
    const aggregateSql = '''
      SELECT item_id AS itemId, item_name AS itemName, SUM(quantity) AS totalQuantity
      FROM inventory_entries
      GROUP BY item_id, item_name
      ORDER BY item_id
    ''';

    final rows = await _executeRead(aggregateSql);
    return rows
        .map(
          (row) => {
            'itemId': _asInt(_pick(row, ['itemId', 'ITEMID'])),
            'itemName': '${_pick(row, ['itemName', 'ITEMNAME'])}',
            'totalQuantity': _asInt(_pick(row, ['totalQuantity', 'TOTALQUANTITY'])),
          },
        )
        .toList();
  }

  Future<void> replaceAllData({
    required List<dynamic> items,
    required List<dynamic> entries,
  }) async {
    await _executeWrite('BEGIN TRANSACTION');
    try {
      await _executeWrite('DELETE FROM inventory_entries');
      await _executeWrite('DELETE FROM items');

      for (final item in items) {
        final map = Map<String, dynamic>.from(item as Map);
        await _executeWrite(
          "INSERT INTO items (id, name) VALUES (${map['id']}, N'${_escapeSql('${map['name']}')}')",
        );
      }

      for (final entry in entries) {
        final map = Map<String, dynamic>.from(entry as Map);
        final remarks = map['remarks'];
        final remarksSql = remarks == null ? 'NULL' : "N'${_escapeSql('$remarks')}'";
        await _executeWrite(
          "INSERT INTO inventory_entries ([date], item_id, item_name, quantity, remarks) VALUES (N'${_escapeSql('${map['date']}')}', ${map['itemId']}, N'${_escapeSql('${map['itemName']}')}', ${map['quantity']}, $remarksSql)",
        );
      }

      await _executeWrite('COMMIT TRANSACTION');
    } catch (_) {
      await _executeWrite('ROLLBACK TRANSACTION');
      rethrow;
    }
  }

  Future<void> _seedFromJsonIfEmpty() async {
    final itemCountRows = await _executeRead('SELECT COUNT(*) AS count FROM items');
    final entryCountRows = await _executeRead('SELECT COUNT(*) AS count FROM inventory_entries');
    final itemCount = _asInt(_pick(itemCountRows.first, ['count', 'COUNT']));
    final entryCount = _asInt(_pick(entryCountRows.first, ['count', 'COUNT']));

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

    await replaceAllData(items: masterItems, entries: inventoryEntries);
  }

  Future<List<Map<String, dynamic>>> _executeRead(String query) async {
    final raw = await _mssql.getData(query);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final rows = (decoded['rows'] as List?) ?? const [];
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _executeWrite(String query) async {
    await _mssql.writeData(query);
  }

  Object? _pick(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      if (row.containsKey(key)) {
        return row[key];
      }
    }
    return null;
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value == null) return 0;
    return int.parse('$value');
  }

  String _escapeSql(String value) => value.replaceAll("'", "''");
}
