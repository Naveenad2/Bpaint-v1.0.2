/// Field validators for GSTIN, phone, PIN, email and numeric input.
class V {
  static final RegExp _gstin = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[Z]{1}[0-9A-Z]{1}$',
  );
  static final RegExp _pan = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  static final RegExp _phone = RegExp(r'^[6-9][0-9]{9}$');
  static final RegExp _pin = RegExp(r'^[1-9][0-9]{5}$');
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  static final RegExp _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final RegExp _hsn = RegExp(r'^[0-9]{4,8}$');

  static String? required(String? v, [String field = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  /// GSTIN is optional for B2C customers, but must be valid when supplied.
  static String? gstin(String? v) {
    final s = (v ?? '').trim().toUpperCase();
    if (s.isEmpty) return null;
    if (s.length != 15) return 'GSTIN must be 15 characters';
    if (!_gstin.hasMatch(s)) return 'Invalid GSTIN format';
    if (!_checksumOk(s)) return 'GSTIN checksum failed';
    return null;
  }

  static String? pan(String? v) {
    final s = (v ?? '').trim().toUpperCase();
    if (s.isEmpty) return null;
    return _pan.hasMatch(s) ? null : 'Invalid PAN';
  }

  static String? phone(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return _phone.hasMatch(s) ? null : 'Enter a valid 10-digit mobile number';
  }

  static String? pincode(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return _pin.hasMatch(s) ? null : 'Invalid PIN code';
  }

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return _email.hasMatch(s) ? null : 'Invalid email address';
  }

  static String? ifsc(String? v) {
    final s = (v ?? '').trim().toUpperCase();
    if (s.isEmpty) return null;
    return _ifsc.hasMatch(s) ? null : 'Invalid IFSC code';
  }

  static String? hsn(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return _hsn.hasMatch(s) ? null : 'HSN must be 4 to 8 digits';
  }

  static String? positiveNum(String? v, {bool allowZero = true}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Required';
    final d = double.tryParse(s);
    if (d == null) return 'Enter a number';
    if (d < 0) return 'Cannot be negative';
    if (!allowZero && d == 0) return 'Must be greater than zero';
    return null;
  }

  /// Standard GSTIN mod-36 check-digit verification.
  static bool _checksumOk(String gstin) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      final v = chars.indexOf(gstin[i]);
      if (v < 0) return false;
      final factor = (i % 2 == 0) ? 1 : 2;
      final p = v * factor;
      sum += (p ~/ 36) + (p % 36);
    }
    final check = chars[(36 - (sum % 36)) % 36];
    return check == gstin[14];
  }
}
