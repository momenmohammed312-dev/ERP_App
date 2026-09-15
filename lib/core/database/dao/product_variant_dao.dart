// database/dao/product_variant_dao.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/product_variants_table.dart';

part 'product_variant_dao.g.dart';

/// DAO لأصناف المنتج (ألوان/فئات) — نفس نمط [ProductDao] بالظبط.
///
/// ملاحظات:
/// - Soft delete هو الافتراضي (status = 'Deleted')، والـ hard delete محاولة
///   أولى مع fallback للـ soft عند وجود قيود FK (مثل InvoiceItems.variantId).
/// - الباركود الفارغ يتولد تلقائيًا (20000000 + المعرف) — قاعدة مختلفة عن
///   المنتجات (10000000 + المعرف) عشان مايحصلش تصادم بين الجدولين.
/// - تفرد الباركود عبر الجدولين (products + product_variants) مسئولية
///   طبقة الـ UI/service (يفحص الاتنين قبل الحفظ)، مش constraint على الـ DB
///   عشان الـ migration تفضل آمنة على بيانات موجودة.
@DriftAccessor(tables: [ProductVariants])
class ProductVariantDao extends DatabaseAccessor<AppDatabase>
    with _$ProductVariantDaoMixin {
  ProductVariantDao(super.db);

  Future<List<ProductVariant>> getVariantsByProduct(int productId) =>
      (select(productVariants)
            ..where(
              (v) =>
                  v.productId.equals(productId) &
                  (v.status.equals('Deleted').not() | v.status.isNull()),
            )
            ..orderBy([(v) => OrderingTerm(expression: v.id)]))
          .get();

  Stream<List<ProductVariant>> watchVariantsByProduct(int productId) =>
      (select(productVariants)
            ..where(
              (v) =>
                  v.productId.equals(productId) &
                  (v.status.equals('Deleted').not() | v.status.isNull()),
            )
            ..orderBy([(v) => OrderingTerm(expression: v.id)]))
          .watch();

  Future<ProductVariant?> getVariantById(int id) {
    return (select(
      productVariants,
    )..where((v) => v.id.equals(id))).getSingleOrNull();
  }

  /// البحث بباركود الصنف (للمسح في الكاشير).
  Future<ProductVariant?> getVariantByBarcode(String barcode) {
    return (select(productVariants)
          ..where(
            (v) =>
                (v.status.equals('Deleted').not() | v.status.isNull()) &
                v.barcode.equals(barcode),
          ))
        .getSingleOrNull();
  }

  /// إدخال صنف جديد مع ختم syncId + createdAt/updatedAt.
  /// لو الباركود فارغ — يتولد تلقائيًا (20000000 + المعرف) ويتحفظ فورًا،
  /// عشان يبقى قابل للمسح في الكاشير من أول لحظة.
  Future<int> insertVariant(Insertable<ProductVariant> variant) async {
    final syncId = const Uuid().v4();
    final now = DateTime.now();
    Insertable<ProductVariant> decorated = variant;
    if (variant is ProductVariantsCompanion) {
      decorated = variant.copyWith(
        syncId: Value(syncId),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
    } else if (variant is ProductVariant) {
      decorated = variant.copyWith(
        syncId: Value(syncId),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
    }
    final insertedId = await into(productVariants).insert(decorated);

    final rawBarcode = variant is ProductVariantsCompanion
        ? variant.barcode.value
        : variant is ProductVariant
            ? variant.barcode
            : null;
    if (rawBarcode == null || rawBarcode.trim().isEmpty) {
      await (update(productVariants)..where((v) => v.id.equals(insertedId)))
          .write(
            ProductVariantsCompanion(barcode: Value('${20000000 + insertedId}')),
          );
    }

    return insertedId;
  }

  /// تحديث صنف مع bump تلقائي لـ updatedAt.
  Future updateVariant(Insertable<ProductVariant> variant) async {
    Insertable<ProductVariant> decorated = variant;
    if (variant is ProductVariantsCompanion) {
      decorated = variant.copyWith(updatedAt: Value(DateTime.now()));
    } else if (variant is ProductVariant) {
      decorated = variant.copyWith(updatedAt: Value(DateTime.now()));
    }
    await update(productVariants).replace(decorated);
  }

  /// تحديث كمية صنف فقط (يُستخدم داخل transaction البيع/المرتجع).
  Future<void> updateVariantQuantity(int id, int quantity) async {
    await (update(productVariants)..where((v) => v.id.equals(id))).write(
      ProductVariantsCompanion(
        quantity: Value(quantity),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// مجموع كميات أصناف منتج (لإعادة حساب كمية الأب = المجموع).
  Future<int> getTotalQuantityByProduct(int productId) async {
    final sumExp = productVariants.quantity.sum();
    final query = selectOnly(productVariants)
      ..addColumns([sumExp])
      ..where(
        productVariants.productId.equals(productId) &
            (productVariants.status.equals('Deleted').not() |
                productVariants.status.isNull()),
      );
    final row = await query.getSingle();
    return row.read(sumExp) ?? 0;
  }

  Future deleteVariant(ProductVariant variant) async {
    try {
      // Try hard delete first
      await delete(productVariants).delete(variant);
    } catch (e) {
      // If it fails (likely due to foreign key constraints), do a soft delete
      await update(productVariants)
          .replace(variant.copyWith(status: const Value('Deleted')));
    }
  }
}
