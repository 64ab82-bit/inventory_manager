// JSON形式のデータを扱うためのライブラリ
import 'dart:async';
import 'dart:convert';
// Flutterの基盤機能（debugPrint等）を使うためのライブラリ
import 'package:flutter/foundation.dart';
// デバイスのローカルストレージにデータを保存するためのライブラリ
import 'package:shared_preferences/shared_preferences.dart';
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

// APIの接続先URL（必要ならSharedPreferencesで上書き）
String _apiBaseUrl = 'http://127.0.0.1:8080';
String _apiKey = '';

// ==== GitHub API 認証情報 ====
// GitHub Personal Access Token（認証用のトークン）
String? _githubToken;
// GitHubユーザー名
String? _githubUser;
// GitHubリポジトリ名
String? _githubRepo;

// GitHub設定を保存する関数
Future<void> setGitHubConfig(String token, String user, String repo) async {
  // 受け取った値を変数に保存
  _githubToken = token;
  _githubUser = user;
  _githubRepo = repo;
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
  _apiBaseUrl = prefs.getString('api_base_url') ?? _apiBaseUrl;
  _apiKey = prefs.getString('api_key') ?? '';

}

// GitHub設定が完了しているか確認する関数
bool isGitHubConfigured() => _githubToken != null && _githubUser != null && _githubRepo != null;

// APIの接続先URLを保存する関数
Future<void> setApiBaseUrl(String baseUrl) async {
  _apiBaseUrl = baseUrl.trim();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('api_base_url', _apiBaseUrl);
}

Future<void> setApiKey(String apiKey) async {
  _apiKey = apiKey.trim();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('api_key', _apiKey);
}

String getApiBaseUrl() => _apiBaseUrl;
String getApiKey() => _apiKey;

Map<String, String> _apiHeaders({bool includeJsonContentType = false}) {
  final headers = <String, String>{};
  if (includeJsonContentType) {
    headers['Content-Type'] = 'application/json';
  }
  if (_apiKey.isNotEmpty) {
    headers['X-Api-Key'] = _apiKey;
  }
  return headers;
}

class ApiConnectionTestResult {
  final bool ok;
  final String message;

  ApiConnectionTestResult({required this.ok, required this.message});
}

Future<ApiConnectionTestResult> testApiConnection(String baseUrl, {String? apiKey}) async {
  final normalizedBaseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse('$normalizedBaseUrl/health');

  if (normalizedBaseUrl.isEmpty || uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return ApiConnectionTestResult(
      ok: false,
      message: 'URL形式が不正です（例: http://127.0.0.1:8080）',
    );
  }

  try {
    final headers = <String, String>{};
    final key = (apiKey ?? _apiKey).trim();
    if (key.isNotEmpty) {
      headers['X-Api-Key'] = key;
    }

    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      return ApiConnectionTestResult(
        ok: false,
        message: '接続失敗: HTTP ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'ok') {
      return ApiConnectionTestResult(
        ok: false,
        message: '接続失敗: /health の応答形式が想定外です',
      );
    }

    return ApiConnectionTestResult(
      ok: true,
      message: '接続テスト成功: APIに到達できました',
    );
  } on TimeoutException {
    return ApiConnectionTestResult(
      ok: false,
      message: '接続失敗: タイムアウトしました（3秒）',
    );
  } on FormatException {
    return ApiConnectionTestResult(
      ok: false,
      message: '接続失敗: レスポンスJSONの解析に失敗しました',
    );
  } on http.ClientException catch (e) {
    return ApiConnectionTestResult(
      ok: false,
      message: '接続失敗: ${e.message}',
    );
  } catch (e) {
    return ApiConnectionTestResult(
      ok: false,
      message: '接続失敗: $e',
    );
  }
}

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
// マスタデータと在庫データをAPIから読み込む
Future<void> loadData() async {
  await initializeGitHubConfig();
  _gitHubLoadError = null;

  try {
    final itemsResponse = await http.get(
      Uri.parse('$_apiBaseUrl/items'),
      headers: _apiHeaders(),
    );
    if (itemsResponse.statusCode != 200) {
      throw Exception('items取得失敗: ${itemsResponse.statusCode}');
    }

    final entriesResponse = await http.get(
      Uri.parse('$_apiBaseUrl/entries'),
      headers: _apiHeaders(),
    );
    if (entriesResponse.statusCode != 200) {
      throw Exception('entries取得失敗: ${entriesResponse.statusCode}');
    }

    final itemsJson = jsonDecode(itemsResponse.body) as Map<String, dynamic>;
    final entriesJson = jsonDecode(entriesResponse.body) as Map<String, dynamic>;

    final items = (itemsJson['items'] as List?) ?? const [];
    final entries = (entriesJson['entries'] as List?) ?? const [];

    masterItems = items
        .map((item) => Item.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    inventoryEntries = entries
        .map((entry) => InventoryEntry.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();

    if (masterItems.isEmpty) {
      _nextItemId = 1;
    } else {
      final maxId = masterItems.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      _nextItemId = maxId + 1;
    }

    debugPrint('📖 [loadData] API読み込み完了 - マスタ: ${masterItems.length}件, 在庫: ${inventoryEntries.length}件');
  } catch (e) {
    _gitHubLoadError = 'API読み込みエラー: $e';
    debugPrint(_gitHubLoadError);
    masterItems = [];
    inventoryEntries = [];
    _nextItemId = 1;
  }
}

// ==== データ保存関数 ====
// マスタデータと在庫データをAPIに同期
Future<void> saveData() async {
  debugPrint('💾 [saveData] マスタ件数: ${masterItems.length}, 在庫件数: ${inventoryEntries.length}');

  final payload = {
    'masterItems': masterItems.map((item) => item.toJson()).toList(),
    'inventoryEntries': inventoryEntries.map((entry) => entry.toJson()).toList(),
    'config': {'nextItemId': _nextItemId},
  };

  final response = await http.post(
    Uri.parse('$_apiBaseUrl/sync'),
    headers: _apiHeaders(includeJsonContentType: true),
    body: jsonEncode(payload),
  );

  if (response.statusCode != 200) {
    throw Exception('API保存失敗: ${response.statusCode} ${response.body}');
  }
}