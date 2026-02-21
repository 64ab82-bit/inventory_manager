import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

class DatabaseService {
  DatabaseService({
    required this.workspaceRoot,
    required this.databaseUrl,
    String? masterDataPath,
    String? inventoryEntriesPath,
  })  : _masterDataPathOverride = masterDataPath,
        _inventoryEntriesPathOverride = inventoryEntriesPath;

  final String workspaceRoot;
  final String databaseUrl;
  final String? _masterDataPathOverride;
  final String? _inventoryEntriesPathOverride;
  PostgreSQLConnection? _postgres;

  String get _masterDataPath => _masterDataPathOverride ?? p.join(workspaceRoot, 'master_data.json');
  String get _inventoryEntriesPath =>
      _inventoryEntriesPathOverride ?? p.join(workspaceRoot, 'inventory_entries.json');

  Future<void> initialize() async {
    await _initializePostgres();
    await _seedFromJsonIfEmpty();
  }

  Future<void> _initializePostgres() async {
    final uri = Uri.parse(databaseUrl);
    final userInfo = uri.userInfo.split(':');
    final username = userInfo.isNotEmpty ? Uri.decodeComponent(userInfo[0]) : '';
    final password = userInfo.length > 1 ? Uri.decodeComponent(userInfo.sublist(1).join(':')) : '';
    final databaseName = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres';
    final sslMode = (uri.queryParameters['sslmode'] ?? '').toLowerCase();
    final useSSL = sslMode == 'require';

    _postgres = PostgreSQLConnection(
      uri.host,
      uri.hasPort ? uri.port : 5432,
      databaseName,
      username: username,
      password: password,
      useSSL: useSSL,
    );
    await _postgres!.open();

    await _postgres!.execute('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL
      );
    ''');
    await _postgres!.execute('''
      CREATE TABLE IF NOT EXISTS inventory_entries (
        id SERIAL PRIMARY KEY,
        date TEXT NOT NULL,
        item_id INTEGER NOT NULL REFERENCES items(id),
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        remarks TEXT
      );
    ''');
  }

  Future<void> dispose() async {
    await _postgres?.close();
  }

  Future<List<Map<String, Object?>>> getItems() async {
    final result = await _postgres!.query('SELECT id, name FROM items ORDER BY id');
    return result.map((row) => {'id': row[0], 'name': row[1]}).toList();
  }

  Future<Map<String, Object?>> createItem(String name) async {
    final row = await _postgres!.query('SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM items');
    final id = _asInt(row.first[0]);
    await _postgres!.query(
      'INSERT INTO items (id, name) VALUES (@id, @name)',
      substitutionValues: {'id': id, 'name': name},
    );

    return {'id': id, 'name': name};
  }

  Future<List<Map<String, Object?>>> getEntries({int? itemId}) async {
    final query = StringBuffer(
      'SELECT id, date, item_id, item_name, quantity, remarks FROM inventory_entries',
    );
    final pgParams = <String, Object?>{};

    if (itemId != null) {
      query.write(' WHERE item_id = @itemId');
      pgParams['itemId'] = itemId;
    }
    query.write(' ORDER BY date DESC, id DESC');

    final result = await _postgres!.query(
      query.toString(),
      substitutionValues: pgParams.isEmpty ? null : pgParams,
    );
    return result
        .map(
          (row) => {
            'id': row[0],
            'date': row[1],
            'itemId': row[2],
            'itemName': row[3],
            'quantity': row[4],
            'remarks': row[5],
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
    final inserted = await _postgres!.query(
      '''
      INSERT INTO inventory_entries (date, item_id, item_name, quantity, remarks)
      VALUES (@date, @itemId, @itemName, @quantity, @remarks)
      RETURNING id
      ''',
      substitutionValues: {
        'date': entryDate,
        'itemId': itemId,
        'itemName': itemName,
        'quantity': quantity,
        'remarks': remarks,
      },
    );
    final insertedId = _asInt(inserted.first[0]);

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
    final itemRow = await _postgres!.query(
      'SELECT name FROM items WHERE id = @itemId',
      substitutionValues: {'itemId': itemId},
    );
    if (itemRow.isEmpty) {
      return null;
    }
    return itemRow.first[0] as String;
  }

  Future<List<Map<String, Object?>>> aggregateStock() async {
    const aggregateSql = '''
      SELECT item_id AS itemId, item_name AS itemName, SUM(quantity) AS totalQuantity
      FROM inventory_entries
      GROUP BY item_id, item_name
      ORDER BY item_id
    ''';

    final result = await _postgres!.query(aggregateSql);
    return result
        .map(
          (row) => {
            'itemId': row[0],
            'itemName': row[1],
            'totalQuantity': row[2],
          },
        )
        .toList();
  }

  Future<void> replaceAllData({
    required List<dynamic> items,
    required List<dynamic> entries,
  }) async {
    await _postgres!.transaction((ctx) async {
      await ctx.execute('DELETE FROM inventory_entries');
      await ctx.execute('DELETE FROM items');

      for (final item in items) {
        final map = Map<String, dynamic>.from(item as Map);
        await ctx.query(
          'INSERT INTO items (id, name) VALUES (@id, @name)',
          substitutionValues: {'id': map['id'], 'name': map['name']},
        );
      }

      for (final entry in entries) {
        final map = Map<String, dynamic>.from(entry as Map);
        await ctx.query(
          '''
          INSERT INTO inventory_entries (date, item_id, item_name, quantity, remarks)
          VALUES (@date, @itemId, @itemName, @quantity, @remarks)
          ''',
          substitutionValues: {
            'date': map['date'],
            'itemId': map['itemId'],
            'itemName': map['itemName'],
            'quantity': map['quantity'],
            'remarks': map['remarks'],
          },
        );
      }
    });
  }

  Future<void> _seedFromJsonIfEmpty() async {
    final itemCount = _asInt((await _postgres!.query('SELECT COUNT(*) FROM items')).first[0]);
    final entryCount = _asInt((await _postgres!.query('SELECT COUNT(*) FROM inventory_entries')).first[0]);

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

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is BigInt) {
      return value.toInt();
    }
    return int.parse('$value');
  }
}
