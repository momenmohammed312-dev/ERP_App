import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/core/services/price_list_print_service.dart';
import 'package:pos_offline_desktop/ui/product/labels/label_print_page.dart';

import '../../widgets/widgets.dart';
import 'widgets.dart';
import 'package:pos_offline_desktop/ui/barneka/barneka_tracking_screen.dart';

class ProductContainer extends StatefulWidget {
  final AppDatabase db;

  const ProductContainer({super.key, required this.db});

  @override
  State<ProductContainer> createState() => _ProductContainerState();
}

class _ProductContainerState extends State<ProductContainer>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Product> products = [];
  List<Product> filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<List<Product>>? _productsSub;
  bool _isLoading = true;

  int _currentPage = 0;
  int _rowsPerPage = 25;
  static const List<int> _availableRowsPerPage = [15, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    _productsSub = widget.db.productDao.watchAllProducts().listen((event) {
      if (mounted) {
        setState(() {
          products = event;
          _applySearch();
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    _searchController.dispose();
    super.dispose();
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

  void _searchProducts(String query) {
    setState(() {
      _applySearch();
    });
  }

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      filteredProducts = List.from(products);
    } else {
      filteredProducts = products
          .where(
            (product) =>
                product.name.toLowerCase().contains(q) ||
                (product.barcode?.toLowerCase().contains(q) ?? false) ||
                (product.category?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    final maxPages = (filteredProducts.length / _rowsPerPage).ceil();
    if (_currentPage >= maxPages && maxPages > 0) {
      _currentPage = maxPages - 1;
    } else if (maxPages == 0) {
      _currentPage = 0;
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
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    final inStockCount = products.where((p) => p.quantity > 0).length;
    final outOfStockCount = products.where((p) => p.quantity <= 0).length;

    final totalItems = filteredProducts.length;
    final totalPages = (totalItems / _rowsPerPage).ceil().clamp(1, 999999);
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalItems);
    final pageProducts = (startIndex < totalItems)
        ? filteredProducts.sublist(startIndex, endIndex)
        : <Product>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Bar: Title, Quick KPI Badges, and Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      context.l10n.product_list,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'الإجمالي: ${products.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'متوفر: $inStockCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    if (outOfStockCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'نفد: $outOfStockCount',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
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
                  ElevatedButton.icon(
                    onPressed: () => PriceListPrintService.printPriceList(products),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(
                      Icons.print,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'طباعة الأسعار',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LabelPrintPage(db: widget.db),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(
                      Icons.qr_code_2,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'طباعة ملصق',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Gap(14),
          SearchWidget(
            controller: _searchController,
            onSearch: _searchProducts,
            hintText: context.l10n.search_product_hint,
          ),
          const Gap(14),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Card(
                    elevation: 1,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
                      ),
                    ),
                    child: filteredProducts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const Gap(12),
                                Text(
                                  context.l10n.no_products_available_drawer,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth: constraints.maxWidth,
                                        ),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.vertical,
                                          child: DataTable(
                                            columnSpacing: 24,
                                            headingRowColor: WidgetStateProperty.all(
                                              Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.05),
                                            ),
                                            headingTextStyle: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            dataTextStyle: const TextStyle(fontSize: 13),
                                            columns: [
                                              DataColumn(label: Text(context.l10n.index_short)),
                                              DataColumn(label: Text(context.l10n.product)),
                                              DataColumn(label: Text(context.l10n.category)),
                                              DataColumn(label: Text(context.l10n.quantity)),
                                              DataColumn(label: Text(context.l10n.price)),
                                              DataColumn(label: Text(context.l10n.status)),
                                              DataColumn(label: Text(context.l10n.actions)),
                                            ],
                                            rows: List.generate(pageProducts.length, (index) {
                                              final product = pageProducts[index];
                                              final displayIndex = startIndex + index + 1;
                                              return DataRow(
                                                cells: [
                                                  DataCell(Text('$displayIndex')),
                                                  DataCell(
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          product.name,
                                                          style: const TextStyle(
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                        if (product.barneka) ...[
                                                          const SizedBox(width: 8),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: Colors.teal.withValues(
                                                                alpha: 0.12,
                                                              ),
                                                              borderRadius: BorderRadius.circular(10),
                                                            ),
                                                            child: const Text(
                                                              'برنيكه',
                                                              style: TextStyle(
                                                                color: Colors.teal,
                                                                fontWeight: FontWeight.w600,
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  DataCell(Text(product.category ?? '-')),
                                                  DataCell(
                                                    Text(
                                                      '${product.quantity}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        color: product.quantity <= 0
                                                            ? Colors.red
                                                            : null,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      '${product.price} ${context.l10n.currency_symbol}',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: (product.status ?? 'Active') == 'Active'
                                                            ? Colors.green.withValues(alpha: 0.1)
                                                            : Colors.red.withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Text(
                                                        (product.status ?? 'Active') == 'Active'
                                                            ? context.l10n.active
                                                            : context.l10n.inactive,
                                                        style: TextStyle(
                                                          color: (product.status ?? 'Active') == 'Active'
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
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (product.barneka)
                                                          IconButton(
                                                            icon: const Icon(
                                                              Icons.people_alt_outlined,
                                                              color: Colors.teal,
                                                            ),
                                                            tooltip: 'عملاء البرنيكه',
                                                            onPressed: () {
                                                              Navigator.of(context).push(
                                                                MaterialPageRoute(
                                                                  builder: (context) => BarnekaTrackingScreen(
                                                                    db: widget.db,
                                                                    product: product,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        IconButton(
                                                          icon: const Icon(Icons.edit_outlined),
                                                          tooltip: 'تعديل',
                                                          onPressed: () => _editProduct(product),
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.delete_outline,
                                                            color: Colors.red,
                                                          ),
                                                          tooltip: 'حذف',
                                                          onPressed: () => _showDeleteConfirmation(product),
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
                                    );
                                  },
                                ),
                              ),
                              // Bottom pagination controls
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
                                  border: Border(
                                    top: BorderSide(
                                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'عرض ${totalItems == 0 ? 0 : startIndex + 1} - $endIndex من إجمالي $totalItems منتج',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'العناصر في الصفحة:',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                          ),
                                        ),
                                        const Gap(8),
                                        DropdownButton<int>(
                                          value: _rowsPerPage,
                                          isDense: true,
                                          underline: const SizedBox.shrink(),
                                          items: _availableRowsPerPage.map((n) {
                                            return DropdownMenuItem<int>(
                                              value: n,
                                              child: Text('$n', style: const TextStyle(fontSize: 12)),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null && val != _rowsPerPage) {
                                              setState(() {
                                                _rowsPerPage = val;
                                                _currentPage = 0;
                                              });
                                            }
                                          },
                                        ),
                                        const Gap(16),
                                        IconButton(
                                          icon: const Icon(Icons.first_page, size: 20),
                                          tooltip: 'الصفحة الأولى',
                                          onPressed: _currentPage > 0
                                              ? () => setState(() => _currentPage = 0)
                                              : null,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left, size: 20),
                                          tooltip: 'الصفحة السابقة',
                                          onPressed: _currentPage > 0
                                              ? () => setState(() => _currentPage--)
                                              : null,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          child: Text(
                                            '${_currentPage + 1} / $totalPages',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right, size: 20),
                                          tooltip: 'الصفحة التالية',
                                          onPressed: _currentPage < totalPages - 1
                                              ? () => setState(() => _currentPage++)
                                              : null,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.last_page, size: 20),
                                          tooltip: 'الصفحة الأخيرة',
                                          onPressed: _currentPage < totalPages - 1
                                              ? () => setState(() => _currentPage = totalPages - 1)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
