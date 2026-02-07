// JSON形式のデータを扱うためのライブラリ
import 'dart:convert';
// Flutterの基盤機能（debugPrint等）を使うためのライブラリ
import 'package:flutter/foundation.dart';
// アプリに含まれるファイル（assets）を読み込むためのライブラリ
import 'package:flutter/services.dart';
// デバイスのローカルストレージにデータを保存するためのライブラリ
import 'package:shared_preferences/shared_preferences.dart';
// CSVファイルを読み書きするためのライブラリ
import 'package:csv/csv.dart';
// GitHub APIを使うためのライブラリ（github という名前で参照）
import 'package:github/github.dart' as github;
// HTTP通信を行うためのライブラリ（http という名前で参照）
import 'package:http/http.dart' as http;

// アイテム（商品）を表すクラス
class Item {
  final int id;       // アイテムの一意なID（変更不可）
  String name;        // アイテムの名前（変更可能）
  
  // コンストラクタ：新しいアイテムを作成するときに呼ばれる
  Item({required this.id, required this.name});

  // このアイテムをJSON形式（保存用のデータ形式）に変換
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  
  // JSON形式からアイテムを作成（復元）
  factory Item.fromJson(Map<String, dynamic> json) => Item(id: json['id'], name: json['name']);
}

// 在庫の入力履歴を表すクラス
class InventoryEntry {
  final DateTime date;       // 入力した日時
  final int itemId;          // どのアイテムか（アイテムのID）
  final String itemName;     // アイテム名（表示用に保持）
  final int quantity;        // 数量
  final String? remarks;     // 備考（オプション：null の場合もある）
  
  // コンストラクタ：新しい在庫履歴を作成するときに呼ばれる
  InventoryEntry({required this.date, required this.itemId, required this.itemName, required this.quantity, this.remarks});

  // この在庫履歴をJSON形式に変換
  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'itemId': itemId, 'itemName': itemName, 'quantity': quantity, 'remarks': remarks};
  
  // JSON形式から在庫履歴を作成（復元）
  factory InventoryEntry.fromJson(Map<String, dynamic> json) => InventoryEntry(
        date: DateTime.parse(json['date']),
        itemId: json['itemId'],
        itemName: json['itemName'],
        quantity: json['quantity'],
        remarks: json['remarks'],
      );
}

// マスタデータ：すべてのアイテムを保持するリスト
List<Item> masterItems = [];

// 在庫データ：すべての在庫入力履歴を保持するリスト
List<InventoryEntry> inventoryEntries = [];

// 次に作成するアイテムのID（重複を避けるためにカウントアップする）
int _nextItemId = 1;

// ==== GitHub API 認証情報 ====
// GitHub Personal Access Token（認証用のトークン）
String? _githubToken;
// GitHubユーザー名
String? _githubUser;
// GitHubリポジトリ名
String? _githubRepo;
// GitHubクライアント（APIを呼び出すためのオブジェクト）
github.GitHub? _githubClient;

// GitHub設定を保存する関数
Future<void> setGitHubConfig(String token, String user, String repo) async {
  // 受け取った値を変数に保存
  _githubToken = token;
  _githubUser = user;
  _githubRepo = repo;
  // トークンを使ってGitHubクライアントを作成
  _githubClient = github.GitHub(auth: github.Authentication.withToken(token));

  // デバイスのローカルストレージにも保存（次回起動時に読み込むため）
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('github_token', token);
  await prefs.setString('github_user', user);
  await prefs.setString('github_repo', repo);
}

// アプリ起動時にGitHub設定を読み込む関数
Future<void> initializeGitHubConfig() async {
  // ローカルストレージから設定を取得
  final prefs = await SharedPreferences.getInstance();
  _githubToken = prefs.getString('github_token');
  _githubUser = prefs.getString('github_user');
  _githubRepo = prefs.getString('github_repo');

  // トークンが保存されていれば、GitHubクライアントを作成
  if (_githubToken != null) {
    _githubClient = github.GitHub(auth: github.Authentication.withToken(_githubToken));
  }
}

// GitHub設定が完了しているか確認する関数
bool isGitHubConfigured() => _githubToken != null && _githubUser != null && _githubRepo != null;

// 指定したGitHubユーザーのリポジトリ一覧を取得する関数
Future<List<String>> fetchUserRepositories(String token, String username) async {
  try {
    // トークンで認証したGitHubクライアントを作成
    final client = github.GitHub(auth: github.Authentication.withToken(token));
    // ユーザーのリポジトリ一覧を取得
    final repos = await client.repositories.listUserRepositories(username).toList();
    // リポジトリ名のリストを返す
    return repos.map((r) => r.name).toList();
  } catch (e) {
    // エラーが発生した場合はコンソールに表示
    debugPrint('Error fetching repositories: $e');
    // 空のリストを返す
    return [];
  }
}

