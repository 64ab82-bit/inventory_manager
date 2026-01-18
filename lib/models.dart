import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';
import 'package:github/github.dart' as github;
import 'package:http/http.dart' as http;

class Item {
  final int id;
  String name;
  Item({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Item.fromJson(Map<String, dynamic> json) => Item(id: json['id'], name: json['name']);
}

class InventoryEntry {
  final DateTime date;
  final int itemId;
  final String itemName;
  final int quantity;
  final String? remarks;  // 備考フィールドを追加
  InventoryEntry({required this.date, required this.itemId, required this.itemName, required this.quantity, this.remarks});

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'itemId': itemId, 'itemName': itemName, 'quantity': quantity, 'remarks': remarks};
  factory InventoryEntry.fromJson(Map<String, dynamic> json) => InventoryEntry(
        date: DateTime.parse(json['date']),
        itemId: json['itemId'],
        itemName: json['itemName'],
        quantity: json['quantity'],
        remarks: json['remarks'],
      );
}

// マスタデータ
List<Item> masterItems = [];

// 在庫データ
List<InventoryEntry> inventoryEntries = [];

int _nextItemId = 1;

// GitHub API認証
String? _githubToken;
String? _githubUser;
String? _githubRepo;
github.GitHub? _githubClient;

Future<void> setGitHubConfig(String token, String user, String repo) async {
  _githubToken = token;
  _githubUser = user;
  _githubRepo = repo;
  _githubClient = github.GitHub(auth: github.Authentication.withToken(token));

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('github_token', token);
  await prefs.setString('github_user', user);
  await prefs.setString('github_repo', repo);
}

Future<void> initializeGitHubConfig() async {
  final prefs = await SharedPreferences.getInstance();
  _githubToken = prefs.getString('github_token');
  _githubUser = prefs.getString('github_user');
  _githubRepo = prefs.getString('github_repo');

  if (_githubToken != null) {
    _githubClient = github.GitHub(auth: github.Authentication.withToken(_githubToken));
  }
}

bool isGitHubConfigured() => _githubToken != null && _githubUser != null && _githubRepo != null;

// GitHub ユーザーのリポジトリ一覧を取得
Future<List<String>> fetchUserRepositories(String token, String username) async {
  try {
    final client = github.GitHub(auth: github.Authentication.withToken(token));
    final repos = await client.repositories.listUserRepositories(username).toList();
    return repos.map((r) => r.name).toList();
  } catch (e) {
    print('Error fetching repositories: $e');
    return [];
  }
}

int getNextItemId() => _nextItemId++;

// GitHub読み込みエラーメッセージ
String? _gitHubLoadError;
String? getGitHubLoadError() => _gitHubLoadError;
void clearGitHubLoadError() => _gitHubLoadError = null;

// データ読み込み関数（マスタと在庫を別々に読み込み）
Future<void> loadData() async {
  await initializeGitHubConfig();
  _gitHubLoadError = null;

  try {
    if (isGitHubConfigured() && _githubClient != null) {
      // GitHubから読み込み
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);
      
      try {
        // マスタデータを読み込み
        final masterFile = await _githubClient!.repositories.getContents(repoSlug, 'master_data.json');
        if (masterFile.file != null) {
          final encodedContent = (masterFile.file!.content ?? '').replaceAll('\n', '').replaceAll('\r', '');
          final decodedBytes = base64Decode(encodedContent);
          final jsonString = utf8.decode(decodedBytes);
          final data = jsonDecode(jsonString);
          
          final items = data['masterItems'] as List?;
          if (items != null) {
            masterItems = items.map((item) => Item.fromJson(item)).toList();
          }
          final config = data['config'] as Map?;
          if (config != null) {
            _nextItemId = config['nextItemId'] ?? 1;
          }
          print('📖 [loadData] マスタ読み込み完了: ${masterItems.length}件');
        }

        // 在庫データを読み込み
        final inventoryFile = await _githubClient!.repositories.getContents(repoSlug, 'inventory_entries.json');
        if (inventoryFile.file != null) {
          final encodedContent = (inventoryFile.file!.content ?? '').replaceAll('\n', '').replaceAll('\r', '');
          final decodedBytes = base64Decode(encodedContent);
          final jsonString = utf8.decode(decodedBytes);
          final data = jsonDecode(jsonString);
          
          final entries = data['inventoryEntries'] as List?;
          if (entries != null) {
            inventoryEntries = entries.map((entry) => InventoryEntry.fromJson(entry)).toList();
          }
          print('📖 [loadData] 在庫読み込み完了: ${inventoryEntries.length}件');
        }
        return;
      } catch (e) {
        final errorMsg = 'GitHub読み込みエラー: $e';
        _gitHubLoadError = errorMsg;
        rethrow;
      }
    }
  } catch (e) {
    // GitHub load error は無視してローカルにフォールバック
  }

