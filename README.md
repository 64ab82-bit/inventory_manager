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

## Inventory API (JSON -> SQLite)

`master_data.json` と `inventory_entries.json` の内容を SQLite に移行し、
HTTP API で参照・登録できるバックエンドを `backend/` に追加しています。

### 起動手順

1. `cd backend`
2. `dart pub get`
3. `dart run bin/server.dart`

起動後: `http://127.0.0.1:8080`

### DBファイル

- `backend/inventory.db`
- 初回起動時のみ、JSONファイルから自動投入します（既存データがある場合は投入しません）

### API

- `GET /health`
- `GET /items`
- `POST /items` body: `{ "name": "MF_Pikachu" }`
- `GET /entries?itemId=1` (`itemId` は任意)
- `POST /entries` body: `{ "itemId": 1, "quantity": 5, "remarks": "memo" }`
- `GET /aggregate`
- `POST /sync` body: `{ "masterItems": [...], "inventoryEntries": [...], "config": { "nextItemId": 5 } }`

Flutterアプリの `loadData()/saveData()` はこのAPIを利用するように変更済みです。
設定画面では API URL の保存前に「接続テスト」で `/health` 疎通確認ができます。

### 本番公開向け設定（公開URLで利用）

`backend/.env.example` を参考に、環境変数を設定してください。

- `HOST` (デフォルト: `0.0.0.0`)
- `PORT` (デフォルト: `8080`)
- `API_KEY` (任意: 設定すると `/health` 以外に `X-Api-Key` が必須)
- `CORS_ALLOWED_ORIGINS` (任意: `https://a.com,https://b.com` のように指定)

`API_KEY` 未設定時は認証なしでアクセス可能です（公開運用では設定推奨）。

### デプロイ例（Render / Railway / Fly など）

1. `backend/` をデプロイ対象にする
2. Start Command を `dart run bin/server.dart` に設定
3. Environment Variables に `PORT`, `API_KEY`, `CORS_ALLOWED_ORIGINS` を設定
4. Flutter側の設定画面で API URL を公開URLに変更

### Flutter側設定（公開URLに接続）

メニュー > 設定 で以下を設定します。

- `API Base URL`: 例 `https://your-api.example.com`
- `API Key（任意）`: サーバーで `API_KEY` を設定した場合のみ入力

その後「接続テスト」で疎通確認し、保存してください。

注意: 現在DBは `backend/inventory.db` (SQLiteローカルファイル) なので、単一インスタンス前提です。
複数台・高可用性が必要なら PostgreSQL などの外部DBへ移行してください。

### Renderで公開URLを発行する手順（このリポジトリ対応済み）

このリポジトリには以下を追加済みです。

- `render.yaml`（Web Service + 永続ディスク設定）
- `backend/Dockerfile`
- `backend/.dockerignore`
- `backend/.env.example`

手順:

1. GitHubにこのリポジトリをpush
2. Renderで「Blueprint」作成時にリポジトリを選択（`render.yaml` を自動認識）
3. 環境変数を設定
	- `API_KEY`（推奨）
	- `CORS_ALLOWED_ORIGINS`（Flutter Webを使う場合は公開元URLを指定）
4. デプロイ完了後、`https://<your-service>.onrender.com/health` が `{"status":"ok"}` を返すことを確認
5. Flutterアプリの設定画面で
	- `API Base URL` に公開URLを入力
	- `API Key（任意）` に `API_KEY` を入力
	- 「接続テスト」→「保存」

補足:

- `DB_PATH` は `render.yaml` で `/data/inventory.db` に設定済み（永続ディスク）
- 初回のみJSONシードを使いたい場合は `MASTER_DATA_PATH` と `INVENTORY_ENTRIES_PATH` を設定
