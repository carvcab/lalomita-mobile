import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';

class CajasScreen extends StatefulWidget {
  const CajasScreen({super.key});

  @override
  State<CajasScreen> createState() => _CajasScreenState();
}

class _CajasScreenState extends State<CajasScreen> {
  double _negocioBalance(DbService db) {
    double bal = 0;
    for (final c in db.closings) {
      if (c['isDistributed'] != true) continue;
      final dist = db.distributions.where((d) => d['closingId'] == c['id']).firstOrNull;
      if (dist != null) {
        bal += ((dist['negocio'] as num?)?.toDouble() ?? 0);
      }
    }
    for (final p in db.purchases) {
      if (p['paid'] == true) {
        bal -= ((p['total'] as num?)?.toDouble() ?? 0);
      }
    }
    for (final p in db.fiadosPagos) {
      if (p['payMethod'] == 'cash') {
        bal += ((p['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    for (final r in db.repairs) {
      for (final pay in (r['payments'] as List? ?? [])) {
        bal += ((pay['amount'] as num?)?.toDouble() ?? 0);
      }
      for (final exp in (r['expenses'] as List? ?? [])) {
        bal -= ((exp['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    for (final ce in db.copyExpenses) {
      bal -= ((ce['amount'] as num?)?.toDouble() ?? 0);
    }
    for (final ct in db.cajaTransactions) {
      if (ct['to'] == 'negocio') bal += ((ct['amount'] as num?)?.toDouble() ?? 0);
      if (ct['from'] == 'negocio') bal -= ((ct['amount'] as num?)?.toDouble() ?? 0);
    }
    return bal;
  }

  double _gananciasBalance(DbService db) {
    double bal = 0;
    for (final c in db.closings) {
      if (c['isDistributed'] != true) continue;
      final dist = db.distributions.where((d) => d['closingId'] == c['id']).firstOrNull;
      if (dist != null) {
        bal += ((dist['ganancias'] as num?)?.toDouble() ?? 0);
      }
    }
    for (final ct in db.cajaTransactions) {
      if (ct['to'] == 'ganancias') bal += ((ct['amount'] as num?)?.toDouble() ?? 0);
      if (ct['from'] == 'ganancias') bal -= ((ct['amount'] as num?)?.toDouble() ?? 0);
    }
    return bal;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();

    final negocio = _negocioBalance(db);
    final ganancias = _gananciasBalance(db);
    final txs = List<Map<String, dynamic>>.from(db.cajaTransactions);
    txs.sort((a, b) => (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: _balanceCard('Caja Negocio', negocio, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _balanceCard('Caja Ganancias', ganancias, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _balanceCard('Total', negocio + ganancias, const Color(0xFF0D9488))),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(Icons.swap_horiz, size: 16),
              SizedBox(width: 4),
              Text('Transferencias', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
          ),
          Expanded(
            child: txs.isEmpty
                ? const Center(child: Text('Sin transferencias', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: txs.length,
                    itemBuilder: (_, i) {
                      final t = txs[i];
                      final amount = ((t['amount'] as num?)?.toDouble() ?? 0);
                      final from = t['from'] ?? '';
                      final to = t['to'] ?? '';
                      final icon = to == 'ganancias' ? Icons.arrow_upward : Icons.arrow_downward;
                      final color = to == 'ganancias' ? Colors.green : Colors.blue;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 16)),
                          title: Text('$from → $to: ${fmtMoney(amount)}', style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${t['date'] ?? ''} - ${t['concept'] ?? ''}', style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            onPressed: () async {
                              db.cajaTransactions.removeWhere((x) => x['id'] == t['id']);
                              await db.saveCache();
                              db.notifyListeners();
                              if (sync.firebaseEnabled) sync.saveAndSync();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTransfer(context, db, sync),
        backgroundColor: const Color(0xFF0D9488),
        child: const Icon(Icons.swap_horiz, color: Colors.white),
      ),
    );
  }

  Widget _balanceCard(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(children: [
        Text(title, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(fmtMoney(amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  final _amountCtrl = TextEditingController();
  final _conceptCtrl = TextEditingController();
  String _fromBox = 'negocio';
  String _toBox = 'ganancias';

  void _openTransfer(BuildContext ctx, DbService db, SyncService sync) {
    _amountCtrl.clear();
    _conceptCtrl.clear();
    _fromBox = 'negocio';
    _toBox = 'ganancias';

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Transferir entre Cajas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              Row(children: [
                Expanded(child: ChoiceChip(label: const Text('Caja Negocio'), selected: _fromBox == 'negocio', onSelected: (_) => setModalState(() => _fromBox = 'negocio'), selectedColor: Colors.blue.shade100)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward),
                const SizedBox(width: 8),
                Expanded(child: ChoiceChip(label: const Text('Caja Ganancias'), selected: _toBox == 'ganancias', onSelected: (_) => setModalState(() => _toBox = 'ganancias'), selectedColor: Colors.green.shade100)),
              ]),
              const SizedBox(height: 4),
              TextButton(onPressed: () => setModalState(() { _fromBox = 'ganancias'; _toBox = 'negocio'; }), child: const Text('Invertir direccion', style: TextStyle(fontSize: 11))),
              TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _conceptCtrl, decoration: const InputDecoration(labelText: 'Concepto', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(_amountCtrl.text) ?? 0;
                    if (amount <= 0) return;
                    db.cajaTransactions.add({
                      'id': db.genId(),
                      'date': db.today(),
                      'from': _fromBox,
                      'to': _toBox,
                      'amount': amount,
                      'concept': _conceptCtrl.text.trim().isEmpty ? 'Transferencia' : _conceptCtrl.text.trim(),
                      'createdAt': DateTime.now().toIso8601String(),
                    });
                    await db.saveCache();
                    db.notifyListeners();
                    if (sync.firebaseEnabled) sync.saveAndSync();
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                  child: const Text('Transferir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
  }
}
