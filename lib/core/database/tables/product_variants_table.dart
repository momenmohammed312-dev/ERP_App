import 'package:drift/drift.dart';
import 'product_table.dart';

/// أصناف المنتج (ألوان/فئات) — كل صنف له كمية وباركود مستقل.
/// مثال: قماش X له 5 ألوان، كل لون كمية مختلفة وباركود مختلف.
///
/// القواعد:
/// - المنتج الأب يبقى للعرض والتجميع، والمخزون الحقيقي على مستوى الصنف.
/// - كمية الأب = مجموع كميات الأصناف (تُحسب في الـ service، مش trigger).
/// - السعر الفارغ (NULL) = نفس سعر الأب وقت البيع.
/// - تفرد الباركود يُفحص كودًا عبر الجدولين (products + product_variants)،
///   وقاعدة التوليد التلقائي هنا بقاعدة مختلفة (20000000) عشان مايحصلش
///   تصادم مع باركودات المنتجات (10000000 + المعرف).
@DataClassName('ProductVariant')
class ProductVariants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  RealColumn get price => real().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get status => text().nullable().withDefault(
    const Constant('Active'),
  )(); // Active/Inactive/Deleted (soft delete هو الافتراضي)

  /// Sync identity للمزامنة متعددة الأجهزة (مثل products، للاستخدام المستقبلي).
  TextColumn get syncId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
