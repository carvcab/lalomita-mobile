import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';

class DistributionScreen extends StatefulWidget {
  final String closingId;
  const DistributionScreen({super.key, required this.closingId});

  @override
  State<DistributionScreen> createState() => _DistributionScreenState();
}

class _DistributionScreenState extends State<DistributionScreen> {
  final Map<String, TextEditingController> _controllers = {};
  double _totalDistributed = 0.0;

  final List<Map<String, dynamic>> _defaultCategories = [
    { 'id': 'cat_0', 'name': 'Caja Principal', 'type': 'daily', 'order': 0, 'active': true },
    { 'id': 'cat_1', 'name': 'Sueldo Mamá (Semanal)', 'type': 'weekly', 'order': 1, 'active': true },
    { 'id': 'cat_2', 'name': 'Sueldo Papá (Semanal)', 'type': 'weekly', 'order': 2, 'active': true },
    { 'id': 'cat_3', 'name': 'Arriendo', 'type': 'monthly', 'order': 3, 'active': true },
    { 'id': 'cat_4', 'name': 'Facturas Casa y Comida', 'type': 'weekly', 'order': 4, 'active': true },
    { 'id': 'cat_5', 'name': 'Deudas del Negocio', 'type': 'weekly', 'order': 5, 'active': true },
    { 'id': 'cat_6', 'name': 'Deudas Personales', 'type': 'weekly', 'order': 6, 'active': true },
    { 'id': 'cat_7', 'name': 'Caja Chica', 'type': 'daily', 'order': 7, 'active': true },
    { 'id': 'cat_8', 'name': 'Facturas (Proveedores)', 'type': 'weekly', 'order': 8, 'active': true },
    { 'id': 'cat_9', 'name': 'Reposición de Mercancía', 'type': 'weekly', 'order': 9, 'active': true },
  ];

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _calculateTotal() {
    double sum = 0.0;
    _controllers.forEach((_, ctrl) {
      sum += double.tryParse(ctrl.text) ?? 0.0;
    });
    setState(() {
      _totalDistributed = sum;
    });
  }

  int _getWeekNumber(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final dayNum = d.weekday;
    final utcDate = d.add(Duration(days: 4 - dayNum));
    final yearStart = DateTime.utc(utcDate.year, 1, 1);
    return ((utcDate.difference(yearStart).inDays + 1) / 7).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();

    final closing = db.closings.where((c) => c['id'] == widget.closingId).firstOrNull;
    if (closing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Cierre no encontrado')),
      );
    }

    final totalAmount = (closing['actualCash'] as num?)?.toDouble() ?? 0.0;
    final dateStr = closing['date'] as String? ?? '';

    // Fetch categories
    var categories = db.distributionCategories.isNotEmpty ? db.distributionCategories : _defaultCategories;
    categories = categories.where((c) => c['active'] == true).toList()
      ..sort((a, b) => ((a['order'] as num?)?.toInt() ?? 99).compareTo((b['order'] as num?)?.toInt() ?? 99));

    // Initialize controllers if they don't exist
    final existingDist = db.distributions.where((d) => d['closingId'] == widget.closingId).firstOrNull;
    for (final cat in categories) {
      final id = cat['id'] as String;
      if (!_controllers.containsKey(id)) {
        double initialVal = 0.0;
        if (existingDist != null) {
          final items = existingDist['items'] as List? ?? [];
          final item = items.firstWhere((x) => x['categoryId'] == id, orElse: () => null);
          if (item != null) {
            initialVal = (item['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
        _controllers[id] = TextEditingController(
          text: initialVal > 0 ? initialVal.toStringAsFixed(0) : '',
        );
      }
    }

    if (_totalDistributed == 0.0 && existingDist != null) {
      _calculateTotal();
    }

    final remaining = totalAmount - _totalDistributed;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: const Text('Distribuir Caja', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Header summary card
          Card(
            margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Fecha de Cierre:', style: TextStyle(color: Colors.black54)),
                      Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Efectivo Total:', style: TextStyle(color: Colors.black54)),
                      Text(fmtMoney(totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF0D9488))),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Distribuido:', style: TextStyle(color: Colors.black54)),
                      Text(fmtMoney(_totalDistributed), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Restante:', style: TextStyle(color: Colors.black54)),
                      Text(
                        fmtMoney(remaining),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: remaining == 0
                              ? Colors.green
                              : (remaining > 0 ? Colors.blue : Colors.red),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Categories list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categories.length,
              itemBuilder: (ctx, idx) {
                final cat = categories[idx];
                final id = cat['id'] as String;
                final name = cat['name'] as String? ?? '';
                final type = cat['type'] as String? ?? 'daily';
                final ctrl = _controllers[id]!;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text(type == 'daily' ? 'Diario' : (type == 'weekly' ? 'Semanal' : 'Mensual')),
                    trailing: SizedBox(
                      width: 140,
                      child: TextField(
                        controller: ctrl,
                        onChanged: (_) => _calculateTotal(),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: '0',
                          prefixText: '\$ ',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Save button row
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _totalDistributed == 0.0
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        if (remaining != 0) {
                          final bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Confirmar Distribución'),
                              content: Text('⚠️ Tienes una diferencia de ${fmtMoney(remaining)}. ¿Quieres continuar de todas formas?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                        }

                        // Collect items
                        final items = <Map<String, dynamic>>[];
                        _controllers.forEach((catId, ctrl) {
                          final amount = double.tryParse(ctrl.text) ?? 0.0;
                          if (amount > 0) {
                            final cat = categories.firstWhere((x) => x['id'] == catId);
                            items.add({
                              'categoryId': catId,
                              'name': cat['name'],
                              'type': cat['type'] ?? 'daily',
                              'amount': amount,
                            });
                          }
                        });

                        final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                        final dist = {
                          'id': existingDist != null ? existingDist['id'] : db.genId(),
                          'closingId': widget.closingId,
                          'date': dateStr,
                          'totalAmount': totalAmount,
                          'totalDistributed': _totalDistributed,
                          'week': _getWeekNumber(date),
                          'month': date.month,
                          'year': date.year,
                          'items': items,
                          'createdAt': existingDist != null ? existingDist['createdAt'] : DateTime.now().toIso8601String(),
                          'updatedAt': DateTime.now().toIso8601String(),
                        };

                        try {
                          await sync.saveDistribution(dist).timeout(const Duration(seconds: 15));
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString().contains('TimeoutException') ? 'Tiempo de espera agotado' : e.toString()}')),
                          );
                          return;
                        }
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('✓ Distribución guardada')),
                        );
                      },
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                icon: const Icon(Icons.check),
                label: const Text('GUARDAR DISTRIBUCIÓN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
