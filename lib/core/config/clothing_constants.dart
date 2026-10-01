import 'package:flutter/material.dart';

/// Predefined size presets, standard colors, and categories for clothing stores.
class ClothingConstants {
  ClothingConstants._();

  /// Default categories tailored for fashion & clothing shops.
  static const List<String> defaultCategories = [
    'رجالي',
    'حريمي',
    'أطفال أولاد',
    'أطفال بنات',
    'أحذية رجالي',
    'أحذية حريمي',
    'أحذية أطفال',
    'ملابس رياضية',
    'ملابس داخلية ولانجري',
    'حقائب وإكسسوارات',
    'شيلان وطرح',
  ];

  /// Standard Alpha garment sizes.
  static const List<String> alphaSizes = [
    'XS',
    'S',
    'M',
    'L',
    'XL',
    '2XL',
    '3XL',
    '4XL',
    '5XL',
    'Free Size',
  ];

  /// Numeric pants/waist sizes.
  static const List<String> pantsSizes = [
    '28',
    '30',
    '32',
    '34',
    '36',
    '38',
    '40',
    '42',
    '44',
    '46',
    '48',
  ];

  /// Numeric shoe sizes.
  static const List<String> shoeSizes = [
    '36',
    '37',
    '38',
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
  ];

  /// Children sizes / ages.
  static const List<String> kidsSizes = [
    '0-3M',
    '3-6M',
    '6-12M',
    '1-2Y',
    '2-3Y',
    '3-4Y',
    '4-5Y',
    '6-7Y',
    '8-9Y',
    '10-12Y',
    '14-16Y',
  ];

  /// Common clothing colors with preview colors.
  static const List<Map<String, dynamic>> commonColors = [
    {'name': 'أسود', 'color': Colors.black},
    {'name': 'أبيض', 'color': Colors.white},
    {'name': 'كحلي', 'color': Color(0xFF001F3F)},
    {'name': 'أزرق', 'color': Colors.blue},
    {'name': 'رمادي', 'color': Colors.grey},
    {'name': 'بيج', 'color': Color(0xFFF5F5DC)},
    {'name': 'بني', 'color': Colors.brown},
    {'name': 'أحمر', 'color': Colors.red},
    {'name': 'نبيتي', 'color': Color(0xFF800020)},
    {'name': 'أخضر', 'color': Colors.green},
    {'name': 'زيتي', 'color': Color(0xFF556B2F)},
    {'name': 'أصفر', 'color': Colors.amber},
    {'name': 'وردي', 'color': Colors.pink},
    {'name': 'موف', 'color': Colors.purple},
    {'name': 'برتقالي', 'color': Colors.orange},
  ];

  static List<String> get colorNames =>
      commonColors.map((e) => e['name'] as String).toList();
}
