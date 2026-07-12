import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';

class ConsumptionsScreen extends StatefulWidget {
  const ConsumptionsScreen({super.key});

  @override
  State<ConsumptionsScreen> createState() => _ConsumptionsScreenState();
}

class _ConsumptionsScreenState extends State<ConsumptionsScreen> {
  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();

    final consumptions = List<Map<String, dynamic>>.from(db.consumptions);
    consumptions.sort((a, b) => (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));

    final totalValue = consumptions.fold(0.0, (s, c) => s + ((c['total'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total Consumos:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(fmtMoney(totalValue), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
            ]),
          ),
          Expanded(
            child: consumptions.isEmpty
                ? const Center(child: Text('Sin consumos registrados', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: consumptions.length,
                    itemBuilder: (_, i) {
                      final c = consumptions[i];
                      final total = (c['total'] as num?)?.toDouble() ?? 0;
                      final items = (c['items'] as List?) ?? [];
                      final itemDesc = items.map((it) => '${it['productName']} x${it['quantity']}').join(', ');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: const Icon(Icons.restaurant, color: Colors.orange),
                          ),
                          title: Text(fmtMoney(total), style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${c['date'] ?? ''}${c['notes'] != null && (c['notes'] as String).isNotEmpty ? ' - ${c['notes']}' : ''}', style: const TextStyle(fontSize: 11)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _confirmDelete(c['id'], total, db, sync),
              ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(itemDesc, style: const TextStyle(fontSize: 12)),
                                  if (c['notes'] != null && (c['notes'] as String).isNotEmpty)
                                    Text('Notas: ${c['notes']}', style: const TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context, db, sync),
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _confirmDelete(String id, double total, DbService db, SyncService sync) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar consumo?'),
        content: Text('Eliminar ${fmtMoney(total)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () async {
            db.consumptions.removeWhere((x) => x['id'] == id);
            await db.saveCache();
            db.notifyListeners();
            if (sync.firebaseEnabled) sync.saveAndSync();
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  final _notesCtrl = TextEditingController();
  final List<_ConsumptionItem> _newItems = [];

  void _openForm(BuildContext ctx, DbService db, SyncService sync) {
    _notesCtrl.clear();
    _newItems.clear();

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nuevo Consumo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Productos:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(onPressed: () => _pickProduct(db, setModalState), icon: const Icon(Icons.add), label: const Text('Agregar')),
              ]),
              ..._newItems.asMap().entries.map((e) {
                final idx = e.key;
                final item = e.value;
                final sellable = db.getSellableProducts();
                final product = sellable.where((sp) => sp.product.id == item.productId).firstOrNull;
                final price = product?.link.salePrice ?? 0;
                final subtotal = item.qty * price;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    dense: true,
                    title: Text(product?.product.name ?? 'Producto', style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${item.qty} x ${fmtMoney(price.toDouble())} = ${fmtMoney(subtotal.toDouble())}', style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                      onPressed: () { _newItems.removeAt(idx); setModalState(() {}); },
                    ),
                  ),
                );
              }),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total: ${fmtMoney(_newItems.fold(0.0, (s, i) => s + (i.qty * (db.prodSuppliers.where((ps) => ps.productId == i.productId).firstOrNull?.salePrice ?? 0.0))))}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _newItems.isEmpty ? null : () async {
                    final items = <Map<String, dynamic>>[];
                    double total = 0;
                    for (final ci in _newItems) {
                      final link = db.prodSuppliers.where((ps) => ps.productId == ci.productId).firstOrNull;
                      final name = db.products.where((p) => p.id == ci.productId).firstOrNull?.name ?? '';
                      final price = link?.salePrice ?? 0;
                      items.add({'productId': ci.productId, 'productName': name, 'quantity': ci.qty, 'sellPrice': price});
                      total += ci.qty * price;
                    }
                    db.consumptions.add({
                      'id': db.genId(),
                      'date': db.today(),
                      'items': items,
                      'total': total,
                      'notes': _notesCtrl.text.trim(),
                      'createdAt': DateTime.now().toIso8601String(),
                    });
                    await db.saveCache();
                    db.notifyListeners();
                    if (sync.firebaseEnabled) sync.saveAndSync();
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('Registrar Consumo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
  }

  void _pickProduct(DbService db, Function setModalState) {
    final sellable = db.getSellableProducts();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleccionar Producto'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: sellable.map((sp) {
              return ListTile(
                dense: true,
                title: Text(sp.product.name),
                subtitle: Text(fmtMoney(sp.link.salePrice.toDouble())),
                onTap: () {
                  final exists = _newItems.indexWhere((i) => i.productId == sp.product.id);
                  if (exists >= 0) {
                    _newItems[exists].qty++;
                  } else {
                    _newItems.add(_ConsumptionItem(productId: sp.product.id, qty: 1));
                  }
                  setModalState(() {});
                  Navigator.pop(ctx);
                },
              );
            }).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      ),
    );
  }
}

class _ConsumptionItem {
  final String productId;
  int qty;
  _ConsumptionItem({required this.productId, this.qty = 1});
}
