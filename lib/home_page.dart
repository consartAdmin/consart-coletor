import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'inventories_page.dart';
import 'login_page.dart';
import 'models.dart';
import 'produto_page.dart';
import 'scanner_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = ApiService.instance;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  List<Inventory> _inventories = [];
  String? _inventoryId;
  bool _loadingInventories = false;
  bool _searching = false;
  bool _continuous = true;
  int _savedCount = 0;

  // Leitor de código de barras (bipe) que funciona como teclado: guarda as
  // teclas que chegam em sequência rápida e usa o código inteiro no Enter,
  // sem depender do campo de texto (que pode perder os últimos dígitos).
  final _scanBuffer = StringBuffer();
  DateTime _lastScanKey = DateTime(0);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _loadInventories();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
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

  Future<void> _handleAuthError(Object e) async {
    if (e is ApiException && e.status == 401) {
      await _api.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
      return;
    }
    _snack(e.toString(), error: true);
  }

  Future<void> _loadInventories() async {
    setState(() => _loadingInventories = true);
    try {
      final list = await _api.listOpenInventories();
      final wanted = _inventoryId ?? _api.lastInventoryId;
      setState(() {
        _inventories = list;
        _inventoryId = list.any((i) => i.id == wanted)
            ? wanted
            : (list.isNotEmpty ? list.first.id : null);
      });
      await _api.rememberInventory(_inventoryId);
    } catch (e) {
      await _handleAuthError(e);
    } finally {
      if (mounted) setState(() => _loadingInventories = false);
    }
  }

  Future<void> _createInventory() async {
    final code = TextEditingController(text: ApiService.autoInventoryCode());
    final desc = TextEditingController(text: 'Inventário Mobile');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo inventário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Nome / código',
                suffixIcon: IconButton(
                  tooltip: 'Gerar automático',
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: () => code.text = ApiService.autoInventoryCode(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: desc,
              decoration: const InputDecoration(labelText: 'Descrição'),
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
    );
    final codeText = code.text.trim();
    final descText = desc.text.trim();
    code.dispose();
    desc.dispose();
    if (ok != true) return;
    if (codeText.isEmpty) {
      _snack('Informe o nome do inventário.', error: true);
      return;
    }
    try {
      if (await _api.inventoryCodeExists(codeText)) {
        _snack('Já existe um inventário "$codeText". Use outro nome.',
            error: true);
        return;
      }
      final id =
          await _api.createInventory(code: codeText, description: descText);
      _inventoryId = id;
      await _loadInventories();
      if (mounted) _snack('Inventário "$codeText" criado.');
    } catch (e) {
      await _handleAuthError(e);
    }
  }

  Future<void> _openInventories() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => InventoriesPage(currentId: _inventoryId),
      ),
    );
    await _loadInventories();
    if (id != null && mounted) {
      setState(() => _inventoryId = id);
      await _api.rememberInventory(id);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (code != null) await _lookup(code);
  }

  bool _onHardwareKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    final now = DateTime.now();
    if (now.difference(_lastScanKey) > const Duration(milliseconds: 100)) {
      _scanBuffer.clear();
    }
    _lastScanKey = now;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _scanBuffer.toString();
      _scanBuffer.clear();
      if (code.length < 4 || _searching) return false;
      _search.text = code;
      _lookup(code);
      return true;
    }
    final ch = e.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) {
      _scanBuffer.write(ch);
    }
    return false;
  }

  // Leitores físicos às vezes enviam o Enter antes dos últimos dígitos
  // chegarem ao campo; espera um instante e usa o texto completo do campo.
  Future<void> _onSearchSubmitted(String _) async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _lookup(_search.text);
  }

  Future<void> _lookup(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) {
      _snack('Digite ou escaneie um código.', error: true);
      return;
    }
    if (isLocationBarcode(code)) {
      _snack('Primeiro escaneie o produto. Depois escaneie a localização.',
          error: true);
      return;
    }
    if (_inventoryId == null) {
      _snack('Selecione ou crie um inventário.', error: true);
      return;
    }

    setState(() => _searching = true);
    Product? product;
    try {
      product = await _api.findProduct(code);
      // Código lido sem o dígito verificador: tenta completar (EAN-13/DUN-14).
      final fixed = withGtinCheckDigit(code);
      if (product == null && fixed != null) {
        product = await _api.findProduct(fixed);
      }
    } catch (e) {
      await _handleAuthError(e);
      return;
    } finally {
      if (mounted) setState(() => _searching = false);
    }
    if (!mounted) return;
    if (product == null) {
      _snack('Produto não encontrado: $code', error: true);
      _search.text = code;
      _searchFocus.requestFocus();
      return;
    }
    _search.clear();

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProdutoPage(product: product!, inventoryId: _inventoryId!),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      setState(() => _savedCount++);
      _snack('Contagem salva com sucesso.');
      if (_continuous) {
        await _scan();
        return;
      }
    }
    _searchFocus.requestFocus();
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventário Mobile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(_api.userName ?? ''),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Inventário', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                                'inv-$_inventoryId-${_inventories.length}'),
                            isExpanded: true,
                            initialValue: _inventoryId,
                            hint: Text(_loadingInventories
                                ? 'Carregando...'
                                : 'Nenhum inventário aberto'),
                            items: _inventories
                                .map((i) => DropdownMenuItem(
                                      value: i.id,
                                      child: Text(i.label,
                                          overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              setState(() => _inventoryId = v);
                              _api.rememberInventory(v);
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Recarregar',
                          onPressed:
                              _loadingInventories ? null : _loadInventories,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openInventories,
                            icon: const Icon(Icons.list_alt),
                            label: const Text('Ver inventários'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _createInventory,
                            icon: const Icon(Icons.add),
                            label: const Text('Novo inventário'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                  textStyle: theme.textTheme.titleMedium),
              onPressed: _searching ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner, size: 32),
              label: const Text('Ler código de barras'),
            ),
            const SizedBox(height: 16),
            // Campo também recebe leitores físicos (coletores) que digitam + Enter.
            TextField(
              controller: _search,
              focusNode: _searchFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSearchSubmitted,
              decoration: InputDecoration(
                labelText: 'Barcode ou SKU do produto',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () => _lookup(_search.text),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Abrir câmera após salvar'),
              subtitle: const Text('Agiliza a contagem em sequência'),
              value: _continuous,
              onChanged: (v) => setState(() => _continuous = v),
            ),
            if (_savedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$_savedCount contagem(ns) salva(s) nesta sessão',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
