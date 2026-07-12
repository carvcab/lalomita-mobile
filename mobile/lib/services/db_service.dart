import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lalomita_db.dart';

dynamic _sanitize(dynamic v) {
  if (v is double && !v.isFinite) return 0.0;
  if (v is Map) {
    return v.map<String, dynamic>((k, val) => MapEntry(k.toString(), _sanitize(val)));
  }
  if (v is List) return v.map(_sanitize).toList();
  return v;
}

class DbService extends ChangeNotifier {
  List<LalomitaProduct> products = [];
  List<LalomitaSupplier> suppliers = [];
  List<ProdSupplierLink> prodSuppliers = [];
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> purchases = [];
  List<Map<String, dynamic>> consumptions = [];
  List<Map<String, dynamic>> withdrawals = [];
  List<Map<String, dynamic>> stockAdjustments = [];
  List<Map<String, dynamic>> inventarioMovimientos = [];
  List<Map<String, dynamic>> historicoPrecios = [];
  List<Map<String, dynamic>> closings = [];
  List<Map<String, dynamic>> distributions = [];
  List<Map<String, dynamic>> fiadosPagos = [];
  List<Map<String, dynamic>> repairs = [];
  List<Map<String, dynamic>> distributionCategories = [];
  Map<String, dynamic> clientDetails = {};
  Map<String, dynamic> settings = {'businessName': 'Variedades La Lomita', 'currency': '\$'};
  Map<String, dynamic> copyPrices = {};
  Map<String, dynamic> copyPaperStock = {};
  Map<String, dynamic> copyReamStock = {};
  List<Map<String, dynamic>> copyExpenses = [];
  List<Map<String, dynamic>> copyPaperTypes = [];
  List<Map<String, dynamic>> cajaTransactions = [];

  static const _cacheKey = 'lalomita_mobile_cache';

