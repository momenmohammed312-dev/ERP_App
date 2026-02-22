import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';

import '../../widgets/widgets.dart';
import 'widgets.dart';

class ProductContainer extends StatefulWidget {
  final AppDatabase db;

  const ProductContainer({super.key, required this.db});

  @override
  State<ProductContainer> createState() => _ProductContainerState();
}

class _ProductContainerState extends State<ProductContainer> {
  List<Product> products = [];
  List<Product> filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();

  // Load products when the page loads
  @override
  void initState() {
    super.initState();
    widget.db.productDao.watchAllProducts().listen((event) {
      if (mounted) {
        setState(() {
          products = event;
          filteredProducts = event; // Initially, show all products
        });
      }
    });
  }

  void _showDeleteConfirmation(Product product) {
    showDialog(
      context: context,
      builder: (context) {
        return DeleteConfirmationDialog(
          name: product.name,
          onConfirm: () async {
            await widget.db.productDao.deleteProduct(product);
          },
        );
      },
    );
  }

  // Search function to filter the products
  void _searchProducts(String query) {
    final filtered = products
        .where(
          (product) => product.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();

    if (mounted) {
      setState(() {
        filteredProducts = filtered;
      });
    }
  }

  void _editProduct(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductForm(product: product, db: widget.db),
      ),
    );
  }

  void _addProduct() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => ProductForm(db: widget.db)));
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is removed from the tree
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  context.l10n.product_list,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Gap(16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _addProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: Text(
                      context.l10n.add_product,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => exportProductsToExcel(widget.db, context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 73, 8, 85),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(
                      Icons.table_chart,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      context.l10n.export,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Gap(16),
          SearchWidget(
            controller: _searchController,
            onSearch: _searchProducts,
            hintText: context.l10n.search_product_hint,
          ),
          const Gap(20),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: widget.db.productDao.watchAllProducts(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final products = filteredProducts;
                if (products.isEmpty) {
                  return Center(
                    child: Text(context.l10n.no_products_available_drawer),
                  );
                }

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 350,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            columnSpacing: 20,
                            headingRowColor: WidgetStateProperty.all(
                              Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.05),
                            ),
                            headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            dataTextStyle: const TextStyle(fontSize: 13),
                            columns: [
                              DataColumn(label: Text(context.l10n.index_short)),
                              DataColumn(label: Text(context.l10n.product)),
                              DataColumn(label: Text(context.l10n.quantity)),
                              DataColumn(label: Text(context.l10n.price)),
                              DataColumn(label: Text(context.l10n.status)),
                              DataColumn(label: Text(context.l10n.actions)),
                            ],
                            rows: List.generate(products.length, (index) {
                              final product = products[index];
                              return DataRow(
                                cells: [
                                  DataCell(Text('${index + 1}')),
                                  DataCell(Text(product.name)),
                                  DataCell(Text('${product.quantity}')),
                                  DataCell(
                                    Text(
                                      '${product.price} ${context.l10n.currency_symbol}',
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (product.status ?? 'Active') ==
                                                'Active'
                                            ? Colors.green.withValues(
                                                alpha: 0.1,
                                              )
                                            : Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        (product.status ?? 'Active') == 'Active'
                                            ? context.l10n.active
                                            : context.l10n.inactive,
                                        style: TextStyle(
                                          color:
                                              (product.status ?? 'Active') ==
                                                  'Active'
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () =>
                                              _editProduct(product),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          onPressed: () =>
                                              _showDeleteConfirmation(product),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
