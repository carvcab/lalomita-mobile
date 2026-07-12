class LalomitaProduct {
  final String id;
  String name;
  String category;
  bool active;
  int initialStock;
  bool unlimited;
  String barcode;
  String createdAt;
  String updatedAt;

  LalomitaProduct({
    required this.id, required this.name, this.category = '', this.active = true,
    this.initialStock = 0, this.unlimited = false, this.barcode = '',
    this.createdAt = '', this.updatedAt = '',
  });

  factory LalomitaProduct.fromJson(Map<String, dynamic> j) => LalomitaProduct(
    id: j['id']?.toString() ?? '', name: j['name']?.toString() ?? '',
    category: j['category']?.toString() ?? '', active: j['active'] != false && j['active'] != 0,
    initialStock: (j['initialStock'] as num?)?.toInt() ?? 0,
    unlimited: j['unlimited'] == true || j['unlimited'] == 'true',
    barcode: j['barcode']?.toString() ?? '', createdAt: j['createdAt']?.toString() ?? '',
    updatedAt: j['updatedAt']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'category': category, 'active': active,
    'initialStock': initialStock, 'unlimited': unlimited, 'barcode': barcode,
    'createdAt': createdAt, 'updatedAt': updatedAt,
  };
}

class LalomitaSupplier {
  final String id; String name; String contact; String address;
  LalomitaSupplier({required this.id, required this.name, this.contact = '', this.address = ''});
  factory LalomitaSupplier.fromJson(Map<String, dynamic> j) => LalomitaSupplier(
    id: j['id']?.toString() ?? '', name: j['name']?.toString() ?? '',
    contact: j['contact']?.toString() ?? '', address: j['address']?.toString() ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'contact': contact, 'address': address,
    'createdAt': DateTime.now().toIso8601String(), 'updatedAt': DateTime.now().toIso8601String(),
  };
}

class ProdSupplierLink {
  final String id; String productId; String supplierId;
  double purchasePrice; double salePrice; bool isDefault;
  ProdSupplierLink({required this.id, required this.productId, required this.supplierId,
    this.purchasePrice = 0, this.salePrice = 0, this.isDefault = true});
  factory ProdSupplierLink.fromJson(Map<String, dynamic> j) => ProdSupplierLink(
    id: j['id']?.toString() ?? '', productId: j['productId']?.toString() ?? '',
    supplierId: j['supplierId']?.toString() ?? '',
    purchasePrice: (j['purchasePrice'] as num?)?.toDouble() ?? 0,
    salePrice: (j['salePrice'] as num?)?.toDouble() ?? 0,
    isDefault: j['isDefault'] == true,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'productId': productId, 'supplierId': supplierId,
    'purchasePrice': purchasePrice.isFinite ? purchasePrice : 0,
    'salePrice': salePrice.isFinite ? salePrice : 0, 'isDefault': isDefault,
    'createdAt': DateTime.now().toIso8601String(), 'updatedAt': DateTime.now().toIso8601String(),
  };
}

class SaleItem {
  final String productId; final String productName;
  final double unitPrice; int quantity;
  SaleItem({required this.productId, required this.productName, required this.unitPrice, this.quantity = 1});
  double get total => unitPrice * quantity;
  Map<String, dynamic> toJson() => {
    'productId': productId, 'productName': productName,
    'unitPrice': unitPrice.isFinite ? unitPrice : 0, 'quantity': quantity,
    'total': total.isFinite ? total : 0,
  };
}

class LalomitaSale {
  final String id; String date; List<SaleItem> items; double total;
  String paymentMethod; String paymentMethodName; String customerName;
  String notes; String createdAt; bool isCopySale; String copyPaperType;
  double discount; double discountPct; double cashAmount; double transferAmount;

  LalomitaSale({
    required this.id, required this.date, required this.items, required this.total,
    this.paymentMethod = 'cash', this.paymentMethodName = 'Efectivo',
    this.customerName = '', this.notes = 'Venta desde app movil',
    required this.createdAt, this.isCopySale = false, this.copyPaperType = '',
    this.discount = 0, this.discountPct = 0, this.cashAmount = 0, this.transferAmount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'items': items.map((i) => i.toJson()).toList(),
    'total': total.isFinite ? total : 0, 'paymentMethod': paymentMethod,
    'paymentMethodName': paymentMethodName, 'cashAmount': cashAmount,
    'transferAmount': transferAmount, 'customerName': customerName,
    'notes': notes, 'createdAt': createdAt, 'isCopySale': isCopySale,
    'copyPaperType': copyPaperType, 'discount': discount, 'discountPct': discountPct,
  };
}

class RepairPayment {
  final String id; double amount; String date; String method;
  RepairPayment({required this.id, this.amount = 0, this.date = '', this.method = 'cash'});
  factory RepairPayment.fromJson(Map<String, dynamic> j) => RepairPayment(
    id: j['id']?.toString() ?? '', amount: (j['amount'] as num?)?.toDouble() ?? 0,
    date: j['date']?.toString() ?? '', method: j['method']?.toString() ?? 'cash',
  );
  Map<String, dynamic> toJson() => {'id': id, 'amount': amount, 'date': date, 'method': method};
}

class RepairExpense {
  final String id; double amount; String date; String method; String description;
  RepairExpense({required this.id, this.amount = 0, this.date = '', this.method = 'cash', this.description = ''});
  factory RepairExpense.fromJson(Map<String, dynamic> j) => RepairExpense(
    id: j['id']?.toString() ?? '', amount: (j['amount'] as num?)?.toDouble() ?? 0,
    date: j['date']?.toString() ?? '', method: j['method']?.toString() ?? 'cash',
    description: j['description']?.toString() ?? '',
  );
  Map<String, dynamic> toJson() => {'id': id, 'amount': amount, 'date': date, 'method': method, 'description': description};
}

class LalomitaRepair {
  final String id; String customerName; String customerPhone; String phoneModel;
  String description; String status; double totalPrice;
  List<RepairPayment> payments; List<RepairExpense> expenses;
  String createdAt; String updatedAt;

