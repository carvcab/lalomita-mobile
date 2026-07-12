// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lalomita_db.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../widgets/barcode_scanner_sheet.dart';

class ProductFormScreen extends StatefulWidget {
  final LalomitaProduct? product;
  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _buyCtrl = TextEditingController();
  final _sellCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');
  String? _supplierId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.product != null) {
        final p = widget.product!;
        _nameCtrl.text = p.name;
        _categoryCtrl.text = p.category;
        _barcodeCtrl.text = p.barcode;
        _stockCtrl.text = p.initialStock.toString();

        final db = context.read<DbService>();
        // Find default link
        final link = db.prodSuppliers.firstWhere(
          (l) => l.productId == p.id && l.isDefault,
          orElse: () => db.prodSuppliers.firstWhere(
            (l) => l.productId == p.id,
            orElse: () => ProdSupplierLink(id: '', productId: '', supplierId: ''),
          ),
        );
        if (link.id.isNotEmpty) {
          setState(() {
            _supplierId = link.supplierId.isEmpty ? null : link.supplierId;
            _buyCtrl.text = link.purchasePrice == 0 ? '' : link.purchasePrice.toString();
            _sellCtrl.text = link.salePrice == 0 ? '' : link.salePrice.toString();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _barcodeCtrl.dispose();
    _buyCtrl.dispose();
    _sellCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await BarcodeScannerSheet.show(context, title: 'Escanear producto');
    if (code != null) setState(() => _barcodeCtrl.text = code);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Nombre obligatorio');
      return;
    }
    setState(() => _saving = true);
    final sync = context.read<SyncService>();

    final buyPrice = double.tryParse(_buyCtrl.text) ?? 0;
    final sellPrice = double.tryParse(_sellCtrl.text) ?? 0;

    try {
      if (widget.product != null) {
        // Edit Mode
        await sync.updateProduct(
          id: widget.product!.id,
          name: name,
          category: _categoryCtrl.text.trim(),
          barcode: _barcodeCtrl.text.trim(),
          supplierId: _supplierId ?? '',
          buyPrice: buyPrice,
          sellPrice: sellPrice,
        ).timeout(const Duration(seconds: 15));
        if (!mounted) return;
        _snack('Producto actualizado');
        Navigator.pop(context);
      } else {
        // Create Mode
        await sync.registerProduct(
          name: name,
          category: _categoryCtrl.text.trim(),
          barcode: _barcodeCtrl.text.trim(),
          supplierId: _supplierId ?? '',
          buyPrice: buyPrice,
          sellPrice: sellPrice,
          initialStock: int.tryParse(_stockCtrl.text) ?? 0,
        ).timeout(const Duration(seconds: 15));
        if (!mounted) return;
        _snack('Producto registrado y sincronizado');
        _nameCtrl.clear();
        _categoryCtrl.clear();
        _barcodeCtrl.clear();
        _buyCtrl.clear();
        _sellCtrl.clear();
        _stockCtrl.text = '0';
        setState(() => _supplierId = null);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado. Verifica tu conexión.' : e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dar de baja producto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se desactivará "${widget.product!.name}" y no aparecerá en ventas.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DAR DE BAJA'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();

    if (confirmed != true) return;
    setState(() => _saving = true);
    final sync = context.read<SyncService>();
    try {
      await sync.deleteProduct(widget.product!.id, reason: reasonCtrl.text.trim()).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _snack('Producto dado de baja');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado' : e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreProduct() async {
    setState(() => _saving = true);
    final sync = context.read<SyncService>();
    try {
      await sync.restoreProduct(widget.product!.id).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _snack('Producto reactivado');
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
    final isEdit = widget.product != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: isEdit
          ? AppBar(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              title: const Text('Editar Producto'),
            )
          : null,
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
                    Text(
                      isEdit ? 'Editar Producto' : 'Registrar Producto',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEdit
                          ? 'Modifica los datos del producto. Los cambios se sincronizarán.'
                          : 'Escanea el código de barras y completa los datos. Se sincroniza con el PC.',
                      style: const TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _barcodeCtrl,
                            decoration: InputDecoration(
                              labelText: 'Código de barras',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.barcode_reader),
                            ),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _scanBarcode,
                          icon: const Icon(Icons.qr_code_scanner, size: 28),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            minimumSize: const Size(56, 56),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nombre del producto *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _categoryCtrl,
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Precio compra',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixText: '\$ ',
                            ),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _sellCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Precio venta',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixText: '\$ ',
                            ),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    if (!isEdit) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Stock inicial',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 24),
                        label: Text(
                          isEdit ? 'GUARDAR CAMBIOS' : 'GUARDAR Y SINCRONIZAR',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                      ),
                    ),
                    if (isEdit && (widget.product?.active ?? true)) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _delete,
                          icon: const Icon(Icons.block, color: Colors.red),
                          label: const Text('DAR DE BAJA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                    if (isEdit && widget.product != null && !widget.product!.active) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _restoreProduct,
                          icon: const Icon(Icons.undo, color: Color(0xFF0D9488)),
                          label: const Text('REACTIVAR PRODUCTO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0D9488)),
                          ),
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