// 次のアイテムIDを取得して、カウンタを増やす関数
int getNextItemId() => _nextItemId++;

// GitHub読み込みエラーメッセージを保持する変数
String? _gitHubLoadError;
// エラーメッセージを取得する関数
String? getGitHubLoadError() => _gitHubLoadError;
// エラーメッセージをクリアする関数
void clearGitHubLoadError() => _gitHubLoadError = null;

// ==== データ読み込み関数 ====
// マスタデータと在庫データをGitHubまたはローカルから読み込む
Future<void> loadData() async {
  // GitHub設定を初期化（ローカルストレージから読み込む）
  await initializeGitHubConfig();
  // エラーメッセージをクリア
  _gitHubLoadError = null;

  try {
    // GitHub設定が完了している場合
    if (isGitHubConfigured() && _githubClient != null) {
      // GitHubから読み込む
      // リポジトリを特定するための情報（ユーザー名/リポジトリ名）
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);
      
      try {
        // ==== マスタデータを読み込み ====
        // GitHubから master_data.json ファイルの内容を取得
        final masterFile = await _githubClient!.repositories.getContents(repoSlug, 'master_data.json');
        if (masterFile.file != null) {
          // ファイルの内容はBase64でエンコードされているので、改行を削除
          final encodedContent = (masterFile.file!.content ?? '').replaceAll('\n', '').replaceAll('\r', '');
          // Base64でデコードしてバイト列に変換
          final decodedBytes = base64Decode(encodedContent);
          // バイト列をUTF-8文字列に変換
          final jsonString = utf8.decode(decodedBytes);
          // JSON文字列をデータ構造に変換
          final data = jsonDecode(jsonString);
          
          // マスタアイテムのリストを取得
          final items = data['masterItems'] as List?;
          if (items != null) {
            // 各アイテムをItemオブジェクトに変換して保存
            masterItems = items.map((item) => Item.fromJson(item)).toList();
          }
          // 設定情報（次のIDなど）を取得
          final config = data['config'] as Map?;
          if (config != null) {
            _nextItemId = config['nextItemId'] ?? 1;
          }
          debugPrint('📖 [loadData] マスタ読み込み完了: ${masterItems.length}件');
        }

        // ==== 在庫データを読み込み ====
        // GitHubから inventory_entries.json ファイルの内容を取得
        final inventoryFile = await _githubClient!.repositories.getContents(repoSlug, 'inventory_entries.json');
        if (inventoryFile.file != null) {
          // ファイルの内容をデコード（マスタと同様の手順）
          final encodedContent = (inventoryFile.file!.content ?? '').replaceAll('\n', '').replaceAll('\r', '');
          final decodedBytes = base64Decode(encodedContent);
          final jsonString = utf8.decode(decodedBytes);
          final data = jsonDecode(jsonString);
          
          // 在庫履歴のリストを取得
          final entries = data['inventoryEntries'] as List?;
          if (entries != null) {
            // 各履歴をInventoryEntryオブジェクトに変換して保存
            inventoryEntries = entries.map((entry) => InventoryEntry.fromJson(entry)).toList();
          }
          debugPrint('📖 [loadData] 在庫読み込み完了: ${inventoryEntries.length}件');
        }
        return;  // GitHubからの読み込みが成功したので終了
      } catch (e) {
        // GitHub読み込みエラーをメッセージに保存
        final errorMsg = 'GitHub読み込みエラー: $e';
        _gitHubLoadError = errorMsg;
        rethrow;  // エラーを上位に伝える
      }
    }
  } catch (e) {
    // GitHub読み込みエラーは無視してローカルにフォールバック
  }

  // ==== ローカルストレージから読み込み ====
  // GitHub設定がない場合、ローカルデータを使用
  try {
    // SharedPreferencesを取得（デバイス内のデータ保存場所）
    final prefs = await SharedPreferences.getInstance();
    // 保存済みのJSONデータを読み込む
    String? jsonString = prefs.getString('app_data_json');

    if (jsonString == null) {
      // 保存データがない場合は、初期データをCSVファイルから読み込む
      final csvString = await rootBundle.loadString('assets/data.csv');
      // CSVをJSON形式に変換
      jsonString = _csvToJson(csvString);
    }

    // JSONデータをパースしてメモリに展開
    _parseJSON(jsonString);
  } catch (e) {
    // ローカル読み込みエラー（エラー処理不要）
  }
}

