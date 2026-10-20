import '../core/formatters.dart';

/// ---------------------------------------------------------------------------
/// Company profile (single row, id = 1)
/// ---------------------------------------------------------------------------
class Company {
  int id;
  String name;
  String legalName;
  String address1;
  String address2;
  String city;
  String stateCode;
  String pincode;
  String gstin;
  String pan;
  String phone;
  String phone2;
  String email;
  String website;
  String logoPath;
  String bankName;
  String accountNo;
  String ifsc;
  String branch;
  String upiId;
  String jurisdiction;
  String licenceNo;

  Company({
    this.id = 1,
    this.name = '',
    this.legalName = '',
    this.address1 = '',
    this.address2 = '',
    this.city = '',
    this.stateCode = '',
    this.pincode = '',
    this.gstin = '',
    this.pan = '',
    this.phone = '',
    this.phone2 = '',
    this.email = '',
    this.website = '',
    this.logoPath = '',
    this.bankName = '',
    this.accountNo = '',
    this.ifsc = '',
    this.branch = '',
    this.upiId = '',
    this.jurisdiction = '',
    this.licenceNo = '',
  });

  bool get isRegistered => gstin.trim().length == 15;

  String get addressLine {
    final parts = [address1, address2, city, pincode]
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  factory Company.fromMap(Map<String, Object?> m) => Company(
        id: Fmt.toInt(m['id'], 1),
        name: (m['name'] ?? '') as String,
        legalName: (m['legal_name'] ?? '') as String,
        address1: (m['address1'] ?? '') as String,
        address2: (m['address2'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        stateCode: (m['state_code'] ?? '') as String,
        pincode: (m['pincode'] ?? '') as String,
        gstin: (m['gstin'] ?? '') as String,
        pan: (m['pan'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        phone2: (m['phone2'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        website: (m['website'] ?? '') as String,
        logoPath: (m['logo_path'] ?? '') as String,
        bankName: (m['bank_name'] ?? '') as String,
        accountNo: (m['account_no'] ?? '') as String,
        ifsc: (m['ifsc'] ?? '') as String,
        branch: (m['branch'] ?? '') as String,
        upiId: (m['upi_id'] ?? '') as String,
        jurisdiction: (m['jurisdiction'] ?? '') as String,
        licenceNo: (m['licence_no'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'legal_name': legalName,
        'address1': address1,
        'address2': address2,
        'city': city,
        'state_code': stateCode,
        'pincode': pincode,
        'gstin': gstin,
        'pan': pan,
        'phone': phone,
        'phone2': phone2,
        'email': email,
        'website': website,
        'logo_path': logoPath,
        'bank_name': bankName,
        'account_no': accountNo,
        'ifsc': ifsc,
        'branch': branch,
        'upi_id': upiId,
        'jurisdiction': jurisdiction,
        'licence_no': licenceNo,
      };
}

/// ---------------------------------------------------------------------------
/// Users
/// ---------------------------------------------------------------------------
class AppUser {
  int? id;
  String name;
  String username;
  String passwordHash;
  String salt;
  String role;
  bool active;
  DateTime? lastLogin;

  AppUser({
    this.id,
    this.name = '',
    this.username = '',
    this.passwordHash = '',
    this.salt = '',
    this.role = 'CASHIER',
    this.active = true,
    this.lastLogin,
  });

  bool get isAdmin => role == 'ADMIN';
  bool get canManage => role == 'ADMIN' || role == 'MANAGER';

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        username: (m['username'] ?? '') as String,
        passwordHash: (m['password_hash'] ?? '') as String,
        salt: (m['salt'] ?? '') as String,
        role: (m['role'] ?? 'CASHIER') as String,
        active: Fmt.toBool(m['active'], true),
        lastLogin: Fmt.parseIso(m['last_login'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'username': username,
        'password_hash': passwordHash,
        'salt': salt,
        'role': role,
        'active': active ? 1 : 0,
        'last_login': lastLogin?.toIso8601String(),
      };
}

/// ---------------------------------------------------------------------------
/// Party — one table for customers and suppliers (`kind`).
/// ---------------------------------------------------------------------------
class Party {
  int? id;
  String kind; // CUSTOMER | SUPPLIER
  String code;
  String name;
  String contactPerson;
  String phone;
  String phone2;
  String email;
  String gstin;
  String pan;
  String address1;
  String address2;
  String city;
  String stateCode;
  String pincode;
  String priceTier;
  double creditLimit;
  int creditDays;
  double openingBalance;
  double balance; // + = they owe us (receivable) for customers
  String notes;
  bool active;
  DateTime? createdAt;

  Party({
    this.id,
    this.kind = 'CUSTOMER',
    this.code = '',
    this.name = '',
    this.contactPerson = '',
    this.phone = '',
    this.phone2 = '',
    this.email = '',
    this.gstin = '',
    this.pan = '',
    this.address1 = '',
    this.address2 = '',
    this.city = '',
    this.stateCode = '',
    this.pincode = '',
    this.priceTier = 'RETAIL',
    this.creditLimit = 0,
    this.creditDays = 0,
    this.openingBalance = 0,
    this.balance = 0,
    this.notes = '',
    this.active = true,
    this.createdAt,
  });

  bool get isWalkIn => id == 1 && kind == 'CUSTOMER';
  bool get hasGst => gstin.trim().length == 15;

  String get addressLine => [address1, address2, city, pincode]
      .where((e) => e.trim().isNotEmpty)
      .join(', ');

  String get display => phone.isEmpty ? name : '$name  ·  $phone';

  factory Party.fromMap(Map<String, Object?> m) => Party(
        id: m['id'] as int?,
        kind: (m['kind'] ?? 'CUSTOMER') as String,
        code: (m['code'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        contactPerson: (m['contact_person'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        phone2: (m['phone2'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        gstin: (m['gstin'] ?? '') as String,
        pan: (m['pan'] ?? '') as String,
        address1: (m['address1'] ?? '') as String,
        address2: (m['address2'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        stateCode: (m['state_code'] ?? '') as String,
        pincode: (m['pincode'] ?? '') as String,
        priceTier: (m['price_tier'] ?? 'RETAIL') as String,
        creditLimit: Fmt.toDouble(m['credit_limit']),
        creditDays: Fmt.toInt(m['credit_days']),
        openingBalance: Fmt.toDouble(m['opening_balance']),
        balance: Fmt.toDouble(m['balance']),
        notes: (m['notes'] ?? '') as String,
        active: Fmt.toBool(m['active'], true),
        createdAt: Fmt.parseIso(m['created_at'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'kind': kind,
        'code': code,
        'name': name,
        'contact_person': contactPerson,
        'phone': phone,
        'phone2': phone2,
        'email': email,
        'gstin': gstin.toUpperCase(),
        'pan': pan.toUpperCase(),
        'address1': address1,
        'address2': address2,
        'city': city,
        'state_code': stateCode,
        'pincode': pincode,
        'price_tier': priceTier,
        'credit_limit': creditLimit,
        'credit_days': creditDays,
        'opening_balance': openingBalance,
        'balance': balance,
        'notes': notes,
        'active': active ? 1 : 0,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      };

  Party copy() => Party.fromMap(toMap()..['id'] = id);
}

/// ---------------------------------------------------------------------------
/// Product — paint-aware (base, shade code, pack size, tinting).
/// ---------------------------------------------------------------------------
class Product {
  int? id;
  String sku;
  String barcode;
  String name;
  String brand;
  String category;
  String hsn;
  String baseType; // White / Pastel / Deep / Ultra Deep / N.A.
  String shadeCode;
  String shadeName;
  String colorHex;
  String packSize;
  String unit;
  double mrp;
  double purchasePrice;
  double retailPrice;
  double dealerPrice;
  double contractorPrice;
  double gstRate;
  double cessRate;
  bool taxInclusive;
  double stock;
  double minStock;
  double openingStock;
  String rack;
  bool isService; // labour / tinting charge, no stock impact
  bool active;
  String notes;
  DateTime? createdAt;
  DateTime? updatedAt;

  Product({
    this.id,
    this.sku = '',
    this.barcode = '',
    this.name = '',
    this.brand = '',
    this.category = '',
    this.hsn = '3208',
    this.baseType = '',
    this.shadeCode = '',
    this.shadeName = '',
    this.colorHex = '',
    this.packSize = '',
    this.unit = 'LTR',
    this.mrp = 0,
    this.purchasePrice = 0,
    this.retailPrice = 0,
    this.dealerPrice = 0,
    this.contractorPrice = 0,
    this.gstRate = 18,
    this.cessRate = 0,
    this.taxInclusive = false,
    this.stock = 0,
    this.minStock = 0,
    this.openingStock = 0,
    this.rack = '',
    this.isService = false,
    this.active = true,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Full display name used on the bill line.
  String get fullName {
    final bits = <String>[
      if (brand.trim().isNotEmpty) brand.trim(),
      name.trim(),
      if (shadeName.trim().isNotEmpty) '- ${shadeName.trim()}',
      if (packSize.trim().isNotEmpty) '(${packSize.trim()})',
    ];
    return bits.join(' ');
  }

  String get searchBlob => [
        sku,
        barcode,
        name,
        brand,
        category,
        shadeCode,
        shadeName,
        packSize,
        rack,
      ].join(' ').toLowerCase();

  double priceFor(String tier) {
    switch (tier) {
      case 'DEALER':
        return dealerPrice > 0 ? dealerPrice : retailPrice;
      case 'CONTRACTOR':
        return contractorPrice > 0 ? contractorPrice : retailPrice;
      default:
        return retailPrice > 0 ? retailPrice : mrp;
    }
  }

  bool get lowStock => !isService && stock <= minStock;

  double get marginPct {
    if (purchasePrice <= 0 || retailPrice <= 0) return 0;
    return Fmt.round((retailPrice - purchasePrice) / purchasePrice * 100, 1);
  }

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        sku: (m['sku'] ?? '') as String,
        barcode: (m['barcode'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        brand: (m['brand'] ?? '') as String,
        category: (m['category'] ?? '') as String,
        hsn: (m['hsn'] ?? '') as String,
        baseType: (m['base_type'] ?? '') as String,
        shadeCode: (m['shade_code'] ?? '') as String,
        shadeName: (m['shade_name'] ?? '') as String,
        colorHex: (m['color_hex'] ?? '') as String,
        packSize: (m['pack_size'] ?? '') as String,
        unit: (m['unit'] ?? 'LTR') as String,
        mrp: Fmt.toDouble(m['mrp']),
        purchasePrice: Fmt.toDouble(m['purchase_price']),
        retailPrice: Fmt.toDouble(m['retail_price']),
        dealerPrice: Fmt.toDouble(m['dealer_price']),
        contractorPrice: Fmt.toDouble(m['contractor_price']),
        gstRate: Fmt.toDouble(m['gst_rate'], 18),
        cessRate: Fmt.toDouble(m['cess_rate']),
        taxInclusive: Fmt.toBool(m['tax_inclusive']),
        stock: Fmt.toDouble(m['stock']),
        minStock: Fmt.toDouble(m['min_stock']),
        openingStock: Fmt.toDouble(m['opening_stock']),
        rack: (m['rack'] ?? '') as String,
        isService: Fmt.toBool(m['is_service']),
        active: Fmt.toBool(m['active'], true),
        notes: (m['notes'] ?? '') as String,
        createdAt: Fmt.parseIso(m['created_at'] as String?),
        updatedAt: Fmt.parseIso(m['updated_at'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'sku': sku,
        'barcode': barcode,
        'name': name,
        'brand': brand,
        'category': category,
        'hsn': hsn,
        'base_type': baseType,
        'shade_code': shadeCode,
        'shade_name': shadeName,
        'color_hex': colorHex,
        'pack_size': packSize,
        'unit': unit,
        'mrp': mrp,
        'purchase_price': purchasePrice,
        'retail_price': retailPrice,
        'dealer_price': dealerPrice,
        'contractor_price': contractorPrice,
        'gst_rate': gstRate,
        'cess_rate': cessRate,
        'tax_inclusive': taxInclusive ? 1 : 0,
        'stock': stock,
        'min_stock': minStock,
        'opening_stock': openingStock,
        'rack': rack,
        'is_service': isService ? 1 : 0,
        'active': active ? 1 : 0,
        'notes': notes,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

  Product copy() {
    final p = Product.fromMap(toMap());
    p.id = id;
    return p;
  }
}

/// ---------------------------------------------------------------------------
/// Sales document (Invoice / Estimate / Credit Note / Challan)
/// ---------------------------------------------------------------------------
class SalesDoc {
  int? id;
  String docType;
  String docNo;
  DateTime docDate;
  DateTime? dueDate;
  int? partyId;
  String partyName;
  String partyPhone;
  String partyGstin;
  String partyAddress;
  String placeOfSupply;
  bool isIgst;
  bool priceIncludesTax;
  String priceTier;
  double grossAmount; // sum of line taxable before doc-level discount
  double itemDiscount;
  double docDiscountPct;
  double docDiscountAmt;
  double taxableAmount;
  double cgst;
  double sgst;
  double igst;
  double cess;
  double freight;
  double otherCharges;
  double roundOff;
  double total;
  double paid;
  double balance;
  String status;
  String paymentMode;
  String refNo;
  String vehicleNo;
  String transport;
  String notes;
  int? userId;
  String userName;
  int? refDocId; // credit note -> original invoice
  String refDocNo;
  DateTime? createdAt;
  List<SalesItem> items;

  SalesDoc({
    this.id,
    this.docType = 'INVOICE',
    this.docNo = '',
    DateTime? docDate,
    this.dueDate,
    this.partyId,
    this.partyName = '',
    this.partyPhone = '',
    this.partyGstin = '',
    this.partyAddress = '',
    this.placeOfSupply = '',
    this.isIgst = false,
    this.priceIncludesTax = false,
    this.priceTier = 'RETAIL',
    this.grossAmount = 0,
    this.itemDiscount = 0,
    this.docDiscountPct = 0,
    this.docDiscountAmt = 0,
    this.taxableAmount = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cess = 0,
    this.freight = 0,
    this.otherCharges = 0,
    this.roundOff = 0,
    this.total = 0,
    this.paid = 0,
    this.balance = 0,
    this.status = 'UNPAID',
    this.paymentMode = 'CASH',
    this.refNo = '',
    this.vehicleNo = '',
    this.transport = '',
    this.notes = '',
    this.userId,
    this.userName = '',
    this.refDocId,
    this.refDocNo = '',
    this.createdAt,
    List<SalesItem>? items,
  })  : docDate = docDate ?? DateTime.now(),
        items = items ?? <SalesItem>[];

  double get totalTax => cgst + sgst + igst + cess;
  double get totalQty => items.fold<double>(0.0, (s, e) => s + e.qty);
  bool get isCancelled => status == 'CANCELLED';
  bool get isReturn => docType == 'CREDIT_NOTE';

  /// Estimates and challans never post to stock, tax reports or ledgers.
  bool get affectsAccounts => docType == 'INVOICE' || docType == 'CREDIT_NOTE';

  factory SalesDoc.fromMap(Map<String, Object?> m) => SalesDoc(
        id: m['id'] as int?,
        docType: (m['doc_type'] ?? 'INVOICE') as String,
        docNo: (m['doc_no'] ?? '') as String,
        docDate: Fmt.parseIso(m['doc_date'] as String?) ?? DateTime.now(),
        dueDate: Fmt.parseIso(m['due_date'] as String?),
        partyId: m['party_id'] as int?,
        partyName: (m['party_name'] ?? '') as String,
        partyPhone: (m['party_phone'] ?? '') as String,
        partyGstin: (m['party_gstin'] ?? '') as String,
        partyAddress: (m['party_address'] ?? '') as String,
        placeOfSupply: (m['place_of_supply'] ?? '') as String,
        isIgst: Fmt.toBool(m['is_igst']),
        priceIncludesTax: Fmt.toBool(m['price_includes_tax']),
        priceTier: (m['price_tier'] ?? 'RETAIL') as String,
        grossAmount: Fmt.toDouble(m['gross_amount']),
        itemDiscount: Fmt.toDouble(m['item_discount']),
        docDiscountPct: Fmt.toDouble(m['doc_discount_pct']),
        docDiscountAmt: Fmt.toDouble(m['doc_discount_amt']),
        taxableAmount: Fmt.toDouble(m['taxable_amount']),
        cgst: Fmt.toDouble(m['cgst']),
        sgst: Fmt.toDouble(m['sgst']),
        igst: Fmt.toDouble(m['igst']),
        cess: Fmt.toDouble(m['cess']),
        freight: Fmt.toDouble(m['freight']),
        otherCharges: Fmt.toDouble(m['other_charges']),
        roundOff: Fmt.toDouble(m['round_off']),
        total: Fmt.toDouble(m['total']),
        paid: Fmt.toDouble(m['paid']),
        balance: Fmt.toDouble(m['balance']),
        status: (m['status'] ?? 'UNPAID') as String,
        paymentMode: (m['payment_mode'] ?? 'CASH') as String,
        refNo: (m['ref_no'] ?? '') as String,
        vehicleNo: (m['vehicle_no'] ?? '') as String,
        transport: (m['transport'] ?? '') as String,
        notes: (m['notes'] ?? '') as String,
        userId: m['user_id'] as int?,
        userName: (m['user_name'] ?? '') as String,
        refDocId: m['ref_doc_id'] as int?,
        refDocNo: (m['ref_doc_no'] ?? '') as String,
        createdAt: Fmt.parseIso(m['created_at'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'doc_type': docType,
        'doc_no': docNo,
        'doc_date': docDate.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'party_id': partyId,
        'party_name': partyName,
        'party_phone': partyPhone,
        'party_gstin': partyGstin,
        'party_address': partyAddress,
        'place_of_supply': placeOfSupply,
        'is_igst': isIgst ? 1 : 0,
        'price_includes_tax': priceIncludesTax ? 1 : 0,
        'price_tier': priceTier,
        'gross_amount': grossAmount,
        'item_discount': itemDiscount,
        'doc_discount_pct': docDiscountPct,
        'doc_discount_amt': docDiscountAmt,
        'taxable_amount': taxableAmount,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'cess': cess,
        'freight': freight,
        'other_charges': otherCharges,
        'round_off': roundOff,
        'total': total,
        'paid': paid,
        'balance': balance,
        'status': status,
        'payment_mode': paymentMode,
        'ref_no': refNo,
        'vehicle_no': vehicleNo,
        'transport': transport,
        'notes': notes,
        'user_id': userId,
        'user_name': userName,
        'ref_doc_id': refDocId,
        'ref_doc_no': refDocNo,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      };
}

class SalesItem {
  int? id;
  int? docId;
  int? productId;
  String sku;
  String name;
  String hsn;
  String shade;
  String packSize;
  String unit;
  double qty;
  double freeQty;
  double mrp;
  double rate; // net of tax when priceIncludesTax == false
  double grossRate; // rate as typed by the operator
  double discountPct;
  double discountAmt;
  double taxable;
  double gstRate;
  double cgst;
  double sgst;
  double igst;
  double cessRate;
  double cess;
  double total;
  double costPrice; // snapshot for profit reports
  String batch;
  String notes;

  SalesItem({
    this.id,
    this.docId,
    this.productId,
    this.sku = '',
    this.name = '',
    this.hsn = '',
    this.shade = '',
    this.packSize = '',
    this.unit = 'LTR',
    this.qty = 1,
    this.freeQty = 0,
    this.mrp = 0,
    this.rate = 0,
    this.grossRate = 0,
    this.discountPct = 0,
    this.discountAmt = 0,
    this.taxable = 0,
    this.gstRate = 18,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cessRate = 0,
    this.cess = 0,
    this.total = 0,
    this.costPrice = 0,
    this.batch = '',
    this.notes = '',
  });

  double get taxAmount => cgst + sgst + igst + cess;
  double get profit => Fmt.round(taxable - (costPrice * qty));

  factory SalesItem.fromMap(Map<String, Object?> m) => SalesItem(
        id: m['id'] as int?,
        docId: m['doc_id'] as int?,
        productId: m['product_id'] as int?,
        sku: (m['sku'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        hsn: (m['hsn'] ?? '') as String,
        shade: (m['shade'] ?? '') as String,
        packSize: (m['pack_size'] ?? '') as String,
        unit: (m['unit'] ?? '') as String,
        qty: Fmt.toDouble(m['qty']),
        freeQty: Fmt.toDouble(m['free_qty']),
        mrp: Fmt.toDouble(m['mrp']),
        rate: Fmt.toDouble(m['rate']),
        grossRate: Fmt.toDouble(m['gross_rate']),
        discountPct: Fmt.toDouble(m['discount_pct']),
        discountAmt: Fmt.toDouble(m['discount_amt']),
        taxable: Fmt.toDouble(m['taxable']),
        gstRate: Fmt.toDouble(m['gst_rate']),
        cgst: Fmt.toDouble(m['cgst']),
        sgst: Fmt.toDouble(m['sgst']),
        igst: Fmt.toDouble(m['igst']),
        cessRate: Fmt.toDouble(m['cess_rate']),
        cess: Fmt.toDouble(m['cess']),
        total: Fmt.toDouble(m['total']),
        costPrice: Fmt.toDouble(m['cost_price']),
        batch: (m['batch'] ?? '') as String,
        notes: (m['notes'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'doc_id': docId,
        'product_id': productId,
        'sku': sku,
        'name': name,
        'hsn': hsn,
        'shade': shade,
        'pack_size': packSize,
        'unit': unit,
        'qty': qty,
        'free_qty': freeQty,
        'mrp': mrp,
        'rate': rate,
        'gross_rate': grossRate,
        'discount_pct': discountPct,
        'discount_amt': discountAmt,
        'taxable': taxable,
        'gst_rate': gstRate,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'cess_rate': cessRate,
        'cess': cess,
        'total': total,
        'cost_price': costPrice,
        'batch': batch,
        'notes': notes,
      };
}

/// ---------------------------------------------------------------------------
/// Purchase (GRN) — mirrors SalesDoc but for inward supply.
/// ---------------------------------------------------------------------------
class PurchaseDoc {
  int? id;
  String docType; // PURCHASE | PURCHASE_RETURN
  String docNo; // internal number
  String supplierBillNo;
  DateTime docDate;
  DateTime? billDate;
  int? partyId;
  String partyName;
  String partyGstin;
  String placeOfSupply;
  bool isIgst;
  double taxableAmount;
  double cgst;
  double sgst;
  double igst;
  double cess;
  double discountAmt;
  double freight;
  double otherCharges;
  double roundOff;
  double total;
  double paid;
  double balance;
  String status;
  String paymentMode;
  String notes;
  int? userId;
  DateTime? createdAt;
  List<PurchaseItem> items;

  PurchaseDoc({
    this.id,
    this.docType = 'PURCHASE',
    this.docNo = '',
    this.supplierBillNo = '',
    DateTime? docDate,
    this.billDate,
    this.partyId,
    this.partyName = '',
    this.partyGstin = '',
    this.placeOfSupply = '',
    this.isIgst = false,
    this.taxableAmount = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cess = 0,
    this.discountAmt = 0,
    this.freight = 0,
    this.otherCharges = 0,
    this.roundOff = 0,
    this.total = 0,
    this.paid = 0,
    this.balance = 0,
    this.status = 'UNPAID',
    this.paymentMode = 'CREDIT',
    this.notes = '',
    this.userId,
    this.createdAt,
    List<PurchaseItem>? items,
  })  : docDate = docDate ?? DateTime.now(),
        items = items ?? <PurchaseItem>[];

  double get totalTax => cgst + sgst + igst + cess;

  factory PurchaseDoc.fromMap(Map<String, Object?> m) => PurchaseDoc(
        id: m['id'] as int?,
        docType: (m['doc_type'] ?? 'PURCHASE') as String,
        docNo: (m['doc_no'] ?? '') as String,
        supplierBillNo: (m['supplier_bill_no'] ?? '') as String,
        docDate: Fmt.parseIso(m['doc_date'] as String?) ?? DateTime.now(),
        billDate: Fmt.parseIso(m['bill_date'] as String?),
        partyId: m['party_id'] as int?,
        partyName: (m['party_name'] ?? '') as String,
        partyGstin: (m['party_gstin'] ?? '') as String,
        placeOfSupply: (m['place_of_supply'] ?? '') as String,
        isIgst: Fmt.toBool(m['is_igst']),
        taxableAmount: Fmt.toDouble(m['taxable_amount']),
        cgst: Fmt.toDouble(m['cgst']),
        sgst: Fmt.toDouble(m['sgst']),
        igst: Fmt.toDouble(m['igst']),
        cess: Fmt.toDouble(m['cess']),
        discountAmt: Fmt.toDouble(m['discount_amt']),
        freight: Fmt.toDouble(m['freight']),
        otherCharges: Fmt.toDouble(m['other_charges']),
        roundOff: Fmt.toDouble(m['round_off']),
        total: Fmt.toDouble(m['total']),
        paid: Fmt.toDouble(m['paid']),
        balance: Fmt.toDouble(m['balance']),
        status: (m['status'] ?? 'UNPAID') as String,
        paymentMode: (m['payment_mode'] ?? 'CREDIT') as String,
        notes: (m['notes'] ?? '') as String,
        userId: m['user_id'] as int?,
        createdAt: Fmt.parseIso(m['created_at'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'doc_type': docType,
        'doc_no': docNo,
        'supplier_bill_no': supplierBillNo,
        'doc_date': docDate.toIso8601String(),
        'bill_date': billDate?.toIso8601String(),
        'party_id': partyId,
        'party_name': partyName,
        'party_gstin': partyGstin,
        'place_of_supply': placeOfSupply,
        'is_igst': isIgst ? 1 : 0,
        'taxable_amount': taxableAmount,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'cess': cess,
        'discount_amt': discountAmt,
        'freight': freight,
        'other_charges': otherCharges,
        'round_off': roundOff,
        'total': total,
        'paid': paid,
        'balance': balance,
        'status': status,
        'payment_mode': paymentMode,
        'notes': notes,
        'user_id': userId,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      };
}

class PurchaseItem {
  int? id;
  int? docId;
  int? productId;
  String name;
  String hsn;
  String packSize;
  String unit;
  double qty;
  double freeQty;
  double rate;
  double mrp;
  double salePrice;
  double discountPct;
  double discountAmt;
  double taxable;
  double gstRate;
  double cgst;
  double sgst;
  double igst;
  double cess;
  double total;
  String batch;
  DateTime? expiry;

  PurchaseItem({
    this.id,
    this.docId,
    this.productId,
    this.name = '',
    this.hsn = '',
    this.packSize = '',
    this.unit = 'LTR',
    this.qty = 1,
    this.freeQty = 0,
    this.rate = 0,
    this.mrp = 0,
    this.salePrice = 0,
    this.discountPct = 0,
    this.discountAmt = 0,
    this.taxable = 0,
    this.gstRate = 18,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cess = 0,
    this.total = 0,
    this.batch = '',
    this.expiry,
  });

  factory PurchaseItem.fromMap(Map<String, Object?> m) => PurchaseItem(
        id: m['id'] as int?,
        docId: m['doc_id'] as int?,
        productId: m['product_id'] as int?,
        name: (m['name'] ?? '') as String,
        hsn: (m['hsn'] ?? '') as String,
        packSize: (m['pack_size'] ?? '') as String,
        unit: (m['unit'] ?? '') as String,
        qty: Fmt.toDouble(m['qty']),
        freeQty: Fmt.toDouble(m['free_qty']),
        rate: Fmt.toDouble(m['rate']),
        mrp: Fmt.toDouble(m['mrp']),
        salePrice: Fmt.toDouble(m['sale_price']),
        discountPct: Fmt.toDouble(m['discount_pct']),
        discountAmt: Fmt.toDouble(m['discount_amt']),
        taxable: Fmt.toDouble(m['taxable']),
        gstRate: Fmt.toDouble(m['gst_rate']),
        cgst: Fmt.toDouble(m['cgst']),
        sgst: Fmt.toDouble(m['sgst']),
        igst: Fmt.toDouble(m['igst']),
        cess: Fmt.toDouble(m['cess']),
        total: Fmt.toDouble(m['total']),
        batch: (m['batch'] ?? '') as String,
        expiry: Fmt.parseIso(m['expiry'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'doc_id': docId,
        'product_id': productId,
        'name': name,
        'hsn': hsn,
        'pack_size': packSize,
        'unit': unit,
        'qty': qty,
        'free_qty': freeQty,
        'rate': rate,
        'mrp': mrp,
        'sale_price': salePrice,
        'discount_pct': discountPct,
        'discount_amt': discountAmt,
        'taxable': taxable,
        'gst_rate': gstRate,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'cess': cess,
        'total': total,
        'batch': batch,
        'expiry': expiry?.toIso8601String(),
      };
}

/// ---------------------------------------------------------------------------
/// Payment voucher (receipt from customer / payment to supplier)
/// ---------------------------------------------------------------------------
class PaymentVoucher {
  int? id;
  String voucherNo;
  DateTime date;
  String direction; // IN | OUT
  int? partyId;
  String partyName;
  int? docId;
  String docNo;
  double amount;
  double discount;
  String mode;
  String refNo;
  String bankName;
  DateTime? chequeDate;
  String notes;
  int? userId;
  DateTime? createdAt;

  PaymentVoucher({
    this.id,
    this.voucherNo = '',
    DateTime? date,
    this.direction = 'IN',
    this.partyId,
    this.partyName = '',
    this.docId,
    this.docNo = '',
    this.amount = 0,
    this.discount = 0,
    this.mode = 'CASH',
    this.refNo = '',
    this.bankName = '',
    this.chequeDate,
    this.notes = '',
    this.userId,
    this.createdAt,
  }) : date = date ?? DateTime.now();

  factory PaymentVoucher.fromMap(Map<String, Object?> m) => PaymentVoucher(
        id: m['id'] as int?,
        voucherNo: (m['voucher_no'] ?? '') as String,
        date: Fmt.parseIso(m['date'] as String?) ?? DateTime.now(),
        direction: (m['direction'] ?? 'IN') as String,
        partyId: m['party_id'] as int?,
        partyName: (m['party_name'] ?? '') as String,
        docId: m['doc_id'] as int?,
        docNo: (m['doc_no'] ?? '') as String,
        amount: Fmt.toDouble(m['amount']),
        discount: Fmt.toDouble(m['discount']),
        mode: (m['mode'] ?? 'CASH') as String,
        refNo: (m['ref_no'] ?? '') as String,
        bankName: (m['bank_name'] ?? '') as String,
        chequeDate: Fmt.parseIso(m['cheque_date'] as String?),
        notes: (m['notes'] ?? '') as String,
        userId: m['user_id'] as int?,
        createdAt: Fmt.parseIso(m['created_at'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'voucher_no': voucherNo,
        'date': date.toIso8601String(),
        'direction': direction,
        'party_id': partyId,
        'party_name': partyName,
        'doc_id': docId,
        'doc_no': docNo,
        'amount': amount,
        'discount': discount,
        'mode': mode,
        'ref_no': refNo,
        'bank_name': bankName,
        'cheque_date': chequeDate?.toIso8601String(),
        'notes': notes,
        'user_id': userId,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      };
}

/// ---------------------------------------------------------------------------
/// Stock ledger entry
/// ---------------------------------------------------------------------------
class StockMove {
  int? id;
  int productId;
  String productName;
  DateTime date;
  String refType;
  int? refId;
  String refNo;
  double qtyIn;
  double qtyOut;
  double balanceAfter;
  double rate;
  String notes;

  StockMove({
    this.id,
    required this.productId,
    this.productName = '',
    DateTime? date,
    this.refType = 'ADJUSTMENT',
    this.refId,
    this.refNo = '',
    this.qtyIn = 0,
    this.qtyOut = 0,
    this.balanceAfter = 0,
    this.rate = 0,
    this.notes = '',
  }) : date = date ?? DateTime.now();

  factory StockMove.fromMap(Map<String, Object?> m) => StockMove(
        id: m['id'] as int?,
        productId: Fmt.toInt(m['product_id']),
        productName: (m['product_name'] ?? '') as String,
        date: Fmt.parseIso(m['date'] as String?) ?? DateTime.now(),
        refType: (m['ref_type'] ?? '') as String,
        refId: m['ref_id'] as int?,
        refNo: (m['ref_no'] ?? '') as String,
        qtyIn: Fmt.toDouble(m['qty_in']),
        qtyOut: Fmt.toDouble(m['qty_out']),
        balanceAfter: Fmt.toDouble(m['balance_after']),
        rate: Fmt.toDouble(m['rate']),
        notes: (m['notes'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'product_name': productName,
        'date': date.toIso8601String(),
        'ref_type': refType,
        'ref_id': refId,
        'ref_no': refNo,
        'qty_in': qtyIn,
        'qty_out': qtyOut,
        'balance_after': balanceAfter,
        'rate': rate,
        'notes': notes,
      };
}

/// ---------------------------------------------------------------------------
/// Expense voucher (shop running costs — feeds the P&L report)
/// ---------------------------------------------------------------------------
class Expense {
  int? id;
  DateTime date;
  String category;
  String description;
  double amount;
  String mode;
  String refNo;
  int? userId;

  Expense({
    this.id,
    DateTime? date,
    this.category = 'General',
    this.description = '',
    this.amount = 0,
    this.mode = 'CASH',
    this.refNo = '',
    this.userId,
  }) : date = date ?? DateTime.now();

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int?,
        date: Fmt.parseIso(m['date'] as String?) ?? DateTime.now(),
        category: (m['category'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        amount: Fmt.toDouble(m['amount']),
        mode: (m['mode'] ?? 'CASH') as String,
        refNo: (m['ref_no'] ?? '') as String,
        userId: m['user_id'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date.toIso8601String(),
        'category': category,
        'description': description,
        'amount': amount,
        'mode': mode,
        'ref_no': refNo,
        'user_id': userId,
      };
}

/// Row used by the ledger screen (invoices + payments merged).
class LedgerRow {
  final DateTime date;
  final String particulars;
  final String voucherType;
  final String voucherNo;
  final double debit;
  final double credit;
  double running;

  LedgerRow({
    required this.date,
    required this.particulars,
    required this.voucherType,
    required this.voucherNo,
    this.debit = 0,
    this.credit = 0,
    this.running = 0,
  });
}
