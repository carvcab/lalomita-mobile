import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lalomita_db.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../widgets/barcode_scanner_sheet.dart';
import 'product_form_screen.dart';

class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _invoiceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _supplierId;
  final _items = <_PurchaseItem>[];
  bool _paid = true;
  bool _saving = false;

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.subtotal);

  Future<void> _scanBarcode() async {
    final code = await BarcodeScannerSheet.show(context, title: 'Escanear producto');
    if (code == null || !mounted) return;
    final db = context.read<DbService>();
    final product = db.findByBarcode(code);
    if (product == null) {
      final create = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Producto no encontrado'),
          content: Text('No existe un producto con el código:\n$code\n\n¿Quieres crear uno nuevo con este código de barras?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              child: const Text('CREAR PRODUCTO'),
            ),
          ],
        ),
      );
      if (create == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductFormScreen()),
        );
        if (mounted) {
          final created = db.findByBarcode(code);
          if (created != null) {
            _addProduct(created);
            _snack('${created.name} agregado a la compra');
          }
        }
      }
      return;
    }
    _addProduct(product);
  }

  void _addProduct(LalomitaProduct product) {
    final db = context.read<DbService>();
    final existing = _items.where((i) => i.productId == product.id).firstOrNull;
    if (existing != null) {
      existing.qtyCtrl.text = (int.tryParse(existing.qtyCtrl.text) ?? 0 + 1).toString();
      setState(() {});
      return;
    }
    final link = db.getDefaultLink(product.id);
    final item = _PurchaseItem(
      productId: product.id,
      productName: product.name,
      qtyCtrl: TextEditingController(text: '1'),
      buyPriceCtrl: TextEditingController(text: link?.purchasePrice.toString() ?? ''),
      sellPriceCtrl: TextEditingController(text: link?.salePrice.toString() ?? ''),
    );
    setState(() => _items.add(item));
  }

  void _removeItem(int index) {
    final item = _items[index];
    item.qtyCtrl.dispose();
    item.buyPriceCtrl.dispose();
    item.sellPriceCtrl.dispose();
    setState(() => _items.removeAt(index));
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      _snack('Agrega al menos un producto');
      return;
    }
    setState(() => _saving = true);
    final db = context.read<DbService>();
    final sync = context.read<SyncService>();

    final purchaseItems = <Map<String, dynamic>>[];
    for (final item in _items) {
      final qty = int.tryParse(item.qtyCtrl.text) ?? 0;
      if (qty <= 0) continue;
      final buyPrice = double.tryParse(item.buyPriceCtrl.text) ?? 0;
      final sellPrice = double.tryParse(item.sellPriceCtrl.text) ?? 0;
      purchaseItems.add({
        'productId': item.productId,
        'productName': item.productName,
        'quantity': qty,
        'purchasePrice': buyPrice,
        'salePrice': sellPrice,
        'subtotal': qty * buyPrice,
      });
    }

    if (purchaseItems.isEmpty) {
      _snack('Cantidades inválidas');
      setState(() => _saving = false);
      return;
    }

    final now = DateTime.now().toIso8601String();
    final purchase = {
      'id': db.genId(),
      'supplierId': _supplierId ?? '',
      'date': db.today(),
      'items': purchaseItems,
      'total': purchaseItems.fold(0.0, (s, i) => s + (i['subtotal'] as double)),
      'notes': _notesCtrl.text.trim(),
      'invoiceNumber': _invoiceCtrl.text.trim(),
      'paid': _paid,
      'createdAt': now,
      'updatedAt': now,
    };

    try {
      await sync.registerPurchase(purchase).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _snack('Compra registrada y sincronizada');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado' : e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: const Text('Recibir Mercancía'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Datos de la compra',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _supplierId,
                            decoration: InputDecoration(
                              labelText: 'Proveedor',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Sin proveedor')),
                              ...db.suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
                            ],
                            onChanged: (v) => setState(() => _supplierId = v),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _invoiceCtrl,
                            decoration: InputDecoration(
                              labelText: 'N° Factura / Remito',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notesCtrl,
                            decoration: InputDecoration(
                              labelText: 'Notas',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: const Text('Compra Pagada (descuenta de caja)'),
                            value: _paid,
                            onChanged: (v) => setState(() => _paid = v),
                            activeColor: const Color(0xFF0D9488),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Productos',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton.filled(
                        onPressed: _scanBarcode,
                        icon: const Icon(Icons.qr_code_scanner, size: 24),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => _showProductPicker(db),
                        icon: const Icon(Icons.search, size: 24),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'Agrega productos con el escáner o buscándolos',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._items.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.productName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20, color: Colors.red),
                                    onPressed: () => _removeItem(i),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: item.qtyCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Cantidad',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: item.buyPriceCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'P. compra',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        prefixText: '\$ ',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: item.sellPriceCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'P. venta',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        prefixText: '\$ ',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                              if (item.subtotal > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Subtotal: \$${item.subtotal.toStringAsFixed(0)}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_items.length} ${_items.length == 1 ? 'producto' : 'productos'}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        Text('\$${_total.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, size: 24),
                      label: const Text('GUARDAR COMPRA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProductPicker(DbService db) async {
    final searchCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = searchCtrl.text.toLowerCase();
            final active = db.products.where((p) => p.active && p.name.toLowerCase().contains(q)).toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollCtrl) {
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: TextField(
                          controller: searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Buscar producto...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                          ),
                          onChanged: (_) => setSheetState(() {}),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () async {
                              final countBefore = db.products.length;
                              Navigator.pop(ctx);
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ProductFormScreen()),
                              );
                              if (mounted && db.products.length > countBefore) {
                                final newProduct = db.products.lastOrNull;
                                if (newProduct != null) {
                                  _addProduct(newProduct);
                                }
                              }
                            },
                            icon: const Icon(Icons.add_circle, color: Color(0xFF0D9488)),
                            label: const Text(
                              'Crear producto nuevo',
                              style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: active.isEmpty
                            ? const Center(child: Text('Sin resultados'))
                            : ListView.builder(
                                controller: scrollCtrl,
                                itemCount: active.length,
                                itemBuilder: (_, i) {
                                  final p = active[i];
                                  return ListTile(
                                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('Código: ${p.barcode.isEmpty ? "S/N" : p.barcode}'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _addProduct(p);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PurchaseItem {
  final String productId;
  final String productName;
  final TextEditingController qtyCtrl;
  final TextEditingController buyPriceCtrl;
  final TextEditingController sellPriceCtrl;

  _PurchaseItem({
    required this.productId,
    required this.productName,
    required this.qtyCtrl,
    required this.buyPriceCtrl,
    required this.sellPriceCtrl,
  });

  double get subtotal {
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final price = double.tryParse(buyPriceCtrl.text) ?? 0;
    return qty * price;
  }
}
