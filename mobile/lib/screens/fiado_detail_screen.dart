import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';
import 'package:share_plus/share_plus.dart';

class FiadoDetailScreen extends StatefulWidget {
  final String customerName;

  const FiadoDetailScreen({super.key, required this.customerName});

  @override
  State<FiadoDetailScreen> createState() => _FiadoDetailScreenState();
}

class _FiadoDetailScreenState extends State<FiadoDetailScreen> {
  late String _customerName;

  @override
  void initState() {
    super.initState();
    _customerName = widget.customerName;
  }

  List<Map<String, dynamic>> _getCreditSales(DbService db) {
    return db.sales.where((s) {
      return s['paymentMethod'] == 'credit' &&
          (s['customerName'] as String?)?.trim().toLowerCase() == _customerName.trim().toLowerCase();
    }).toList();
  }

  List<Map<String, dynamic>> _paymentsForCustomer(DbService db) {
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
      return pCustomer.trim().toLowerCase() == _customerName.trim().toLowerCase();
    }).toList();
  }

  double _customerPaid(DbService db) {
    final payments = _paymentsForCustomer(db);
    return payments.fold(0.0, (sum, p) => sum + (double.tryParse(p['amount']?.toString() ?? '0') ?? 0));
  }

  double _customerTotal(DbService db) {
    double total = 0;
    for (final s in _getCreditSales(db)) {
      total += double.tryParse(s['total']?.toString() ?? '0') ?? 0;
    }
    return total;
  }

  double _customerDebt(DbService db) {
    return _customerTotal(db) - _customerPaid(db);
  }

  double _saleRemaining(DbService db, String saleId, double total) {
    final paid = db.fiadosPagos
        .where((p) => p['saleId'] == saleId)
        .fold(0.0, (sum, p) => sum + (double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0));
    return total - paid;
  }

  Map<String, dynamic>? _clientInfo(DbService db) {
    return db.clientDetails[_customerName] as Map<String, dynamic>?;
  }

  void _shareStatement(DbService db) {
    final sales = _getCreditSales(db);
    final payments = _paymentsForCustomer(db);
    
    double totalFiado = 0;
    double totalAbonado = 0;
    final List<Map<String, dynamic>> pendingSales = [];
    
    for (final s in sales) {
      final saleId = s['id'] as String;
      final saleTotal = double.tryParse(s['total']?.toString() ?? '0') ?? 0.0;
      final remaining = _saleRemaining(db, saleId, saleTotal);
      totalFiado += saleTotal;
      if (remaining > 0.05) {
        pendingSales.add(s);
      }
    }
    
    for (final p in payments) {
      totalAbonado += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
    }
    
    final totalRemaining = totalFiado - totalAbonado;
    
    final buffer = StringBuffer();
    buffer.writeln('📋 *ESTADO DE CUENTA - ' + (db.settings['businessName'] ?? 'Variedades La Lomita') + '*');
    buffer.writeln('------------------------------------------');
    buffer.writeln('👤 *Cliente:* $_customerName');
    buffer.writeln('📅 *Fecha de emisión:* ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}');
    buffer.writeln('------------------------------------------');
    buffer.writeln('💰 *SALDO PENDIENTE (DEBE):* ' + fmtMoney(totalRemaining));
    buffer.writeln('💵 Total Comprado: ' + fmtMoney(totalFiado));
    buffer.writeln('✅ Total Abonado: ' + fmtMoney(totalAbonado));
    buffer.writeln('------------------------------------------');
    buffer.writeln('');
    
    buffer.writeln('📦 *PRODUCTOS QUE DEBE:*');
    if (pendingSales.isEmpty) {
      buffer.writeln('🎉 ¡No debe ningún producto en este momento!');
    } else {
      for (final s in pendingSales) {
        final saleId = s['id'] as String;
        final saleTotal = double.tryParse(s['total']?.toString() ?? '0') ?? 0.0;
        final remaining = _saleRemaining(db, saleId, saleTotal);
        final dateStr = s['date']?.toString() ?? '';
        final timeStr = s['createdAt'] != null 
            ? DateTime.tryParse(s['createdAt'].toString())?.toLocal().toString().substring(11, 16) ?? ''
            : '';
        final carriedBy = s['carriedBy']?.toString() ?? 'Cliente';
        
        buffer.writeln('• *Compra del ' + dateStr + (timeStr.isNotEmpty ? " (" + timeStr + ")" : "") + '*');
        buffer.writeln('  Llevado por: ' + carriedBy);
        
        final items = s['items'] as List? ?? [];
        for (final i in items) {
          final name = i['productName']?.toString() ?? 'Producto';
          final qty = i['quantity'] ?? 1;
          buffer.writeln('  - ' + name + ' x' + qty.toString());
        }
        buffer.writeln('  Total compra: ' + fmtMoney(saleTotal) + ' | Saldo: ' + fmtMoney(remaining));
        buffer.writeln('');
      }
    }
    
    buffer.writeln('------------------------------------------');
    buffer.writeln('💰 *HISTORIAL DE ABONOS:*');
    if (payments.isEmpty) {
      buffer.writeln('No hay abonos registrados.');
    } else {
      for (final p in payments) {
        final amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
        final dt = p['date']?.toString() ?? '';
        final method = p['payMethod'] == 'cash' ? 'Efectivo' : 'Transferencia';
        buffer.writeln('• ' + fmtMoney(amt) + ' (' + dt + ') - ' + method);
      }
    }
    
    buffer.writeln('');
    buffer.writeln('¡Muchas gracias por su confianza!');
    
    Share.share(buffer.toString(), subject: 'Estado de Cuenta - ' + _customerName);
  }


