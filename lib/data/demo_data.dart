import 'models.dart';
import 'repos/party_repo.dart';
import 'repos/product_repo.dart';

/// Loads a realistic starter catalogue so a new shop can try the software
/// before typing in its own stock. Everything here is ordinary trade data —
/// generic product descriptions, round prices and standard HSN codes.
class DemoData {
  static const List<String> brands = [
    'Asian Paints',
    'Berger',
    'Nerolac',
    'Dulux',
    'Indigo',
  ];

  /// (name, category, base, pack, unit, hsn, purchase, mrp, retail, dealer,
  ///  contractor, stock, minStock)
  static const List<
      (
        String,
        String,
        String,
        String,
        String,
        String,
        double,
        double,
        double,
        double,
        double,
        double,
        double
      )> catalogue = [
    (
      'Premium Emulsion Interior',
      'Interior Emulsion',
      'White Base',
      '1 LTR',
      'LTR',
      '3209',
      265,
      395,
      355,
      330,
      320,
      36,
      8
    ),
    (
      'Premium Emulsion Interior',
      'Interior Emulsion',
      'White Base',
      '4 LTR',
      'LTR',
      '3209',
      980,
      1450,
      1300,
      1215,
      1180,
      24,
      6
    ),
    (
      'Premium Emulsion Interior',
      'Interior Emulsion',
      'White Base',
      '10 LTR',
      'LTR',
      '3209',
      2320,
      3450,
      3100,
      2880,
      2790,
      12,
      4
    ),
    (
      'Premium Emulsion Interior',
      'Interior Emulsion',
      'White Base',
      '20 LTR',
      'LTR',
      '3209',
      4480,
      6650,
      5990,
      5560,
      5390,
      8,
      3
    ),
    (
      'Royal Luxury Emulsion',
      'Interior Emulsion',
      'Pastel Base',
      '1 LTR',
      'LTR',
      '3209',
      420,
      625,
      565,
      525,
      510,
      20,
      6
    ),
    (
      'Royal Luxury Emulsion',
      'Interior Emulsion',
      'Pastel Base',
      '4 LTR',
      'LTR',
      '3209',
      1580,
      2350,
      2115,
      1965,
      1905,
      14,
      4
    ),
    (
      'Weather Shield Exterior',
      'Exterior Emulsion',
      'White Base',
      '4 LTR',
      'LTR',
      '3209',
      1340,
      1995,
      1795,
      1670,
      1615,
      18,
      5
    ),
    (
      'Weather Shield Exterior',
      'Exterior Emulsion',
      'White Base',
      '10 LTR',
      'LTR',
      '3209',
      3180,
      4740,
      4265,
      3960,
      3840,
      9,
      3
    ),
    (
      'Weather Shield Exterior',
      'Exterior Emulsion',
      'Deep Base',
      '20 LTR',
      'LTR',
      '3209',
      6150,
      9160,
      8245,
      7660,
      7420,
      6,
      2
    ),
    (
      'Distemper Acrylic Washable',
      'Distemper',
      'Ready Mix',
      '5 KG',
      'KG',
      '3209',
      285,
      425,
      385,
      358,
      348,
      30,
      8
    ),
    (
      'Distemper Acrylic Washable',
      'Distemper',
      'Ready Mix',
      '20 KG',
      'KG',
      '3209',
      1050,
      1565,
      1410,
      1310,
      1270,
      15,
      4
    ),
    (
      'Wall Putty (White Cement Based)',
      'Putty',
      '',
      '20 KG',
      'KG',
      '3214',
      620,
      925,
      835,
      775,
      750,
      40,
      10
    ),
    (
      'Wall Putty (White Cement Based)',
      'Putty',
      '',
      '40 KG',
      'KG',
      '3214',
      1190,
      1775,
      1600,
      1485,
      1440,
      22,
      6
    ),
    (
      'Acrylic Wall Primer Water Based',
      'Primer',
      '',
      '4 LTR',
      'LTR',
      '3209',
      640,
      955,
      860,
      800,
      775,
      20,
      5
    ),
    (
      'Acrylic Wall Primer Water Based',
      'Primer',
      '',
      '10 LTR',
      'LTR',
      '3209',
      1480,
      2205,
      1985,
      1845,
      1785,
      10,
      3
    ),
    (
      'Red Oxide Metal Primer',
      'Primer',
      '',
      '1 LTR',
      'LTR',
      '3208',
      195,
      290,
      265,
      245,
      238,
      25,
      6
    ),
    (
      'Synthetic Enamel Gloss',
      'Enamel',
      'White Base',
      '1 LTR',
      'LTR',
      '3208',
      315,
      470,
      425,
      395,
      382,
      28,
      8
    ),
    (
      'Synthetic Enamel Gloss',
      'Enamel',
      'White Base',
      '4 LTR',
      'LTR',
      '3208',
      1180,
      1760,
      1585,
      1470,
      1425,
      16,
      4
    ),
    (
      'PU Wood Finish Clear Gloss',
      'Wood Finish',
      '',
      '1 LTR',
      'LTR',
      '3208',
      690,
      1030,
      925,
      860,
      835,
      10,
      3
    ),
    (
      'Melamine Wood Polish',
      'Wood Finish',
      '',
      '1 LTR',
      'LTR',
      '3208',
      540,
      805,
      725,
      675,
      655,
      8,
      3
    ),
    (
      'Waterproofing Compound 2K',
      'Waterproofing',
      '',
      '20 KG',
      'KG',
      '3214',
      3250,
      4850,
      4365,
      4050,
      3925,
      6,
      2
    ),
    (
      'Roof Waterproof Coating',
      'Waterproofing',
      '',
      '10 LTR',
      'LTR',
      '3209',
      2450,
      3655,
      3290,
      3055,
      2960,
      7,
      2
    ),
    (
      'Thinner / Mineral Turpentine',
      'Solvent',
      '',
      '1 LTR',
      'LTR',
      '3814',
      88,
      132,
      119,
      110,
      107,
      45,
      12
    ),
    (
      'Thinner / Mineral Turpentine',
      'Solvent',
      '',
      '5 KG',
      'KG',
      '3814',
      395,
      590,
      530,
      492,
      477,
      18,
      5
    ),
    (
      'Paint Brush 2 inch',
      'Accessories',
      '',
      '1 NOS',
      'NOS',
      '9603',
      42,
      65,
      58,
      54,
      52,
      60,
      15
    ),
    (
      'Paint Brush 4 inch',
      'Accessories',
      '',
      '1 NOS',
      'NOS',
      '9603',
      78,
      118,
      106,
      98,
      95,
      40,
      10
    ),
    (
      'Roller 9 inch with Handle',
      'Accessories',
      '',
      '1 NOS',
      'NOS',
      '9603',
      135,
      205,
      185,
      172,
      166,
      30,
      8
    ),
    (
      'Masking Tape 24 mm',
      'Accessories',
      '',
      '1 NOS',
      'NOS',
      '3919',
      32,
      50,
      45,
      42,
      40,
      80,
      20
    ),
    (
      'Emery Paper No. 80',
      'Accessories',
      '',
      '1 NOS',
      'NOS',
      '6805',
      12,
      20,
      18,
      16,
      15,
      200,
      50
    ),
    (
      'Putty Blade Stainless 4 inch',
      'Accessories',
      '',
      '1 NOS',
      'NOS',
      '8205',
      55,
      85,
      76,
      71,
      68,
      25,
      8
    ),
  ];

