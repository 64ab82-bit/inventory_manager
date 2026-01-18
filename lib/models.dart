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
  InventoryEntry({required this.date, required this.itemId, required this.itemName, required this.quantity});

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'itemId': itemId, 'itemName': itemName, 'quantity': quantity};
  factory InventoryEntry.fromJson(Map<String, dynamic> json) => InventoryEntry(
        date: DateTime.parse(json['date']),
        itemId: json['itemId'],
        itemName: json['itemName'],
        quantity: json['quantity'],
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

int getNextItemId() => _nextItemId++;

// データ読み込み関数
Future<void> loadData() async {
  await initializeGitHubConfig();

  try {
    if (isGitHubConfigured() && _githubClient != null) {
      // GitHubから読み込み
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);
      final file = await _githubClient!.repositories.getContents(repoSlug, 'inventory_data.json');

      if (file.file != null) {
        final jsonString = file.file!.content ?? '';
        _parseJSON(jsonString);
        return;
      }
    }
  } catch (e) {
    print('GitHub load error: $e');
  }

  // GitHubが使えない場合、ローカルから読み込み
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
    print('Local load error: $e');
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

  final config = data['config'] as Map?;
  if (config != null) {
    _nextItemId = config['nextItemId'] ?? 1;
  }
}

// データ保存関数
Future<void> saveData() async {
  final jsonData = {
    'masterItems': masterItems.map((item) => item.toJson()).toList(),
    'inventoryEntries': inventoryEntries.map((entry) => entry.toJson()).toList(),
    'config': {'nextItemId': _nextItemId},
  };

  final jsonString = jsonEncode(jsonData);

  // GitHubに保存
  if (isGitHubConfigured() && _githubClient != null) {
    try {
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);
      final filePath = 'inventory_data.json';

      // GitHubにファイルを保存（PUT リクエストを使用）
      // 注: github パッケージは高レベルAPIなため、直接HTTPで対応
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
        print('File does not exist yet: $e');
      }

      final body = {
        'message': sha != null ? 'Update inventory data' : 'Initial inventory data',
        'content': base64Encode(utf8.encode(jsonString)).toString(),
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

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('GitHub save successful: ${response.statusCode}');
      } else {
        print('GitHub save failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('GitHub save error: $e');
    }
  }

  // ローカルにも保存
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_data_json', jsonString);
}