import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';

class CopiasScreen extends StatefulWidget {
  const CopiasScreen({super.key});

  @override
  State<CopiasScreen> createState() => _CopiasScreenState();
}

class _CopiasScreenState extends State<CopiasScreen> {
  String _paperType = 'normal';
  final Map<String, int> _qtys = {};
  int _reamQty = 0;
  double _discount = 0;
  String _payMethod = 'cash';
  int _activeTab = 0;

  static const _services = [
    {'id': 'copyBN', 'name': 'Fotocopia B/N', 'field': 'copyBN', 'group': 'FOTOCOPIAS'},
    {'id': 'copyColor', 'name': 'Fotocopia Color', 'field': 'copyColor', 'group': 'FOTOCOPIAS'},
    {'id': 'copyDuplexBN', 'name': 'Fotocopia Doble Cara B/N', 'field': 'copyDuplexBN', 'group': 'FOTOCOPIAS'},
    {'id': 'copyDuplexColor', 'name': 'Fotocopia Doble Cara Color', 'field': 'copyDuplexColor', 'group': 'FOTOCOPIAS'},
    {'id': 'printBN', 'name': 'Impresion B/N', 'field': 'printBN', 'group': 'IMPRESIONES'},
    {'id': 'printColor', 'name': 'Impresion Color', 'field': 'printColor', 'group': 'IMPRESIONES'},
    {'id': 'printDuplexBN', 'name': 'Impresion Doble Cara B/N', 'field': 'printDuplexBN', 'group': 'IMPRESIONES'},
    {'id': 'printDuplexColor', 'name': 'Impresion Doble Cara Color', 'field': 'printDuplexColor', 'group': 'IMPRESIONES'},
    {'id': 'scan', 'name': 'Escaneo (por hoja)', 'field': 'scan', 'group': 'ESCANEO'},
    {'id': 'ampBN', 'name': 'Copia Ampliada/Reducida B/N', 'field': 'ampBN', 'group': 'AMPLIADAS'},
    {'id': 'ampColor', 'name': 'Copia Ampliada/Reducida Color', 'field': 'ampColor', 'group': 'AMPLIADAS'},
  ];

  List<Map<String, dynamic>> _paperTypes(DbService db) {
    return db.copyPaperTypes.isNotEmpty
        ? db.copyPaperTypes
        : [
            {'id': 'normal', 'name': 'Normal'},
            {'id': 'foto', 'name': 'Foto'},
            {'id': 'cartulina', 'name': 'Cartulina'},
          ];
  }

  Map<String, dynamic> _prices(DbService db) {
    if (db.copyPrices[_paperType] is Map) {
      return Map<String, dynamic>.from(db.copyPrices[_paperType] as Map);
    }
    return _defaultPrices(_paperType);
  }

  Map<String, dynamic> _defaultPrices(String type) {
    switch (type) {
      case 'normal':
        return {'copyBN': 150, 'copyColor': 500, 'copyDuplexBN': 250, 'copyDuplexColor': 800, 'printBN': 200, 'printColor': 800, 'printDuplexBN': 350, 'printDuplexColor': 1200, 'scan': 300, 'ampBN': 300, 'ampColor': 800, 'reamPrice': 12000};
      case 'foto':
        return {'copyBN': 0, 'copyColor': 1200, 'copyDuplexBN': 0, 'copyDuplexColor': 2000, 'printBN': 0, 'printColor': 1800, 'printDuplexBN': 0, 'printDuplexColor': 2500, 'scan': 500, 'ampBN': 0, 'ampColor': 1500, 'reamPrice': 25000};
      case 'cartulina':
        return {'copyBN': 300, 'copyColor': 800, 'copyDuplexBN': 500, 'copyDuplexColor': 1200, 'printBN': 400, 'printColor': 1200, 'printDuplexBN': 600, 'printDuplexColor': 1800, 'scan': 300, 'ampBN': 500, 'ampColor': 1200, 'reamPrice': 18000};
      default:
        return {};
    }
  }

  double _servicePrice(DbService db, String field) {
    final p = _prices(db);
    return (p[field] as num?)?.toDouble() ?? 0;
  }

