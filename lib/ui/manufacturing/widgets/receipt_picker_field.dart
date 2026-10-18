import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Searchable customer-material-receipt picker (primary entry for
/// manufacturing-for-others: "الاستلام من العميل").
///
/// Searches by receipt number/code, customer name, customer ID and customer
/// phone. Participates in [Form] validation via [FormField]. The results
/// list is height-constrained so it cannot overflow the dialog/page.
class ReceiptPickerField extends StatefulWidget {
  final AppDatabase db;
  final String label;
  final int? initialReceiptId;
  final ValueChanged<CustomerMaterialReceipt?> onChanged;
  final String? Function(CustomerMaterialReceipt?)? validator;
  final bool enabled;

  const ReceiptPickerField({
    super.key,
    required this.db,
    required this.label,
    required this.onChanged,
    this.initialReceiptId,
    this.validator,
    this.enabled = true,
  });

  @override
  State<ReceiptPickerField> createState() => _ReceiptPickerFieldState();
}

class _ReceiptPickerFieldState extends State<ReceiptPickerField> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<CustomerMaterialReceipt> _receipts = [];
  Map<String, Customer> _customerMap = {};
  List<CustomerMaterialReceipt> _results = [];
  CustomerMaterialReceipt? _selected;
  bool _loading = true;
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReceiptPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialReceiptId != widget.initialReceiptId) {
      _applyInitial();
    }
  }

  Future<void> _load() async {
    try {
      final receipts =
          await widget.db.customerMaterialReceiptDao.getAllReceipts();
      final customers =
          await widget.db.customerDao.getCustomersForManufacturing();
      if (!mounted) return;
      setState(() {
        _receipts = receipts;
        _customerMap = {for (var c in customers) c.id: c};
        _loading = false;
      });
      _applyInitial();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyInitial() {
    final id = widget.initialReceiptId;
    if (id == null) return;
    final match = _receipts.where((r) => r.id == id);
    if (match.isNotEmpty && _selected?.id != id) {
      setState(() => _selected = match.first);
    }
  }

  void _search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || !widget.enabled) return;
      final q = query.trim().toLowerCase();
      setState(() {
        if (q.isEmpty) {
          _results = List.of(_receipts);
        } else {
          _results = _receipts.where((r) {
            final c = _customerMap[r.customerId];
            final hay =
                '${r.receiptNumber} ${c?.name ?? ''} ${r.customerId} ${c?.phone ?? ''}'
                    .toLowerCase();
            return hay.contains(q);
          }).toList();
        }
        _searchOpen = true;
      });
    });
  }

  void _select(FormFieldState<CustomerMaterialReceipt?> field,
      CustomerMaterialReceipt r) {
    setState(() {
      _selected = r;
      _searchOpen = false;
      _searchCtrl.clear();
      _results = [];
    });
    field.didChange(r);
    widget.onChanged(r);
  }

  void _clear(FormFieldState<CustomerMaterialReceipt?> field) {
    setState(() {
      _selected = null;
      _results = [];
      _searchOpen = false;
    });
    _searchCtrl.clear();
    field.didChange(null);
    widget.onChanged(null);
  }

  String _subtitle(CustomerMaterialReceipt r) {
    final c = _customerMap[r.customerId];
    final date = DateFormat('yyyy/MM/dd').format(r.receivedDate);
    return '${c?.name ?? r.customerId} • $date';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormField<CustomerMaterialReceipt?>(
      initialValue: _selected,
      validator: widget.validator,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_selected != null)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: widget.label,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.input),
                  errorText: field.errorText,
                  suffixIcon: widget.enabled
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'تغيير الإذن',
                          onPressed: () => _clear(field),
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selected!.receiptNumber,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _subtitle(_selected!),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              TextField(
                controller: _searchCtrl,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: 'ابحث برقم الإذن أو العميل…',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  errorText: field.errorText,
                ),
                onChanged: _search,
                onTap: () {
                  if (!widget.enabled) return;
                  if (_results.isEmpty) {
                    _search(_searchCtrl.text);
                  } else {
                    setState(() => _searchOpen = true);
                  }
                },
              ),
            if (_selected == null &&
                !_loading &&
                _searchOpen &&
                widget.enabled) ...[
              const Gap(4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _results.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('لا توجد أذونات مطابقة',
                              textAlign: TextAlign.center),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _results.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _results[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.receipt_long),
                              title: Text(
                                r.receiptNumber,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                _subtitle(r),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _select(field, r),
                            );
                          },
                        ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