  LalomitaRepair({
    required this.id, this.customerName = '', this.customerPhone = '',
    this.phoneModel = '', this.description = '', this.status = 'Ingresado',
    this.totalPrice = 0, this.payments = const [], this.expenses = const [],
    this.createdAt = '', this.updatedAt = '',
  });

  factory LalomitaRepair.fromJson(Map<String, dynamic> j) {
    final pList = (j['payments'] as List<dynamic>?)?.map((e) => RepairPayment.fromJson(e)).toList() ?? [];
    final eList = (j['expenses'] as List<dynamic>?)?.map((e) => RepairExpense.fromJson(e)).toList() ?? [];
    return LalomitaRepair(
      id: j['id']?.toString() ?? '', customerName: j['customerName']?.toString() ?? '',
      customerPhone: j['customerPhone']?.toString() ?? '', phoneModel: j['phoneModel']?.toString() ?? '',
      description: j['description']?.toString() ?? '', status: j['status']?.toString() ?? 'Ingresado',
      totalPrice: (j['totalPrice'] as num?)?.toDouble() ?? 0, payments: pList, expenses: eList,
      createdAt: j['createdAt']?.toString() ?? '', updatedAt: j['updatedAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'customerName': customerName, 'customerPhone': customerPhone,
    'phoneModel': phoneModel, 'description': description, 'status': status,
    'totalPrice': totalPrice, 'payments': payments.map((p) => p.toJson()).toList(),
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'createdAt': createdAt, 'updatedAt': updatedAt,
  };

  double get totalPaid => payments.fold(0, (s, p) => s + p.amount);
  double get totalExpenses => expenses.fold(0, (s, e) => s + e.amount);
  double get basePrice => totalPrice > 0 ? totalPrice : totalExpenses;
  double get pending => basePrice - totalPaid;
}

class CopyExpense {
  final String id; String date; double amount; String type;
  String paperType; int sheets; String description; String createdAt;
  CopyExpense({required this.id, this.date = '', this.amount = 0, this.type = 'tinta',
    this.paperType = '', this.sheets = 0, this.description = '', this.createdAt = ''});
  factory CopyExpense.fromJson(Map<String, dynamic> j) => CopyExpense(
    id: j['id']?.toString() ?? '', date: j['date']?.toString() ?? '',
    amount: (j['amount'] as num?)?.toDouble() ?? 0, type: j['type']?.toString() ?? 'tinta',
    paperType: j['paperType']?.toString() ?? '', sheets: (j['sheets'] as num?)?.toInt() ?? 0,
    description: j['description']?.toString() ?? '', createdAt: j['createdAt']?.toString() ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'amount': amount, 'type': type,
    'paperType': paperType, 'sheets': sheets, 'description': description, 'createdAt': createdAt,
  };
}

class CopyPaperType {
  final String id; String name;
  CopyPaperType({required this.id, required this.name});
  factory CopyPaperType.fromJson(Map<String, dynamic> j) => CopyPaperType(
    id: j['id']?.toString() ?? '', name: j['name']?.toString() ?? '',
  );
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class LalomitaDB {
  List<LalomitaProduct> products;
  List<LalomitaSupplier> suppliers;
  List<ProdSupplierLink> prodSuppliers;
  List<LalomitaSale> sales;
  List<LalomitaRepair> repairs;
  List<CopyExpense> copyExpenses;
  List<CopyPaperType> copyPaperTypes;
  Map<String, dynamic> copyPrices;
  Map<String, dynamic> copyPaperStock;
  Map<String, dynamic> copyReamStock;
  Map<String, dynamic> settings;

  LalomitaDB({
    this.products = const [], this.suppliers = const [], this.prodSuppliers = const [],
    this.sales = const [], this.repairs = const [], this.copyExpenses = const [],
    this.copyPaperTypes = const [], this.copyPrices = const {},
    this.copyPaperStock = const {}, this.copyReamStock = const {},
    this.settings = const {},
  });
}
