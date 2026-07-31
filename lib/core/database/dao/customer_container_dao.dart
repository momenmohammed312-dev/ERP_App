import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_containers_table.dart';

part 'customer_container_dao.g.dart';

@DriftAccessor(tables: [CustomerContainers])
class CustomerContainerDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerContainerDaoMixin {
  CustomerContainerDao(super.db);

  /// All container records for a given product.
  Stream<List<CustomerContainer>> watchByProduct(int productId) =>
      (select(customerContainers)
            ..where((c) => c.productId.equals(productId)))
          .watch();

  /// Single record for a (product, customer) pair, or null.
  Future<CustomerContainer?> getByProductAndCustomer(
    int productId,
    String customerId,
  ) {
    return (select(customerContainers)
          ..where(
            (c) =>
                c.productId.equals(productId) &
                c.customerId.equals(customerId),
          ))
        .getSingleOrNull();
  }

  /// Insert or update a container record (keyed by productId + customerId).
  Future<void> upsert(CustomerContainersCompanion entry) =>
      into(customerContainers).insertOnConflictUpdate(entry);

  /// Remove all container records for a product (used when untracking).
  Future<int> deleteByProduct(int productId) =>
      (delete(customerContainers)
            ..where((c) => c.productId.equals(productId)))
          .go();
}
