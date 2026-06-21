import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/damaged_items_dao.dart';

const Color _bgDark = Color(0xFF0D1117);
const Color _bgCard = Color(0xFF161B22);
const Color _gold = Color(0xFFC9A84C);

const Color _border = Color(0xFF30363D);
const Color _textMuted = Color(0xFF7D8590);
const Color _accentGreen = Color(0xFF3FB950);

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
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: const Text('إدارة الهالك والتالف'),
        backgroundColor: _bgCard,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: _gold,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: _gold),
            tooltip: 'إضافة هالك جديد',
            onPressed: () => _showAddDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<DamagedItemWithProduct>>(
        stream: widget.db.damagedItemsDao.watchAllDamagedItemsWithProducts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _gold));
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'خطأ: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return _buildEmptyState();
          }

          final totalLoss = items.fold<double>(
            0.0,
            (sum, e) => sum + e.item.totalLoss,
          );
          final totalQty = items.fold<int>(
            0,
            (sum, e) => sum + e.item.quantity,
          );

          return Column(
            children: [
              _buildSummaryBar(items.length, totalQty, totalLoss),
              Expanded(child: _buildItemsList(items)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        backgroundColor: _gold,
        foregroundColor: _bgDark,
        tooltip: 'إضافة هالك',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: _gold.withValues(alpha: 0.2)),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 48,
              color: _gold,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'لا يوجد سجلات للمنتجات التالفة',
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'المخزون سليم — اضغط + لتسجيل أي تالف',
            style: TextStyle(fontSize: 14, color: _textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(int count, int totalQty, double totalLoss) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.withValues(alpha: 0.12),
            Colors.red.withValues(alpha: 0.04),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _buildStatItem('إجمالي السجلات', '$count', Icons.receipt_long),
          Container(
            height: 32,
            width: 1,
            color: Colors.red.withValues(alpha: 0.2),
          ),
          _buildStatItem('الكمية التالفة', '$totalQty', Icons.inventory),
          Container(
            height: 32,
            width: 1,
            color: Colors.red.withValues(alpha: 0.2),
          ),
          _buildStatItem(
            'إجمالي الخسارة',
            '${totalLoss.toStringAsFixed(2)} ج.م',
            Icons.money_off,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.red, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: _textMuted)),
        ],
      ),
    );
  }

  Widget _buildItemsList(List<DamagedItemWithProduct> items) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final itemWithProduct = items[index];
        final item = itemWithProduct.item;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + index * 50),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delete_sweep,
                      color: Colors.red,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemWithProduct.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.reason} · ${DateFormat('yyyy-MM-dd HH:mm').format(item.damageDate)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${item.totalLoss.toStringAsFixed(2)} ج.م',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Column(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.edit, size: 16, color: _gold),
                          onPressed: () => _showEditDialog(context, item),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                          onPressed: () => _showDeleteConfirm(context, item.id),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddDamagedItemDialog(db: widget.db),
    );
  }

  Future<void> _showEditDialog(BuildContext context, DamagedItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AddDamagedItemDialog(
        db: widget.db,
        existingItem: item,
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _showDeleteConfirm(BuildContext context, int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
        content: const Text(
          'هل تريد حذف هذا السجل؟',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.db.damagedItemsDao.deleteDamagedItem(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف السجل'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

class _AddDamagedItemDialog extends StatefulWidget {
  final AppDatabase db;
  final DamagedItem? existingItem;
  const _AddDamagedItemDialog({required this.db, this.existingItem});

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
  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.db.productDao.getAllProducts();
      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
          if (_isEditing) {
            _reasonController.text = widget.existingItem!.reason;
            _notesController.text = widget.existingItem!.notes ?? '';
            _quantityController.text = widget.existingItem!.quantity.toString();
            _selectedProduct = products.cast<Product?>().firstWhere(
              (p) => p!.id == widget.existingItem!.productId,
              orElse: () => null,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      final qty = int.tryParse(_quantityController.text) ?? 0;
      if (!_isEditing && qty > _selectedProduct!.quantity) {
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
        if (_isEditing) {
          await widget.db.damagedItemsDao.updateDamagedItem(
            DamagedItemsCompanion(
              id: drift.Value(widget.existingItem!.id),
              productId: drift.Value(_selectedProduct!.id),
              quantity: drift.Value(qty),
              unitCost: drift.Value(cost),
              totalLoss: drift.Value(loss),
              reason: drift.Value(_reasonController.text.trim().isEmpty
                  ? 'تالف'
                  : _reasonController.text.trim()),
              damageDate: drift.Value(DateTime.now()),
              notes: drift.Value(_notesController.text.trim()),
            ),
          );
          if (mounted) {
            Navigator.of(context).pop(true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم تحديث الهالك بنجاح.'),
                backgroundColor: _accentGreen,
              ),
            );
          }
        } else {
          await widget.db.transaction(() async {
            await widget.db.damagedItemsDao.insertDamagedItem(
              DamagedItemsCompanion.insert(
                productId: _selectedProduct!.id,
                quantity: qty,
                unitCost: cost,
                totalLoss: loss,
                reason: _reasonController.text.trim().isEmpty
                    ? 'تالف'
                    : _reasonController.text.trim(),
                damageDate: DateTime.now(),
                notes: drift.Value(_notesController.text.trim()),
              ),
            );

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
                backgroundColor: _accentGreen,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
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
      return AlertDialog(
        backgroundColor: _bgCard,
        content: const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator(color: _gold)),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: _bgCard,
      title: Row(
        children: [
          const Icon(Icons.delete_sweep, color: Colors.red),
          const SizedBox(width: 8),
          Text(
            _isEditing ? 'تعديل سجل هالك/تالف' : 'تسجيل منتج هالك/تالف',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Product>(
                  dropdownColor: _bgCard,
                  decoration: const InputDecoration(
                    labelText: 'المنتج',
                    labelStyle: TextStyle(color: _textMuted),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _gold),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
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
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'الكمية التالفة',
                    labelStyle: TextStyle(color: _textMuted),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _gold),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'يرجى إدخال الكمية';
                    if (int.tryParse(val) == null || int.parse(val) <= 0) {
                      return 'كمية غير صالحة';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reasonController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'السبب (مثال: منتهي الصلاحية، كسر...)',
                    labelStyle: TextStyle(color: _textMuted),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _gold),
                    ),
                  ),
                  validator: (val) =>
                      val == null || val.isEmpty ? 'يرجى تحديد السبب' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إضافية',
                    labelStyle: TextStyle(color: _textMuted),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _gold),
                    ),
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
          child: const Text('إلغاء', style: TextStyle(color: _textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: Text(_isEditing ? 'تحديث' : 'حفظ وتسجيل التالف'),
        ),
      ],
    );
  }
}