  static const List<(String, String, String, double, double)> services = [
    ('Tinting / Colour mixing charge', '9954', 'NOS', 30, 0),
    ('Delivery charge (local)', '9965', 'NOS', 100, 0),
    ('Painting labour — interior', '9954', 'SQF', 14, 0),
    ('Painting labour — exterior', '9954', 'SQF', 22, 0),
  ];

  /// Adds the catalogue, two suppliers and three customers.
  /// Returns the number of records created.
  static Future<int> load({String stateCode = ''}) async {
    final products = ProductRepo();
    final parties = PartyRepo();
    var created = 0;

    for (var i = 0; i < catalogue.length; i++) {
      final c = catalogue[i];
      final brand = brands[i % brands.length];
      await products.save(Product(
        name: c.$1,
        brand: brand,
        category: c.$2,
        baseType: c.$3,
        packSize: c.$4,
        unit: c.$5,
        hsn: c.$6,
        purchasePrice: c.$7,
        mrp: c.$8,
        retailPrice: c.$9,
        dealerPrice: c.$10,
        contractorPrice: c.$11,
        openingStock: c.$12,
        minStock: c.$13,
        gstRate: 18,
      ));
      created++;
    }

    for (final s in services) {
      await products.save(Product(
        name: s.$1,
        category: 'Services',
        hsn: s.$2,
        unit: s.$3,
        retailPrice: s.$4,
        mrp: s.$4,
        purchasePrice: s.$5,
        gstRate: 18,
        isService: true,
      ));
      created++;
    }

    for (final sup in const [
      ('Sunrise Paint Distributors', '9845012345', 'Depot supplier'),
      ('Metro Hardware & Paints', '9900123456', 'Accessories supplier'),
    ]) {
      await parties.save(Party(
        kind: 'SUPPLIER',
        name: sup.$1,
        phone: sup.$2,
        notes: sup.$3,
        stateCode: stateCode,
      ));
      created++;
    }

    for (final cust in const [
      ('Ramesh Contractors', '9812345670', 'CONTRACTOR', 50000.0, 30),
      ('Sri Balaji Hardware', '9812345671', 'DEALER', 100000.0, 15),
      ('Anita Sharma', '9812345672', 'RETAIL', 0.0, 0),
    ]) {
      await parties.save(Party(
        kind: 'CUSTOMER',
        name: cust.$1,
        phone: cust.$2,
        priceTier: cust.$3,
        creditLimit: cust.$4,
        creditDays: cust.$5,
        stateCode: stateCode,
      ));
      created++;
    }

    return created;
  }
}
