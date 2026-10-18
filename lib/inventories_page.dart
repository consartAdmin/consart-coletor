import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';

/// Lista os inventários abertos. Ao tocar em um, mostra os produtos
/// contados nele. Faz pop(id) quando o usuário escolhe "Usar este".
class InventoriesPage extends StatefulWidget {
  final String? currentId;
  const InventoriesPage({super.key, this.currentId});

  @override
  State<InventoriesPage> createState() => _InventoriesPageState();
}

class _InventoriesPageState extends State<InventoriesPage> {
  final _api = ApiService.instance;
  late Future<List<Inventory>> _future = _api.listOpenInventories(limit: 200);

  Future<void> _reload() async {
    final f = _api.listOpenInventories(limit: 200);
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventários abertos')),
      body: FutureBuilder<List<Inventory>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.error_outline,
              text: snap.error.toString(),
              onRetry: _reload,
            );
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return _Message(
              icon: Icons.inventory_2_outlined,
              text: 'Nenhum inventário aberto.',
              onRetry: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final inv = list[i];
                final current = inv.id == widget.currentId;
                final subtitle = [
                  if (inv.description.isNotEmpty) inv.description,
                  if (inv.referenceDate != null)
                    formatDateBR(inv.referenceDate!),
                  if (inv.itemsCount != null) '${inv.itemsCount} itens',
                ].join(' · ');
                return ListTile(
                  leading: Icon(
                    current ? Icons.check_circle : Icons.inventory_2_outlined,
                    color:
                        current ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(inv.code),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final use = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => InventoryItemsPage(inventory: inv),
                      ),
                    );
                    if (use == true && context.mounted) {
                      Navigator.of(context).pop(inv.id);
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Produtos já contados em um inventário.
class InventoryItemsPage extends StatefulWidget {
  final Inventory inventory;
  const InventoryItemsPage({super.key, required this.inventory});

  @override
  State<InventoryItemsPage> createState() => _InventoryItemsPageState();
}

class _InventoryItemsPageState extends State<InventoryItemsPage> {
  final _api = ApiService.instance;
  late Future<List<InventoryItem>> _future =
      _api.listInventoryItems(widget.inventory.id);
  String _filter = '';

  Future<void> _reload() async {
    final f = _api.listInventoryItems(widget.inventory.id);
    setState(() => _future = f);
    await f;
  }

  bool _matches(InventoryItem it) {
    if (_filter.isEmpty) return true;
    final q = _filter.toLowerCase();
    return it.productCode.toLowerCase().contains(q) ||
        it.description.toLowerCase().contains(q) ||
        it.location.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inv = widget.inventory;
    return Scaffold(
      appBar: AppBar(
        title: Text(inv.code, overflow: TextOverflow.ellipsis),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('Contar neste inventário'),
          ),
        ),
      ),
      body: FutureBuilder<List<InventoryItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.error_outline,
              text: snap.error.toString(),
              onRetry: _reload,
            );
          }
          final all = snap.data ?? [];
          final items = all.where(_matches).toList();
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (inv.description.isNotEmpty)
                  Text(inv.description, style: theme.textTheme.titleMedium),
                Text(
                  '${all.length} produto(s) contado(s)',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Filtrar por SKU, nome ou local',
                  ),
                  onChanged: (v) => setState(() => _filter = v.trim()),
                ),
                const SizedBox(height: 8),
                if (all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: Text(
                      'Nenhum produto contado ainda.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ...items.map((it) => Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        title: Text(
                          it.description.isEmpty
                              ? it.productCode
                              : it.description,
                        ),
                        subtitle: Text([
                          'SKU ${it.productCode}',
                          if (it.location.isNotEmpty) it.location,
                          if (it.lot.isNotEmpty) 'Lote ${it.lot}',
                          if (it.systemQty != null)
                            'Sistema ${formatQty(it.systemQty!)}',
                          if (it.differenceQty != null && it.differenceQty != 0)
                            'Dif. ${it.differenceQty! > 0 ? '+' : ''}${formatQty(it.differenceQty!)}',
                          if (it.countedAt != null) formatDateBR(it.countedAt!),
                        ].join(' · ')),
                        trailing: Text(
                          '${formatQty(it.countedQty)} ${it.unit}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Future<void> Function() onRetry;

  const _Message({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
