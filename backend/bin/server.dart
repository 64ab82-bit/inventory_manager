import 'dart:convert';
import 'dart:io';

import 'package:inventory_manager_api/database.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main(List<String> args) async {
  final appConfig = AppConfig.fromEnvironment();
  final database = DatabaseService(
    workspaceRoot: appConfig.workspaceRoot,
    host: appConfig.mssqlHost,
    port: appConfig.mssqlPort,
    databaseName: appConfig.mssqlDatabase,
    username: appConfig.mssqlUser,
    password: appConfig.mssqlPassword,
    masterDataPath: appConfig.masterDataPath,
    inventoryEntriesPath: appConfig.inventoryEntriesPath,
  );
  await database.initialize();

  final router = Router()
    ..get('/health', (Request request) {
      return _jsonResponse({'status': 'ok'});
    })
    ..get('/items', (Request request) async {
      final items = await database.getItems();
      return _jsonResponse({'items': items});
    })
    ..post('/items', (Request request) async {
      try {
        final body = await request.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final name = (json['name'] as String?)?.trim();

        if (name == null || name.isEmpty) {
          return _jsonResponse({'error': 'name は必須です'}, statusCode: 400);
        }

        final item = await database.createItem(name);
        return _jsonResponse({'item': item}, statusCode: 201);
      } catch (e) {
        return _jsonResponse({'error': '不正なリクエストです: $e'}, statusCode: 400);
      }
    })
    ..get('/entries', (Request request) async {
      final itemIdParam = request.url.queryParameters['itemId'];
      final itemId = itemIdParam != null ? int.tryParse(itemIdParam) : null;
      if (itemIdParam != null && itemId == null) {
        return _jsonResponse({'error': 'itemId は整数で指定してください'}, statusCode: 400);
      }

      final entries = await database.getEntries(itemId: itemId);
      return _jsonResponse({'entries': entries});
    })
    ..post('/entries', (Request request) async {
      try {
        final body = await request.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final itemId = json['itemId'] is int
            ? json['itemId'] as int
            : int.tryParse('${json['itemId']}');
        final quantity = json['quantity'] is int
            ? json['quantity'] as int
            : int.tryParse('${json['quantity']}');

        if (itemId == null) {
          return _jsonResponse({'error': 'itemId は必須です'}, statusCode: 400);
        }
        if (quantity == null) {
          return _jsonResponse({'error': 'quantity は必須です'}, statusCode: 400);
        }

        final remarks = json['remarks'] as String?;
        final date = json['date'] as String?;

        final entry = await database.createEntry(
          itemId: itemId,
          quantity: quantity,
          remarks: remarks,
          date: date,
        );
        return _jsonResponse({'entry': entry}, statusCode: 201);
      } on StateError catch (e) {
        return _jsonResponse({'error': e.message}, statusCode: 404);
      } catch (e) {
        return _jsonResponse({'error': '不正なリクエストです: $e'}, statusCode: 400);
      }
    })
    ..get('/aggregate', (Request request) async {
      final rows = await database.aggregateStock();
      return _jsonResponse({'rows': rows});
    })
    ..post('/sync', (Request request) async {
      try {
        final body = await request.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final items = (json['masterItems'] as List?) ?? const [];
        final entries = (json['inventoryEntries'] as List?) ?? const [];

        await database.replaceAllData(items: items, entries: entries);
        return _jsonResponse({'status': 'ok'});
      } catch (e) {
        return _jsonResponse({'error': '不正なリクエストです: $e'}, statusCode: 400);
      }
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware(appConfig))
      .addMiddleware(_apiKeyAuthMiddleware(appConfig))
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, appConfig.host, appConfig.port);
  print('Inventory API running at http://${server.address.host}:${server.port}');
  print('CORS allow origins: ${appConfig.allowedOrigins.isEmpty ? 'ALL(*)' : appConfig.allowedOrigins.join(', ')}');
  print('API key auth: ${appConfig.apiKey == null || appConfig.apiKey!.isEmpty ? 'DISABLED' : 'ENABLED'}');

  ProcessSignal.sigint.watch().listen((_) {
    database.dispose();
    exit(0);
  });
}

Response _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

class AppConfig {
  final InternetAddress host;
  final int port;
  final String? apiKey;
  final Set<String> allowedOrigins;
  final String workspaceRoot;
  final String mssqlHost;
  final String mssqlPort;
  final String mssqlDatabase;
  final String mssqlUser;
  final String mssqlPassword;
  final String? masterDataPath;
  final String? inventoryEntriesPath;

