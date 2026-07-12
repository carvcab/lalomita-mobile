import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';
import '../models/lalomita_db.dart';

class EditSaleScreen extends StatefulWidget {
  final Map<String, dynamic> sale;

  const EditSaleScreen({super.key, required this.sale});

  @override
  State<EditSaleScreen> createState() => _EditSaleScreenState();
}

class _EditSaleScreenState extends State<EditSaleScreen> {
  late Map<String, dynamic> _editingSale;
  late List<Map<String, dynamic>> _items;
  final _searchCtrl = TextEditingController();
  List<LalomitaProduct> _searchResults = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _editingSale = Map<String, dynamic>.from(widget.sale);
    final originalItems = widget.sale['items'] as List? ?? [];
    _items = originalItems.map((i) => Map<String, dynamic>.from(i)).toList();
    _editingSale['items'] = _items;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _subtotal {
    return _items.fold(0.0, (sum, item) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unitPrice'] as num?)?.toDouble() ?? (item['sellPrice'] as num?)?.toDouble() ?? 0.0;
      return sum + (price * qty);
    });
  }

  void _searchProducts(String query, DbService db) {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final q = query.toLowerCase();
    final matches = db.products.where((p) => p.active && p.name.toLowerCase().contains(q)).take(5).toList();
    setState(() => _searchResults = matches);
  }

  void _addItem(LalomitaProduct product, DbService db) {
    final link = db.getDefaultLink(product.id);
    final price = link?.salePrice ?? 0.0;
    
    setState(() {
      final existingIdx = _items.indexWhere((i) => i['productId'] == product.id);
      if (existingIdx != -1) {
        _items[existingIdx]['quantity'] = ((_items[existingIdx]['quantity'] as num?)?.toInt() ?? 0) + 1;
      } else {
        _items.add({
          'productId': product.id,
          'productName': product.name,
          'quantity': 1,
          'unitPrice': price,
          'sellPrice': price,
          'purchasePrice': link?.purchasePrice ?? 0.0,
        });
      }
      _searchResults = [];
      _searchCtrl.clear();
    });
  }

  void _removeItem(int idx) {
    setState(() {
      _items.removeAt(idx);
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La venta no puede quedar vacía. Si deseas eliminarla, usa el botón Eliminar en el historial.')),
      );
      return;
    }

    setState(() => _saving = true);
    
    final total = _subtotal - (double.tryParse(_editingSale['discount']?.toString() ?? '0') ?? 0.0);
    _editingSale['total'] = total;
    if (_editingSale['paymentMethod'] == 'cash') {
      _editingSale['cashAmount'] = total;
    }
    _editingSale['updatedAt'] = DateTime.now().toIso8601String();

    try {
      final originalItems = List<Map<String, dynamic>>.from(widget.sale['items'] as List? ?? []);
      await context.read<SyncService>().updateSale(_editingSale, originalItems).timeout(const Duration(seconds: 15));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Venta actualizada: ${fmtMoney(total)}')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar venta: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final method = _editingSale['paymentMethodName'] ?? _editingSale['paymentMethod'] ?? 'Efectivo';
    final client = _editingSale['customerName'] ?? '-';
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: const Text('Editar Venta', style: TextStyle(fontSize: 18)),
        actions: [
          if (!_saving)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
              tooltip: 'Guardar cambios',
            ),
        ],
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D9488)))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.white,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Método: $method', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                          Text('Cliente: $client', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (val) => _searchProducts(val, db),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF0D9488)),
                          hintText: 'Buscar producto para agregar...',
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _searchProducts('', db);
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    color: Colors.white,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (ctx, idx) {
                        final p = _searchResults[idx];
                        final link = db.getDefaultLink(p.id);
                        final price = link?.salePrice ?? 0.0;
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(p.category, style: const TextStyle(fontSize: 12)),
                          trailing: Text(fmtMoney(price), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
                          onTap: () => _addItem(p, db),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (ctx, idx) {
                      final item = _items[idx];
                      final name = item['productName'] ?? 'Producto';
                      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
                      final price = (item['unitPrice'] as num?)?.toDouble() ?? (item['sellPrice'] as num?)?.toDouble() ?? 0.0;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            setState(() {
                                              if (item['quantity'] > 1) {
                                                item['quantity']--;
                                              } else {
                                                _removeItem(idx);
                                              }
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0D9488)),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            setState(() {
                                              item['quantity']++;
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 24),
                                        Expanded(
                                          child: SizedBox(
                                            height: 36,
                                            child: TextField(
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                prefixText: r'$ ',
                                                labelText: 'P. Unit',
                                                border: OutlineInputBorder(),
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                              ),
                                              controller: TextEditingController(text: price.toStringAsFixed(0))
                                                ..selection = TextSelection.collapsed(offset: price.toStringAsFixed(0).length),
                                              onChanged: (val) {
                                                item['unitPrice'] = double.tryParse(val) ?? 0.0;
                                                item['sellPrice'] = double.tryParse(val) ?? 0.0;
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _removeItem(idx),
                                  ),
                                  Text(
                                    fmtMoney(price * qty),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488), fontSize: 15),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(fmtMoney(_subtotal), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF0D9488))),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
