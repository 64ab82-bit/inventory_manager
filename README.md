# flutter_application_2

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Inventory API (SQL Server)

Microsoft SQL Server に保存し、HTTP API で参照・登録できるバックエンドを `backend/` に追加しています。

### 起動手順

1. `cd backend`
2. `dart pub get`
3. 環境変数を設定（下記）
4. `dart run bin/server.dart`

起動後: `http://127.0.0.1:8080`

### 必須環境変数

- `MSSQL_HOST` 例: `192.168.10.50`
- `MSSQL_PORT` 例: `1433`
- `MSSQL_DATABASE` 例: `inventory_manager`
- `MSSQL_USER` 例: `sa`
- `MSSQL_PASSWORD`

任意:

- `HOST` (デフォルト: `0.0.0.0`)
- `PORT` (デフォルト: `8080`)
- `API_KEY` (設定すると `/health` 以外に `X-Api-Key` が必須)
- `CORS_ALLOWED_ORIGINS` (例: `https://a.com,https://b.com`)
- `MASTER_DATA_PATH`, `INVENTORY_ENTRIES_PATH`（初期JSONシードを別パスに置く場合）

### API

- `GET /health`
- `GET /items`
- `POST /items` body: `{ "name": "MF_Pikachu" }`
- `GET /entries?itemId=1` (`itemId` は任意)
- `POST /entries` body: `{ "itemId": 1, "quantity": 5, "remarks": "memo" }`
- `GET /aggregate`
- `POST /sync` body: `{ "masterItems": [...], "inventoryEntries": [...], "config": { "nextItemId": 5 } }`

Flutterアプリの `loadData()/saveData()` はこのAPIを利用します。
設定画面で `API Base URL` と `API Key`（設定した場合）を入力し、`接続テスト` → `保存` してください。

### Windows 常時起動運用（無料運用向け）

1. 常時起動PCにこのリポジトリ（最低 `backend/`）を配置
2. タスクスケジューラでログオン時に `dart run bin/server.dart` を起動
3. 必要に応じて `cloudflared tunnel --url http://localhost:8080` を別タスクで常時起動
4. Flutter側の `API Base URL` に公開URLを設定