  // GitHub設定がない場合のみ、ローカルから読み込み
  try {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('app_data_json');

    if (jsonString == null) {
      // 初期データはCSVから読み込み
      final csvString = await rootBundle.loadString('assets/data.csv');
      jsonString = _csvToJson(csvString);
    }

    _parseJSON(jsonString);
  } catch (e) {
    // ローカル読み込みエラー（エラー処理不要）
  }
}

String _csvToJson(String csvString) {
  final csvData = const CsvToListConverter().convert(csvString);

  final items = <Map<String, dynamic>>[];
  final entries = <Map<String, dynamic>>[];
  int nextId = 1;

  for (var row in csvData) {
    if (row[0] == 'master' && row.length >= 3) {
      items.add({'id': int.parse(row[1]), 'name': row[2]});
    } else if (row[0] == 'inventory' && row.length >= 5) {
      entries.add({
        'date': row[1],
        'itemId': int.parse(row[2]),
        'itemName': row[3],
        'quantity': int.parse(row[4]),
      });
    } else if (row[0] == 'config' && row[1] == 'nextItemId' && row.length >= 3) {
      nextId = int.parse(row[2]);
    }
  }

  return jsonEncode({
    'masterItems': items,
    'inventoryEntries': entries,
    'config': {'nextItemId': nextId},
  });
}

void _parseJSON(String jsonString) {
  print('📖 [_parseJSON] JSON解析開始');
  final data = jsonDecode(jsonString);

  masterItems.clear();
  inventoryEntries.clear();

  final items = data['masterItems'] as List?;
  if (items != null) {
    masterItems = items.map((item) => Item.fromJson(item)).toList();
  }

  final entries = data['inventoryEntries'] as List?;
  if (entries != null) {
    inventoryEntries = entries.map((entry) => InventoryEntry.fromJson(entry)).toList();
  }

  print('📖 [_parseJSON] 解析完了 - マスタ件数: ${masterItems.length}, 在庫件数: ${inventoryEntries.length}');

  final config = data['config'] as Map?;
  if (config != null) {
    _nextItemId = config['nextItemId'] ?? 1;
  }
}

// データ保存関数（マスタと在庫を別々に保存）
Future<void> saveData() async {
  print('💾 [saveData] マスタ件数: ${masterItems.length}, 在庫件数: ${inventoryEntries.length}');

  // GitHubに保存
  if (isGitHubConfigured() && _githubClient != null) {
    try {
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);

      // マスタデータを保存
      final masterData = {
        'masterItems': masterItems.map((item) => item.toJson()).toList(),
        'config': {'nextItemId': _nextItemId},
      };
      final masterJsonString = jsonEncode(masterData);
      await _saveToGitHub(repoSlug, 'master_data.json', masterJsonString, 'Update master data');
      print('💾 [saveData] マスタ保存完了');

      // 在庫データを保存
      final inventoryData = {
        'inventoryEntries': inventoryEntries.map((entry) => entry.toJson()).toList(),
      };
      final inventoryJsonString = jsonEncode(inventoryData);
      await _saveToGitHub(repoSlug, 'inventory_entries.json', inventoryJsonString, 'Update inventory entries');
      print('💾 [saveData] 在庫保存完了');
    } catch (e) {
      print('GitHub save error: $e');
    }
  }

  // ローカルにも保存（互換性のため統合形式で保存）
  final jsonData = {
    'masterItems': masterItems.map((item) => item.toJson()).toList(),
    'inventoryEntries': inventoryEntries.map((entry) => entry.toJson()).toList(),
    'config': {'nextItemId': _nextItemId},
  };
  final jsonString = jsonEncode(jsonData);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_data_json', jsonString);
}

// GitHubにファイルを保存する共通関数
Future<void> _saveToGitHub(github.RepositorySlug repoSlug, String filePath, String content, String message) async {
  final url = Uri.parse(
    'https://api.github.com/repos/$_githubUser/$_githubRepo/contents/$filePath',
  );

  // 既存ファイルの情報を取得
  String? sha;
  try {
    final existingFile = await _githubClient!.repositories.getContents(repoSlug, filePath);
    if (existingFile.file != null) {
      sha = existingFile.file!.sha;
    }
  } catch (e) {
    // ファイルが存在しない場合は新規作成
  }

  final body = {
    'message': message,
    'content': base64Encode(utf8.encode(content)).toString(),
  };

  if (sha != null) {
    body['sha'] = sha;
  }
  
  final response = await http.put(
    url,
    headers: {
      'Authorization': 'token $_githubToken',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(body),
  );

  if (response.statusCode != 201 && response.statusCode != 200) {
    print('GitHub save failed for $filePath: ${response.statusCode} - ${response.body}');
    throw Exception('Failed to save $filePath');
  }
}