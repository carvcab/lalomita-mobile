import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';

class WithdrawalsScreen extends StatefulWidget {
  const WithdrawalsScreen({super.key});

  @override
  State<WithdrawalsScreen> createState() => _WithdrawalsScreenState();
}

class _WithdrawalsScreenState extends State<WithdrawalsScreen> {
  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();

    final withdrawals = List<Map<String, dynamic>>.from(db.withdrawals);
    withdrawals.sort((a, b) => (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));
    final total = withdrawals.fold(0.0, (s, w) => s + ((w['amount'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total Egresos:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(fmtMoney(total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
            ]),
          ),
          Expanded(
            child: withdrawals.isEmpty
                ? const Center(child: Text('Sin retiros registrados', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: withdrawals.length,
                    itemBuilder: (_, i) {
                      final w = withdrawals[i];
                      final amount = (w['amount'] as num?)?.toDouble() ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade100,
                            child: const Icon(Icons.arrow_downward, color: Colors.red),
                          ),
                          title: Text(fmtMoney(amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${w['date'] ?? ''} - ${w['reason'] ?? 'Sin motivo'}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Eliminar retiro?'),
                                  content: Text('Eliminar ${fmtMoney(amount)}?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                db.withdrawals.removeWhere((x) => x['id'] == w['id']);
                                await db.saveCache();
                                db.notifyListeners();
                                if (sync.firebaseEnabled) sync.saveAndSync();
                              }
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
        onPressed: () => _openForm(context, db, sync),
        backgroundColor: Colors.red,
        child: const Icon(Icons.remove, color: Colors.white),
      ),
    );
  }

  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  void _openForm(BuildContext ctx, DbService db, SyncService sync) {
    _amountCtrl.clear();
    _reasonCtrl.clear();
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nuevo Retiro / Gasto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _reasonCtrl, decoration: const InputDecoration(labelText: 'Motivo', border: OutlineInputBorder()), maxLines: 2),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ActionChip(label: const Text('Gastos Familiares'), onPressed: () => _reasonCtrl.text = 'Gastos familiares'),
              ActionChip(label: const Text('Transporte'), onPressed: () => _reasonCtrl.text = 'Transporte'),
              ActionChip(label: const Text('Almuerzo'), onPressed: () => _reasonCtrl.text = 'Almuerzo'),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () async {
                  final amount = double.tryParse(_amountCtrl.text) ?? 0;
                  if (amount <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Ingresa el monto')));
                    return;
                  }
                  db.withdrawals.add({
                    'id': db.genId(),
                    'date': db.today(),
                    'amount': amount,
                    'reason': _reasonCtrl.text.trim().isEmpty ? 'Sin motivo' : _reasonCtrl.text.trim(),
                    'createdAt': DateTime.now().toIso8601String(),
                  });
                  await db.saveCache();
                  db.notifyListeners();
                  if (sync.firebaseEnabled) sync.saveAndSync();
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Registrar Retiro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
