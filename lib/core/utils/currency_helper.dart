import 'package:intl/intl.dart';

class CurrencyHelper {
  // منع إنشاء instances
  CurrencyHelper._();

  /// رمز العملة المصرية
  static const String egpSymbol = 'ج.م';

  /// تنسيق المبلغ بالجنيه المصري
  static String formatCurrency(dynamic amount, {bool showSymbol = true}) {
    // معالجة الحالات الخاصة
    if (amount == null) return showSymbol ? '0.00 $egpSymbol' : '0.00';

    double numAmount;

    if (amount is String) {
      numAmount = double.tryParse(amount) ?? 0.0;
    } else if (amount is int) {
      numAmount = amount.toDouble();
    } else if (amount is double) {
      numAmount = amount;
    } else {
      numAmount = 0.0;
    }

    // معالجة NaN و Infinity
    if (numAmount.isNaN || numAmount.isInfinite) {
      numAmount = 0.0;
    }

    // تنسيق الرقم مع فواصل الآلاف باستخدام اللغة الإنجليزية للأرقام
    final formatter = NumberFormat('#,##0.00', 'en_US');
    final formatted = formatter.format(numAmount);

    return showSymbol ? '$formatted $egpSymbol' : formatted;
  }

  /// تنسيق بدون فواصل الآلاف
  static String formatCurrencySimple(dynamic amount, {bool showSymbol = true}) {
    // معالجة الحالات الخاصة
    if (amount == null) return showSymbol ? '0.00 $egpSymbol' : '0.00';

    double numAmount;

    if (amount is String) {
      numAmount = double.tryParse(amount) ?? 0.0;
    } else if (amount is int) {
      numAmount = amount.toDouble();
    } else if (amount is double) {
      numAmount = amount;
    } else {
      numAmount = 0.0;
    }

    // معالجة NaN و Infinity
    if (numAmount.isNaN || numAmount.isInfinite) {
      numAmount = 0.0;
    }

    final formatted = numAmount.toStringAsFixed(2);

    return showSymbol ? '$formatted $egpSymbol' : formatted;
  }

  /// استخراج الرقم من نص منسق
  static double parseFormattedCurrency(String formattedAmount) {
    if (formattedAmount.isEmpty) return 0.0;

    // إزالة رمز العملة والمسافات
    String cleaned = formattedAmount
        .replaceAll(egpSymbol, '')
        .replaceAll('EGP', '')
        .replaceAll(' ', '')
        .replaceAll(',', '')
        .trim();

    return double.tryParse(cleaned) ?? 0.0;
  }

