import 'dart:convert';
import 'dart:math' show min;
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

// GitHub読み込みエラーメッセージ
String? _gitHubLoadError;
String? getGitHubLoadError() => _gitHubLoadError;
void clearGitHubLoadError() => _gitHubLoadError = null;

// データ読み込み関数
Future<void> loadData() async {
  await initializeGitHubConfig();
  _gitHubLoadError = null;

  try {
    if (isGitHubConfigured() && _githubClient != null) {
      // GitHubから読み込み（GitHub設定がある場合は必須）
      print('=== GitHub Load Start ===');
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);
      
      try {
        final file = await _githubClient!.repositories.getContents(repoSlug, 'inventory_data.json');

        if (file.file != null) {
          // GitHub APIのcontentはBase64エンコードされているのでデコード
          final encodedContent = file.file!.content ?? '';
          print('Loaded from GitHub - encoded content length: ${encodedContent.length}');
          
          final decodedBytes = base64Decode(encodedContent);
          final jsonString = utf8.decode(decodedBytes);
          final preview = jsonString.substring(0, min(100, jsonString.length));
          print('Decoded JSON string: $preview...');
          
          _parseJSON(jsonString);
          print('✅ Successfully loaded from GitHub');
          return;
        }
      } catch (e) {
        final errorMsg = 'GitHub読み込みエラー: $e';
        print('❌ $errorMsg');
        _gitHubLoadError = errorMsg;
        rethrow; // GitHub設定がある場合は、エラーを上げる
      }
    }
  } catch (e) {
    print('GitHub load error: $e');
  }

  // GitHub設定がない場合のみ、ローカルから読み込み
  try {
    print('Loading from local storage...');
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('app_data_json');

    if (jsonString == null) {
      // 初期データはCSVから読み込み
      print('Loading from CSV...');
      final csvString = await rootBundle.loadString('assets/data.csv');
      jsonString = _csvToJson(csvString);
    }

    _parseJSON(jsonString);
    print('✅ Successfully loaded from local storage');
  } catch (e) {
    print('❌ Local load error: $e');
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
    print('=== GitHub Save Start ===');
    print('User: $_githubUser, Repo: $_githubRepo');
    try {
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);
      final filePath = 'inventory_data.json';

      // GitHubにファイルを保存（PUT リクエストを使用）
      final url = Uri.parse(
        'https://api.github.com/repos/$_githubUser/$_githubRepo/contents/$filePath',
      );
      print('URL: $url');

      // 既存ファイルの情報を取得
      String? sha;
      try {
        final existingFile = await _githubClient!.repositories.getContents(repoSlug, filePath);
        if (existingFile.file != null) {
          sha = existingFile.file!.sha;
          print('Found existing file, SHA: $sha');
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

      print('Sending PUT request...');
      print('Headers: Authorization: token ${_githubToken?.substring(0, 10)}***');
      
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'token $_githubToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      print('Response Status: ${response.statusCode}');
      final bodyPreview = response.body.length > 200 
        ? response.body.substring(0, 200) 
        : response.body;
      print('Response Body: $bodyPreview');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ GitHub save successful!');
      } else {
        print('❌ GitHub save failed: ${response.statusCode}');
        print('Full response: ${response.body}');
      }
    } catch (e) {
      print('❌ GitHub save error: $e');
      print(e);
    }
    print('=== GitHub Save End ===');
  } else {
    print('⚠️  GitHub not configured - saving to local only');
  }

  // ローカルにも保存
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_data_json', jsonString);
}