  String genId() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${r.nextInt(999999).toRadixString(36)}';
  }

  String today() => DateTime.now().toIso8601String().split('T').first;

  void loadFromJson(Map<String, dynamic> data) {
    products = (data['products'] as List? ?? [])
        .map((e) => LalomitaProduct.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    suppliers = (data['suppliers'] as List? ?? [])
        .map((e) => LalomitaSupplier.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    prodSuppliers = (data['prodSuppliers'] as List? ?? [])
        .map((e) => ProdSupplierLink.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    sales = (data['sales'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    purchases = (data['purchases'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    consumptions = (data['consumptions'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    withdrawals = (data['withdrawals'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    stockAdjustments = (data['stockAdjustments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    inventarioMovimientos = (data['inventario_movimientos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    historicoPrecios = (data['historico_precios'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    closings = (data['closings'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    distributions = (data['distributions'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    fiadosPagos = (data['fiados_pagos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    distributionCategories = (data['distributionCategories'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    repairs = (data['repairs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    copyPrices = Map<String, dynamic>.from(data['copyPrices'] as Map? ?? {});
    copyPaperStock = Map<String, dynamic>.from(data['copyPaperStock'] as Map? ?? {});
    copyReamStock = Map<String, dynamic>.from(data['copyReamStock'] as Map? ?? {});
    copyExpenses = (data['copyExpenses'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    copyPaperTypes = (data['copyPaperTypes'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    cajaTransactions = (data['cajaTransactions'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    clientDetails = Map<String, dynamic>.from(data['clientDetails'] as Map? ?? {});
    if (data['settings'] != null) {
      settings = Map<String, dynamic>.from(data['settings'] as Map);
    }
  }

  /// Merge server data into local collections.
  /// Keeps local-only items; updates or adds items from the server.
  void mergeCollection(String colName, List<Map<String, dynamic>> serverList) {
    switch (colName) {
      case 'products':
        for (final doc in serverList) {
          final id = doc['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final idx = products.indexWhere((e) => e.id == id);
          if (idx == -1) {
            products.add(LalomitaProduct.fromJson(doc));
          } else {
            final serverUpdated = doc['updatedAt']?.toString() ?? '';
            final localUpdated = products[idx].updatedAt;
            if (serverUpdated.isEmpty || serverUpdated.compareTo(localUpdated) >= 0) {
              products[idx] = LalomitaProduct.fromJson(doc);
            }
          }
        }
        break;
      case 'suppliers':
        for (final doc in serverList) {
          final id = doc['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final idx = suppliers.indexWhere((e) => e.id == id);
          if (idx == -1) {
            suppliers.add(LalomitaSupplier.fromJson(doc));
          } else {
            suppliers[idx] = LalomitaSupplier.fromJson(doc);
          }
        }
        break;
      case 'prodSuppliers':
        for (final doc in serverList) {
          final id = doc['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final idx = prodSuppliers.indexWhere((e) => e.id == id);
          if (idx == -1) {
            prodSuppliers.add(ProdSupplierLink.fromJson(doc));
          } else {
            prodSuppliers[idx] = ProdSupplierLink.fromJson(doc);
          }
        }
        break;
      case 'sales':
      case 'purchases':
      case 'consumptions':
      case 'withdrawals':
      case 'closings':
      case 'distributions':
      case 'stockAdjustments':
      case 'inventario_movimientos':
      case 'historico_precios':
      case 'fiados_pagos':
      case 'distributionCategories':
      case 'repairs':
      case 'copyExpenses':
      case 'copyPaperTypes':
        _mergeMapList(_listFor(colName), serverList);
        break;
      case 'copyPrices':
        if (serverList.isNotEmpty) {
          final src = serverList.first;
          src.remove('id');
          copyPrices = Map<String, dynamic>.from(src);
        }
        break;
      case 'copyPaperStock':
        if (serverList.isNotEmpty) {
          final src = serverList.first;
          src.remove('id');
          copyPaperStock = Map<String, dynamic>.from(src);
        }
        break;
      case 'copyReamStock':
        if (serverList.isNotEmpty) {
          final src = serverList.first;
          src.remove('id');
          copyReamStock = Map<String, dynamic>.from(src);
        }
        break;
      case 'settings':
        if (serverList.isNotEmpty) {
          final src = serverList.firstWhere(
            (x) => x['id'] == 'general',
            orElse: () => serverList.first,
          );
          settings = Map<String, dynamic>.from(src);
          settings.remove('id');
        }
        break;
      case 'clientDetails':
        for (final doc in serverList) {
          final name = doc['id']?.toString() ?? doc['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          clientDetails[name] = {
            'phone': doc['phone']?.toString() ?? '',
            'limit': double.tryParse(doc['limit']?.toString() ?? doc['creditLimit']?.toString() ?? '0') ?? 0.0,
          };
        }
        break;
    }
  }

  List<Map<String, dynamic>> _listFor(String colName) {
    switch (colName) {
      case 'sales':
        return sales;
      case 'purchases':
        return purchases;
      case 'consumptions':
        return consumptions;
      case 'withdrawals':
        return withdrawals;
      case 'closings':
        return closings;
      case 'distributions':
        return distributions;
      case 'stockAdjustments':
        return stockAdjustments;
      case 'inventario_movimientos':
        return inventarioMovimientos;
      case 'historico_precios':
        return historicoPrecios;
      case 'fiados_pagos':
        return fiadosPagos;
      case 'distributionCategories':
        return distributionCategories;
      case 'repairs':
        return repairs;
      case 'copyExpenses':
        return copyExpenses;
      case 'copyPaperTypes':
        return copyPaperTypes;
      case 'cajaTransactions':
        return cajaTransactions;
      default:
        return [];
    }
  }

  void _mergeMapList(List<Map<String, dynamic>> localList, List<Map<String, dynamic>> serverList) {
    for (final doc in serverList) {
      final id = doc['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final idx = localList.indexWhere((e) => e['id']?.toString() == id);
      if (idx == -1) {
        localList.add(Map<String, dynamic>.from(doc));
      } else {
        localList[idx] = Map<String, dynamic>.from(doc);
      }
    }
  }

  Map<String, dynamic> sanitizedToJson() => _sanitize(toJson()) as Map<String, dynamic>;

  Map<String, dynamic> toJson() => {
        'products': products.map((p) => p.toJson()).toList(),
        'suppliers': suppliers.map((s) => s.toJson()).toList(),
        'prodSuppliers': prodSuppliers.map((l) => l.toJson()).toList(),
        'purchases': purchases,
        'sales': sales,
        'consumptions': consumptions,
        'withdrawals': withdrawals,
        'closings': closings,
        'distributions': distributions,
        'stockAdjustments': stockAdjustments,
        'inventario_movimientos': inventarioMovimientos,
        'historico_precios': historicoPrecios,
        'fiados_pagos': fiadosPagos,
        'clientDetails': clientDetails,
        'distributionCategories': distributionCategories,
        'settings': settings,
        'repairs': repairs,
        'copyPrices': copyPrices,
        'copyPaperStock': copyPaperStock,
        'copyReamStock': copyReamStock,
        'copyExpenses': copyExpenses,
        'copyPaperTypes': copyPaperTypes,
        'cajaTransactions': cajaTransactions,
      };

  Future<void> saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_sanitize(toJson())));
  }

  Future<bool> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return false;
    try {
      loadFromJson(jsonDecode(raw) as Map<String, dynamic>);
      return true;
    } catch (_) {
      return false;
    }
  }

  int getStock(String productId) {
    final p = products.where((x) => x.id == productId).firstOrNull;
    if (p == null) return 0;
    // Ignorar campo unlimited para controlar el stock de todos los productos
    // if (p.unlimited) return 999999;
    var initial = p.initialStock;
    var bought = 0, sold = 0, consumed = 0, adjusted = 0;
    for (final pur in purchases) {
      for (final i in (pur['items'] as List? ?? [])) {
        if (i['productId'] == productId) bought += (i['quantity'] as num?)?.toInt() ?? 0;
      }
    }
    for (final s in sales) {
      for (final i in (s['items'] as List? ?? [])) {
        if (i['productId'] == productId) sold += (i['quantity'] as num?)?.toInt() ?? 0;
      }
    }
    for (final c in consumptions) {
      for (final i in (c['items'] as List? ?? [])) {
        if (i['productId'] == productId) consumed += (i['quantity'] as num?)?.toInt() ?? 0;
      }
    }
    for (final a in stockAdjustments) {
      if (a['productId'] == productId) adjusted += (a['quantity'] as num?)?.toInt() ?? 0;
    }
    return initial + bought - sold - consumed + adjusted;
  }

  ProdSupplierLink? getDefaultLink(String productId) {
    final links = prodSuppliers.where((l) => l.productId == productId).toList();
    if (links.isEmpty) return null;
    return links.firstWhere((l) => l.isDefault, orElse: () => links.first);
  }

  List<({LalomitaProduct product, ProdSupplierLink link})> getSellableProducts() {
    final result = <({LalomitaProduct product, ProdSupplierLink link})>[];
    for (final link in prodSuppliers.where((l) => l.salePrice > 0 && l.salePrice.isFinite)) {
      final p = products.where((x) => x.id == link.productId && x.active).firstOrNull;
      if (p != null) result.add((product: p, link: link));
    }
    return result;
  }

  LalomitaProduct? findByBarcode(String barcode) {
    if (barcode.isEmpty) return null;
    return products.where((p) => p.barcode == barcode && p.active).firstOrNull;
  }

  void addMovement(String productId, String type, int prevQty, int newQty, String reason) {
    final p = products.where((x) => x.id == productId).firstOrNull;
    inventarioMovimientos.add({
      'id': genId(),
      'productId': productId,
      'productName': p?.name ?? '',
      'type': type,
      'prevQty': prevQty,
      'newQty': newQty,
      'reason': reason,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  void registerProduct({
    required String name,
    required String category,
    required String barcode,
    required String supplierId,
    required double buyPrice,
    required double sellPrice,
    required int initialStock,
  }) {
    final now = DateTime.now().toIso8601String();
    final productId = genId();
    products.add(LalomitaProduct(
      id: productId,
      name: name,
      category: category,
      barcode: barcode,
      initialStock: initialStock,
      createdAt: now,
      updatedAt: now,
    ));
    if (initialStock > 0) {
      addMovement(productId, 'Ajuste', 0, initialStock, 'Stock inicial (app móvil)');
    }
    if (supplierId.isNotEmpty) {
      prodSuppliers.add(ProdSupplierLink(
        id: genId(),
        productId: productId,
        supplierId: supplierId,
        purchasePrice: buyPrice,
        salePrice: sellPrice,
        isDefault: true,
      ));
      historicoPrecios.add({
        'id': genId(),
        'productId': productId,
        'supplierId': supplierId,
        'purchasePrice': buyPrice,
        'salePrice': sellPrice,
        'reason': 'Registro desde app móvil',
        'createdAt': now,
      });
    }
    notifyListeners();
  }

  void registerPurchase(Map<String, dynamic> purchase) {
    purchases.add(purchase);
    for (final item in (purchase['items'] as List? ?? [])) {
      final pid = item['productId'] as String;
      if (pid.isEmpty) continue;
      final qty = (item['quantity'] as num).toInt();
      final stockBefore = getStock(pid);
      addMovement(pid, 'Compra', stockBefore, stockBefore + qty, 'Compra: ${purchase['invoiceNumber'] ?? 'S/N'}');
    }
    notifyListeners();
  }

  void registerStockAdjustment(Map<String, dynamic> adjustment) {
    final pid = adjustment['productId'] as String? ?? '';
    final qty = (adjustment['quantity'] as num?)?.toInt() ?? 0;
    final stockBefore = pid.isNotEmpty ? getStock(pid) : 0;
    stockAdjustments.add(adjustment);
    if (pid.isNotEmpty) {
      addMovement(pid, 'Ajuste', stockBefore, stockBefore + qty, adjustment['reason'] ?? 'Ajuste manual');
    }
    notifyListeners();
  }

  void completeSale(LalomitaSale sale) {
    sales.add(sale.toJson());
    for (final item in sale.items) {
      final stockAfter = getStock(item.productId);
      addMovement(item.productId, 'Venta', stockAfter + item.quantity, stockAfter, 'Venta POS móvil ${sale.id}');
    }
    notifyListeners();
  }

  double getRunningCashForDate(String targetDate) {
    final closingsList = closings.where((c) => ((c['date'] as String?) ?? '').compareTo(targetDate) < 0).toList();
    closingsList.sort((a, b) => ((a['date'] as String?) ?? '').compareTo((b['date'] as String?) ?? ''));
    final lastClosing = closingsList.isNotEmpty ? closingsList.last : null;
    final afterDate = lastClosing != null ? ((lastClosing['date'] as String?) ?? '2000-01-01') : '2000-01-01';
    
    final afterSales = sales
        .where((s) => ((s['date'] as String?) ?? '').compareTo(afterDate) > 0 && 
                      ((s['date'] as String?) ?? '').compareTo(targetDate) <= 0 && 
                      s['paymentMethod'] != 'credit')
        .fold(0.0, (sum, s) => sum + (double.tryParse(s['total']?.toString() ?? '0') ?? 0.0));
        
    final afterWithdrawals = withdrawals
        .where((w) => ((w['date'] as String?) ?? '').compareTo(afterDate) > 0 && 
                      ((w['date'] as String?) ?? '').compareTo(targetDate) <= 0)
        .fold(0.0, (sum, w) => sum + (double.tryParse(w['amount']?.toString() ?? '0') ?? 0.0));
        
    final afterAbonos = fiadosPagos
        .where((p) => ((p['date'] as String?) ?? '').compareTo(afterDate) > 0 && 
                      ((p['date'] as String?) ?? '').compareTo(targetDate) <= 0 && 
                      p['payMethod'] == 'cash')
        .fold(0.0, (sum, p) => sum + (double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0));
        
    double afterRepairsIncome = 0;
    for (final r in repairs) {
      final payments = r['payments'] as List? ?? [];
      for (final p in payments) {
        final date = (p['date'] as String?) ?? '';
        final method = (p['method'] as String?) ?? '';
        if (date.compareTo(afterDate) > 0 && date.compareTo(targetDate) <= 0 && method == 'cash') {
          afterRepairsIncome += double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0;
        }
      }
    }
    
    double afterRepairsExpenses = 0;
    for (final r in repairs) {
      final expenses = r['expenses'] as List? ?? [];
      for (final e in expenses) {
        final date = (e['date'] as String?) ?? '';
        final method = (e['method'] as String?) ?? '';
        if (date.compareTo(afterDate) > 0 && date.compareTo(targetDate) <= 0 && method == 'cash') {
          afterRepairsExpenses += double.tryParse(e['amount']?.toString() ?? '0') ?? 0.0;
        }
      }
    }
    
    final afterPurchasesPaid = purchases
        .where((p) => (p['paid'] as bool? ?? false) && 
                      ((p['date'] as String?) ?? '').compareTo(afterDate) > 0 && 
                      ((p['date'] as String?) ?? '').compareTo(targetDate) <= 0)
        .fold(0.0, (sum, p) => sum + (double.tryParse(p['total']?.toString() ?? '0') ?? 0.0));
        
    final base = lastClosing != null ? (double.tryParse(lastClosing['actualCash']?.toString() ?? '0') ?? 0.0) : 0.0;
    return base + afterSales + afterAbonos + afterRepairsIncome - afterWithdrawals - afterRepairsExpenses - afterPurchasesPaid;
  }

  void updateSale(Map<String, dynamic> editedSale) {
    final id = editedSale['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final idx = sales.indexWhere((s) => s['id']?.toString() == id);
    if (idx != -1) {
      sales[idx] = Map<String, dynamic>.from(editedSale);
      sales[idx]['updatedAt'] = DateTime.now().toIso8601String();
      notifyListeners();
    }
  }

}
