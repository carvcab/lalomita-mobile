import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../utils/format.dart';
import 'fiado_detail_screen.dart';

class FiadosScreen extends StatefulWidget {
  const FiadosScreen({super.key});

  @override
  State<FiadosScreen> createState() => _FiadosScreenState();
}

class _FiadosScreenState extends State<FiadosScreen> {
  String _filter = 'all';

  List<Map<String, dynamic>> _getCreditSales(DbService db) {
    return db.sales.where((s) => s['paymentMethod'] == 'credit').toList();
  }

  Map<String, List<Map<String, dynamic>>> _getGroupedByCustomer(DbService db) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final s in _getCreditSales(db)) {
      final name = (s['customerName'] as String?)?.trim() ?? 'Sin nombre';
      final existingKey = map.keys.where((k) => k.toLowerCase() == name.toLowerCase()).firstOrNull;
      if (existingKey != null) {
        map[existingKey]!.add(s);
      } else {
        map[name] = [s];
      }
    }
    return map;
  }

  List<Map<String, dynamic>> _paymentsForCustomer(DbService db, String customerName) {
    return db.fiadosPagos.where((p) {
      String pCustomer = (p['customerName'] as String?)?.trim() ?? '';
      if (pCustomer.isEmpty) {
        final saleId = p['saleId'] as String?;
        if (saleId != null && saleId.isNotEmpty) {
          final sale = db.sales.where((s) => s['id'] == saleId).firstOrNull;
          if (sale != null) {
            pCustomer = (sale['customerName'] as String?)?.trim() ?? '';
          }
        }
      }
      return pCustomer.trim().toLowerCase() == customerName.trim().toLowerCase();
    }).toList();
  }

  double _customerPaid(DbService db, String customerName) {
    final payments = _paymentsForCustomer(db, customerName);
    return payments.fold(0.0, (sum, p) => sum + (double.tryParse(p['amount']?.toString() ?? '0') ?? 0));
  }

  double _customerDebt(DbService db, List<Map<String, dynamic>> sales) {
    double total = sales.fold(0.0, (sum, s) => sum + (double.tryParse(s['total']?.toString() ?? '0') ?? 0));
    final customerName = (sales.firstOrNull?['customerName'] as String?)?.trim() ?? '';
    double paid = _customerPaid(db, customerName);
    return total - paid;
  }

  double _customerTotal(DbService db, String customerName) {
    double total = 0;
    for (final s in _getCreditSales(db)) {
      if ((s['customerName'] as String?)?.trim().toLowerCase() == customerName.trim().toLowerCase()) {
        total += double.tryParse(s['total']?.toString() ?? '0') ?? 0;
      }
    }
    return total;
  }



  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final grouped = _getGroupedByCustomer(db);

    final customers = grouped.entries.where((e) {
      final debt = _customerDebt(db, e.value);
      if (_filter == 'debt') return debt > 0;
      if (_filter == 'paid') return debt <= 0;
      return true;
    }).toList()..sort((a, b) => _customerDebt(db, b.value).compareTo(_customerDebt(db, a.value)));

    final totalDebt = customers.fold(0.0, (s, e) => s + _customerDebt(db, e.value));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: const Text('Fiados'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'all', child: Text(_filter == 'all' ? '✓ Todos' : 'Todos')),
              PopupMenuItem(value: 'debt', child: Text(_filter == 'debt' ? '✓ Con deuda' : 'Con deuda')),
              PopupMenuItem(value: 'paid', child: Text(_filter == 'paid' ? '✓ Pagados' : 'Pagados')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Fiado:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(fmtMoney(totalDebt), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.red)),
                ],
              ),
            ),
          ),
          Expanded(
            child: customers.isEmpty
                ? const Center(child: Text('No hay fiados', style: TextStyle(color: Colors.grey, fontSize: 16)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: customers.length,
                    itemBuilder: (_, i) {
                      final e = customers[i];
                      final name = e.key;
                      final debt = _customerDebt(db, e.value);
                      final total = _customerTotal(db, name);
                      final paid = _customerPaid(db, name);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.white,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FiadoDetailScreen(customerName: name),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: debt > 0 ? Colors.red.shade50 : Colors.green.shade50,
                                  child: Icon(debt > 0 ? Icons.person : Icons.check, color: debt > 0 ? Colors.red : Colors.green),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _miniChip('Total', fmtMoney(total)),
                                          const SizedBox(width: 8),
                                          _miniChip('Pagado', fmtMoney(paid), Colors.green),
                                          if (debt > 0) ...[
                                            const SizedBox(width: 8),
                                            _miniChip('Deuda', fmtMoney(debt), Colors.red),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (debt > 0)
                                  IconButton(
                                    icon: const Icon(Icons.payments, color: Color(0xFF0D9488)),
                                    onPressed: () {
                                      // Navigate and then add payment
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FiadoDetailScreen(customerName: name),
                                        ),
                                      );
                                    },
                                    tooltip: 'Registrar abono',
                                  ),
                                Icon(Icons.chevron_right, color: Colors.grey.shade400),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, String value, [Color? color]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.black54).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label: $value',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color ?? Colors.black54)),
    );
  }
}