  /// تحويل آمن إلى double
  static double toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) {
      if (value.isNaN || value.isInfinite) return 0.0;
      return value;
    }
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// تقريب لأقرب منزلتين عشريتين
  static double round(dynamic value) {
    final num = toDouble(value);
    return (num * 100).round() / 100;
  }

  /// تحويل الرقم إلى أرقام عربية
  static String toArabicNumbers(String number) {
    const arabicNumbers = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String result = '';
    for (int i = 0; i < number.length; i++) {
      String char = number[i];
      if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        result += arabicNumbers[int.parse(char)];
      } else {
        result += char;
      }
    }
    return result;
  }

  /// تنسيق العملة بالأرقام العربية
  static String formatCurrencyArabic(dynamic amount, {bool showSymbol = true}) {
    final formatted = formatCurrency(amount, showSymbol: false);
    final arabicNumbers = toArabicNumbers(formatted);
    return showSymbol ? '$arabicNumbers $egpSymbol' : arabicNumbers;
  }

  /// تحويل المبلغ إلى كلمات عربية (للشيكات والإيصالات)
  static String amountToWordsArabic(dynamic amount) {
    double numAmount = toDouble(amount);
    int pounds = numAmount.floor();
    int piasters = ((numAmount - pounds) * 100).round();

    String result = _convertNumberToArabicWords(pounds);

    if (piasters > 0) {
      result += ' و ${_convertNumberToArabicWords(piasters)} قرشاً';
    }

    return '$result فقط لا غير';
  }

  /// تحويل الأرقام إلى كلمات عربية (دالة مساعدة)
  static String _convertNumberToArabicWords(int number) {
    if (number == 0) return 'صفر';
    if (number == 1) return 'واحد';
    if (number == 2) return 'اثنان';
    if (number == 3) return 'ثلاثة';
    if (number == 4) return 'أربعة';
    if (number == 5) return 'خمسة';
    if (number == 6) return 'ستة';
    if (number == 7) return 'سبعة';
    if (number == 8) return 'ثمانية';
    if (number == 9) return 'تسعة';
    if (number == 10) return 'عشرة';
    if (number == 11) return 'أحد عشر';
    if (number == 12) return 'اثنا عشر';
    if (number == 13) return 'ثلاثة عشر';
    if (number == 14) return 'أربعة عشر';
    if (number == 15) return 'خمسة عشر';
    if (number == 16) return 'ستة عشر';
    if (number == 17) return 'سبعة عشر';
    if (number == 18) return 'ثمانية عشر';
    if (number == 19) return 'تسعة عشر';
    if (number == 20) return 'عشرون';
    if (number == 30) return 'ثلاثون';
    if (number == 40) return 'أربعون';
    if (number == 50) return 'خمسون';
    if (number == 60) return 'ستون';
    if (number == 70) return 'سبعون';
    if (number == 80) return 'ثمانون';
    if (number == 90) return 'تسعون';
    if (number == 100) return 'مئة';
    if (number == 200) return 'مئتان';
    if (number == 300) return 'ثلاثمئة';
    if (number == 400) return 'أربعمئة';
    if (number == 500) return 'خمسمئة';
    if (number == 600) return 'ستمئة';
    if (number == 700) return 'سبعمئة';
    if (number == 800) return 'ثمانمئة';
    if (number == 900) return 'تسعمئة';
    if (number == 1000) return 'ألف';

    // For numbers > 20 and not multiples of 10
    if (number < 100) {
      int tens = (number ~/ 10) * 10;
      int ones = number % 10;
      return '${_convertNumberToArabicWords(tens)} ${_convertNumberToArabicWords(ones)}';
    }

    // For larger numbers (simplified version)
    if (number < 1000) {
      int hundreds = number ~/ 100;
      int remainder = number % 100;
      String hundredsWord = _convertNumberToArabicWords(hundreds * 100);
      if (remainder == 0) return hundredsWord;
      return '$hundredsWord و ${_convertNumberToArabicWords(remainder)}';
    }

    // For thousands (simplified)
    if (number < 1000000) {
      int thousands = number ~/ 1000;
      int remainder = number % 1000;
      String thousandsWord = '${_convertNumberToArabicWords(thousands)} ألف';
      if (remainder == 0) return thousandsWord;
      return '$thousandsWord و ${_convertNumberToArabicWords(remainder)}';
    }

    // For millions (simplified)
    if (number < 1000000000) {
      int millions = number ~/ 1000000;
      int remainder = number % 1000000;
      String millionsWord = '${_convertNumberToArabicWords(millions)} مليون';
      if (remainder == 0) return millionsWord;
      return '$millionsWord و ${_convertNumberToArabicWords(remainder)}';
    }

    return number.toString(); // Fallback for very large numbers
  }

  /// التحقق من صحة المبلغ
  static bool isValidAmount(dynamic amount) {
    final numAmount = toDouble(amount);
    return numAmount > 0 && !numAmount.isNaN && !numAmount.isInfinite;
  }

  /// حساب الضريبة المضافة
  static double calculateVAT(dynamic amount, {double vatRate = 0.14}) {
    final numAmount = toDouble(amount);
    return numAmount * vatRate;
  }

  /// حساب المبلغ شامل الضريبة
  static double calculateAmountWithVAT(
    dynamic amount, {
    double vatRate = 0.14,
  }) {
    final numAmount = toDouble(amount);
    return numAmount * (1 + vatRate);
  }

  /// حساب المبلغ قبل الضريبة
  static double calculateAmountBeforeVAT(
    dynamic amountWithVAT, {
    double vatRate = 0.14,
  }) {
    final numAmount = toDouble(amountWithVAT);
    return numAmount / (1 + vatRate);
  }
}
