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
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  String? _selectedRepo;
  List<String> _availableRepos = [];
  bool _loadingRepos = false;

  @override
  void initState() {
    super.initState();
    _checkGitHubSetup();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _userController.dispose();
    super.dispose();
  }

  void _checkGitHubSetup() {
    if (!isGitHubConfigured()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GitHubの接続先設定が未完了です。'),
            duration: Duration(seconds: 3),
          ),
        );
      });
    } else {
      // GitHub設定がある場合、読み込みエラーを確認
      final errorMsg = getGitHubLoadError();
      if (errorMsg != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('⚠️ GitHub読み込みエラー'),
              content: Text(errorMsg),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
                ElevatedButton(
                  onPressed: () {
                    clearGitHubLoadError();
                    Navigator.pop(context);
                    _showGitHubSetup();
                  },
                  child: const Text('設定を変更'),
                ),
              ],
            ),
          );
        });
      }
    }
  }

  void _showGitHubSetup() {
    _selectedRepo = null;
    _availableRepos = [];
    bool obscureToken = true;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('データ取得設定'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('GitHub APIの認証情報を入力してください', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  
                  // トークン入力（ペースト対応 + 表示/非表示）
                  TextField(
                    controller: _tokenController,
                    obscureText: obscureToken,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Personal Access Token',
                      hintText: 'ghp_で始まる文字列',
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(obscureToken ? Icons.visibility : Icons.visibility_off),
                            tooltip: obscureToken ? '表示' : '非表示',
                            onPressed: () {
                              setDialogState(() => obscureToken = !obscureToken);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.paste),
                            tooltip: 'クリップボードから貼り付け',
                            onPressed: () async {
                              final clipboardData = await Clipboard.getData('text/plain');
                              if (clipboardData != null && clipboardData.text != null) {
                                _tokenController.text = clipboardData.text!;
                                setDialogState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('トークンを貼り付けました'), duration: Duration(milliseconds: 500)),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // ユーザー名入力（ペースト対応）
                  TextField(
                    controller: _userController,
                    onChanged: (_) => setDialogState(() {}),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'GitHubユーザー名',
                      hintText: 'あなたのユーザー名',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste),
                        tooltip: 'クリップボードから貼り付け',
                        onPressed: () async {
                          final clipboardData = await Clipboard.getData('text/plain');
                          if (clipboardData != null && clipboardData.text != null) {
                            _userController.text = clipboardData.text!;
                            setDialogState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ユーザー名を貼り付けました'), duration: Duration(milliseconds: 500)),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // リポジトリ取得ボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _loadingRepos ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                      label: const Text('リポジトリを読み込み'),
                      onPressed: (_tokenController.text.isEmpty || _userController.text.isEmpty || _loadingRepos)
                        ? null
                        : () async {
                          setDialogState(() => _loadingRepos = true);
                          _availableRepos = await fetchUserRepositories(_tokenController.text, _userController.text);
                          _selectedRepo = null;
                          setDialogState(() => _loadingRepos = false);
                          
                          if (_availableRepos.isEmpty) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('リポジトリが見つかりません')),
                              );
                            }
                          }
                        },
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // リポジトリプルダウン
                  if (_availableRepos.isNotEmpty)
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'リポジトリ名',
                        border: OutlineInputBorder(),
                      ),
                      items: _availableRepos.map((repo) => DropdownMenuItem(value: repo, child: Text(repo))).toList(),
                      onChanged: (value) => setDialogState(() => _selectedRepo = value),
                      initialValue: _selectedRepo,
                    )
                  else if (_loadingRepos)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    )
                  else
                    const Text('上のボタンをタップしてリポジトリを読み込んでください', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: (_tokenController.text.isEmpty || _userController.text.isEmpty || _selectedRepo == null)
                ? null
                : () async {
                  await setGitHubConfig(
                    _tokenController.text,
                    _userController.text,
                    _selectedRepo!,
                  );
                  await loadData();
                  _tokenController.clear();
                  _userController.clear();
                  _selectedRepo = null;
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GitHub設定完了！')));
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
                          onTap: _showGitHubSetup,
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
                                const Text('認証情報を登録', style: TextStyle(fontSize: 11, color: Colors.grey)),
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