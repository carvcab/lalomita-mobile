import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';

class InventoryMovementsScreen extends StatefulWidget {
  final String? filterProductId;
  const InventoryMovementsScreen({super.key, this.filterProductId});

  @override
  State<InventoryMovementsScreen> createState() => _InventoryMovementsScreenState();
}

class _InventoryMovementsScreenState extends State<InventoryMovementsScreen> {
  final _searchCtrl = TextEditingController();
  String _typeFilter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'venta':
        return Icons.shopping_cart;
      case 'compra':
        return Icons.shopping_bag;
      case 'ajuste':
        return Icons.tune;
      case 'corrección':
        return Icons.edit;
      case 'eliminación':
        return Icons.delete;
      default:
        return Icons.swap_horiz;
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'venta':
        return Colors.orange;
      case 'compra':
        return Colors.green;
      case 'ajuste':
        return Colors.blue;
      case 'corrección':
        return Colors.purple;
      case 'eliminación':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbService>();

    var movements = db.inventarioMovimientos.reversed.toList();

    if (widget.filterProductId != null) {
      movements = movements.where((m) => m['productId'] == widget.filterProductId).toList();
    }

    final q = _searchCtrl.text.toLowerCase();
    if (q.isNotEmpty) {
      movements = movements.where((m) {
        final name = (m['productName'] as String?)?.toLowerCase() ?? '';
        final type = (m['type'] as String?)?.toLowerCase() ?? '';
        final reason = (m['reason'] as String?)?.toLowerCase() ?? '';
        return name.contains(q) || type.contains(q) || reason.contains(q);
      }).toList();
    }

    if (_typeFilter.isNotEmpty) {
      movements = movements.where((m) => (m['type'] as String?)?.toLowerCase() == _typeFilter.toLowerCase()).toList();
    }

    final types = db.inventarioMovimientos.map((m) => m['type'] as String? ?? '').where((t) => t.isNotEmpty).toSet().toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: const Text('Movimientos de Inventario'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por producto, tipo o motivo...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          if (types.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('Todos', style: TextStyle(fontWeight: FontWeight.w600, color: _typeFilter.isEmpty ? Colors.white : Colors.black87, fontSize: 12)),
                      selected: _typeFilter.isEmpty,
                      onSelected: (_) => setState(() => _typeFilter = ''),
                      selectedColor: const Color(0xFF0D9488),
                      checkmarkColor: Colors.white,
                    ),
                  ),
                  ...types.map((t) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: _typeFilter == t ? Colors.white : Colors.black87, fontSize: 12)),
                      selected: _typeFilter == t,
                      onSelected: (_) => setState(() => _typeFilter = _typeFilter == t ? '' : t),
                      selectedColor: _colorForType(t),
                      checkmarkColor: Colors.white,
                    ),
                  )),
                ],
              ),
            ),
          Expanded(
            child: movements.isEmpty
                ? const Center(
                    child: Text('Sin movimientos', style: TextStyle(color: Colors.black54, fontSize: 16)),
                  )
                : ListView.builder(
                    itemCount: movements.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (_, i) {
                      final m = movements[i];
                      final type = m['type'] as String? ?? '';
                      final name = m['productName'] as String? ?? '';
                      final prev = (m['prevQty'] as num?)?.toInt() ?? 0;
                      final newQty = (m['newQty'] as num?)?.toInt() ?? 0;
                      final reason = m['reason'] as String? ?? '';
                      final date = m['createdAt'] as String? ?? '';

                      final diff = newQty - prev;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _colorForType(type).withValues(alpha: 0.15),
                            foregroundColor: _colorForType(type),
                            child: Icon(_iconForType(type), size: 22),
                          ),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _colorForType(type).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _colorForType(type),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${reason.isEmpty ? "" : "$reason | "}${_formatDate(date)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                diff >= 0 ? '+$diff' : '$diff',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: diff >= 0 ? Colors.green : Colors.red,
                                ),
                              ),
                              Text(
                                '$prev → $newQty',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            ],
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
}
