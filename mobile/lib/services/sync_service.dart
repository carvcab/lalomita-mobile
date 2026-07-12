import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_options.dart';
import '../models/lalomita_db.dart';
import 'db_service.dart';

class SyncService extends ChangeNotifier {
  static const _serverKey = 'lalomita_server_url';
  static const _fbEnabledKey = 'lalomita_firebase_enabled';
  static const _pendingSyncKey = 'lalomita_pending_sync';

  final DbService db;
  String serverUrl = '';
  bool firebaseEnabled = true;
  bool syncing = false;
  bool connected = false;
  String? lastError;
  DateTime? lastSync;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  final List<StreamSubscription> _subscriptions = [];
  bool _firebaseInitialized = false;
  bool _pendingSync = false;
  final Set<String> _locallyDeletedSaleIds = {};

  SyncService(this.db);

  String get dbUrl => serverUrl.isEmpty ? '' : '$serverUrl/api/db';
  String get infoUrl => serverUrl.isEmpty ? '' : '$serverUrl/api/info';

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString(_serverKey) ?? '';
    firebaseEnabled = prefs.getBool(_fbEnabledKey) ?? true;
    _pendingSync = prefs.getBool(_pendingSyncKey) ?? false;
    notifyListeners();
    if (firebaseEnabled) {
      try {
        await initFirebase();
      } catch (_) {
        connected = false;
        lastError = 'Sin conexion - trabajando offline';
        notifyListeners();
      }
      if (_pendingSync) {
        _scheduleReconnectRetry();
      }
    } else {
      _cancelSubscriptions();
      if (serverUrl.isNotEmpty) {
        startAutoSync();
      }
    }
  }

  Future<void> saveServerUrl(String url) async {
    serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, serverUrl);
    notifyListeners();
    if (!firebaseEnabled) {
      await testConnection();
    }
  }

  Future<void> toggleFirebase(bool enabled) async {
    firebaseEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fbEnabledKey, enabled);
    notifyListeners();
    if (enabled) {
      stopAutoSync();
      await initFirebase();
    } else {
      _cancelSubscriptions();
      connected = false;
      lastError = null;
      notifyListeners();
      if (serverUrl.isNotEmpty) {
        startAutoSync();
      }
    }
  }

  static const _firestoreCols = [
    'products', 'suppliers', 'prodSuppliers', 'purchases', 'sales',
    'consumptions', 'withdrawals', 'closings', 'distributions',
    'stockAdjustments', 'inventario_movimientos', 'historico_precios',
    'fiados_pagos', 'distributionCategories', 'repairs', 'copyExpenses',
    'copyPaperTypes', 'copyPrices', 'copyPaperStock', 'copyReamStock', 'settings',
    'clientDetails'
  ];

  Future<void> initFirebase({bool force = false}) async {
    if (force) {
      _stopListeners();
    } else if (_firebaseInitialized) {
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await FirebaseFirestore.instance.settings;
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (_) {}
      _firebaseInitialized = true;
      lastError = null;
      notifyListeners();

      // Test Firestore access
      try {
        await FirebaseFirestore.instance
            .collection('settings')
            .doc('general')
            .get()
            .timeout(const Duration(seconds: 10));
        connected = true;
        lastError = null;
        lastSync = DateTime.now();
        notifyListeners();
      } catch (e) {
        print("Firestore test read failed: $e");
        connected = false;
        lastError = 'No se pudo leer Firestore: $e\n\nVerifica las reglas de Firestore en la consola de Firebase.';
        notifyListeners();
      }

      // Initial pull + real-time listeners
      await _listenToFirestore();
    } catch (e) {
      _firebaseInitialized = false;
      connected = false;
      lastError = 'Error al inicializar Firebase: $e';
      notifyListeners();
    }
  }

  Map<String, dynamic> _firestoreDocData(String col, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data());
    if (col == 'clientDetails') {
      data['id'] = doc.id;
    } else {
      data['id'] = data['id']?.toString() ?? doc.id;
    }
    return data;
  }

  Future<void> _listenToFirestore() async {
    if (!_firebaseInitialized) return;
    _stopListeners();
    final dbRef = FirebaseFirestore.instance;

    try {
      for (final col in _firestoreCols) {
        try {
          final snap = await dbRef.collection(col).get().timeout(const Duration(seconds: 15));
          final list = snap.docs.map((doc) => _firestoreDocData(col, doc)).toList();
          db.mergeCollection(col, list);
        } catch (e) {
          print("Firestore initial pull error on $col: $e");
        }
      }
      await db.saveCache();
      db.notifyListeners();
      connected = true;
      lastError = null;
      lastSync = DateTime.now();
      notifyListeners();
    } catch (e) {
      print("Firestore initial pull failed: $e");
      connected = false;
    }

    for (final col in _firestoreCols) {
      final sub = dbRef.collection(col).snapshots().listen(
        (snapshot) {
          var changed = false;
          for (final doc in snapshot.docs) {
            final data = _firestoreDocData(col, doc);
            final id = data['id']?.toString() ?? doc.id;
            if (col == 'sales' && _locallyDeletedSaleIds.contains(id)) {
              continue;
            }
            db.mergeCollection(col, [data]);
            changed = true;
          }
          if (snapshot.metadata.hasPendingWrites == false && snapshot.docChanges.isNotEmpty) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.removed) {
                _handleRemoved(col, change.doc.id);
                changed = true;
              }
            }
          }
          if (changed) {
            db.saveCache();
            db.notifyListeners();
            lastSync = DateTime.now();
            connected = true;
            lastError = null;
            notifyListeners();
          }
          if (_pendingSync) {
            _flushPendingSync();
          }
        },
        onError: (e) {
          print("Firestore listener error on $col: $e");
          connected = false;
          lastError = 'Error en tiempo real ($col): $e';
          notifyListeners();
          _scheduleReconnectRetry();
        },
      );
      _subscriptions.add(sub);
    }
  }

  void _handleRemoved(String col, String docId) {
    switch (col) {
      case 'products':
        db.products.removeWhere((e) => e.id == docId);
      case 'suppliers':
        db.suppliers.removeWhere((e) => e.id == docId);
      case 'prodSuppliers':
        db.prodSuppliers.removeWhere((e) => e.id == docId);
      case 'sales':
        db.sales.removeWhere((e) => e['id'] == docId);
      case 'purchases':
        db.purchases.removeWhere((e) => e['id'] == docId);
      case 'consumptions':
        db.consumptions.removeWhere((e) => e['id'] == docId);
      case 'withdrawals':
        db.withdrawals.removeWhere((e) => e['id'] == docId);
      case 'closings':
        db.closings.removeWhere((e) => e['id'] == docId);
      case 'distributions':
        db.distributions.removeWhere((e) => e['id'] == docId);
      case 'stockAdjustments':
        db.stockAdjustments.removeWhere((e) => e['id'] == docId);
      case 'inventario_movimientos':
        db.inventarioMovimientos.removeWhere((e) => e['id'] == docId);
      case 'historico_precios':
        db.historicoPrecios.removeWhere((e) => e['id'] == docId);
      case 'fiados_pagos':
        db.fiadosPagos.removeWhere((e) => e['id'] == docId);
      case 'distributionCategories':
        db.distributionCategories.removeWhere((e) => e['id'] == docId);
      case 'repairs':
        db.repairs.removeWhere((e) => e['id'] == docId);
      case 'copyExpenses':
        db.copyExpenses.removeWhere((e) => e['id'] == docId);
      case 'copyPaperTypes':
        db.copyPaperTypes.removeWhere((e) => e['id'] == docId);
      case 'copyPrices':
        db.copyPrices.remove(docId);
      case 'copyPaperStock':
        db.copyPaperStock.remove(docId);
      case 'copyReamStock':
        db.copyReamStock.remove(docId);
      case 'cajaTransactions':
        db.cajaTransactions.removeWhere((e) => e['id'] == docId);
      case 'clientDetails':
        db.clientDetails.remove(docId);
    }
  }

  void _stopListeners() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _cancelSubscriptions() {
    _stopListeners();
    _firebaseInitialized = false;
    _locallyDeletedSaleIds.clear();
  }

  Future<bool> testConnection() async {
    if (serverUrl.isEmpty) {
      lastError = 'Ingresa la IP del PC';
      connected = false;
      notifyListeners();
      return false;
    }
    try {
      final res = await http.get(Uri.parse(infoUrl)).timeout(const Duration(seconds: 5));
      connected = res.statusCode == 200;
      lastError = connected ? null : 'Servidor no responde';
    } catch (e) {
      connected = false;
      lastError = 'No se pudo conectar: $e';
    }
    notifyListeners();
    return connected;
  }

  Future<bool> pullFromServer() async {
    if (serverUrl.isEmpty) return false;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      final res = await http.get(Uri.parse(dbUrl)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data['products'] != null) {
        for (final entry in data.entries) {
          if (entry.value is List) {
            db.mergeCollection(
              entry.key,
              (entry.value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
            );
          }
        }
        if (data['clientDetails'] is Map) {
          final clients = (data['clientDetails'] as Map).entries.map((e) {
            final details = Map<String, dynamic>.from(e.value as Map);
            details['id'] = e.key.toString();
            return details;
          }).toList();
          db.mergeCollection('clientDetails', clients);
        }
        if (data['settings'] is Map) {
          db.mergeCollection('settings', [
            {...Map<String, dynamic>.from(data['settings'] as Map), 'id': 'general'},
          ]);
        }
        await db.saveCache();
        db.notifyListeners();
        lastSync = DateTime.now();
        connected = true;
      }
      syncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Error al descargar: $e';
      syncing = false;
      connected = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> pushToServer() async {
    if (serverUrl.isEmpty) return false;
    syncing = true;
    notifyListeners();
    try {
      final res = await http
          .post(
            Uri.parse(dbUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(db.sanitizedToJson()),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      lastSync = DateTime.now();
      connected = true;
      syncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Error al subir: $e';
      syncing = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> sync() async {
    if (firebaseEnabled) {
      if (!_firebaseInitialized) {
        await initFirebase();
      } else {
        await _listenToFirestore();
      }
      return connected;
    } else {
      await pullFromServer();
      if (serverUrl.isNotEmpty) {
        await pushToServer();
      }
      return connected;
    }
  }

  Future<bool> saveAndSync() async {
    await db.saveCache();
    if (firebaseEnabled && _firebaseInitialized && connected) {
      try {
        final ok = await _pushAllToFirestore();
        if (!ok) await _setPendingSync(true);
        return ok;
      } catch (_) {
        await _setPendingSync(true);
        return false;
      }
    }
    if (firebaseEnabled && !connected) {
      await _setPendingSync(true);
      return false;
    }
    if (!firebaseEnabled && serverUrl.isNotEmpty) {
      try {
        return await pushToServer();
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<bool> pushToFirebase() => _pushAllToFirestore();

  Future<bool> _pushAllToFirestore() async {
    if (!_firebaseInitialized) return false;
    syncing = true;
    notifyListeners();
    try {
      final dbRef = FirebaseFirestore.instance;
      final json = db.sanitizedToJson();
      final mapCollections = {'copyPrices', 'copyPaperStock', 'copyReamStock'};
      for (final col in _firestoreCols) {
        if (col == 'clientDetails' || col == 'settings') continue;
        if (mapCollections.contains(col)) {
          final mapData = json[col] as Map? ?? {};
          if (mapData.isNotEmpty) {
            await dbRef.collection(col).doc('general').set(Map<String, dynamic>.from(mapData)).timeout(const Duration(seconds: 8));
          }
          continue;
        }
        final list = json[col] as List? ?? [];
        for (final item in list) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          await dbRef.collection(col).doc(id).set(map).timeout(const Duration(seconds: 8));
        }
      }
      for (final entry in (json['clientDetails'] as Map? ?? {}).entries) {
        await dbRef
            .collection('clientDetails')
            .doc(entry.key.toString())
            .set(Map<String, dynamic>.from(entry.value as Map))
            .timeout(const Duration(seconds: 8));
      }
      final settings = json['settings'] as Map? ?? {};
      if (settings.isNotEmpty) {
        await dbRef.collection('settings').doc('general').set(Map<String, dynamic>.from(settings)).timeout(const Duration(seconds: 8));
      }
      lastSync = DateTime.now();
      connected = true;
      syncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Error al subir a Firebase: $e';
      syncing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> registerProduct({
    required String name,
    required String category,
    required String barcode,
    required String supplierId,
    required double buyPrice,
    required double sellPrice,
    required int initialStock,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final productId = db.genId();
      final p = LalomitaProduct(
        id: productId,
        name: name,
        category: category,
        barcode: barcode,
        initialStock: initialStock,
        createdAt: now,
        updatedAt: now,
      );
      db.products.add(p);

      ProdSupplierLink? link;
      link = ProdSupplierLink(
        id: db.genId(),
        productId: productId,
        supplierId: supplierId,
        purchasePrice: buyPrice,
        salePrice: sellPrice,
        isDefault: true,
      );
      db.prodSuppliers.add(link);
      db.historicoPrecios.add({
        'id': db.genId(),
        'productId': productId,
        'supplierId': supplierId,
        'purchasePrice': buyPrice,
        'salePrice': sellPrice,
        'reason': 'Registro desde app móvil',
        'createdAt': now,
      });


      if (initialStock > 0) {
        db.addMovement(productId, 'Ajuste', 0, initialStock, 'Stock inicial (app móvil)');
      }

      await db.saveCache();
      db.notifyListeners();
      notifyListeners();

      _syncRegisterProduct(p, link, initialStock, now, buyPrice, sellPrice, supplierId, productId);
    } catch (e) {
      print("Unexpected error in registerProduct: $e");
      rethrow;
    }
  }

  Future<void> _syncRegisterProduct(
    LalomitaProduct p,
    ProdSupplierLink? link,
    int initialStock,
    String now,
    double buyPrice,
    double sellPrice,
    String supplierId,
    String productId,
  ) async {
    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('products').doc(p.id).set(p.toJson()).timeout(const Duration(seconds: 4));
        if (link != null) {
          await dbRef.collection('prodSuppliers').doc(link.id).set(link.toJson()).timeout(const Duration(seconds: 4));
          final historyId = db.genId();
          await dbRef.collection('historico_precios').doc(historyId).set({
            'id': historyId,
            'productId': productId,
            'supplierId': supplierId,
            'purchasePrice': buyPrice,
            'salePrice': sellPrice,
            'reason': 'Registro desde app móvil',
            'createdAt': now,
          }).timeout(const Duration(seconds: 4));
        }
        if (initialStock > 0) {
          final movementId = db.genId();
          await dbRef.collection('inventario_movimientos').doc(movementId).set({
            'id': movementId,
            'productId': productId,
            'productName': p.name,
            'type': 'Ajuste',
            'prevQty': 0,
            'newQty': initialStock,
            'reason': 'Stock inicial (app móvil)',
            'createdAt': now,
          }).timeout(const Duration(seconds: 4));
        }
      } catch (e) {
        print("Firebase error saving product: $e");
        lastError = 'Error al registrar producto: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required String category,
    required String barcode,
    required String supplierId,
    required double buyPrice,
    required double sellPrice,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final pIdx = db.products.indexWhere((x) => x.id == id);
      if (pIdx == -1) return;

      db.products[pIdx].name = name;
      db.products[pIdx].category = category;
      db.products[pIdx].barcode = barcode;
      db.products[pIdx].updatedAt = now;

      final linkIdx = db.prodSuppliers.indexWhere((x) => x.productId == id && x.isDefault);
      ProdSupplierLink? link;
      String? oldLinkIdToDelete;

      if (linkIdx != -1) {
        link = db.prodSuppliers[linkIdx];
        final oldBuy = link.purchasePrice;
        final oldSell = link.salePrice;

        link.supplierId = supplierId;
        link.purchasePrice = buyPrice;
        link.salePrice = sellPrice;

        if (oldBuy != buyPrice || oldSell != sellPrice) {
          db.historicoPrecios.add({
            'id': db.genId(),
            'productId': id,
            'supplierId': supplierId,
            'purchasePrice': buyPrice,
            'salePrice': sellPrice,
            'reason': 'Actualización desde app móvil',
            'createdAt': now,
          });
        }
      } else {
        link = ProdSupplierLink(
          id: db.genId(),
          productId: id,
          supplierId: supplierId,
          purchasePrice: buyPrice,
          salePrice: sellPrice,
          isDefault: true,
        );
        db.prodSuppliers.add(link);
        db.historicoPrecios.add({
          'id': db.genId(),
          'productId': id,
          'supplierId': supplierId,
          'purchasePrice': buyPrice,
          'salePrice': sellPrice,
          'reason': 'Actualización desde app móvil (nuevo link)',
          'createdAt': now,
        });
      }

      await db.saveCache();
      db.notifyListeners();
      notifyListeners();

      _syncUpdateProduct(id, pIdx, link, oldLinkIdToDelete, buyPrice, sellPrice, supplierId, now);
    } catch (e) {
      print("Unexpected error in updateProduct: $e");
      rethrow;
    }
  }

  Future<void> _syncUpdateProduct(
    String id,
    int pIdx,
    ProdSupplierLink? link,
    String? oldLinkIdToDelete,
    double buyPrice,
    double sellPrice,
    String supplierId,
    String now,
  ) async {
    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('products').doc(id).set(db.products[pIdx].toJson()).timeout(const Duration(seconds: 4));
        if (oldLinkIdToDelete != null) {
          await dbRef.collection('prodSuppliers').doc(oldLinkIdToDelete).delete().timeout(const Duration(seconds: 4));
        }
        if (link != null) {
          await dbRef.collection('prodSuppliers').doc(link.id).set(link.toJson()).timeout(const Duration(seconds: 4));
          final historyId = db.genId();
          await dbRef.collection('historico_precios').doc(historyId).set({
            'id': historyId,
            'productId': id,
            'supplierId': supplierId,
            'purchasePrice': buyPrice,
            'salePrice': sellPrice,
            'reason': 'Actualización desde app móvil',
            'createdAt': now,
          }).timeout(const Duration(seconds: 4));
        }
      } catch (e) {
        print("Firebase error updating product: $e");
        lastError = 'Error al actualizar producto: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> deleteProduct(String productId, {String reason = ''}) async {
    final idx = db.products.indexWhere((x) => x.id == productId);
    if (idx == -1) return;
    db.products[idx].active = false;
    db.products[idx].updatedAt = DateTime.now().toIso8601String();
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    _syncDeleteProduct(productId, idx);
  }

  Future<void> _syncDeleteProduct(String productId, int idx) async {
    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('products').doc(productId).set(db.products[idx].toJson()).timeout(const Duration(seconds: 4));
      } catch (e) {
        print("Firebase error deactivating product: $e");
        lastError = 'Error al dar de baja producto: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> restoreProduct(String productId) async {
    final idx = db.products.indexWhere((x) => x.id == productId);
    if (idx == -1) return;
    db.products[idx].active = true;
    db.products[idx].updatedAt = DateTime.now().toIso8601String();
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    _syncRestoreProduct(productId, idx);
  }

  Future<void> _syncRestoreProduct(String productId, int idx) async {
    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('products').doc(productId).set(db.products[idx].toJson()).timeout(const Duration(seconds: 4));
      } catch (e) {
        print("Firebase error restoring product: $e");
        lastError = 'Error al reactivar producto: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> registerSupplier({
    required String name,
    required String contact,
    required String address,
  }) async {
    final supplierId = db.genId();
    final s = LalomitaSupplier(
      id: supplierId,
      name: name,
      contact: contact,
      address: address,
    );
    db.suppliers.add(s);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    if (firebaseEnabled && _firebaseInitialized) {
      try {
        await FirebaseFirestore.instance.collection('suppliers').doc(s.id).set(s.toJson()).timeout(const Duration(seconds: 4));
      } catch (e) {
        print("Firebase error saving supplier: $e");
        lastError = 'Error al registrar proveedor: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    required String contact,
    required String address,
  }) async {
    final idx = db.suppliers.indexWhere((x) => x.id == id);
    if (idx == -1) return;
    db.suppliers[idx].name = name;
    db.suppliers[idx].contact = contact;
    db.suppliers[idx].address = address;
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    if (firebaseEnabled && _firebaseInitialized) {
      try {
        await FirebaseFirestore.instance.collection('suppliers').doc(id).set(db.suppliers[idx].toJson()).timeout(const Duration(seconds: 4));
      } catch (e) {
        print("Firebase error updating supplier: $e");
        lastError = 'Error al actualizar proveedor: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> deleteSupplier(String supplierId) async {
    db.suppliers.removeWhere((x) => x.id == supplierId);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    if (firebaseEnabled && _firebaseInitialized) {
      try {
        await FirebaseFirestore.instance.collection('suppliers').doc(supplierId).delete().timeout(const Duration(seconds: 4));
      } catch (e) {
        print("Firebase error deleting supplier: $e");
        lastError = 'Error al eliminar proveedor: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> completeSale(LalomitaSale sale) async {
    db.completeSale(sale);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    // Sincronizar en segundo plano sin bloquear el flujo principal
    _syncSaleToFirestore(sale);
  }

  Future<void> registerPurchase(Map<String, dynamic> purchase) async {
    db.registerPurchase(purchase);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();
    _syncPurchaseToFirestore(purchase);
  }

  Future<void> _syncPurchaseToFirestore(Map<String, dynamic> purchase) async {
    try {
      if (firebaseEnabled && _firebaseInitialized) {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('purchases').doc(purchase['id']).set(purchase).timeout(const Duration(seconds: 8));
        for (final item in (purchase['items'] as List? ?? [])) {
          final pid = item['productId'] as String? ?? '';
          if (pid.isEmpty) continue;
          final qty = (item['quantity'] as num?)?.toInt() ?? 0;
          final stock = db.getStock(pid);
          final movementId = db.genId();
          await dbRef.collection('inventario_movimientos').doc(movementId).set({
            'id': movementId,
            'productId': pid,
            'productName': item['productName'] ?? '',
            'type': 'Compra',
            'prevQty': stock - qty,
            'newQty': stock,
            'reason': 'Compra: ${purchase['invoiceNumber'] ?? 'S/N'}',
            'createdAt': purchase['createdAt'] ?? DateTime.now().toIso8601String(),
          }).timeout(const Duration(seconds: 4));
        }
      }
      if (serverUrl.isNotEmpty) {
        unawaited(pushToServer());
      }
    } catch (e) {
      print("Sync warning: compra guardada localmente, error al sincronizar: $e");
      lastError = 'Error al sincronizar compra: $e';
      connected = false;
      _setPendingSync(true);
      notifyListeners();
    }
  }

  Future<void> registerStockAdjustment(Map<String, dynamic> adjustment) async {
    db.registerStockAdjustment(adjustment);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();
    _syncStockAdjustmentToFirestore(adjustment);
  }

  Future<void> _syncStockAdjustmentToFirestore(Map<String, dynamic> adjustment) async {
    try {
      if (firebaseEnabled && _firebaseInitialized) {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('stockAdjustments').doc(adjustment['id']).set(adjustment).timeout(const Duration(seconds: 8));
        final pid = adjustment['productId'] as String? ?? '';
        if (pid.isNotEmpty) {
          final qty = (adjustment['quantity'] as num?)?.toInt() ?? 0;
          final stock = db.getStock(pid);
          final movementId = db.genId();
          await dbRef.collection('inventario_movimientos').doc(movementId).set({
            'id': movementId,
            'productId': pid,
            'productName': adjustment['productName'] ?? '',
            'type': 'Ajuste',
            'prevQty': stock - qty,
            'newQty': stock,
            'reason': adjustment['reason'] ?? 'Ajuste manual',
            'createdAt': adjustment['createdAt'] ?? DateTime.now().toIso8601String(),
          }).timeout(const Duration(seconds: 4));
        }
      }
      if (serverUrl.isNotEmpty) {
        unawaited(pushToServer());
      }
    } catch (e) {
      print("Sync warning: ajuste guardado localmente, error al sincronizar: $e");
      lastError = 'Error al sincronizar ajuste: $e';
      connected = false;
      _setPendingSync(true);
      notifyListeners();
    }
  }

  Future<void> registerFiadoPago(Map<String, dynamic> pago) async {
    db.fiadosPagos.add(pago);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    _syncFiadoPagoToFirestore(pago);
  }

  Future<void> _syncFiadoPagoToFirestore(Map<String, dynamic> pago) async {
    try {
      if (firebaseEnabled && _firebaseInitialized) {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('fiados_pagos').doc(pago['id']).set(pago).timeout(const Duration(seconds: 8));
      }
      if (serverUrl.isNotEmpty) {
        unawaited(pushToServer());
      }
    } catch (e) {
      print("Sync warning: abono guardado localmente, error al sincronizar: $e");
      lastError = 'Error al sincronizar abono: $e';
      connected = false;
      _setPendingSync(true);
      notifyListeners();
    }
  }

  Future<void> _syncSaleToFirestore(LalomitaSale sale) async {
    try {
      if (firebaseEnabled && _firebaseInitialized) {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('sales').doc(sale.id).set(sale.toJson()).timeout(const Duration(seconds: 8));
        for (final item in sale.items) {
          final stock = db.getStock(item.productId);
          final movementId = db.genId();
          await dbRef.collection('inventario_movimientos').doc(movementId).set({
            'id': movementId,
            'productId': item.productId,
            'productName': item.productName,
            'type': 'Venta',
            'prevQty': stock + item.quantity,
            'newQty': stock,
            'reason': 'Venta POS móvil',
            'createdAt': sale.date,
          }).timeout(const Duration(seconds: 4));
        }
      }
    if (serverUrl.isNotEmpty) {
        unawaited(pushToServer());
      }
    } catch (e) {
      print("Sync warning: venta guardada localmente, error al sincronizar: $e");
      lastError = 'Error al sincronizar venta: $e';
      connected = false;
      _setPendingSync(true);
      notifyListeners();
    }
  }

  Future<void> deleteSale(String saleId) async {
    final idx = db.sales.indexWhere((s) => s['id'] == saleId);
    if (idx == -1) return;
    final sale = db.sales[idx];

    _locallyDeletedSaleIds.add(saleId);

    for (final item in (sale['items'] as List? ?? [])) {
      final productId = item['productId'];
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final stock = db.getStock(productId);
      db.addMovement(productId, 'Eliminación', stock, stock + qty, 'Venta POS móvil eliminada');
    }

    db.sales.removeAt(idx);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('sales').doc(saleId).delete().timeout(const Duration(seconds: 4));
        for (final item in (sale['items'] as List? ?? [])) {
          final productId = item['productId'];
          final qty = (item['quantity'] as num?)?.toInt() ?? 0;
          final stock = db.getStock(productId);
          final movementId = db.genId();
          await dbRef.collection('inventario_movimientos').doc(movementId).set({
            'id': movementId,
            'productId': productId,
            'productName': item['productName'] ?? '',
            'type': 'Eliminación',
            'prevQty': stock - qty,
            'newQty': stock,
            'reason': 'Venta POS móvil eliminada',
            'createdAt': DateTime.now().toIso8601String(),
          }).timeout(const Duration(seconds: 4));
        }
        _locallyDeletedSaleIds.remove(saleId);
      } catch (e) {
        print("Firebase error deleting sale: $e");
        lastError = 'Error al eliminar venta: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      try {
        unawaited(pushToServer());
        _locallyDeletedSaleIds.remove(saleId);
      } catch (e) {
        print("HTTP error pushing delete: $e");
        _setPendingSync(true);
      }
    } else {
      _locallyDeletedSaleIds.remove(saleId);
    }
  }

  Future<void> completeClosing(Map<String, dynamic> closing) async {
    db.closings.add(closing);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('closings').doc(closing['id']).set(closing).timeout(const Duration(seconds: 4));
      } catch (e) {
        print("Firebase error saving closing: $e");
        lastError = 'Error al guardar cierre: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> deleteClosing(String closingId) async {
    db.closings.removeWhere((c) => c['id'] == closingId);
    db.distributions.removeWhere((d) => d['closingId'] == closingId);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('closings').doc(closingId).delete().timeout(const Duration(seconds: 4));
        final distSnaps = await dbRef.collection('distributions').where('closingId', isEqualTo: closingId).get();
        for (final doc in distSnaps.docs) {
          await doc.reference.delete().timeout(const Duration(seconds: 4));
        }
      } catch (e) {
        print("Firebase error deleting closing: $e");
        lastError = 'Error al eliminar cierre: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  Future<void> saveDistribution(Map<String, dynamic> dist) async {
    final closingId = dist['closingId'];
    final closingIdx = db.closings.indexWhere((c) => c['id'] == closingId);
    if (closingIdx != -1) {
      db.closings[closingIdx]['isDistributed'] = true;
      db.closings[closingIdx]['distributedAt'] = dist['createdAt'] ?? DateTime.now().toIso8601String();
    }

    db.distributions.removeWhere((d) => d['closingId'] == closingId);
    db.distributions.add(dist);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    if (firebaseEnabled && _firebaseInitialized) {
      try {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('distributions').doc(dist['id']).set(dist).timeout(const Duration(seconds: 4));
        if (closingIdx != -1) {
          await dbRef.collection('closings').doc(closingId).update({
            'isDistributed': true,
            'distributedAt': db.closings[closingIdx]['distributedAt'],
          }).timeout(const Duration(seconds: 4));
        }
      } catch (e) {
        print("Firebase error saving distribution: $e");
        lastError = 'Error al guardar distribución: $e';
        connected = false;
        _setPendingSync(true);
        notifyListeners();
      }
    }
    if (serverUrl.isNotEmpty) {
      unawaited(pushToServer());
    }
  }

  
  Future<void> updateSale(Map<String, dynamic> editedSale, List<Map<String, dynamic>> originalItems) async {
    db.updateSale(editedSale);
    await db.saveCache();
    db.notifyListeners();
    notifyListeners();

    final editedItems = editedSale['items'] as List? ?? [];
    
    // Log movements for modified or deleted original items
    for (final orig in originalItems) {
      final pid = orig['productId'] as String? ?? '';
      if (pid.isEmpty) continue;
      final isSpecial = pid.startsWith('copy_') || pid.startsWith('print_') || pid.startsWith('duplex_') || pid == 'resma' || pid == 'scan';
      if (isSpecial) continue;
      
      final origQty = (orig['quantity'] as num?)?.toInt() ?? 0;
      final editedItemIdx = editedItems.indexWhere((i) => i['productId'] == pid);
      
      if (editedItemIdx == -1) {
        final stock = db.getStock(pid);
        db.addMovement(pid, 'Corrección', stock - origQty, stock, 'Item quitado venta ' + editedSale['id']);
      } else {
        final editedItem = editedItems[editedItemIdx];
        final newQty = (editedItem['quantity'] as num?)?.toInt() ?? 0;
        final diff = origQty - newQty;
        if (diff != 0) {
          final stock = db.getStock(pid);
          db.addMovement(pid, 'Corrección', stock - diff, stock, 'Cant. editada venta ' + editedSale['id']);
        }
      }
    }

    // Log movements for brand new items added
    for (final edited in editedItems) {
      final pid = edited['productId'] as String? ?? '';
      if (pid.isEmpty) continue;
      final isSpecial = pid.startsWith('copy_') || pid.startsWith('print_') || pid.startsWith('duplex_') || pid == 'resma' || pid == 'scan';
      if (isSpecial) continue;
      
      final origIdx = originalItems.indexWhere((i) => i['productId'] == pid);
      if (origIdx == -1) {
        final newQty = (edited['quantity'] as num?)?.toInt() ?? 0;
        final stock = db.getStock(pid);
        db.addMovement(pid, 'Venta', stock + newQty, stock, 'Item agregado venta ' + editedSale['id']);
      }
    }

    // Push changes online
    try {
      if (firebaseEnabled && _firebaseInitialized) {
        final dbRef = FirebaseFirestore.instance;
        await dbRef.collection('sales').doc(editedSale['id']).set(editedSale).timeout(const Duration(seconds: 8));
        
        // Log online movements
        for (final orig in originalItems) {
          final pid = orig['productId'] as String? ?? '';
          if (pid.isEmpty) continue;
          final isSpecial = pid.startsWith('copy_') || pid.startsWith('print_') || pid.startsWith('duplex_') || pid == 'resma' || pid == 'scan';
          if (isSpecial) continue;
          final origQty = (orig['quantity'] as num?)?.toInt() ?? 0;
          final editedItemIdx = editedItems.indexWhere((i) => i['productId'] == pid);
          if (editedItemIdx == -1) {
            final stock = db.getStock(pid);
            final mId = db.genId();
            await dbRef.collection('inventario_movimientos').doc(mId).set({
              'id': mId,
              'productId': pid,
              'productName': orig['productName'] ?? '',
              'type': 'Corrección',
              'prevQty': stock - origQty,
              'newQty': stock,
              'reason': 'Item quitado venta ' + editedSale['id'],
              'createdAt': DateTime.now().toIso8601String(),
            }).timeout(const Duration(seconds: 4));
          } else {
            final editedItem = editedItems[editedItemIdx];
            final newQty = (editedItem['quantity'] as num?)?.toInt() ?? 0;
            final diff = origQty - newQty;
            if (diff != 0) {
              final stock = db.getStock(pid);
              final mId = db.genId();
              await dbRef.collection('inventario_movimientos').doc(mId).set({
                'id': mId,
                'productId': pid,
                'productName': orig['productName'] ?? '',
                'type': 'Corrección',
                'prevQty': stock - diff,
                'newQty': stock,
                'reason': 'Cant. editada venta ' + editedSale['id'],
                'createdAt': DateTime.now().toIso8601String(),
              }).timeout(const Duration(seconds: 4));
            }
          }
        }
        for (final edited in editedItems) {
          final pid = edited['productId'] as String? ?? '';
          if (pid.isEmpty) continue;
          final isSpecial = pid.startsWith('copy_') || pid.startsWith('print_') || pid.startsWith('duplex_') || pid == 'resma' || pid == 'scan';
          if (isSpecial) continue;
          final origIdx = originalItems.indexWhere((i) => i['productId'] == pid);
          if (origIdx == -1) {
            final newQty = (edited['quantity'] as num?)?.toInt() ?? 0;
            final stock = db.getStock(pid);
            final mId = db.genId();
            await dbRef.collection('inventario_movimientos').doc(mId).set({
              'id': mId,
              'productId': pid,
              'productName': edited['productName'] ?? '',
              'type': 'Venta',
              'prevQty': stock + newQty,
              'newQty': stock,
              'reason': 'Item agregado venta ' + editedSale['id'],
              'createdAt': DateTime.now().toIso8601String(),
            }).timeout(const Duration(seconds: 4));
          }
        }
      }
      if (serverUrl.isNotEmpty) {
        unawaited(pushToServer());
      }
    } catch (e) {
      print("Sync warning: error al sincronizar venta editada: $e");
      lastError = 'Error al sincronizar edición de venta: $e';
      connected = false;
      _setPendingSync(true);
      notifyListeners();
    }
  }


  void startAutoSync({Duration interval = const Duration(seconds: 5)}) {
    _pollTimer?.cancel();
    if (firebaseEnabled) return;
    if (serverUrl.isEmpty) return;
    _pollTimer = Timer.periodic(interval, (_) => pullFromServer());
  }

  void _scheduleReconnectRetry() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!firebaseEnabled) {
        _reconnectTimer?.cancel();
        return;
      }
      if (!connected || !_pendingSync) return;
      try {
        if (!_firebaseInitialized) {
          await initFirebase(force: true);
        }
        if (connected && _pendingSync) {
          await _flushPendingSync();
        }
        if (!_pendingSync && connected) {
          _reconnectTimer?.cancel();
        }
      } catch (_) {}
    });
  }

  Future<void> _setPendingSync(bool value) async {
    _pendingSync = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingSyncKey, value);
    if (value && !connected) {
      _scheduleReconnectRetry();
    }
    notifyListeners();
  }

  Future<void> _flushPendingSync() async {
    if (!_pendingSync || !connected) return;
    syncing = true;
    notifyListeners();
    try {
      if (!_firebaseInitialized) {
        await initFirebase(force: true);
      }
      if (!_firebaseInitialized || !connected) {
        syncing = false;
        notifyListeners();
        return;
      }
      await _pushAllToFirestore();
      await _setPendingSync(false);
    } catch (_) {
      _setPendingSync(true);
    }
    syncing = false;
    notifyListeners();
  }

  void stopAutoSync() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    stopAutoSync();
    _cancelSubscriptions();
    super.dispose();
  }


}
