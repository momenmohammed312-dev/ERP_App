import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class DamagedItemsScreen extends StatefulWidget {
  final AppDatabase db;

  const DamagedItemsScreen({super.key, required this.db});

  @override
  State<DamagedItemsScreen> createState() => _DamagedItemsScreenState();
}

class _DamagedItemsScreenState extends State<DamagedItemsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الهالك والتالف'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة هالك جديد',
            onPressed: () => _showAddDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<DamagedItem>>(
        stream: widget.db.damagedItemsDao.watchAllDamagedItems(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('لا يوجد سجلات للمنتجات التالفة.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep, color: Colors.red),
                  title: FutureBuilder<Product?>(
                    future: widget.db.productDao.getProductById(item.productId),
                    builder: (context, prodSnap) {
                      final prodName = prodSnap.data?.name ?? 'منتج غير معروف';
                      return Text(
                        prodName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                  subtitle: Text(
                    'السبب: ${item.reason}\nالتاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(item.damageDate)}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'الكمية: ${item.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'خسارة: ${item.totalLoss.toStringAsFixed(2)} ج.م',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        tooltip: 'إضافة هالك',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddDamagedItemDialog(db: widget.db),
    );
  }
}

class _AddDamagedItemDialog extends StatefulWidget {
  final AppDatabase db;
  const _AddDamagedItemDialog({required this.db});

  @override
  State<_AddDamagedItemDialog> createState() => _AddDamagedItemDialogState();
}

class _AddDamagedItemDialogState extends State<_AddDamagedItemDialog> {
  final _formKey = GlobalKey<FormState>();
  Product? _selectedProduct;
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  List<Product> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.db.productDao.getAllProducts();
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() async {
    if (_formKey.currentState!.validate() && _selectedProduct != null) {
      final qty = int.parse(_quantityController.text);
      if (qty > _selectedProduct!.quantity) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الكمية الهالكة لا يمكن أن تتجاوز الكمية المتاحة.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final cost = _selectedProduct!.costPrice ?? _selectedProduct!.price;
      final loss = cost * qty;

      try {
        await widget.db.transaction(() async {
          // Add to damaged items
          await widget.db.damagedItemsDao.insertDamagedItem(
            DamagedItemsCompanion.insert(
              productId: _selectedProduct!.id,
              quantity: qty,
              unitCost: cost,
              totalLoss: loss,
              reason: _reasonController.text.trim().isEmpty ? 'تالف' : _reasonController.text.trim(),
              damageDate: DateTime.now(),
              notes: drift.Value(_notesController.text.trim()),
            ),
          );

          // Deduct from product quantity
          final newQty = _selectedProduct!.quantity - qty;
          await widget.db.productDao.updateProduct(
            _selectedProduct!.copyWith(quantity: newQty),
          );
        });

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تسجيل الهالك بنجاح.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار منتج أولاً.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: const Text('تسجيل منتج هالك/تالف'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Product>(
                  decoration: const InputDecoration(
                    labelText: 'المنتج',
                    border: OutlineInputBorder(),
                  ),
                  items: _products.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (المتاح: ${p.quantity})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedProduct = val;
                    });
                  },
                  validator: (val) => val == null ? 'يرجى اختيار المنتج' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الكمية التالفة',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'يرجى إدخال الكمية';
                    if (int.tryParse(val) == null || int.parse(val) <= 0) return 'كمية غير صالحة';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'السبب (مثال: منتهي الصلاحية، كسر...)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'يرجى تحديد السبب' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إضافية',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('حفظ وتسجيل التالف'),
        ),
      ],
    );
  }
}
