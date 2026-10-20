/// Application-wide constants for the Indian GST retail context.
library;

class AppInfo {
  static const String appName = 'PaintPro Billing';
  static const String shortName = 'PaintPro';
  static const String version = '1.0.0';
  static const String vendor = 'PaintPro Software';
}

/// GST state code -> state name. Required on every tax invoice
/// (Place of Supply) and drives CGST+SGST vs IGST selection.
class IndianStates {
  static const Map<String, String> byCode = {
    '01': 'Jammu and Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
  };

  static List<String> get codes => byCode.keys.toList()..sort();

  static String name(String? code) => byCode[code] ?? '';

  /// Extracts the state code from a GSTIN (first two characters).
  static String? codeFromGstin(String? gstin) {
    final g = (gstin ?? '').trim();
    if (g.length < 2) return null;
    final code = g.substring(0, 2);
    return byCode.containsKey(code) ? code : null;
  }
}

/// GST slabs applicable to paints, primers, putty, thinners and hardware.
class TaxRates {
  /// Paints & varnishes (HSN 3208/3209/3210) attract 18% GST.
  /// Putty/wall-care (3214) 18%. Brushes (9603) 18%. Books/labour 0%.
  static const List<double> slabs = [0, 0.25, 3, 5, 12, 18, 28];
  static const double defaultRate = 18;
}

class Units {
  static const List<String> all = [
    'LTR', // litre
    'ML', // millilitre
    'KG', // kilogram
    'GM', // gram
    'NOS', // numbers / pieces
    'BOX',
    'BAG',
    'SET',
    'MTR',
    'SQF', // square feet (labour / area contracts)
  ];
  static const String defaultUnit = 'LTR';
}

/// Typical paint pack sizes used for quick product creation.
class PackSizes {
  static const List<String> all = [
    '100 ML',
    '200 ML',
    '500 ML',
    '900 ML',
    '1 LTR',
    '2 LTR',
    '4 LTR',
    '5 KG',
    '10 LTR',
    '20 LTR',
    '20 KG',
    '40 KG',
  ];
}

class PaymentModes {
  static const String cash = 'CASH';
  static const String upi = 'UPI';
  static const String card = 'CARD';
  static const String bank = 'BANK';
  static const String cheque = 'CHEQUE';
  static const String credit = 'CREDIT';

  static const List<String> all = [cash, upi, card, bank, cheque, credit];
}

class PriceTier {
  static const String retail = 'RETAIL';
  static const String dealer = 'DEALER';
  static const String contractor = 'CONTRACTOR';
  static const List<String> all = [retail, dealer, contractor];
}

class DocType {
  static const String invoice = 'INVOICE';
  static const String estimate = 'ESTIMATE';
  static const String creditNote = 'CREDIT_NOTE';
  static const String challan = 'CHALLAN';

  static const Map<String, String> label = {
    invoice: 'Tax Invoice',
    estimate: 'Estimate / Quotation',
    creditNote: 'Credit Note (Sales Return)',
    challan: 'Delivery Challan',
  };
}

class DocStatus {
  static const String paid = 'PAID';
  static const String partial = 'PARTIAL';
  static const String unpaid = 'UNPAID';
  static const String cancelled = 'CANCELLED';
  static const String draft = 'DRAFT';
}

class UserRole {
  static const String admin = 'ADMIN';
  static const String manager = 'MANAGER';
  static const String cashier = 'CASHIER';
  static const List<String> all = [admin, manager, cashier];
}

class StockRef {
  static const String opening = 'OPENING';
  static const String purchase = 'PURCHASE';
  static const String sale = 'SALE';
  static const String salesReturn = 'SALES_RETURN';
  static const String purchaseReturn = 'PURCHASE_RETURN';
  static const String adjustment = 'ADJUSTMENT';
  static const String damage = 'DAMAGE';
}

/// Settings keys stored in the `settings` table.
class SKeys {
  static const String invoicePrefix = 'invoice_prefix';
  static const String invoiceNext = 'invoice_next';
  static const String estimatePrefix = 'estimate_prefix';
  static const String estimateNext = 'estimate_next';
  static const String creditPrefix = 'credit_prefix';
  static const String creditNext = 'credit_next';
  static const String purchasePrefix = 'purchase_prefix';
  static const String purchaseNext = 'purchase_next';
  static const String financialYear = 'financial_year';
  static const String defaultGst = 'default_gst';
  static const String priceIncludesTax = 'price_includes_tax';
  static const String roundOff = 'round_off';
  static const String printFormat = 'print_format'; // A5L | A4 | T80
  static const String autoPrint = 'auto_print';
  static const String lowStockAlert = 'low_stock_alert';
  static const String terms = 'terms';
  static const String declaration = 'declaration';
  static const String showBankOnInvoice = 'show_bank_on_invoice';
  static const String showUpiQr = 'show_upi_qr';
  static const String negativeStock = 'allow_negative_stock';
  static const String themeMode = 'theme_mode';
  static const String accentColor = 'accent_color';
  static const String backupDir = 'backup_dir';
  static const String lastBackup = 'last_backup';
}

class PrintFormat {
  static const String a5Landscape = 'A5L';
  static const String a5Portrait = 'A5P';
  static const String a4 = 'A4';
  static const String thermal80 = 'T80';

  static const Map<String, String> label = {
    a5Landscape: 'A5 Horizontal (Landscape) — recommended',
    a5Portrait: 'A5 Vertical (Portrait)',
    a4: 'A4 Full Page',
    thermal80: 'Thermal Roll 80 mm',
  };
}
