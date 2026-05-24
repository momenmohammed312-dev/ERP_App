import 'package:shared_preferences/shared_preferences.dart';

enum CalendarThemeMode { light, gray, dark }

class SettingsService {
  static const _calendarThemeKey = 'calendar_theme_mode';
  static const _defaultInvoiceTypeKey = 'default_invoice_type';
  static const _thermalPrinterKey = 'thermal_printer_name';
  static const _a4PrinterKey = 'a4_printer_name';

  static Future<CalendarThemeMode> getCalendarTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_calendarThemeKey) ?? 'light';
    switch (v) {
      case 'gray':
        return CalendarThemeMode.gray;
      case 'dark':
        return CalendarThemeMode.dark;
      case 'light':
      default:
        return CalendarThemeMode.light;
    }
  }

  static Future<void> setCalendarTheme(CalendarThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final v = switch (mode) {
      CalendarThemeMode.gray => 'gray',
      CalendarThemeMode.dark => 'dark',
      CalendarThemeMode.light => 'light',
    };
    await prefs.setString(_calendarThemeKey, v);
  }

  static Future<void> setDefaultInvoiceType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultInvoiceTypeKey, type);
  }

  static Future<String> getDefaultInvoiceType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultInvoiceTypeKey) ?? 'cash';
  }

  // Printer settings
  static Future<void> setThermalPrinter(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove(_thermalPrinterKey);
    } else {
      await prefs.setString(_thermalPrinterKey, name);
    }
  }

  static Future<String?> getThermalPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_thermalPrinterKey);
  }

  static Future<void> setA4Printer(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove(_a4PrinterKey);
    } else {
      await prefs.setString(_a4PrinterKey, name);
    }
  }

  static Future<String?> getA4Printer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_a4PrinterKey);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Business / Store Info
  // ─────────────────────────────────────────────────────────────────────────
  static const _businessNameKey = 'business_name';
  static const _businessPhoneKey = 'business_phone';
  static const _businessAddressKey = 'business_address';
  static const _businessLogoKey = 'business_logo_path';
  static const _taxNumberKey = 'business_tax_number';
  static const _receiptFooterKey = 'receipt_footer_msg';
  static const _currencyKey = 'currency_symbol';
  static const _isFirstRunKey = 'is_first_run_complete';

  static Future<String> getBusinessName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_businessNameKey) ?? 'المحل التجاري';
  }

  static Future<void> setBusinessName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_businessNameKey, name);
  }

  static Future<String> getBusinessPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_businessPhoneKey) ?? '';
  }

  static Future<void> setBusinessPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_businessPhoneKey, phone);
  }

  static Future<String> getBusinessAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_businessAddressKey) ?? '';
  }

  static Future<void> setBusinessAddress(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_businessAddressKey, address);
  }

  static Future<String> getTaxNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_taxNumberKey) ?? '';
  }

  static Future<void> setTaxNumber(String tax) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_taxNumberKey, tax);
  }

  static Future<String> getReceiptFooter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_receiptFooterKey) ?? 'شكراً لزيارتكم';
  }

  static Future<void> setReceiptFooter(String footer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_receiptFooterKey, footer);
  }

  static Future<Map<String, String>> getBusinessInfo() async {
    return {
      'name': await getBusinessName(),
      'phone': await getBusinessPhone(),
      'address': await getBusinessAddress(),
      'taxNumber': await getTaxNumber(),
      'footer': await getReceiptFooter(),
    };
  }

  static Future<String?> getBusinessLogoPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_businessLogoKey);
  }

  static Future<void> setBusinessLogoPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_businessLogoKey);
    } else {
      await prefs.setString(_businessLogoKey, path);
    }
  }

  static Future<String> getCurrencySymbol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currencyKey) ?? 'ج.م';
  }

  static Future<void> setCurrencySymbol(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, symbol);
  }

  static Future<bool> isFirstRunComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isFirstRunKey) ?? false;
  }

  static Future<void> markFirstRunComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isFirstRunKey, true);
  }
}