  const AppConfig({
    required this.host,
    required this.port,
    required this.apiKey,
    required this.allowedOrigins,
    required this.workspaceRoot,
    required this.mssqlHost,
    required this.mssqlPort,
    required this.mssqlDatabase,
    required this.mssqlUser,
    required this.mssqlPassword,
    required this.masterDataPath,
    required this.inventoryEntriesPath,
  });

  factory AppConfig.fromEnvironment() {
    final env = Platform.environment;
    final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
    final hostText = env['HOST'] ?? '0.0.0.0';
    final apiKey = env['API_KEY']?.trim();
    final corsRaw = env['CORS_ALLOWED_ORIGINS']?.trim() ?? '';
    final mssqlHost = env['MSSQL_HOST']?.trim() ?? '';
    final mssqlPort = env['MSSQL_PORT']?.trim().isNotEmpty == true
      ? env['MSSQL_PORT']!.trim()
      : '1433';
    final mssqlDatabase = env['MSSQL_DATABASE']?.trim() ?? '';
    final mssqlUser = env['MSSQL_USER']?.trim() ?? '';
    final mssqlPassword = env['MSSQL_PASSWORD']?.trim() ?? '';
    final workspaceRoot = (env['WORKSPACE_ROOT']?.trim().isNotEmpty ?? false)
      ? env['WORKSPACE_ROOT']!.trim()
      : Directory.current.parent.path;
    final masterDataPath = env['MASTER_DATA_PATH']?.trim();
    final inventoryEntriesPath = env['INVENTORY_ENTRIES_PATH']?.trim();

    if (mssqlHost.isEmpty || mssqlDatabase.isEmpty || mssqlUser.isEmpty || mssqlPassword.isEmpty) {
      throw StateError('MSSQL_HOST / MSSQL_DATABASE / MSSQL_USER / MSSQL_PASSWORD are required.');
    }

    final origins = corsRaw.isEmpty
        ? <String>{}
        : corsRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();

    return AppConfig(
      host: InternetAddress.tryParse(hostText) ?? InternetAddress.anyIPv4,
      port: port,
      apiKey: (apiKey == null || apiKey.isEmpty) ? null : apiKey,
      allowedOrigins: origins,
      workspaceRoot: workspaceRoot,
      mssqlHost: mssqlHost,
      mssqlPort: mssqlPort,
      mssqlDatabase: mssqlDatabase,
      mssqlUser: mssqlUser,
      mssqlPassword: mssqlPassword,
      masterDataPath: (masterDataPath == null || masterDataPath.isEmpty) ? null : masterDataPath,
      inventoryEntriesPath: (inventoryEntriesPath == null || inventoryEntriesPath.isEmpty)
          ? null
          : inventoryEntriesPath,
    );
  }
}

Middleware _apiKeyAuthMiddleware(AppConfig config) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS' || request.url.path == 'health') {
        return innerHandler(request);
      }

      if (config.apiKey == null) {
        return innerHandler(request);
      }

      final headerApiKey = request.headers['x-api-key'];
      if (headerApiKey == config.apiKey) {
        return innerHandler(request);
      }

      return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);
    };
  };
}

Middleware _corsMiddleware(AppConfig config) {
  return (Handler innerHandler) {
    return (Request request) async {
      final origin = request.headers['origin'];
      final allowAll = config.allowedOrigins.isEmpty;
      final originAllowed = origin != null && (allowAll || config.allowedOrigins.contains(origin));

      if (request.method == 'OPTIONS') {
        return Response(
          204,
          headers: _corsHeaders(
            allowAll: allowAll,
            origin: origin,
            originAllowed: originAllowed,
          ),
        );
      }

      final response = await innerHandler(request);
      return response.change(
        headers: {
          ...response.headers,
          ..._corsHeaders(
            allowAll: allowAll,
            origin: origin,
            originAllowed: originAllowed,
          ),
        },
      );
    };
  };
}

Map<String, String> _corsHeaders({
  required bool allowAll,
  required String? origin,
  required bool originAllowed,
}) {
  final accessControlAllowOrigin = allowAll
      ? '*'
      : (originAllowed && origin != null ? origin : 'null');

  return {
    'access-control-allow-origin': accessControlAllowOrigin,
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'Content-Type, X-Api-Key',
  };
}
