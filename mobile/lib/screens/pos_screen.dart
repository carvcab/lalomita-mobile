// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lalomita_db.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';
import '../widgets/barcode_scanner_sheet.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();
  final _cart = <String, SaleItem>{};
  String _category = '';
  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _subtotal => _cart.values.fold(0.0, (s, i) => s + i.total);

  void _addToCart(LalomitaProduct product, ProdSupplierLink link) {
    final db = context.read<DbService>();
    if (!link.salePrice.isFinite || link.salePrice <= 0) {
      _snack('Precio inválido: ${product.name}');
      return;
    }
    final stock = db.getStock(product.id);
    if (stock <= 0) {
      _snack('Sin stock');
      return;
    }
    if (_cart.containsKey(product.id) && _cart[product.id]!.quantity >= stock) {
      _snack('Stock insuficiente: ${product.name}');
      return;
    }
    setState(() {
      if (_cart.containsKey(product.id)) {
        _cart[product.id]!.quantity++;
      } else {
        _cart[product.id] = SaleItem(
          productId: product.id,
          productName: product.name,
          unitPrice: link.salePrice,
        );
      }
    });
  }

  void _changeQty(String id, int delta) {
    final db = context.read<DbService>();
    final item = _cart[id];
    if (item == null) return;
    if (delta > 0) {
      final stock = db.getStock(item.productId);
      if (item.quantity + delta > stock) {
        _snack('Stock insuficiente');
        return;
      }
    }
    setState(() {
      item.quantity += delta;
      if (item.quantity <= 0) _cart.remove(id);
    });
  }

  Future<void> _scanBarcode() async {
    final code = await BarcodeScannerSheet.show(context, title: 'Escanear para vender');
    if (code == null || !mounted) return;
    final db = context.read<DbService>();
    final product = db.findByBarcode(code);
    if (product == null) {
      _snack('Producto no encontrado: $code');
      return;
    }
    final link = db.getDefaultLink(product.id);
    if (link == null || link.salePrice <= 0) {
      _snack('Producto sin precio de venta');
      return;
    }
    _addToCart(product, link);
    _snack('Agregado: ${product.name}');
  }

  Future<void> _showCheckoutDialog() async {
    if (_cart.isEmpty) return;
    final db = context.read<DbService>();
    final sync = context.read<SyncService>();

    for (final item in _cart.values) {
      final p = db.products.where((x) => x.id == item.productId).firstOrNull;
      if (p != null && db.getStock(item.productId) < item.quantity) {
        _snack('Stock insuficiente: ${p.name}');
        return;
      }
    }

    final payMethod = ValueNotifier<String>('cash');
    final amountReceivedCtrl = TextEditingController();
    final customerNameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final printReceipt = ValueNotifier<bool>(false);
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final received = double.tryParse(amountReceivedCtrl.text) ?? 0;
            final change = received - _subtotal;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.payment, color: Color(0xFF0D9488)),
                  const SizedBox(width: 8),
                  const Text('Cobrar', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(fmtMoney(_subtotal), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Método de pago', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'cash', label: Text('Efectivo'), icon: Icon(Icons.payments)),
                        ButtonSegment(value: 'card', label: Text('Tarjeta'), icon: Icon(Icons.credit_card)),
                        ButtonSegment(value: 'credit', label: Text('Fiado'), icon: Icon(Icons.book)),
                      ],
                      selected: {payMethod.value},
                      onSelectionChanged: (s) {
                        payMethod.value = s.first;
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    if (payMethod.value == 'cash') ...[
                      TextField(
                        controller: amountReceivedCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Con cuánto paga?',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (received >= _subtotal && _subtotal > 0)
                        Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Vuelto:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(fmtMoney(change), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.green)),
                              ],
                            ),
                          ),
                        ),
                      if (received > 0 && received < _subtotal)
                        Text('Faltan ${fmtMoney(_subtotal - received)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ],
                    if (payMethod.value == 'credit') ...[
                      Autocomplete<String>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                          final input = textEditingValue.text.toLowerCase();
                          final customers = db.sales
                              .where((s) => s['paymentMethod'] == 'credit')
                              .map((s) => s['customerName']?.toString() ?? '')
                              .where((n) => n.isNotEmpty)
                              .toSet()
                              .where((name) => name.toLowerCase().contains(input))
                              .toList();
                          return customers;
                        },
                        onSelected: (v) => customerNameCtrl.text = v,
                        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                          controller.addListener(() => customerNameCtrl.text = controller.text);
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Nombre del cliente *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.person),
                            ),
                            style: const TextStyle(fontSize: 16),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nota (opcional)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        maxLines: 2,
                      ),
                    ],
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: printReceipt.value,
                      onChanged: (v) => setDialogState(() => printReceipt.value = v ?? false),
                      title: const Text('Imprimir factura'),
                      subtitle: const Text('Compartir recibo para imprimir'),
                      secondary: const Icon(Icons.receipt),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                  child: const Text('CANCELAR'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (payMethod.value == 'credit' && customerNameCtrl.text.trim().isEmpty) {
                            _snack('Nombre del cliente obligatorio para fiado');
                            return;
                          }
                          if (payMethod.value == 'cash' && amountReceivedCtrl.text.trim().isEmpty) {
                            _snack('Indica con cuánto paga');
                            return;
                          }
                          setDialogState(() => saving = true);

                          final methodName = switch (payMethod.value) {
                            'cash' => 'Efectivo',
                            'card' => 'Tarjeta',
                            'credit' => 'Crédito',
                            _ => 'Efectivo',
                          };

                          final sale = LalomitaSale(
                            id: db.genId(),
                            date: db.today(),
                            items: _cart.values.toList(),
                            total: _subtotal,
                            paymentMethod: payMethod.value,
                            paymentMethodName: methodName,
                            customerName: customerNameCtrl.text.trim(),
                            notes: notesCtrl.text.trim().isEmpty ? 'Venta desde app móvil' : notesCtrl.text.trim(),
                            createdAt: DateTime.now().toIso8601String(),
                          );

                          try {
                            await sync.completeSale(sale).timeout(const Duration(seconds: 15));

                            if (printReceipt.value && ctx.mounted) {
                              _shareReceipt(sale);
                            }

                            if (ctx.mounted) {
                              Navigator.pop(ctx, true);
                              if (payMethod.value == 'credit') {
                                _snack('Fiado registrado: \$${fmtMoney(sale.total)}');
                              } else {
                                _snack('Venta registrada: \$${fmtMoney(sale.total)}');
                              }
                            }
                          } catch (e) {
                            print("Error al cobrar venta: $e");
                            if (ctx.mounted) {
                              setDialogState(() => saving = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Error al guardar la venta: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  icon: saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle),
                  label: Text(saving ? 'GUARDANDO...' : 'COBRAR \$${fmtMoney(_subtotal)}'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      setState(() => _cart.clear());
    }
  }

  void _shareReceipt(LalomitaSale sale) {
    final buffer = StringBuffer();
    buffer.writeln('================================');
    buffer.writeln('    VARIEDADES LA LOMITA');
    buffer.writeln('================================');
    buffer.writeln('Fecha: ${fmtDate(sale.createdAt)}');
    buffer.writeln('Método: ${sale.paymentMethodName}');
    buffer.writeln('--------------------------------');
    for (final item in sale.items) {
      buffer.writeln('${item.quantity}x ${item.productName}');
      buffer.writeln('     ${fmtMoney(item.unitPrice)} = ${fmtMoney(item.total)}');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('TOTAL: ${fmtMoney(sale.total)}');
    if (sale.paymentMethodName == 'Crédito' && sale.customerName.isNotEmpty) {
      buffer.writeln('Cliente: ${sale.customerName}');
    }
    buffer.writeln('================================');
    buffer.writeln('Gracias por su compra!');

    Share.share(
      buffer.toString(),
      subject: 'Factura La Lomita - ${fmtDate(sale.createdAt)}',
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();
    final q = _searchCtrl.text.toLowerCase();
    var items = db.getSellableProducts();
    if (_category.isNotEmpty) items = items.where((e) => e.product.category == _category).toList();
    if (q.isNotEmpty) {
      items = items.where((e) =>
          e.product.name.toLowerCase().contains(q) ||
          e.product.barcode.contains(q) ||
          e.product.category.toLowerCase().contains(q)).toList();
    }
    final categories = {...items.map((e) => e.product.category).where((c) => c.isNotEmpty)}.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar producto...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                  foregroundColor: Colors.white,
                  minimumSize: const Size(52, 52),
                ),
              ),
              FutureBuilder<int>(
                future: _suspendedCount(),
                builder: (_, snap) {
                  final count = snap.data ?? 0;
                  return IconButton(
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count', style: const TextStyle(fontSize: 10)),
                      child: const Icon(Icons.pause_circle_outline),
                    ),
                    tooltip: 'Ventas en espera',
                    onPressed: _showSuspendedCartsSheet,
                  );
                },
              ),
              IconButton(
                onPressed: () => sync.sync(),
                icon: sync.syncing
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(sync.connected ? Icons.cloud_done : Icons.cloud_off, color: sync.connected ? Colors.green : Colors.grey),
              ),
            ],
          ),
        ),
        if (categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _catChip('Todos', _category.isEmpty, () => setState(() => _category = '')),
                ...categories.map((c) => _catChip(c, _category == c, () => setState(() => _category = c))),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) {
              final isWide = constraints.maxWidth >= 700;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildProductGrid(db, items),
                    ),
                    _buildCartPanel(db),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: _buildProductGrid(db, items)),
                  if (_cart.isNotEmpty) _buildMobileCartBar(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductGrid(DbService db, List<({LalomitaProduct product, ProdSupplierLink link})> items) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 360 ? 2 : (width < 560 ? 3 : (width < 760 ? 4 : 5));
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 1.1,
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final e = items[i];
            final stock = db.getStock(e.product.id);
            final out = stock <= 0;
            return Material(
              color: out ? Colors.grey.shade200 : Colors.white,
              borderRadius: BorderRadius.circular(10),
              elevation: 1.5,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: out ? null : () => _addToCart(e.product, e.link),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: out ? Colors.grey : Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: stock <= 0
                                  ? Colors.red
                                  : (stock <= 5 ? Colors.orange : Colors.teal.shade100),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$stock',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: stock <= 5 ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        fmtMoney(e.link.salePrice),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: out ? Colors.grey : const Color(0xFF0D9488),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCartPanel(DbService db) {
    return Container(
      width: 300,
      margin: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart, color: Color(0xFF0D9488)),
                const SizedBox(width: 8),
                Text('Carrito (${_cart.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cart.isEmpty
                ? const Center(child: Text('Vacío', style: TextStyle(color: Colors.grey, fontSize: 16)))
                : ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (_, i) {
                      final item = _cart.values.elementAt(i);
                      return ListTile(
                        dense: true,
                        title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(fmtMoney(item.unitPrice)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _changeQty(item.productId, -1),
                            ),
                            Text('${item.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _changeQty(item.productId, 1),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(fmtMoney(_subtotal), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _cart.isEmpty ? null : _showCheckoutDialog,
                    icon: const Icon(Icons.check_circle, size: 24),
                    label: const Text('COBRAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Vender a Fiado'),
                          content: const Text('Agrega productos al carrito, luego presiona COBRAR y selecciona el método "Fiado".'),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                        ),
                      );
                    },
                    icon: const Icon(Icons.book, size: 18),
                    label: const Text('Vender a Fiado', style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0D9488)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCartBar() {
    return GestureDetector(
      onTap: _cart.isNotEmpty ? _showCartBottomSheet : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shopping_cart, size: 16, color: Color(0xFF0D9488)),
                        const SizedBox(width: 4),
                        Text('${_cart.length} ${_cart.length == 1 ? 'producto' : 'productos'}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                    Text(fmtMoney(_subtotal), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.pause_circle_outline, size: 28),
                tooltip: 'Pausar venta',
                onPressed: _cart.isNotEmpty ? _suspendCart : null,
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _cart.isNotEmpty ? _showCheckoutDialog : null,
                icon: const Icon(Icons.shopping_cart_checkout, size: 20),
                label: const Text('COBRAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollCtrl) {
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Row(
                          children: [
                            const Icon(Icons.shopping_cart, color: Color(0xFF0D9488)),
                            const SizedBox(width: 8),
                            Text('Carrito (${_cart.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.pause_circle_outline, color: Color(0xFF0D9488)),
                              tooltip: 'Pausar venta',
                              onPressed: () {
                                Navigator.pop(ctx);
                                _suspendCart();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_sweep, color: Colors.red),
                              tooltip: 'Vaciar carrito',
                              onPressed: () {
                                setState(() => _cart.clear());
                                Navigator.pop(ctx);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: _cart.isEmpty
                            ? const Center(child: Text('Carrito vacío', style: TextStyle(color: Colors.grey, fontSize: 16)))
                            : ListView.builder(
                                controller: scrollCtrl,
                                itemCount: _cart.length,
                                itemBuilder: (_, i) {
                                  final item = _cart.values.elementAt(i);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    child: Card(
                                      margin: EdgeInsets.zero,
                                      child: ListTile(
                                        dense: true,
                                        title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        subtitle: Text('${fmtMoney(item.unitPrice)} c/u'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, size: 22),
                                              onPressed: () {
                                                _changeQty(item.productId, -1);
                                                setSheetState(() {});
                                              },
                                            ),
                                            SizedBox(
                                              width: 28,
                                              child: Text('${item.quantity}', textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, size: 22),
                                              onPressed: () {
                                                _changeQty(item.productId, 1);
                                                setSheetState(() {});
                                              },
                                            ),
                                            const SizedBox(width: 4),
                                            SizedBox(
                                              width: 80,
                                              child: Text(fmtMoney(item.total),
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${_cart.length} ${_cart.length == 1 ? 'producto' : 'productos'}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  Text(fmtMoney(_subtotal),
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showCheckoutDialog();
                              },
                              icon: const Icon(Icons.shopping_cart_checkout, size: 20),
                              label: const Text('COBRAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0D9488),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              ),
                            ),
                          ],
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

  static const _suspendedCartsKey = 'lalomita_suspended_carts';

  Future<int> _suspendedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_suspendedCartsKey);
    if (raw == null) return 0;
    try {
      return (jsonDecode(raw) as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _suspendCart() async {
    if (_cart.isEmpty) return;
    final cartData = _cart.values.map((item) => {
      'productId': item.productId,
      'productName': item.productName,
      'unitPrice': item.unitPrice,
      'quantity': item.quantity,
    }).toList();
    final prefs = await SharedPreferences.getInstance();
    final carts = (jsonDecode(prefs.getString(_suspendedCartsKey) ?? '[]') as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    carts.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'date': DateTime.now().toIso8601String(),
      'items': cartData,
    });
    await prefs.setString(_suspendedCartsKey, jsonEncode(carts));
    setState(() => _cart.clear());
    if (mounted) _snack('Venta guardada en espera');
  }

  void _showSuspendedCartsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadSuspendedCarts(),
              builder: (_, snapshot) {
                final carts = snapshot.data ?? [];
                return DraggableScrollableSheet(
                  initialChildSize: 0.5,
                  minChildSize: 0.3,
                  maxChildSize: 0.8,
                  expand: false,
                  builder: (_, scrollCtrl) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              const Icon(Icons.pause_circle, color: Color(0xFF0D9488)),
                              const SizedBox(width: 8),
                              const Text('Ventas en espera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cerrar'),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        Expanded(
                          child: carts.isEmpty
                              ? const Center(child: Text('No hay ventas en espera', style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  controller: scrollCtrl,
                                  itemCount: carts.length,
                                  itemBuilder: (_, i) {
                                    final cart = carts[i];
                                    final items = (cart['items'] as List?) ?? [];
                                    final total = items.fold(0.0, (s, item) =>
                                        s + ((item['unitPrice'] as num?)?.toDouble() ?? 0) * ((item['quantity'] as num?)?.toInt() ?? 0));
                                    final time = _formatTime(cart['date'] as String? ?? '');
                                    final desc = items.take(3).map((item) =>
                                        '${item['quantity']}x ${item['productName']}').join(', ');
                                    return Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      child: ListTile(
                                        title: Text('$time - ${fmtMoney(total)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.folder_open, color: Color(0xFF0D9488)),
                                              tooltip: 'Reanudar',
                                              onPressed: () {
                                                _resumeCart(cart['id'] as String);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                                              tooltip: 'Eliminar',
                                              onPressed: () async {
                                                await _deleteSuspendedCart(cart['id'] as String);
                                                setSheetState(() {});
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadSuspendedCarts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_suspendedCartsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _deleteSuspendedCart(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_suspendedCartsKey);
    if (raw == null) return;
    final carts = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    carts.removeWhere((c) => c['id'] == id);
    await prefs.setString(_suspendedCartsKey, jsonEncode(carts));
  }

  void _resumeCart(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_suspendedCartsKey);
    if (raw == null) return;
    final carts = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final idx = carts.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    final cart = carts[idx];
    final items = (cart['items'] as List?) ?? [];

    setState(() {
      _cart.clear();
      for (final item in items) {
        final pid = item['productId'] as String? ?? '';
        final name = item['productName'] as String? ?? '';
        final price = (item['unitPrice'] as num?)?.toDouble() ?? 0;
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        if (pid.isNotEmpty) {
          _cart[pid] = SaleItem(
            productId: pid,
            productName: name,
            unitPrice: price,
            quantity: qty,
          );
        }
      }
    });

    carts.removeAt(idx);
    await prefs.setString(_suspendedCartsKey, jsonEncode(carts));
    _snack('Venta reanudada (${_cart.length} productos)');
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _catChip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.black87)),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFF0D9488),
        checkmarkColor: Colors.white,
      ),
    );
  }
}
