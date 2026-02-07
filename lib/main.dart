// Flutter UIフレームワークのコアライブラリをインポート
import 'package:flutter/material.dart';
// メニュー画面のファイルをインポート
import 'package:inventory_manager/screens/menu_screen.dart';
// データモデル（アイテムや在庫情報）のファイルをインポート
import 'package:inventory_manager/models.dart';

// アプリケーションのエントリーポイント（最初に実行される関数）
void main() async {
  // Flutterの初期化を確実に行う（非同期処理を使う前に必須）
  WidgetsFlutterBinding.ensureInitialized();
  // データを読み込む（GitHub または ローカルストレージから）
  await loadData();
  // アプリケーションを起動
  runApp(const MyApp());
}

// アプリケーションのルートウィジェット（状態を持たないウィジェット）
class MyApp extends StatelessWidget {
  // コンストラクタ（ウィジェットを作成するときに呼ばれる）
  const MyApp({super.key});

  // UIを構築するメソッド
  @override
  Widget build(BuildContext context) {
    // MaterialAppウィジェット：アプリ全体の設定を行う
    return MaterialApp(
      title: '在庫管理システム', // アプリのタイトル
      theme: ThemeData(primarySwatch: Colors.blue), // アプリ全体のテーマ色を青に設定
      home: const MenuScreen(), // 最初に表示する画面（メニュー画面）
    );
  }
}