Future<void> _addPayment() async {
    final amountCtrl = TextEditingController();
    final db = context.read<DbService>();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar Abono'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cliente: $_customerName', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Deuda: ${fmtMoney(_customerDebt(db))}',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monto del abono',
                prefixText: '\$ ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Compartir Estado',
            onPressed: () => _shareStatement(db),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(ctx, amount);
            },
            child: const Text('REGISTRAR ABONO'),
          ),
        ],
      ),
    );

    if (result != null && result > 0 && mounted) {
      final sync = context.read<SyncService>();
      final customerSales = _getCreditSales(db)
        ..sort((a, b) {
          final aDate = a['date'] as String? ?? '';
          final bDate = b['date'] as String? ?? '';
          return aDate.compareTo(bDate);
        });

      double remaining = result;
      final List<Map<String, dynamic>> newPayments = [];

      for (final sale in customerSales) {
        if (remaining <= 0.01) break;
        final saleId = sale['id'] as String;
        final total = double.tryParse(sale['total']?.toString() ?? '0') ?? 0.0;
        final pending = _saleRemaining(db, saleId, total);
        if (pending > 0.01) {
          final toPay = remaining < pending ? remaining : pending;
          newPayments.add({
            'id': db.genId(),
            'saleId': saleId,
            'customerName': _customerName.trim(),
            'amount': toPay,
            'payMethod': 'cash',
            'date': db.today(),
            'createdAt': DateTime.now().toIso8601String(),
          });
          remaining -= toPay;
        }
      }

      if (remaining > 0.01 || newPayments.isEmpty) {
        newPayments.add({
          'id': db.genId(),
          'saleId': '',
          'customerName': _customerName.trim(),
          'amount': remaining,
          'payMethod': 'cash',
          'date': db.today(),
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      for (final p in newPayments) {
        await sync.registerFiadoPago(p);
      }

      if (mounted) setState(() {});
      _snack('Abono de ${fmtMoney(result)} registrado');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sales = _getCreditSales(db)..sort((a, b) {
      final aDate = a['date'] as String? ?? '';
      final bDate = b['date'] as String? ?? '';
      return bDate.compareTo(aDate);
    });
    final payments = _paymentsForCustomer(db)..sort((a, b) {
      final aDate = a['date'] as String? ?? '';
      final bDate = b['date'] as String? ?? '';
      return bDate.compareTo(aDate);
    });
    final total = _customerTotal(db);
    final paid = _customerPaid(db);
    final debt = _customerDebt(db);
    final info = _clientInfo(db);

    // Build combined timeline
    final timeline = <({String type, String date, Map<String, dynamic> data})>[];
    for (final s in sales) {
      timeline.add((type: 'sale', date: s['date']?.toString() ?? s['createdAt']?.toString() ?? '', data: s));
    }
    for (final p in payments) {
      timeline.add((type: 'payment', date: p['date']?.toString() ?? p['createdAt']?.toString() ?? '', data: p));
    }
    timeline.sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: Text(_customerName, style: const TextStyle(fontSize: 18)),
        actions: [
          if (debt > 0)
            IconButton(
              icon: const Icon(Icons.payments),
              tooltip: 'Registrar abono',
              onPressed: _addPayment,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (info != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.black54),
                        const SizedBox(width: 6),
                        Text('${info['phone'] ?? 'Sin teléfono'}',
                            style: const TextStyle(fontSize: 14, color: Colors.black54)),
                      ],
                    ),
                    if ((info['limit'] ?? 0) > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.credit_card, size: 16, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text('Límite: ${fmtMoney(info['limit'])}',
                              style: const TextStyle(fontSize: 14, color: Colors.black54)),
                        ],
                      ),
                    ],
                    const Divider(),
                  ],
                  Row(
                    children: [
                      _infoChip('Total', fmtMoney(total), Colors.black54),
                      const SizedBox(width: 8),
                      _infoChip('Pagado', fmtMoney(paid), Colors.green),
                      const SizedBox(width: 8),
                      _infoChip('Deuda', fmtMoney(debt), debt > 0 ? Colors.red : Colors.green),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (debt > 0)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Estado de cuenta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text('Debe ${fmtMoney(debt)} de ${fmtMoney(total)}',
                              style: TextStyle(color: Colors.orange.shade800, fontSize: 14)),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _addPayment,
                      icon: const Icon(Icons.payments, size: 18),
                      label: const Text('Abonar'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                    ),
                  ],
                ),
              ),
            ),
          if (debt <= 0)
            Card(
              color: Colors.green.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Cuenta saldada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Movimientos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
          const SizedBox(height: 8),
          if (timeline.isEmpty)
            Card(
              color: Colors.white,
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Sin movimientos', style: TextStyle(color: Colors.grey))),
              ),
            )
          else
            ...timeline.map((t) {
              if (t.type == 'sale') {
                final s = t.data;
                final saleId = s['id'] as String;
                final saleTotal = double.tryParse(s['total']?.toString() ?? '0') ?? 0;
                final remaining = _saleRemaining(db, saleId, saleTotal);
                final items = s['items'] as List? ?? [];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.white,
                  child: ExpansionTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0F2F1),
                      child: Icon(Icons.shopping_cart, color: Color(0xFF0D9488), size: 20),
                    ),
                    title: Text('Venta ${fmtMoney(saleTotal)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text(
                      '${fmtDate(s['createdAt']?.toString() ?? s['date']?.toString() ?? '')}  |  ${items.length} artículos',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (remaining > 0)
                          Text('Debe: ${fmtMoney(remaining)}',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13))
                        else
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      ],
                    ),
                    children: [
                      const Divider(),
                      ...items.map((item) => ListTile(
                            dense: true,
                            title: Text(item['productName']?.toString() ?? '?',
                                style: const TextStyle(fontSize: 14)),
                            trailing: Text(
                              '${item['quantity']} x ${fmtMoney(double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          )),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(fmtMoney(saleTotal),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0D9488))),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                final p = t.data;
                final amount = double.tryParse(p['amount']?.toString() ?? '0') ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.green.shade50,
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.check_circle, color: Colors.white, size: 20),
                    ),
                    title: Text('Abono ${fmtMoney(amount)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                    subtitle: Text(p['date']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                  ),
                );
              }
            }),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
