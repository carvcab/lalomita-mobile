import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';

class RepairsScreen extends StatefulWidget {
  const RepairsScreen({super.key});

  @override
  State<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends State<RepairsScreen> {
  int _pageSize = 15;
  int _page = 0;
  String _search = '';
  String _statusFilter = 'all';

  static const _statuses = ['all', 'Ingresado', 'En Diagnostico', 'En Proceso', 'Esperando Repuesto', 'Listo', 'Entregado'];

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();

    var repairs = List<Map<String, dynamic>>.from(db.repairs);
    repairs.sort((a, b) => (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));

    if (_search.isNotEmpty) {
      final s = _search.toLowerCase();
      repairs = repairs.where((r) {
        return (r['customerName']?.toString().toLowerCase().contains(s) ?? false) ||
            (r['phone']?.toString().toLowerCase().contains(s) ?? false) ||
            (r['phoneModel']?.toString().toLowerCase().contains(s) ?? false);
      }).toList();
    }
    if (_statusFilter != 'all') {
      repairs = repairs.where((r) => r['status'] == _statusFilter).toList();
    }

    final totalPages = (repairs.length / _pageSize).ceil();
    if (_page >= totalPages && totalPages > 0) _page = totalPages - 1;
    final pageItems = repairs.skip(_page * _pageSize).take(_pageSize).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar cliente, telefono, modelo...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() { _search = v; _page = 0; }),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: _statuses.map((st) {
                final active = _statusFilter == st;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text(st == 'all' ? 'Todas' : st, style: TextStyle(fontSize: 11)),
                    selected: active,
                    onSelected: (_) => setState(() { _statusFilter = st; _page = 0; }),
                    selectedColor: const Color(0xFF0D9488),
                    labelStyle: TextStyle(color: active ? Colors.white : null, fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: repairs.isEmpty
                ? const Center(child: Text('Sin reparaciones', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: pageItems.length,
                    itemBuilder: (_, i) => _repairCard(pageItems[i], db, sync),
                  ),
          ),
          if (totalPages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: _page > 0 ? () => setState(() => _page--) : null, icon: const Icon(Icons.chevron_left)),
                Text('${_page + 1} / $totalPages', style: const TextStyle(fontSize: 12)),
                IconButton(onPressed: _page < totalPages - 1 ? () => setState(() => _page++) : null, icon: const Icon(Icons.chevron_right)),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context, null, db, sync),
        backgroundColor: const Color(0xFF0D9488),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _repairCard(Map<String, dynamic> r, DbService db, SyncService sync) {
    final total = (r['totalPrice'] as num?)?.toDouble() ?? 0;
    final payments = (r['payments'] as List?) ?? [];
    final expenses = (r['expenses'] as List?) ?? [];
    final paid = payments.fold(0.0, (s, p) => s + (p['amount'] as num?)!.toDouble());
    final exp = expenses.fold(0.0, (s, e) => s + (e['amount'] as num?)!.toDouble());
    final balance = total - paid;
    final status = r['status']?.toString() ?? 'Ingresado';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: _statusIcon(status),
        title: Text(r['customerName']?.toString() ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${r['phoneModel'] ?? ''} | ${r['date'] ?? ''}', style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(fmtMoney(balance), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: balance > 0 ? Colors.red : Colors.green)),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _openForm(context, r, db, sync);
                if (action == 'finance') _openFinance(context, r, db, sync);
                if (action == 'delete') _confirmDelete(r['id'], db, sync);
                if (action == 'status') _changeStatus(r, db, sync);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                const PopupMenuItem(value: 'finance', child: Text('Finanzas / Pagos')),
                const PopupMenuItem(value: 'status', child: Text('Cambiar Estado')),
                const PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r['phone'] != null && (r['phone'] as String).isNotEmpty)
                  Text('Telefono: ${r['phone']}', style: const TextStyle(fontSize: 12)),
                if (r['description'] != null && (r['description'] as String).isNotEmpty)
                  Text('Descripcion: ${r['description']}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                _row('Total:', fmtMoney(total)),
                _row('Pagado:', fmtMoney(paid)),
                _row('Gastos:', fmtMoney(exp)),
                const Divider(),
                _row('Pendiente:', fmtMoney(balance), bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(String status) {
    IconData icon;
    Color color;
    switch (status) {
      case 'Ingresado': icon = Icons.phone_android; color = Colors.blue; break;
      case 'En Diagnostico': icon = Icons.search; color = Colors.orange; break;
      case 'En Proceso': icon = Icons.build; color = Colors.purple; break;
      case 'Esperando Repuesto': icon = Icons.hourglass_bottom; color = Colors.amber; break;
      case 'Listo': icon = Icons.check_circle; color = Colors.green; break;
      case 'Entregado': icon = Icons.done_all; color = Colors.grey; break;
      default: icon = Icons.help; color = Colors.grey;
    }
    return Icon(icon, color: color, size: 20);
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }

  void _confirmDelete(String id, DbService db, SyncService sync) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar reparacion?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () async {
            db.repairs.removeWhere((r) => r['id'] == id);
            await db.saveCache();
            db.notifyListeners();
            if (sync.firebaseEnabled) sync.saveAndSync();
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _changeStatus(Map<String, dynamic> r, DbService db, SyncService sync) {
    final current = r['status']?.toString() ?? 'Ingresado';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar Estado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _statuses.where((s) => s != 'all').map((s) {
            final active = s == current;
            return ListTile(
              dense: true,
              leading: _statusIcon(s),
              title: Text(s, style: TextStyle(fontWeight: active ? FontWeight.bold : FontWeight.normal)),
              selected: active,
              onTap: () {
                r['status'] = s;
                if (s == 'Entregado') r['deliveredAt'] = DateTime.now().toIso8601String();
                db.saveCache();
                db.notifyListeners();
                if (sync.firebaseEnabled) sync.saveAndSync();
                Navigator.pop(ctx);
                setState(() {});
              },
            );
          }).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      ),
    );
  }

  void _openFinance(BuildContext ctx, Map<String, dynamic> r, DbService db, SyncService sync) {
    final total = (r['totalPrice'] as num?)?.toDouble() ?? 0;
    final payments = List<Map<String, dynamic>>.from(r['payments'] as List? ?? []);
    final expenses = List<Map<String, dynamic>>.from(r['expenses'] as List? ?? []);
    final paid = payments.fold(0.0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0));
    final exp = expenses.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
    final balance = total - paid;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FinanceSheet(r: r, total: total, paid: paid, exp: exp, balance: balance, payments: payments, expenses: expenses, sync: sync, db: db),
    );
  }

  final _formNameCtrl = TextEditingController();
  final _formPhoneCtrl = TextEditingController();
  final _formModelCtrl = TextEditingController();
  final _formDescCtrl = TextEditingController();
  final _formTotalCtrl = TextEditingController();
  final _formAbonoCtrl = TextEditingController();
  final _formRepuestoCtrl = TextEditingController();

  void _openForm(BuildContext ctx, Map<String, dynamic>? existing, DbService db, SyncService sync) {
    _formNameCtrl.text = existing?['customerName']?.toString() ?? '';
    _formPhoneCtrl.text = existing?['phone']?.toString() ?? '';
    _formModelCtrl.text = existing?['phoneModel']?.toString() ?? '';
    _formDescCtrl.text = existing?['description']?.toString() ?? '';
    _formTotalCtrl.text = existing?['totalPrice']?.toString() ?? '';
    _formAbonoCtrl.clear();
    _formRepuestoCtrl.clear();
    final isEdit = existing != null;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isEdit ? 'Editar Reparacion' : 'Nueva Reparacion', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Divider(),
                _tf('Nombre Cliente', _formNameCtrl),
                _tf('Telefono', _formPhoneCtrl),
                _tf('Modelo', _formModelCtrl),
                _tf('Descripcion', _formDescCtrl, maxLines: 2),
                _tf('Precio Total', _formTotalCtrl, isNumber: true),
                if (!isEdit) ...[
                  const SizedBox(height: 8),
                  const Text('Opcional (inicial)', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  _tf('Abono inicial', _formAbonoCtrl, isNumber: true),
                  _tf('Costo repuesto', _formRepuestoCtrl, isNumber: true),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () async {
                      final name = _formNameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nombre requerido')));
                        return;
                      }
                      final total = double.tryParse(_formTotalCtrl.text) ?? 0;
                      final now = DateTime.now().toIso8601String();
                      final date = DateTime.now().toIso8601String().split('T').first;

                      final repair = existing != null
                          ? existing
                          : <String, dynamic>{
                              'id': db.genId(),
                              'date': date,
                              'status': 'Ingresado',
                              'createdAt': now,
                              'payments': <Map<String, dynamic>>[],
                              'expenses': <Map<String, dynamic>>[],
                            };

                      repair['customerName'] = name;
                      repair['phone'] = _formPhoneCtrl.text.trim();
                      repair['phoneModel'] = _formModelCtrl.text.trim();
                      repair['description'] = _formDescCtrl.text.trim();
                      repair['totalPrice'] = total;

                      final abono = double.tryParse(_formAbonoCtrl.text) ?? 0;
                      if (abono > 0 && !isEdit) {
                        (repair['payments'] as List).add({'date': date, 'amount': abono, 'method': 'cash'});
                      }
                      final repuesto = double.tryParse(_formRepuestoCtrl.text) ?? 0;
                      if (repuesto > 0 && !isEdit) {
                        (repair['expenses'] as List).add({'date': date, 'amount': repuesto, 'method': 'cash', 'description': 'Repuesto'});
                      }

                      if (!isEdit) db.repairs.add(repair);
                      await db.saveCache();
                      db.notifyListeners();
                      if (sync.firebaseEnabled) sync.saveAndSync();
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                    child: Text(isEdit ? 'Guardar Cambios' : 'Registrar Reparacion', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _tf(String label, TextEditingController ctrl, {bool isNumber = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      ),
    );
  }
}

class _FinanceSheet extends StatefulWidget {
  final Map<String, dynamic> r;
  final double total, paid, exp, balance;
  final List<Map<String, dynamic>> payments, expenses;
  final SyncService sync;
  final DbService db;

  const _FinanceSheet({required this.r, required this.total, required this.paid, required this.exp, required this.balance, required this.payments, required this.expenses, required this.sync, required this.db});

  @override
  State<_FinanceSheet> createState() => _FinanceSheetState();
}

class _FinanceSheetState extends State<_FinanceSheet> {
  final _payAmountCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Finanzas: ${widget.r['customerName']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          _row('Total:', fmtMoney(widget.total), bold: true),
          _row('Pagado:', fmtMoney(widget.paid)),
          _row('Gastos:', fmtMoney(widget.exp)),
          _row('Pendiente:', fmtMoney(widget.balance), color: widget.balance > 0 ? Colors.red : Colors.green),
          const SizedBox(height: 12),
          if (widget.balance > 0.01) ...[
            Row(children: [
              Expanded(child: TextField(controller: _payAmountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto a pagar', isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(_payAmountCtrl.text) ?? 0;
                  if (amount <= 0) return;
                  (widget.r['payments'] as List).add({'date': DateTime.now().toIso8601String().split('T').first, 'amount': amount, 'method': 'cash'});
                  widget.db.saveCache();
                  widget.db.notifyListeners();
                  if (widget.sync.firebaseEnabled) widget.sync.saveAndSync();
                  setState(() {});
                  _payAmountCtrl.clear();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Pagar', style: TextStyle(color: Colors.white)),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          const Text('Historial de Pagos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ...widget.payments.map((p) => ListTile(
                dense: true,
                title: Text('${p['date']} - ${fmtMoney(((p['amount'] as num?)?.toDouble()) ?? 0)}'),
                subtitle: Text(p['method'] ?? 'cash'),
                trailing: IconButton(icon: const Icon(Icons.delete, size: 16), onPressed: () {
                  widget.payments.remove(p);
                  widget.db.saveCache();
                  widget.db.notifyListeners();
                  if (widget.sync.firebaseEnabled) widget.sync.saveAndSync();
                  setState(() {});
                }),
              )),
          if (widget.expenses.isNotEmpty) ...[
            const Text('Gastos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ...widget.expenses.map((e) => ListTile(
                  dense: true,
                  title: Text('${e['date']} - ${fmtMoney(((e['amount'] as num?)?.toDouble()) ?? 0)} ${e['description'] ?? ''}'),
                  trailing: IconButton(icon: const Icon(Icons.delete, size: 16), onPressed: () {
                    widget.expenses.remove(e);
                    widget.db.saveCache();
                    widget.db.notifyListeners();
                    if (widget.sync.firebaseEnabled) widget.sync.saveAndSync();
                    setState(() {});
                  }),
                )),
          ],
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
      ]),
    );
  }
}
