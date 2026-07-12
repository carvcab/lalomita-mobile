import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lalomita_db.dart';
import '../services/db_service.dart';
import '../utils/format.dart';
import 'top_products_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'today';

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

  double _saleProfit(DbService db, Map<String, dynamic> sale) {
    final items = sale['items'] as List? ?? [];
    double profit = 0;
    for (final item in items) {
      final pid = item['productId']?.toString() ?? '';
      final link = db.prodSuppliers.firstWhere(
        (l) => l.productId == pid && l.isDefault,
        orElse: () => db.prodSuppliers.firstWhere(
          (l) => l.productId == pid,
          orElse: () => ProdSupplierLink(id: '', productId: '', supplierId: ''),
        ),
      );
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      profit += (unitPrice - link.purchasePrice) * qty;
    }
    return profit;
  }

  Map<String, double> _productProfits(DbService db, List<Map<String, dynamic>> sales) {
    final map = <String, double>{};
    for (final sale in sales) {
      final items = sale['items'] as List? ?? [];
      for (final item in items) {
        final name = item['productName']?.toString() ?? '';
        final pid = item['productId']?.toString() ?? '';
        if (name.isEmpty || pid.isEmpty) continue;
        final link = db.prodSuppliers.firstWhere(
          (l) => l.productId == pid && l.isDefault,
          orElse: () => db.prodSuppliers.firstWhere(
            (l) => l.productId == pid,
            orElse: () => ProdSupplierLink(id: '', productId: '', supplierId: ''),
          ),
        );
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
        map[name] = (map[name] ?? 0) + (unitPrice - link.purchasePrice) * qty;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sales = _filterSales(db);
    final total = sales.fold(0.0, (s, sale) => s + (double.tryParse(sale['total']?.toString() ?? '0') ?? 0));
    final cashSales = sales.where((s) => s['paymentMethod'] == 'cash').fold(0.0, (s, sale) => s + (double.tryParse(sale['total']?.toString() ?? '0') ?? 0));
    final cardSales = sales.where((s) => s['paymentMethod'] == 'card').fold(0.0, (s, sale) => s + (double.tryParse(sale['total']?.toString() ?? '0') ?? 0));
    final creditSales = sales.where((s) => s['paymentMethod'] == 'credit').fold(0.0, (s, sale) => s + (double.tryParse(sale['total']?.toString() ?? '0') ?? 0));
    final count = sales.length;

    final totalProfit = sales.fold(0.0, (s, sale) => s + _saleProfit(db, sale));
    final productProfits = _productProfits(db, sales);
    final sortedProducts = productProfits.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final lowStockProducts = db.products.where((p) {
      final stock = db.getStock(p.id);
      return stock > 0 && stock <= 5 && p.active;
    }).toList()..sort((a, b) => db.getStock(a.id).compareTo(db.getStock(b.id)));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: const Text('Reportes'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
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
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Resumen de Ventas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                  const Divider(),
                  _statRow('Ventas Totales', fmtMoney(total), Colors.teal),
                  _statRow('Cantidad', '$count ventas', Colors.black54),
                  const Divider(),
                  _statRow('Efectivo', fmtMoney(cashSales), Colors.green),
                  _statRow('Tarjeta', fmtMoney(cardSales), Colors.blue),
                  _statRow('Fiado/Crédito', fmtMoney(creditSales), Colors.orange),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Ganancia Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                  const Divider(),
                  _statRow('Ganancia', fmtMoney(totalProfit), Colors.green),
                  _statRow('Margen', total > 0 ? '${((totalProfit / total) * 100).toStringAsFixed(1)}%' : '0%', Colors.black54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Ganancia por Producto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                  const SizedBox(height: 8),
                  if (sortedProducts.isEmpty)
                    const Padding(padding: EdgeInsets.all(8), child: Text('Sin ventas en este período', style: TextStyle(color: Colors.grey)))
                  else
                    ...sortedProducts.take(10).map((e) => _statRow(e.key, fmtMoney(e.value), Colors.green.shade700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Distribución de Ventas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                  const SizedBox(height: 12),
                  if (total > 0) ...[
                    _progressBar('Efectivo', cashSales, total, Colors.green),
                    const SizedBox(height: 8),
                    _progressBar('Tarjeta', cardSales, total, Colors.blue),
                    const SizedBox(height: 8),
                    _progressBar('Fiado', creditSales, total, Colors.orange),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: lowStockProducts.isEmpty ? Colors.white : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory, color: lowStockProducts.isEmpty ? Colors.teal : Colors.orange, size: 22),
                      const SizedBox(width: 8),
                      Text('Stock Bajo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: lowStockProducts.isEmpty ? Colors.teal.shade700 : Colors.orange.shade800)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (lowStockProducts.isEmpty)
                    const Text('No hay productos con stock bajo', style: TextStyle(color: Colors.grey))
                  else
                    ...lowStockProducts.map((p) {
                      final stock = db.getStock(p.id);
                      final link = db.prodSuppliers.firstWhere(
                        (l) => l.productId == p.id && l.isDefault,
                        orElse: () => db.prodSuppliers.firstWhere(
                          (l) => l.productId == p.id,
                          orElse: () => ProdSupplierLink(id: '', productId: '', supplierId: ''),
                        ),
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: stock <= 2 ? Colors.red : Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$stock', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            const SizedBox(width: 8),
                            Text(fmtMoney(link.salePrice), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF0D9488).withValues(alpha: 0.06),
            child: ListTile(
              leading: const Icon(Icons.trending_up, color: Color(0xFF0D9488), size: 32),
              title: const Text('Productos más vendidos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text('Ver ranking con filtros por período, proveedor y categoría'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopProductsScreen())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _progressBar(String label, double amount, double total, Color color) {
    final pct = total > 0 ? amount / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text('${fmtMoney(amount)} (${(pct * 100).toStringAsFixed(1)}%)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 12,
          ),
        ),
      ],
    );
  }
}