  double _subtotal(DbService db) {
    double sum = 0;
    for (final sv in _services) {
      final qty = _qtys[sv['id']] ?? 0;
      if (qty > 0) sum += qty * _servicePrice(db, sv['field'] as String);
    }
    if (_reamQty > 0) sum += _reamQty * ((_prices(db)['reamPrice'] as num?)?.toDouble() ?? 0);
    return sum;
  }

  double _total(DbService db) {
    final sub = _subtotal(db);
    return (sub - _discount) > 0 ? (sub - _discount) : 0;
  }

  int _totalSheets() {
    int s = 0;
    for (final sv in _services) {
      s += _qtys[sv['id']] ?? 0;
    }
    return s;
  }

  int _paperStock(DbService db) {
    return (db.copyPaperStock[_paperType] as num?)?.toInt() ?? 0;
  }

  int _reamStock(DbService db) {
    return (db.copyReamStock[_paperType] as num?)?.toInt() ?? 0;
  }

  String _paperName(DbService db) {
    final pts = _paperTypes(db);
    return pts.where((p) => p['id'] == _paperType).firstOrNull?['name']?.toString() ?? _paperType;
  }

  void _charge(DbService db, SyncService sync) async {
    final total = _total(db);
    if (total <= 0) {
      _snack('Agrega cantidades para cobrar');
      return;
    }
    final sheets = _totalSheets();
    final stock = _paperStock(db);
    if (sheets > stock && stock > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Stock bajo'),
          content: Text('Solo hay $stock hojas de ${_paperName(db)}. Faltan ${sheets - stock}. Continuar?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continuar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    final items = <Map<String, dynamic>>[];
    for (final sv in _services) {
      final qty = _qtys[sv['id']] ?? 0;
      if (qty > 0) {
        items.add({
          'productId': sv['id'],
          'productName': '${sv['name']} (${_paperName(db)})',
          'quantity': qty,
          'sellPrice': _servicePrice(db, sv['field'] as String),
          'purchasePrice': 0,
        });
      }
    }
    if (_reamQty > 0) {
      items.add({
        'productId': 'resma',
        'productName': 'Resma ${_paperName(db)} (500 hojas)',
        'quantity': _reamQty,
        'sellPrice': (_prices(db)['reamPrice'] as num?)?.toDouble() ?? 0,
        'purchasePrice': 0,
      });
    }

    final sale = <String, dynamic>{
      'id': db.genId(),
      'date': db.today(),
      'items': items,
      'total': total,
      'discount': _discount,
      'discountPct': 0,
      'paymentMethod': _payMethod,
      'paymentMethodName': _payMethod == 'cash' ? 'Efectivo' : 'Nequi / Transferencia',
      'cashAmount': _payMethod == 'cash' ? total : 0,
      'transferAmount': _payMethod == 'transfer' ? total : 0,
      'customerName': '',
      'notes': 'Copias en ${_paperName(db)}',
      'createdAt': DateTime.now().toIso8601String(),
      'isCopySale': true,
      'copyPaperType': _paperType,
    };

    db.sales.add(sale);

    db.copyPaperStock[_paperType] = ((db.copyPaperStock[_paperType] as num?)?.toInt() ?? 0) - sheets;
    if (db.copyPaperStock[_paperType] < 0) db.copyPaperStock[_paperType] = 0;

    if (_reamQty > 0) {
      db.copyReamStock[_paperType] = ((db.copyReamStock[_paperType] as num?)?.toInt() ?? 0) - _reamQty;
      if (db.copyReamStock[_paperType] < 0) db.copyReamStock[_paperType] = 0;
    }

    await db.saveCache();
    db.notifyListeners();

    if (sync.firebaseEnabled) {
      sync.saveAndSync();
    } else if (sync.serverUrl.isNotEmpty) {
      sync.pushToServer();
    }

    _clearForm();
    _snack('Venta de copias: ${fmtMoney(total)}');
  }

  void _clearForm() {
    setState(() {
      _qtys.clear();
      _reamQty = 0;
      _discount = 0;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  List<Map<String, dynamic>> _copySales(DbService db) {
    return db.sales.where((s) => s['isCopySale'] == true).toList()
      ..sort((a, b) => (b['createdAt'] as String? ?? '').compareTo(a['createdAt'] as String? ?? ''));
  }

  List<Map<String, dynamic>> _inkExpenses(DbService db) {
    return db.copyExpenses.where((e) => e['type'] == 'ink').toList()
      ..sort((a, b) => (b['createdAt'] as String? ?? '').compareTo(a['createdAt'] as String? ?? ''));
  }

  List<Map<String, dynamic>> _recentReamPurchases(DbService db) {
    final purchases = <Map<String, dynamic>>[];
    for (final entry in (db.copyReamStock as Map).entries) {
      final v = (entry.value as num?)?.toInt() ?? 0;
      if (v > 0) {
        purchases.add({'paperType': entry.key, 'stock': v});
      }
    }
    return purchases;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();
    final sync = context.watch<SyncService>();
    final prices = _prices(db);
    final paperName = _paperName(db);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _activeTab == 0
                  ? _buildCalculator(db, sync, prices, paperName)
                  : _activeTab == 1
                      ? _buildSalesHistory(db, sync)
                      : _buildStock(db),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF0D9488),
      child: Row(
        children: [
          const Text('Copias', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const Spacer(),
          _tabBtn('Calculadora', 0),
          const SizedBox(width: 4),
          _tabBtn('Historial', 1),
          const SizedBox(width: 4),
          _tabBtn('Stock', 2),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int idx) {
    final active = _activeTab == idx;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: TextStyle(color: Colors.white, fontWeight: active ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
      ),
    );
  }

  Widget _buildCalculator(DbService db, SyncService sync, Map<String, dynamic> prices, String paperName) {
    final types = _paperTypes(db);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paperSelector(db, types),
          const SizedBox(height: 8),
          _stockBar(db),
          const Divider(),
          ..._buildServiceRows(db, prices),
          const SizedBox(height: 8),
          _buildReamRow(db, prices, paperName),
          const Divider(),
          _buildDiscountRow(),
          const SizedBox(height: 8),
          _buildTotalRow(db),
          const SizedBox(height: 8),
          _payMethodRow(),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _charge(db, sync),
              icon: const Icon(Icons.point_of_sale),
              label: Text('Cobrar ${fmtMoney(_total(db))}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperSelector(DbService db, List<Map<String, dynamic>> types) {
    return Row(
      children: types.map((pt) {
        final id = pt['id'] as String;
        final name = pt['name'] as String;
        final active = _paperType == id;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(name),
            selected: active,
            onSelected: (_) => setState(() => _paperType = id),
            selectedColor: const Color(0xFF0D9488),
            labelStyle: TextStyle(color: active ? Colors.white : null),
          ),
        );
      }).toList(),
    );
  }

  Widget _stockBar(DbService db) {
    final pts = _paperTypes(db);
    final parts = <Widget>[];
    for (final pt in pts) {
      final id = pt['id'] as String;
      final name = pt['name'] as String;
      final sheets = (db.copyPaperStock[id] as num?)?.toInt() ?? 0;
      final reams = (db.copyReamStock[id] as num?)?.toInt() ?? 0;
      final sheetColor = sheets < 50 ? Colors.red : Colors.green;
      parts.add(
        Text('$name: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
      );
      parts.add(
        Text('$reams resmas ', style: TextStyle(color: Colors.blue.shade700, fontSize: 11)),
      );
      parts.add(
        Text('$sheets hojas', style: TextStyle(color: sheetColor, fontSize: 11)),
      );
      parts.add(const Text(' | ', style: TextStyle(fontSize: 11)));
    }
    if (parts.isNotEmpty) parts.removeLast();
    return Wrap(children: parts);
  }

  List<Widget> _buildServiceRows(DbService db, Map<String, dynamic> prices) {
    final widgets = <Widget>[];
    String lastGroup = '';
    for (final sv in _services) {
      final group = sv['group'] as String;
      final id = sv['id'] as String;
      final field = sv['field'] as String;
      if (group != lastGroup) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(group, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D9488), fontSize: 13)),
        ));
        lastGroup = group;
      }
      final price = _servicePrice(db, field);
      final qty = _qtys[id] ?? 0;
      final sub = qty * price;
      widgets.add(Card(
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(sv['name'] as String, style: const TextStyle(fontSize: 13))),
              Text(fmtMoney(price), style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    hintText: '0',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _qtys[id] = int.tryParse(v) ?? 0;
                      if (_qtys[id] == 0) _qtys.remove(id);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 60, child: Text(fmtMoney(sub.toDouble()), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ],
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildReamRow(DbService db, Map<String, dynamic> prices, String paperName) {
    final reamPrice = (prices['reamPrice'] as num?)?.toDouble() ?? 0;
    final sub = _reamQty * reamPrice;
    return Card(
      color: const Color(0xFFE8F5E9),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text('Resma $paperName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            Text(fmtMoney(reamPrice), style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  hintText: '0',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _reamQty = int.tryParse(v) ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 60, child: Text(fmtMoney(sub.toDouble()), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountRow() {
    return Row(
      children: [
        const Text('Descuento: ', style: TextStyle(fontSize: 13)),
        SizedBox(
          width: 80,
          child: TextField(
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              hintText: '0',
              border: OutlineInputBorder(),
              prefixText: '\$ ',
            ),
            onChanged: (v) => setState(() => _discount = double.tryParse(v) ?? 0),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRow(DbService db) {
    final sub = _subtotal(db);
    final tot = _total(db);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D9488).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Subtotal:', style: TextStyle(fontSize: 14)),
            Text(fmtMoney(sub), style: const TextStyle(fontSize: 14)),
          ]),
          if (_discount > 0)
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Descuento:', style: TextStyle(fontSize: 14)),
              Text('-${fmtMoney(_discount)}', style: const TextStyle(fontSize: 14, color: Colors.red)),
            ]),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('TOTAL:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(fmtMoney(tot), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
          ]),
        ],
      ),
    );
  }

  Widget _payMethodRow() {
    return Row(
      children: [
        const Text('Pago: ', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Efectivo'),
          selected: _payMethod == 'cash',
          onSelected: (_) => setState(() => _payMethod = 'cash'),
          selectedColor: Colors.green.shade100,
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Nequi/Transf.'),
          selected: _payMethod == 'transfer',
          onSelected: (_) => setState(() => _payMethod = 'transfer'),
          selectedColor: Colors.purple.shade100,
        ),
      ],
    );
  }

  Widget _buildSalesHistory(DbService db, SyncService sync) {
    final sales = _copySales(db);
    if (sales.isEmpty) {
      return const Center(child: Text('Sin ventas de copias', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sales.length,
      itemBuilder: (_, i) {
        final s = sales[i];
        final total = (s['total'] as num?)?.toDouble() ?? 0;
        final date = s['date'] ?? '';
        final paper = s['copyPaperType'] ?? '';
        final items = (s['items'] as List?) ?? [];
        final desc = items.map((it) => '${it['productName']} x${it['quantity']}').join(', ');
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            dense: true,
            title: Text('${fmtMoney(total)} - $paper', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$date\n$desc', style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Eliminar venta?'),
                    content: Text('Eliminar ${fmtMoney(total)}?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
                    ],
                  ),
                );
                if (ok == true) {
                  db.sales.removeWhere((x) => x['id'] == s['id']);
                  await db.saveCache();
                  db.notifyListeners();
                  if (sync.firebaseEnabled) sync.saveAndSync();
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildStock(DbService db) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tinta / Recargas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _inkExpenses(db).isEmpty
              ? const Text('Sin registros', style: TextStyle(color: Colors.grey))
              : Column(
                  children: _inkExpenses(db).map((e) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        dense: true,
                        title: Text(e['description'] ?? 'Recarga de tinta'),
                        subtitle: Text(e['date'] ?? ''),
                        trailing: Text(fmtMoney((e['amount'] as num?)?.toDouble() ?? 0)),
                      ),
                    );
                  }).toList(),
                ),
          const Divider(),
          const Text('Resmas en inventario', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ..._recentReamPurchases(db).map((r) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: ListTile(
                dense: true,
                title: Text(r['paperType'] ?? ''),
                trailing: Text('${r['stock']} resmas', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          }),
          const Divider(),
          const Text('Tipos de papel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ..._paperTypes(db).map((pt) {
            final id = pt['id'] as String;
            final sheets = (db.copyPaperStock[id] as num?)?.toInt() ?? 0;
            final reams = (db.copyReamStock[id] as num?)?.toInt() ?? 0;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: ListTile(
                dense: true,
                title: Text(pt['name'] as String),
                trailing: Text('$reams resmas | $sheets hojas'),
              ),
            );
          }),
        ],
      ),
    );
  }
}