// CSVデータをJSON形式に変換する関数
String _csvToJson(String csvString) {
  // CSVデータを行ごとに分割してリスト化
  final csvData = const CsvToListConverter().convert(csvString);

  // マスタアイテムと在庫履歴を格納するリスト
  final items = <Map<String, dynamic>>[];
  final entries = <Map<String, dynamic>>[];
  int nextId = 1;

  // CSVの各行を処理
  for (var row in csvData) {
    if (row[0] == 'master' && row.length >= 3) {
      // 'master'で始まる行はマスタアイテム
      items.add({'id': int.parse(row[1]), 'name': row[2]});
    } else if (row[0] == 'inventory' && row.length >= 5) {
      // 'inventory'で始まる行は在庫履歴
      entries.add({
        'date': row[1],
        'itemId': int.parse(row[2]),
        'itemName': row[3],
        'quantity': int.parse(row[4]),
      });
    } else if (row[0] == 'config' && row[1] == 'nextItemId' && row.length >= 3) {
      // 'config'行は設定情報（次のIDなど）
      nextId = int.parse(row[2]);
    }
  }

  // 集めたデータをJSON形式に変換して返す
  return jsonEncode({
    'masterItems': items,
    'inventoryEntries': entries,
    'config': {'nextItemId': nextId},
  });
}

// JSON文字列をパースしてメモリ上のデータに展開する関数
void _parseJSON(String jsonString) {
  debugPrint('📖 [_parseJSON] JSON解析開始');
  // JSON文字列をデータ構造に変換
  final data = jsonDecode(jsonString);

  // 既存のデータをクリア
  masterItems.clear();
  inventoryEntries.clear();

  // マスタアイテムを読み込む
  final items = data['masterItems'] as List?;
  if (items != null) {
    // 各アイテムをItemオブジェクトに変換
    masterItems = items.map((item) => Item.fromJson(item)).toList();
  }

  // 在庫履歴を読み込む
  final entries = data['inventoryEntries'] as List?;
  if (entries != null) {
    // 各履歴をInventoryEntryオブジェクトに変換
    inventoryEntries = entries.map((entry) => InventoryEntry.fromJson(entry)).toList();
  }

  debugPrint('📖 [_parseJSON] 解析完了 - マスタ件数: ${masterItems.length}, 在庫件数: ${inventoryEntries.length}');

  // 設定情報を読み込む
  final config = data['config'] as Map?;
  if (config != null) {
    _nextItemId = config['nextItemId'] ?? 1;  // 次のIDを取得（なければ1をデフォルトに）
  }
}

// ==== データ保存関数 ====
// マスタデータと在庫データをGitHubとローカルに保存
Future<void> saveData() async {
  debugPrint('💾 [saveData] マスタ件数: ${masterItems.length}, 在庫件数: ${inventoryEntries.length}');

  // ==== GitHubに保存 ====
  if (isGitHubConfigured() && _githubClient != null) {
    try {
      // リポジトリ情報を作成
      final repoSlug = github.RepositorySlug(_githubUser!, _githubRepo!);

      // マスタデータを保存
      final masterData = {
        'masterItems': masterItems.map((item) => item.toJson()).toList(),
        'config': {'nextItemId': _nextItemId},
      };
      // データをJSON文字列に変換
      final masterJsonString = jsonEncode(masterData);
      // GitHubに master_data.json として保存
      await _saveToGitHub(repoSlug, 'master_data.json', masterJsonString, 'Update master data');
      debugPrint('💾 [saveData] マスタ保存完了');

      // 在庫データを保存
      final inventoryData = {
        'inventoryEntries': inventoryEntries.map((entry) => entry.toJson()).toList(),
      };
      // データをJSON文字列に変換
      final inventoryJsonString = jsonEncode(inventoryData);
      // GitHubに inventory_entries.json として保存
      await _saveToGitHub(repoSlug, 'inventory_entries.json', inventoryJsonString, 'Update inventory entries');
      debugPrint('💾 [saveData] 在庫保存完了');
    } catch (e) {
      debugPrint('GitHub save error: $e');
    }
  }

  // ==== ローカルストレージにも保存 ====
  // (互換性のため統合形式で保存)
  final jsonData = {
    'masterItems': masterItems.map((item) => item.toJson()).toList(),
    'inventoryEntries': inventoryEntries.map((entry) => entry.toJson()).toList(),
    'config': {'nextItemId': _nextItemId},
  };
  // データをJSON文字列に変換
  final jsonString = jsonEncode(jsonData);
  // SharedPreferencesに保存
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
    debugPrint('GitHub save failed for $filePath: ${response.statusCode} - ${response.body}');
    throw Exception('Failed to save $filePath');
  }
}