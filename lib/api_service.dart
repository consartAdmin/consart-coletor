import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Cliente das APIs do ERP usadas pelo Inventário Mobile
/// (backend/public/inventoryMobile).
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const defaultServer = 'https://erp.consart.com.br';
  static const _kServer = 'server_url';
  static const _kToken = 'token';
  static const _kUserName = 'user_name';
  static const _kInventory = 'inventory_id';

  String serverUrl = '';
  String? token;
  String? userName;
  String? lastInventoryId;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kServer) ?? defaultServer;
    token = p.getString(_kToken);
    userName = p.getString(_kUserName);
    lastInventoryId = p.getString(_kInventory);
  }

  Future<void> rememberInventory(String? id) async {
    lastInventoryId = id;
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      await p.remove(_kInventory);
    } else {
      await p.setString(_kInventory, id);
    }
  }

  Future<void> logout() async {
    token = null;
    userName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUserName);
  }

  static String normalizeServer(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (serverUrl.isEmpty) {
      throw ApiException('Configure o endereço do servidor.');
    }
    return Uri.parse('$serverUrl$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool allow404 = false,
  }) async {
    final uri = _uri(path, query);
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 20)),
      );
    } on TimeoutException {
      throw ApiException('Servidor não respondeu. Verifique a conexão.');
    } catch (_) {
      throw ApiException('Sem conexão com o servidor ($serverUrl).');
    }

    Map<String, dynamic> json = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}

    if (res.statusCode == 404 && allow404) return json;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = json['error'] ?? json['message'] ?? json['erro'];
      throw ApiException(
        msg is String && msg.isNotEmpty
            ? msg
            : 'Erro na requisição (${res.statusCode}).',
        res.statusCode,
      );
    }
    return json;
  }

  // ── Login ────────────────────────────────────────────────────────────
  Future<void> login(String server, String login, String password) async {
    final url = normalizeServer(server);
    serverUrl = url;
    final json = await _send('POST', '/api/login',
        body: {'login': login.trim(), 'password': password});
    final t = json['token'];
    if (t is! String || t.isEmpty) {
      throw ApiException('Login sem token na resposta.');
    }
    token = t;
    final user = json['user'];
    userName = user is Map ? (user['name']?.toString() ?? login) : login;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, url);
    await p.setString(_kToken, t);
    await p.setString(_kUserName, userName!);
  }

  // ── Inventários ──────────────────────────────────────────────────────
  Future<List<Inventory>> listOpenInventories({int limit = 50}) async {
    final json = await _send('GET', '/api/inventories',
        query: {'status': 'OPEN', 'limit': '$limit'});
    return _rows(json).map((e) => Inventory.fromJson(e)).toList();
  }

  Future<List<InventoryItem>> listInventoryItems(String inventoryId) async {
    final json = await _send('GET', '/api/inventories/$inventoryId/items');
    return _rows(json).map((e) => InventoryItem.fromJson(e)).toList();
  }

  /// Nome automático: INV-MOBILE-AAAAMMDD-HHMM.
  static String autoInventoryCode([DateTime? at]) {
    final now = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'INV-MOBILE-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}';
  }

  /// true se já existe inventário com exatamente este código.
  Future<bool> inventoryCodeExists(String code) async {
    final json = await _send('GET', '/api/inventories',
        query: {'search': code.trim(), 'limit': '20'});
    final c = code.trim().toUpperCase();
    return _rows(json)
        .any((r) => (r['code'] ?? '').toString().trim().toUpperCase() == c);
  }

  Future<String?> createInventory({
    required String code,
    required String description,
  }) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final iso = '${now.year}-${two(now.month)}-${two(now.day)}';

    final json = await _send('POST', '/api/inventories', body: {
      'code': code.trim(),
      'description':
          description.trim().isEmpty ? 'Inventário Mobile' : description.trim(),
      'type': 'GENERAL',
      'status': 'OPEN',
      'reference_date': iso,
      'notes': 'Inventário criado pelo app coletor.',
    });
    final row = json['data'] ?? json['row'] ?? json['inventory'] ?? json;
    final id = row is Map ? (row['inventory_id'] ?? row['id']) : null;
    return id?.toString();
  }

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> json) {
    final raw = json['rows'] ?? json['items'] ?? json['data'] ?? [];
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> saveCount(String inventoryId, Map<String, dynamic> payload) =>
      _send('POST', '/api/inventories/$inventoryId/items', body: payload);

  // ── Produtos ─────────────────────────────────────────────────────────
  /// Busca por código de barras ou SKU. Retorna null se não encontrado.
  Future<Product?> findProduct(String code) async {
    final json = await _send(
      'GET',
      '/api/products-mobile/search/${Uri.encodeComponent(code.trim())}',
      allow404: true,
    );
    final p = json['product'];
    if (p is! Map) return null;
    return Product.fromJson(p.cast<String, dynamic>());
  }

  Future<void> createLot(Product product, String lotCode, String? expiresAt) =>
      _send('POST', '/api/productsStockLots', body: {
        'product_code': product.productCode,
        'product_stock_id': product.productStockId,
        'lot_code': lotCode.trim().isEmpty ? 'LOTE PADRÃO' : lotCode.trim(),
        'expires_at': expiresAt,
        'qty_on_hand': 0,
      });

  // ── Localizações ─────────────────────────────────────────────────────
  Future<List<LocationOption>> listLocations() async {
    final json = await _send('GET', '/api/products-mobile/locations/options');
    final rows = (json['rows'] as List?) ?? [];
    return rows
        .whereType<Map>()
        .map((e) => LocationOption.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<LocationOption?> findLocation(String barcode) async {
    final json = await _send(
      'GET',
      '/api/products-mobile/locations/barcode/${Uri.encodeComponent(barcode.trim())}',
      allow404: true,
    );
    final row = json['data'] ?? json['location'] ?? json['row'];
    if (row is! Map) return null;
    return LocationOption.fromJson(row.cast<String, dynamic>());
  }

  Future<void> updateProductLocation(String productCode, String locationId) =>
      _send(
        'PUT',
        '/api/products-mobile/${Uri.encodeComponent(productCode)}/location',
        body: {
          'location_barcode_id': locationId,
          'location_id': locationId,
          'product_location_id': locationId,
        },
      );
}
