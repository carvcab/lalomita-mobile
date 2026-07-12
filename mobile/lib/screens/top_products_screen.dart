import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../utils/format.dart';

class TopProductsScreen extends StatefulWidget {
  const TopProductsScreen({super.key});

  @override
  State<TopProductsScreen> createState() => _TopProductsScreenState();
}

class _TopProductsScreenState extends State<TopProductsScreen> {
  String _period = 'all';
  int _topN = 10;
  String? _supplierId;
  String? _category;

  List<Map<String, dynamic>> _filterSales(DbService db) {
    final today = db.today();
    return db.sales.where((s) {
      final date = s['date']?.toString() ?? '';
      switch (_period) {
        case 'today':
          return date == today;
        case 'week': {
          final d = DateTime.tryParse(date);
          if (d == null) return false;
          final now = DateTime.now();
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return d.isAfter(weekStart.subtract(const Duration(days: 1)));
        }
        case 'month': {
          final d = DateTime.tryParse(date);
          if (d == null) return false;
          return d.month == DateTime.now().month && d.year == DateTime.now().year;
        }
        default:
          return true;
      }
    }).toList();
  }

  List<_ProductSummary> _aggregate(DbService db) {
    final sales = _filterSales(db);
    final map = <String, _ProductSummary>{};

    for (final sale in sales) {
      for (final item in (sale['items'] as List? ?? [])) {
        final pid = item['productId'] as String? ?? '';
        final name = item['productName'] as String? ?? '';
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final total = (item['total'] as num?)?.toDouble() ?? 0.0;
        if (pid.isEmpty) continue;

        if (_supplierId != null) {
          final link = db.prodSuppliers.where((l) => l.productId == pid && l.supplierId == _supplierId).firstOrNull;
          if (link == null) continue;
        }

        if (_category != null) {
          final product = db.products.where((p) => p.id == pid).firstOrNull;
          if (product == null || product.category != _category) continue;
        }

        if (map.containsKey(pid)) {
          map[pid] = map[pid]!.copy(qty: map[pid]!.qty + qty, total: map[pid]!.total + total);
        } else {
          map[pid] = _ProductSummary(productId: pid, productName: name, qty: qty, total: total);
        }
      }
    }

    final sorted = map.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));
    return sorted.take(_topN).toList();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final top = _aggregate(db);
    final allSales = _filterSales(db);
    final grandTotal = allSales.fold(0.0, (s, sale) => s + (double.tryParse(sale['total']?.toString() ?? '0') ?? 0));
    final topTotal = top.fold(0.0, (s, p) => s + p.total);
    final maxQty = top.isNotEmpty ? top.first.qty : 1;

    final categories = db.products.map((p) => p.category).where((c) => c.isNotEmpty).toSet().toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        title: const Text('Productos más vendidos'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Period filter
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Período', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'today', label: Text('Hoy')),
                      ButtonSegment(value: 'week', label: Text('Semana')),
                      ButtonSegment(value: 'month', label: Text('Mes')),
                      ButtonSegment(value: 'all', label: Text('Todo')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) => setState(() => _period = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Top N + Supplier + Category
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filtros', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Mostrar:', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 5, label: Text('5')),
                          ButtonSegment(value: 10, label: Text('10')),
                          ButtonSegment(value: 20, label: Text('20')),
                          ButtonSegment(value: 50, label: Text('50')),
                        ],
                        selected: {_topN},
                        onSelectionChanged: (s) => setState(() => _topN = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: _supplierId,
                    decoration: InputDecoration(
                      labelText: 'Proveedor',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos los proveedores')),
                      ...db.suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                  const SizedBox(height: 12),
                  if (categories.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        FilterChip(
                          label: const Text('Todas'),
                          selected: _category == null,
                          onSelected: (_) => setState(() => _category = null),
                          selectedColor: const Color(0xFF0D9488),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(color: _category == null ? Colors.white : Colors.black87),
                        ),
                        ...categories.map((c) => FilterChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                          selectedColor: const Color(0xFF0D9488),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(color: _category == c ? Colors.white : Colors.black87),
                        )),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Summary
          Card(
            color: const Color(0xFF0D9488).withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text('$grandTotal', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                        const Text('Ventas totales', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  Expanded(
                    child: Column(
                      children: [
                        Text(fmtMoney(topTotal), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                        const Text('Top productos', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Top products list
          if (top.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No hay ventas en este período', style: TextStyle(color: Colors.grey, fontSize: 16))),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 32, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600))),
                        const Expanded(child: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54))),
                        SizedBox(width: 60, child: Text('Cant.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54), textAlign: TextAlign.right)),
                        SizedBox(width: 90, child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54), textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...List.generate(top.length, (i) {
                    final p = top[i];
                    final pct = maxQty > 0 ? p.qty / maxQty : 0.0;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: i < 3 ? const Color(0xFF0D9488) : Colors.grey.shade600)),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: pct,
                                        backgroundColor: Colors.grey.shade200,
                                        color: i == 0 ? const Color(0xFF0D9488) : i == 1 ? Colors.amber.shade700 : i == 2 ? Colors.brown.shade400 : Colors.grey.shade400,
                                        minHeight: 4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 60,
                                child: Text('${p.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.right),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(fmtMoney(p.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0D9488)), textAlign: TextAlign.right),
                              ),
                            ],
                          ),
                        ),
                        if (i < top.length - 1) const Divider(height: 1, indent: 16),
                      ],
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductSummary {
  final String productId;
  final String productName;
  final int qty;
  final double total;

  _ProductSummary({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.total,
  });

  _ProductSummary copy({int? qty, double? total}) => _ProductSummary(
        productId: productId,
        productName: productName,
        qty: qty ?? this.qty,
        total: total ?? this.total,
      );
}
