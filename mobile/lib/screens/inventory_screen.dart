// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lalomita_db.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import 'product_form_screen.dart';
import 'purchase_form_screen.dart';
import 'stock_adjustment_screen.dart';
import 'inventory_movements_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _showInactive = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Helper to show add/edit supplier dialog
  void _showSupplierDialog(BuildContext context, [LalomitaSupplier? supplier]) {
    final nameCtrl = TextEditingController(text: supplier?.name ?? '');
    final contactCtrl = TextEditingController(text: supplier?.contact ?? '');
    final addressCtrl = TextEditingController(text: supplier?.address ?? '');
    bool saving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(supplier == null ? 'Nuevo Proveedor' : 'Editar Proveedor'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contactCtrl,
                      decoration: const InputDecoration(labelText: 'Contacto / Teléfono'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(labelText: 'Dirección'),
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                if (supplier != null)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: saving
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('¿Eliminar proveedor?'),
                                content: Text('Esto eliminará a "${supplier.name}".'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCELAR')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    child: const Text('ELIMINAR'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              setDialogState(() => saving = true);
                              try {
                                await context.read<SyncService>().deleteSupplier(supplier.id).timeout(const Duration(seconds: 15));
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado' : e.toString()}')),
                                  );
                                }
                                setDialogState(() => saving = false);
                                return;
                              }
                              if (context.mounted) {
                                Navigator.pop(context); // Close edit dialog
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Proveedor eliminado')),
                                );
                              }
                            }
                          },
                  )
                else
                  const SizedBox.shrink(),
                Row(
                  children: [
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: const Text('CANCELAR'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Nombre obligatorio')),
                                );
                                return;
                              }
                              setDialogState(() => saving = true);
                              final sync = context.read<SyncService>();

                              try {
                                if (supplier == null) {
                                  await sync.registerSupplier(
                                    name: name,
                                    contact: contactCtrl.text.trim(),
                                    address: addressCtrl.text.trim(),
                                  ).timeout(const Duration(seconds: 15));
                                } else {
                                  await sync.updateSupplier(
                                    id: supplier.id,
                                    name: name,
                                    contact: contactCtrl.text.trim(),
                                    address: addressCtrl.text.trim(),
                                  ).timeout(const Duration(seconds: 15));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado' : e.toString()}')),
                                  );
                                }
                                setDialogState(() => saving = false);
                                return;
                              }
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      supplier == null ? 'Proveedor registrado' : 'Proveedor actualizado',
                                    ),
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                      ),
                      child: saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(supplier == null ? 'REGISTRAR' : 'GUARDAR'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: const Color(0xFF0D9488)),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: BorderSide(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();

    // Filter products
    final filteredProducts = db.products.where((p) {
      if (!_showInactive && !p.active) return false;
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F0EB),
        appBar: AppBar(
          toolbarHeight: 0, // Hide main toolbar, TabBar is enough
          bottom: const TabBar(
            labelColor: Color(0xFF0D9488),
            unselectedLabelColor: Colors.black54,
            indicatorColor: Color(0xFF0D9488),
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.shopping_bag), text: 'PRODUCTOS'),
              Tab(icon: Icon(Icons.receipt), text: 'COMPRAS'),
              Tab(icon: Icon(Icons.local_shipping), text: 'PROVEEDORES'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // --- Tab 1: Products ---
            Scaffold(
              backgroundColor: const Color(0xFFF5F0EB),
              floatingActionButton: FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProductFormScreen()),
                  );
                },
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                child: const Icon(Icons.add),
              ),
              body: Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar producto por nombre o código...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        _actionChip(Icons.shopping_bag, 'Recibir', () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseFormScreen()));
                        }),
                        const SizedBox(width: 8),
                        _actionChip(Icons.tune, 'Ajustar stock', () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const StockAdjustmentScreen()));
                        }),
                        const SizedBox(width: 8),
                        _actionChip(Icons.history, 'Movimientos', () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryMovementsScreen()));
                        }),
                        const Spacer(),
                        Switch(
                          value: _showInactive,
                          onChanged: (v) => setState(() => _showInactive = v),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        Text('Inactivos', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filteredProducts.isEmpty
                        ? const Center(
                            child: Text(
                              'No se encontraron productos.',
                              style: TextStyle(color: Colors.black54, fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredProducts.length,
                            itemBuilder: (context, index) {
                              final p = filteredProducts[index];
                              final stock = db.getStock(p.id);

                              // Lookup default price
                              final link = db.prodSuppliers.firstWhere(
                                (l) => l.productId == p.id && l.isDefault,
                                orElse: () => db.prodSuppliers.firstWhere(
                                  (l) => l.productId == p.id,
                                  orElse: () => ProdSupplierLink(id: '', productId: '', supplierId: ''),
                                ),
                              );

                              final isInactive = !p.active;
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                color: isInactive ? Colors.grey.shade100 : null,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  title: Row(
                                    children: [
                                      if (isInactive) ...[
                                        Icon(Icons.block, size: 16, color: Colors.red.shade300),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isInactive ? Colors.grey : null,
                                          decoration: isInactive ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    'Categoría: ${p.category.isEmpty ? "Sin categoría" : p.category}\n'
                                    'Código: ${p.barcode.isEmpty ? "S/N" : p.barcode}',
                                    style: const TextStyle(height: 1.3),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '\$ ${link.salePrice.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Color(0xFF0D9488),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: stock <= 0
                                              ? Colors.red.shade50
                                              : (stock <= 5 ? Colors.orange.shade50 : Colors.teal.shade50),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Stock: $stock',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: stock <= 0
                                                ? Colors.red
                                                : (stock <= 5 ? Colors.orange : const Color(0xFF0D9488)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ProductFormScreen(product: p),
                                      ),
                                    );
                                  },
                                  onLongPress: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => StockAdjustmentScreen(product: p),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

            // --- Tab 3: Purchases ---
            Scaffold(
              backgroundColor: const Color(0xFFF5F0EB),
              floatingActionButton: FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PurchaseFormScreen()),
                  );
                },
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                child: const Icon(Icons.add),
              ),
              body: db.purchases.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay compras registradas.\nPresiona + para recibir mercancía.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: db.purchases.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (context, index) {
                        final p = db.purchases.reversed.toList()[index];
                        final supplierId = p['supplierId'] as String? ?? '';
                        final supplier = db.suppliers.where((s) => s.id == supplierId).firstOrNull;
                        final items = p['items'] as List? ?? [];
                        final total = p['total'] as num? ?? 0;
                        final date = p['date'] as String? ?? '';
                        final invoice = p['invoiceNumber'] as String? ?? '';
                        final paid = p['paid'] as bool? ?? true;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: paid ? const Color(0xFFE0F2F1) : Colors.orange.shade100,
                              foregroundColor: paid ? const Color(0xFF0D9488) : Colors.orange,
                              child: Icon(paid ? Icons.check_circle : Icons.pending),
                            ),
                            title: Text(
                              supplier?.name ?? 'Sin proveedor',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '$date${invoice.isNotEmpty ? ' | Fact: $invoice' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: paid ? Colors.green.shade100 : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    paid ? 'Pagado' : 'Pendiente',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: paid ? Colors.green.shade700 : Colors.orange.shade700),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '\$${total.toStringAsFixed(0)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0D9488)),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    final sync = context.read<SyncService>();
                                    if (action == 'toggle') {
                                      p['paid'] = !paid;
                                      await db.saveCache();
                                      db.notifyListeners();
                                      if (sync.firebaseEnabled) sync.saveAndSync();
                                      setState(() {});
                                    } else if (action == 'delete') {
                                      db.purchases.removeWhere((x) => x['id'] == p['id']);
                                      await db.saveCache();
                                      db.notifyListeners();
                                      if (sync.firebaseEnabled) sync.saveAndSync();
                                      setState(() {});
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(value: 'toggle', child: Text(paid ? 'Marcar Pendiente' : 'Marcar Pagado')),
                                    const PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              ],
                            ),
                            children: [
                              ...items.map((item) {
                                final qty = item['quantity'] as num? ?? 0;
                                final name = item['productName'] as String? ?? '';
                                final buyPrice = item['purchasePrice'] as num? ?? 0;
                                return ListTile(
                                  dense: true,
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  trailing: Text(
                                    '$qty x \$${buyPrice.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // --- Tab 2: Suppliers ---
            Scaffold(
              backgroundColor: const Color(0xFFF5F0EB),
              floatingActionButton: FloatingActionButton(
                onPressed: () => _showSupplierDialog(context),
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                child: const Icon(Icons.local_shipping),
              ),
              body: db.suppliers.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay proveedores registrados.',
                        style: TextStyle(color: Colors.black54, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: db.suppliers.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (context, index) {
                        final s = db.suppliers[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFE0F2F1),
                              foregroundColor: Color(0xFF0D9488),
                              child: Icon(Icons.local_shipping),
                            ),
                            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              'Contacto: ${s.contact.isEmpty ? "S/N" : s.contact}\n'
                              'Dirección: ${s.address.isEmpty ? "S/N" : s.address}',
                              style: const TextStyle(height: 1.3),
                            ),
                            onTap: () => _showSupplierDialog(context, s),
                          ),
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
