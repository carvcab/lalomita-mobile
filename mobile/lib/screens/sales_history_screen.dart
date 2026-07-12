import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';
import 'edit_sale_screen.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final Set<String> _expandedSales = {};

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final salesList = List<Map<String, dynamic>>.from(db.sales);
    salesList.sort((a, b) {
      final aTime = a['createdAt'] as String? ?? a['date'] as String? ?? '';
      final bTime = b['createdAt'] as String? ?? b['date'] as String? ?? '';
      return bTime.compareTo(aTime);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      body: salesList.isEmpty
          ? const Center(
              child: Text('No hay ventas registradas', style: TextStyle(color: Colors.grey, fontSize: 16)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: salesList.length,
              itemBuilder: (ctx, idx) {
                final sale = salesList[idx];
                final id = sale['id'] as String;
                final total = (sale['total'] as num?)?.toDouble() ?? 0.0;
                final date = sale['date'] as String? ?? '';
                final payMethod = sale['paymentMethod'] as String? ?? 'cash';
                final payMethodName = sale['paymentMethodName'] as String? ?? (payMethod == 'cash' ? 'Efectivo' : 'Tarjeta');
                final items = sale['items'] as List? ?? [];
                final isExpanded = _expandedSales.contains(id);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedSales.remove(id);
                            } else {
                              _expandedSales.add(id);
                            }
                          });
                        },
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.1),
                          foregroundColor: const Color(0xFF0D9488),
                          child: Icon(payMethod == 'cash' ? Icons.payments : Icons.credit_card),
                        ),
                        title: Text(
                          fmtMoney(total),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                        ),
                        subtitle: Text('$date • $payMethodName'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Color(0xFF0D9488)),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EditSaleScreen(sale: sale),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _confirmDelete(context, id),
                            ),
                            Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                          ],
                        ),
                      ),
                      if (isExpanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Productos vendidos:',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              ...items.map((i) {
                                final name = i['productName'] as String? ?? 'Producto';
                                final qty = (i['quantity'] as num?)?.toInt() ?? 1;
                                final price = (i['unitPrice'] as num?)?.toDouble() ?? 0.0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$name x$qty',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                      Text(
                                        fmtMoney(price * qty),
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, String saleId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar venta?'),
        content: const Text('Esto revertirá el stock de los productos vendidos y eliminará el registro de la nube.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              try {
                await context.read<SyncService>().deleteSale(saleId).timeout(const Duration(seconds: 15));
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado' : e.toString()}')),
                  );
                }
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
