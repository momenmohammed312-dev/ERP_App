import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/purchase_orders_tables.dart';

part 'purchase_orders_dao.g.dart';

@DriftAccessor(
  tables: [PurchaseOrders, PurchaseOrderItems, PurchaseOrderStatuses],
)
class PurchaseOrdersDao extends DatabaseAccessor<AppDatabase>
    with _$PurchaseOrdersDaoMixin {
  PurchaseOrdersDao(super.db);

  // ── Get All ──────────────────────────────────────────────────
  Future<List<PurchaseOrder>> getAllOrders() => select(db.purchaseOrders).get();

  Stream<List<PurchaseOrder>> watchAllOrders() =>
      select(db.purchaseOrders).watch();

  // ── Get By ID ─────────────────────────────────────────────────
  Future<PurchaseOrder?> getOrderById(int id) => (select(
    db.purchaseOrders,
  )..where((o) => o.id.equals(id))).getSingleOrNull();

  // ── Get By Supplier ──────────────────────────────────────────
  Stream<List<PurchaseOrder>> watchOrdersBySupplier(int supplierId) => (select(
    db.purchaseOrders,
  )..where((o) => o.supplierId.equals(supplierId))).watch();

  // ── Get By Status ────────────────────────────────────────────
  Stream<List<PurchaseOrder>> watchOrdersByStatus(String status) => (select(
    db.purchaseOrders,
  )..where((o) => o.status.equals(status))).watch();

  // ── Create ────────────────────────────────────────────────────
  Future<int> createOrder(PurchaseOrdersCompanion order) =>
      into(db.purchaseOrders).insert(order);

  // ── Update ────────────────────────────────────────────────────
  Future<bool> updateOrder(PurchaseOrder order) =>
      update(db.purchaseOrders).replace(order);

  // ── Update Status ─────────────────────────────────────────────
  Future<void> updateOrderStatus(int orderId, String newStatus) =>
      (update(db.purchaseOrders)..where((o) => o.id.equals(orderId))).write(
        PurchaseOrdersCompanion(
          status: Value(newStatus),
          updatedAt: Value(DateTime.now()),
        ),
      );

  // ── Delete ────────────────────────────────────────────────────
  Future<int> deleteOrder(int id) =>
      (delete(db.purchaseOrders)..where((o) => o.id.equals(id))).go();

  // ── Order Items ───────────────────────────────────────────────
  Future<List<PurchaseOrderItem>> getOrderItems(int orderId) => (select(
    db.purchaseOrderItems,
  )..where((i) => i.orderId.equals(orderId))).get();

  Future<int> addOrderItem(PurchaseOrderItemsCompanion item) =>
      into(db.purchaseOrderItems).insert(item);

  Future<int> deleteOrderItems(int orderId) => (delete(
    db.purchaseOrderItems,
  )..where((i) => i.orderId.equals(orderId))).go();

  // ── Statistics ─────────────────────────────────────────────────
  Future<double> getTotalOrdersValue() async {
    final orders = await getAllOrders();
    return orders.fold<double>(0.0, (sum, o) => sum + o.totalAmount);
  }

  Future<int> getPendingOrdersCount() async {
    final orders = await (select(
      db.purchaseOrders,
    )..where((o) => o.status.equals('draft') | o.status.equals('sent'))).get();
    return orders.length;
  }
}
