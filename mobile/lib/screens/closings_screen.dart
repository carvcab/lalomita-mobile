import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';
import 'distribution_screen.dart';

class ClosingsScreen extends StatefulWidget {
  const ClosingsScreen({super.key});

  @override
  State<ClosingsScreen> createState() => _ClosingsScreenState();
}

class _ClosingsScreenState extends State<ClosingsScreen> {
  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final closingsList = List<Map<String, dynamic>>.from(db.closings);
    closingsList.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      body: closingsList.isEmpty
          ? const Center(
              child: Text('No hay cierres registrados', style: TextStyle(color: Colors.grey, fontSize: 16)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: closingsList.length,
              itemBuilder: (ctx, idx) {
                final c = closingsList[idx];
                final actual = (c['actualCash'] as num?)?.toDouble() ?? 0.0;
                final expected = (c['expectedCash'] as num?)?.toDouble() ?? 0.0;
                final diff = actual - expected;
                final bool isDistributed = c['isDistributed'] as bool? ?? false;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              c['date'] as String? ?? '',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _confirmDelete(c['id'] as String),
                            ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 6),
                        _row('Ventas Registradas:', fmtMoney((c['registeredSales'] as num?)?.toDouble() ?? 0.0)),
                        _row('Ventas Efectivo:', fmtMoney((c['cashSales'] as num?)?.toDouble() ?? 0.0)),
                        _row('Ventas Tarjeta/Trans.:', fmtMoney((c['cardTransSales'] as num?)?.toDouble() ?? 0.0)),
                        if ((c['creditSales'] as num? ?? 0) > 0)
                          _row('Ventas Crédito:', fmtMoney((c['creditSales'] as num?)?.toDouble() ?? 0.0)),
                        _row('Egresos (Retiros):', fmtMoney((c['withdrawals'] as num?)?.toDouble() ?? 0.0)),
                        _row('Abonos Recibidos:', fmtMoney((c['abonosCash'] as num?)?.toDouble() ?? 0.0)),
                        const SizedBox(height: 6),
                        const Divider(),
                        const SizedBox(height: 6),
                        _row('Caja Esperada:', fmtMoney(expected)),
                        _row('Caja Real (Reportado):', fmtMoney(actual), isBold: true),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Diferencia:', style: TextStyle(color: Colors.black54)),
                            Text(
                              (diff == 0) ? 'Sin descuadre' : fmtMoney(diff),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: (diff == 0)
                                    ? Colors.green
                                    : (diff > 0 ? Colors.blue : Colors.red),
                              ),
                            ),
                          ],
                        ),
                        if (c['notes'] != null && (c['notes'] as String).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Notas: ${c['notes']}',
                            style: const TextStyle(fontSize: 13, color: Colors.black54, fontStyle: FontStyle.italic),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDistributed ? Colors.green.shade100 : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isDistributed ? 'Distribuido' : 'Pendiente Distribución',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDistributed ? Colors.green.shade800 : Colors.orange.shade800,
                                ),
                              ),
                            ),
                            if (!isDistributed)
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DistributionScreen(closingId: c['id'] as String),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('Distribuir'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openClosingForm(context),
        backgroundColor: const Color(0xFF0D9488),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _row(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.black87 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar cierre?'),
        content: const Text('Esto eliminará el cierre y su distribución asociada en la nube.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              try {
                await context.read<SyncService>().deleteClosing(id).timeout(const Duration(seconds: 15));
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

  void _openClosingForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ClosingFormBottomSheet(),
    );
  }
}

class _ClosingFormBottomSheet extends StatefulWidget {
  const _ClosingFormBottomSheet();

  @override
  State<_ClosingFormBottomSheet> createState() => _ClosingFormBottomSheetState();
}

class _ClosingFormBottomSheetState extends State<_ClosingFormBottomSheet> {
  final _notesCtrl = TextEditingController();
  final _actualCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  // Bill calculator values
  final _bills = <int, int>{
    100000: 0,
    50000: 0,
    20000: 0,
    10000: 0,
    5000: 0,
    2000: 0,
    1000: 0,
  };
  int _coins = 0;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _actualCtrl.dispose();
    super.dispose();
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  double _getCalculatedTotal() {
    double total = _coins.toDouble();
    _bills.forEach((denom, qty) {
      total += denom * qty;
    });
    return total;
  }

