import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'models.dart';
import 'scanner_page.dart';

/// Tela de contagem de um produto: localização, unidade, lote,
/// quantidade e observação. Faz pop(true) quando a contagem é salva.
class ProdutoPage extends StatefulWidget {
  final Product product;
  final String inventoryId;

  const ProdutoPage({
    super.key,
    required this.product,
    required this.inventoryId,
  });

  @override
  State<ProdutoPage> createState() => _ProdutoPageState();
}

class _ProdutoPageState extends State<ProdutoPage> {
  final _api = ApiService.instance;
  late Product _product = widget.product;

  final _qty = TextEditingController();
  final _notes = TextEditingController();
  final _locationInput = TextEditingController();
  final _qtyFocus = FocusNode();

  List<LocationOption> _locations = [];
  String? _locationId;
  String? _unitId;
  String? _lotId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _applyProduct(_product);
    _loadLocations();
  }

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    _locationInput.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _applyProduct(Product p) {
    _product = p;
    _locationId = p.locationId;
    final std = p.units.where((u) => u.standard);
    _unitId = p.units.isEmpty
        ? null
        : (std.isNotEmpty ? std.first.id : p.units.first.id);
    _lotId = null;
  }

  void _snack(String msg, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? cs.error : null,
      ));
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadLocations() async {
    try {
      final list = await _api.listLocations();
      if (!mounted) return;
      setState(() {
        _locations = list;
        if (_locationId != null && !list.any((l) => l.id == _locationId)) {
          _locationId = null;
        }
      });
    } catch (e) {
      if (mounted) _snack('Erro ao carregar localizações: $e', error: true);
    }
  }

  Future<void> _reloadProduct() async {
    final p = await _api.findProduct(_product.productCode);
    if (p != null && mounted) setState(() => _applyProduct(p));
  }

  // ── Localização ──────────────────────────────────────────────────────
  Future<void> _scanLocation() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
          builder: (_) => const ScannerPage(title: 'Ler localização')),
    );
    if (code != null) await _applyLocationBarcode(code);
  }

  Future<void> _applyLocationBarcode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    if (!isLocationBarcode(code)) {
      _snack('Código de localização deve começar com LOC-.', error: true);
      return;
    }
    await _run(() async {
      final loc = await _api.findLocation(code);
      if (loc == null) {
        _snack('Localização não encontrada.', error: true);
        return;
      }
      setState(() {
        if (!_locations.any((l) => l.id == loc.id)) {
          _locations = [..._locations, loc];
        }
        _locationId = loc.id;
        _locationInput.clear();
      });
      _snack('Localização: ${loc.label}');
      _qtyFocus.requestFocus();
    });
  }

  Future<void> _updateLocation() async {
    final id = _locationId;
    if (id == null) {
      _snack('Selecione uma localização.', error: true);
      return;
    }
    await _run(() async {
      await _api.updateProductLocation(_product.productCode, id);
      await _reloadProduct();
      _snack('Localização atualizada com sucesso.');
    });
  }

  // ── Unidade ──────────────────────────────────────────────────────────
  List<UnitOption>? _unitOptions;

  Future<void> _createUnit() async {
    if (_unitOptions == null) {
      await _run(() async {
        _unitOptions = await _api.listUnits();
      });
      if (!mounted || _unitOptions == null) return;
    }
    final options = _unitOptions!;
    if (options.isEmpty) {
      _snack('Nenhuma unidade cadastrada no ERP.', error: true);
      return;
    }

    UnitOption? selected;
    final factor = TextEditingController();
    final barcode = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nova unidade'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<UnitOption>(
                  isExpanded: true,
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  hint: const Text('Selecione (CX, PCT, FD...)'),
                  items: options
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(u.label, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (u) => setD(() {
                    selected = u;
                    if (u != null && u.factor > 1) {
                      factor.text = formatQty(u.factor);
                    }
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: factor,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Fator (qtd. de UN por unidade)',
                    hintText: '12',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: barcode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Código de barras da unidade',
                    hintText: 'DUN-14 / EAN da caixa',
                    suffixIcon: IconButton(
                      tooltip: 'Câmera',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () async {
                        final code = await Navigator.of(ctx).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const ScannerPage(
                              title: 'Ler código da unidade',
                            ),
                          ),
                        );
                        if (code != null) barcode.text = code.trim();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    final factorText = factor.text.trim().replaceAll(',', '.');
    final barcodeText = barcode.text.trim();
    factor.dispose();
    barcode.dispose();
    if (ok != true) return;

    final unit = selected;
    final f = double.tryParse(factorText);
    if (unit == null) {
      _snack('Selecione a unidade.', error: true);
      return;
    }
    if (f == null || f <= 0) {
      _snack('Informe um fator maior que zero.', error: true);
      return;
    }
    if (barcodeText.isEmpty) {
      _snack('Informe o código de barras da unidade.', error: true);
      return;
    }

    await _run(() async {
      await _api.createProductUnit(
        productCode: _product.productCode,
        unit: unit,
        factor: f,
        barcode: barcodeText,
      );
      await _reloadProduct();
      String norm(String s) =>
          s.trim().toUpperCase().replaceAll(RegExp(r'\.$'), '');
      final match = _product.units.where(
        (u) => norm(u.unit) == norm(unit.unit) && (u.factor - f).abs() < 0.0001,
      );
      if (!mounted) return;
      if (match.isNotEmpty) setState(() => _unitId = match.first.id);
      _snack('Unidade ${norm(unit.unit)} x ${formatQty(f)} criada.');
    });
  }

  // ── Lote ─────────────────────────────────────────────────────────────
  Future<void> _createLot() async {
    final code = TextEditingController(text: 'LOTE PADRÃO');
    DateTime? expires;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Novo lote'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Código do lote'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(expires == null
                    ? 'Validade (opcional)'
                    : 'Validade: ${formatDateBR(expires!.toIso8601String())}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDate: DateTime.now(),
                  );
                  if (d != null) setD(() => expires = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Criar')),
          ],
        ),
      ),
    );
    final lotCode = code.text;
    code.dispose();
    if (ok != true) return;

    final exp = expires;
    final expIso = exp == null
        ? null
        : '${exp.year}-${exp.month.toString().padLeft(2, '0')}-${exp.day.toString().padLeft(2, '0')}';
    await _run(() async {
      await _api.createLot(_product, lotCode, expIso);
      await _reloadProduct();
      _snack('Lote criado com sucesso.');
    });
  }

  // ── Salvar contagem ──────────────────────────────────────────────────
  Future<void> _save() async {
    final qty = double.tryParse(_qty.text.trim().replaceAll(',', '.'));
    if (qty == null || qty < 0) {
      _snack('Informe uma quantidade contada válida.', error: true);
      _qtyFocus.requestFocus();
      return;
    }

    ProductUnit? unit;
    for (final u in _product.units) {
      if (u.id == _unitId) {
        unit = u;
        break;
      }
    }
    LocationOption? loc;
    for (final l in _locations) {
      if (l.id == _locationId) loc = l;
    }

    final payload = <String, dynamic>{
      'product_code': _product.productCode,
      'barcode': _product.barcode,
      'counted_qty': qty,
      // Sem product_unit_id o ERP acha a unidade do produto pela sigla.
      'product_unit_id': unit?.productUnitId,
      'unit': unit?.unit ?? 'UN',
      'fator': unit?.factor ?? 1,
      'product_location_id': _locationId ?? _product.locationId,
      'location_barcode_id': _locationId ?? _product.locationId,
      'location': loc?.label ??
          (_product.locationLabel.isEmpty ? null : _product.locationLabel),
      'location_barcode': loc?.barcode,
      'lot_id': _lotId,
      'notes': _notes.text.trim().isEmpty
          ? 'Contagem via app coletor'
          : _notes.text.trim(),
    };

    await _run(() async {
      await _api.saveCount(widget.inventoryId, payload);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _product;
    final currentLocation = p.locationLabel.isEmpty
        ? 'Sem localização'
        : p.locationLabel;

    return Scaffold(
      appBar: AppBar(title: const Text('Contagem')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              Text(p.description, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoTile(label: 'SKU', value: p.productCode),
                  const SizedBox(width: 12),
                  _InfoTile(
                    label: 'Estoque',
                    value: formatQty(p.stockQty),
                    highlight: p.stockStatus == 'SEM_ESTOQUE' ||
                        p.stockStatus == 'ABAIXO_MINIMO',
                  ),
                ],
              ),
              if (p.barcode != null) ...[
                const SizedBox(height: 8),
                Text('Barcode: ${p.barcode}',
                    style: theme.textTheme.bodySmall),
              ],
              const Divider(height: 32),

              // Localização
              Text('Localização', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Atual: $currentLocation'),
              const SizedBox(height: 12),
              TextField(
                controller: _locationInput,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: _applyLocationBarcode,
                decoration: InputDecoration(
                  labelText: 'Escanear localização',
                  hintText: 'LOC-BIN-000343',
                  prefixIcon: const Icon(Icons.place_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Câmera',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanLocation,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('loc-$_locationId-${_locations.length}'),
                isExpanded: true,
                initialValue: _locationId,
                decoration:
                    const InputDecoration(labelText: 'Localização da contagem'),
                hint: const Text('Selecione uma localização'),
                items: _locations
                    .map((l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.label, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _locationId = v),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _updateLocation,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Gravar como localização do produto'),
                ),
              ),
              const Divider(height: 32),

              // Unidade e lote
              DropdownButtonFormField<String>(
                key: ValueKey('unit-$_unitId-${p.units.length}'),
                isExpanded: true,
                initialValue: _unitId,
                decoration: const InputDecoration(labelText: 'Unidade'),
                hint: const Text('UN x 1'),
                items: p.units
                    .map((u) =>
                        DropdownMenuItem(value: u.id, child: Text(u.label)))
                    .toList(),
                onChanged: (v) => setState(() => _unitId = v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _createUnit,
                  icon: const Icon(Icons.add),
                  label: const Text('Criar unidade para este produto'),
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String?>(
                key: ValueKey('lot-$_lotId-${p.lots.length}'),
                isExpanded: true,
                initialValue: _lotId,
                decoration: const InputDecoration(labelText: 'Lote'),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                        p.lots.isEmpty ? 'Sem lote encontrado' : 'Sem lote'),
                  ),
                  ...p.lots.map((l) => DropdownMenuItem<String?>(
                        value: l.id,
                        child: Text(l.label, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _lotId = v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _createLot,
                  icon: const Icon(Icons.add),
                  label: const Text('Criar lote para este produto'),
                ),
              ),
              const Divider(height: 32),

              // Quantidade
              TextField(
                controller: _qty,
                focusNode: _qtyFocus,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: theme.textTheme.headlineSmall,
                decoration: const InputDecoration(
                  labelText: 'Quantidade contada',
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Observação (opcional)'),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Salvar contagem'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _InfoTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: highlight ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
