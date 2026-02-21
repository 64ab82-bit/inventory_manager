import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inventory_manager/screens/inventory_screen.dart';
import 'package:inventory_manager/screens/master_maintenance_screen.dart';
import 'package:inventory_manager/screens/aggregate_screen.dart';
import 'package:inventory_manager/models.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final TextEditingController _apiBaseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  bool _testingConnection = false;

  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _initializeSettings() async {
    await initializeGitHubConfig();
    _apiBaseUrlController.text = getApiBaseUrl();
    _apiKeyController.text = getApiKey();

    final errorMsg = getGitHubLoadError();
    if (errorMsg != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      });
    }
  }

  void _showApiSetup() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('API接続設定'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('バックエンドAPIのURLを入力してください', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _apiBaseUrlController,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'http://127.0.0.1:8080',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste),
                        tooltip: 'クリップボードから貼り付け',
                        onPressed: () async {
                          final clipboardData = await Clipboard.getData('text/plain');
                          if (!mounted) return;
                          if (clipboardData != null && clipboardData.text != null) {
                            _apiBaseUrlController.text = clipboardData.text!;
                            setDialogState(() {});
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('URLを貼り付けました'), duration: Duration(milliseconds: 500)),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'API Key（任意）',
                      hintText: 'サーバーでAPI_KEY設定時のみ入力',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste),
                        tooltip: 'クリップボードから貼り付け',
                        onPressed: () async {
                          final clipboardData = await Clipboard.getData('text/plain');
                          if (!mounted) return;
                          if (clipboardData != null && clipboardData.text != null) {
                            _apiKeyController.text = clipboardData.text!;
                            setDialogState(() {});
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('APIキーを貼り付けました'), duration: Duration(milliseconds: 500)),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_apiBaseUrlController.text.trim().isEmpty || _testingConnection)
                          ? null
                          : () async {
                              setDialogState(() => _testingConnection = true);
                              final result = await testApiConnection(
                                _apiBaseUrlController.text,
                                apiKey: _apiKeyController.text,
                              );
                              if (!mounted) return;
                              setDialogState(() => _testingConnection = false);
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(result.message),
                                ),
                              );
                            },
                      icon: _testingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('接続テスト'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: _apiBaseUrlController.text.trim().isEmpty
                ? null
                : () async {
                  try {
                    await setApiBaseUrl(_apiBaseUrlController.text);
                    await setApiKey(_apiKeyController.text);
                    await loadData();
                    clearGitHubLoadError();
                    if (!mounted) return;
                    Navigator.of(this.context).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('API設定を保存しました')),
                    );
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('API接続に失敗しました。URLとサーバー起動を確認してください。')),
                    );
                  }
                },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('メニュー')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('在庫管理システム', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            //const Text('サンプルデータで機能を試せます', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cross = width >= 600 ? 4 : 2; // show 4 columns on wide screens
                  return GridView.count(
                    crossAxisCount: cross,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                    children: [
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryScreen())),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(radius: 10, backgroundColor: Colors.blue, child: const Icon(Icons.playlist_add_check, size: 10, color: Colors.white)),
                                const SizedBox(height: 6),
                                const Text('在庫入力', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 2),
                                const Text('日付・アイテム・数量を登録', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AggregateScreen(initialStart: DateTime.now().subtract(const Duration(days: 7)), initialEnd: DateTime.now()))),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(radius: 10, backgroundColor: Colors.teal, child: const Icon(Icons.calculate, size: 10, color: Colors.white)),
                                const SizedBox(height: 6),
                                const Text('集計', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 2),
                                const Text('期間を指定して集計', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MasterMaintenanceScreen())),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(radius: 10, backgroundColor: Colors.orange, child: const Icon(Icons.settings, size: 10, color: Colors.white)),
                                const SizedBox(height: 6),
                                const Text('マスタ管理', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 2),
                                const Text('アイテムの追加/編集/削除', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _showApiSetup,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(radius: 10, backgroundColor: Colors.purple, child: const Icon(Icons.cloud_sync, size: 10, color: Colors.white)),
                                const SizedBox(height: 6),
                                const Text('設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 2),
                                const Text('API接続先を登録', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),

    );
  }
}