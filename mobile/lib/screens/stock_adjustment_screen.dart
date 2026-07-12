import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lalomita_db.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';

class StockAdjustmentScreen extends StatefulWidget {
  final LalomitaProduct? product;
  const StockAdjustmentScreen({super.key, this.product});

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  final _qtyCtrl = TextEditingController(text: '0');
  final _reasonCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String? _selectedProductId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _selectedProductId = widget.product!.id;
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedProductId == null) {
      _snack('Selecciona un producto');
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    if (qty == 0) {
      _snack('La cantidad debe ser diferente de cero');
      return;
    }
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('Indica el motivo del ajuste');
      return;
    }

    setState(() => _saving = true);
    final db = context.read<DbService>();
    final sync = context.read<SyncService>();
    final product = db.products.where((p) => p.id == _selectedProductId).firstOrNull;

    final adjustment = {
      'id': db.genId(),
      'productId': _selectedProductId,
      'productName': product?.name ?? '',
      'quantity': qty,
      'reason': reason,
      'date': db.today(),
      'createdAt': DateTime.now().toIso8601String(),
    };

    try {
      await sync.registerStockAdjustment(adjustment).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _snack('Stock ajustado');
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

    LalomitaProduct? selected;
    int currentStock = 0;
    if (_selectedProductId != null) {
      selected = db.products.where((p) => p.id == _selectedProductId).firstOrNull;
      currentStock = db.getStock(_selectedProductId!);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: const Text('Ajustar Stock'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Seleccionar Producto',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (widget.product == null) ...[
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar producto...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: ListView(
                          children: db.products
                              .where((p) {
                                final q = _searchCtrl.text.toLowerCase();
                                return p.active && (q.isEmpty || p.name.toLowerCase().contains(q) || p.barcode.toLowerCase().contains(q));
                              })
                              .map((p) {
                                final stock = db.getStock(p.id);
                                return RadioListTile<String>(
                                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  subtitle: Text('Stock: $stock | ${p.barcode.isEmpty ? "S/N" : p.barcode}',
                                      style: const TextStyle(fontSize: 12)),
                                  value: p.id,
                                  groupValue: _selectedProductId,
                                  onChanged: (v) => setState(() => _selectedProductId = v),
                                  activeColor: const Color(0xFF0D9488),
                                  dense: true,
                                );
                              })
                              .toList(),
                        ),
                      ),
                    ],
                    if (selected != null) ...[
                      if (widget.product == null)
                        const Divider()
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            selected.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                          ),
                        ),
                      Card(
                        color: Colors.teal.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Stock actual:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              Text(
                                '$currentStock',
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0D9488)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Cantidad (+ agregar, - quitar)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.add_box),
                        ),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (int.tryParse(_qtyCtrl.text) != 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Text(
                                'Resultado: ${currentStock + (int.tryParse(_qtyCtrl.text) ?? 0)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: currentStock + (int.tryParse(_qtyCtrl.text) ?? 0) >= 0
                                      ? const Color(0xFF0D9488)
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _reasonCtrl,
                        decoration: InputDecoration(
                          labelText: 'Motivo del ajuste *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.description),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.tune, size: 24),
                          label: const Text('AJUSTAR STOCK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