  void _updateActualCashFromCalculator() {
    final total = _getCalculatedTotal();
    _actualCtrl.text = total.toStringAsFixed(0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();

    final expected = db.getRunningCashForDate(_dateStr);
    final actual = double.tryParse(_actualCtrl.text) ?? 0.0;
    final diff = actual - expected;

    // Fetch sales and expenses for this date
    final todaySales = db.sales.where((s) => s['date'] == _dateStr);
    final salesTotal = todaySales.fold(0.0, (sum, s) => sum + (double.tryParse(s['total']?.toString() ?? '0') ?? 0.0));
    final cashSales = todaySales
            .where((s) => s['paymentMethod'] == 'cash')
            .fold(0.0, (sum, s) => sum + (double.tryParse(s['total']?.toString() ?? '0') ?? 0.0)) +
        todaySales
            .where((s) => s['paymentMethod'] == 'mixed')
            .fold(0.0, (sum, s) => sum + (double.tryParse(s['cashAmount']?.toString() ?? '0') ?? 0.0));

    final cardSales = todaySales
            .where((s) => s['paymentMethod'] == 'card' || s['paymentMethod'] == 'transfer')
            .fold(0.0, (sum, s) => sum + (double.tryParse(s['total']?.toString() ?? '0') ?? 0.0)) +
        todaySales
            .where((s) => s['paymentMethod'] == 'mixed')
            .fold(0.0, (sum, s) => sum + (double.tryParse(s['transferAmount']?.toString() ?? '0') ?? 0.0));

    final creditSales = todaySales
        .where((s) => s['paymentMethod'] == 'credit')
        .fold(0.0, (sum, s) => sum + (double.tryParse(s['total']?.toString() ?? '0') ?? 0.0));

    final withdrawals = db.withdrawals
        .where((w) => w['date'] == _dateStr)
        .fold(0.0, (sum, w) => sum + (double.tryParse(w['amount']?.toString() ?? '0') ?? 0.0));

    final abonos = db.fiadosPagos
        .where((p) => p['date'] == _dateStr && p['payMethod'] == 'cash')
        .fold(0.0, (sum, p) => sum + (double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0));

    final purchasesPaid = db.purchases
        .where((p) => (p['paid'] as bool? ?? false) && p['date'] == _dateStr)
        .fold(0.0, (sum, p) => sum + (double.tryParse(p['total']?.toString() ?? '0') ?? 0.0));

    final consumptions = db.consumptions
        .where((c) => c['date'] == _dateStr)
        .fold(0.0, (sum, c) => sum + (double.tryParse(c['total']?.toString() ?? '0') ?? 0.0));

    final purchases = db.purchases
        .where((p) => p['date'] == _dateStr)
        .fold(0.0, (sum, p) => sum + (double.tryParse(p['total']?.toString() ?? '0') ?? 0.0));

    double repairsIncome = 0;
    for (final r in db.repairs) {
      final payments = r['payments'] as List? ?? [];
      for (final p in payments) {
        if (p['date'] == _dateStr && p['method'] == 'cash') {
          repairsIncome += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
        }
      }
    }

    double repairsExpenses = 0;
    for (final r in db.repairs) {
      final exp = r['expenses'] as List? ?? [];
      for (final e in exp) {
        if (e['date'] == _dateStr && e['method'] == 'cash') {
          repairsExpenses += double.tryParse(e['amount']?.toString() ?? '0') ?? 0.0;
        }
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Nuevo Cierre de Caja', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              // Date picker row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Fecha de cierre:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, color: Color(0xFF0D9488)),
                    label: Text(_dateStr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Date summaries
              Card(
                color: Colors.grey.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _row('Ventas del día:', fmtMoney(salesTotal)),
                      _row('Ventas Efectivo:', fmtMoney(cashSales)),
                      _row('Ventas Tarjeta/Trans.:', fmtMoney(cardSales)),
                      _row('Ventas Crédito:', fmtMoney(creditSales)),
                      _row('Egresos (Retiros):', fmtMoney(withdrawals)),
                      _row('Abonos Recibidos:', fmtMoney(abonos)),
                      _row('Reparaciones Recibido:', fmtMoney(repairsIncome)),
                      _row('Reparaciones Egresos:', fmtMoney(repairsExpenses)),
                      _row('Compras Pagadas Caja:', fmtMoney(purchasesPaid)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Bill Calculator Header
              const Text('Calculadora de Efectivo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
              const SizedBox(height: 8),
              _buildBillFields(),
              const SizedBox(height: 16),
              // Expected vs Actual
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Caja Esperada', style: TextStyle(fontSize: 14, color: Colors.black54)),
                        Text(fmtMoney(expected), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _actualCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Caja Real (\$)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Difference
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Diferencia (Descuadre):', style: TextStyle(fontSize: 16)),
                  Text(
                    (diff == 0) ? 'Sin descuadre' : fmtMoney(diff),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: (diff == 0)
                          ? Colors.green
                          : (diff > 0 ? Colors.blue : Colors.red),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Notas / Explicación descuadre',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () async {
                    if (db.closings.any((c) => c['date'] == _dateStr)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ya existe un cierre para esta fecha')),
                      );
                      return;
                    }
                    if (diff.abs() > 5 && _notesCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('❌ Debes escribir una nota explicando el descuadre')),
                      );
                      return;
                    }

                    String finalNotes = _notesCtrl.text.trim();
                    if (diff != 0) {
                      final timeStr = DateFormat('hh:mm a').format(DateTime.now());
                      final descuadreMsg = 'Descuadre registrado a las $timeStr.';
                      finalNotes = finalNotes.isNotEmpty ? '$descuadreMsg Nota: $finalNotes' : descuadreMsg;
                    }

                    final closing = {
                      'id': db.genId(),
                      'date': _dateStr,
                      'registeredSales': salesTotal,
                      'cashSales': cashSales,
                      'cardTransSales': cardSales,
                      'creditSales': creditSales,
                      'withdrawals': withdrawals,
                      'consumptions': consumptions,
                      'purchases': purchases,
                      'purchasesPaid': purchasesPaid,
                      'abonosCash': abonos,
                      'repairsIncome': repairsIncome,
                      'repairsExpenses': repairsExpenses,
                      'actualCash': actual,
                      'expectedCash': expected,
                      'difference': diff,
                      'isDistributed': false,
                      'notes': finalNotes,
                      'userId': 'cajero_movil',
                      'createdAt': DateTime.now().toIso8601String(),
                    };

                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await sync.completeClosing(closing).timeout(const Duration(seconds: 15));
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado' : e.toString()}')),
                      );
                      return;
                    }
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(content: Text('Cierre registrado para $_dateStr')),
                    );
                  },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                  child: const Text('REGISTRAR CIERRE DE CAJA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildBillFields() {
    final denoms = [100000, 50000, 20000, 10000, 5000, 2000, 1000];
    return Card(
      color: Colors.teal.shade50.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.8,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: denoms.length + 1,
              itemBuilder: (ctx, i) {
                if (i < denoms.length) {
                  final denom = denoms[i];
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          denom >= 1000 ? '${denom ~/ 1000}k:' : '$denom:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          onChanged: (val) {
                            final qty = int.tryParse(val) ?? 0;
                            _bills[denom] = qty;
                            _updateActualCashFromCalculator();
                          },
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '0',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  return Row(
                    children: [
                      const Expanded(
                        flex: 2,
                        child: Text('Monedas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          onChanged: (val) {
                            _coins = int.tryParse(val) ?? 0;
                            _updateActualCashFromCalculator();
                          },
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '0',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Efectivo Calculado:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(fmtMoney(_getCalculatedTotal()), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
          Text(value, style: const TextStyle(color: Colors.black87, fontSize: 12.5)),
        ],
      ),
    );
  }
}
