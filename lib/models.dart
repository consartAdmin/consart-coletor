// Modelos usados pelo coletor. Espelham as respostas de
// /api/inventories e /api/products-mobile do ERP.

String _str(dynamic v) => v == null ? '' : v.toString();

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(_str(v).replaceAll(',', '.')) ?? 0;
}

String formatQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

class Inventory {
  final String id;
  final String code;
  final String description;
  final String status;

  Inventory({
    required this.id,
    required this.code,
    required this.description,
    required this.status,
  });

  factory Inventory.fromJson(Map<String, dynamic> j) {
    final id = _str(j['inventory_id'] ?? j['id']);
    return Inventory(
      id: id,
      code: _str(j['code']).isEmpty ? 'Inventário $id' : _str(j['code']),
      description: _str(j['description']),
      status: _str(j['status']),
    );
  }

  String get label =>
      description.isEmpty ? code : '$code — $description';
}

class ProductUnit {
  final String id;
  final String unit;
  final double factor;
  final bool standard;

  ProductUnit({
    required this.id,
    required this.unit,
    required this.factor,
    required this.standard,
  });

  factory ProductUnit.fromJson(Map<String, dynamic> j) {
    final factor = _num(j['factor'] ?? j['fator']);
    return ProductUnit(
      id: _str(j['product_unit_id'] ??
          j['productUnitId'] ??
          j['product_unitId'] ??
          j['unit_id']),
      unit: _str(j['unit'] ?? j['unidade']).isEmpty
          ? 'UN'
          : _str(j['unit'] ?? j['unidade']),
      factor: factor > 0 ? factor : 1,
      standard: j['standard'] == true,
    );
  }

  String get label =>
      '$unit x ${formatQty(factor)}${standard ? ' — padrão' : ''}';
}

class ProductLot {
  final String id;
  final String code;
  final String? expiresAt;
  final double qtyOnHand;

  ProductLot({
    required this.id,
    required this.code,
    required this.expiresAt,
    required this.qtyOnHand,
  });

  factory ProductLot.fromJson(Map<String, dynamic> j) {
    final id = _str(j['lot_id'] ?? j['id']);
    final code = _str(j['lot_code'] ?? j['code']);
    final exp = _str(j['expires_at']);
    return ProductLot(
      id: id,
      code: code.isEmpty ? 'Lote $id' : code,
      expiresAt: exp.isEmpty ? null : exp,
      qtyOnHand: _num(j['qty_on_hand']),
    );
  }

  String get label {
    final parts = <String>[code];
    if (expiresAt != null) parts.add('Val: ${formatDateBR(expiresAt!)}');
    parts.add('Qtd: ${formatQty(qtyOnHand)}');
    return parts.join(' — ');
  }
}

class LocationOption {
  final String id;
  final String label;
  final String barcode;

  LocationOption({required this.id, required this.label, required this.barcode});

  factory LocationOption.fromJson(Map<String, dynamic> j) {
    final id = _str(j['location_barcode_id'] ?? j['id']);
    final barcode = _str(j['barcode']);
    final label = _str(j['label']);
    return LocationOption(
      id: id,
      barcode: barcode,
      label: label.isNotEmpty
          ? label
          : (barcode.isNotEmpty ? barcode : 'Local $id'),
    );
  }
}

class Product {
  final String productCode;
  final String description;
  final String? barcode;
  final String? productStockId;
  final double stockQty;
  final String stockStatus;
  final String locationLabel;
  final String? locationId;
  final List<ProductUnit> units;
  final List<ProductLot> lots;

  Product({
    required this.productCode,
    required this.description,
    required this.barcode,
    required this.productStockId,
    required this.stockQty,
    required this.stockStatus,
    required this.locationLabel,
    required this.locationId,
    required this.units,
    required this.lots,
  });

  factory Product.fromJson(Map<String, dynamic> j) {
    final stock = (j['stock'] as Map?)?.cast<String, dynamic>() ?? {};
    final loc = (j['location'] as Map?)?.cast<String, dynamic>() ?? {};
    final locId = _str(loc['location_barcode_id'] ??
        loc['location_id'] ??
        j['product_location_id']);
    return Product(
      productCode: _str(j['product_code']),
      description: _str(j['description']).isEmpty
          ? 'Produto'
          : _str(j['description']),
      barcode: _str(j['barcode']).isEmpty ? null : _str(j['barcode']),
      productStockId: _str(stock['product_stock_id']).isEmpty
          ? null
          : _str(stock['product_stock_id']),
      stockQty: _num(stock['quantity']),
      stockStatus: _str(stock['status']),
      locationLabel: _str(loc['label']),
      locationId: locId.isEmpty ? null : locId,
      units: ((j['units'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => ProductUnit.fromJson(e.cast<String, dynamic>()))
          .toList(),
      lots: ((j['lots'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => ProductLot.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

String formatDateBR(String value) {
  final d = DateTime.tryParse(value);
  if (d == null) return value.length >= 10 ? value.substring(0, 10) : value;
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}

bool isLocationBarcode(String value) =>
    value.trim().toUpperCase().startsWith('LOC-');
