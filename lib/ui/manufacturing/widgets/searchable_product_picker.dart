import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Searchable product picker for manufacturing dialogs.
///
/// Replaces unbounded [DropdownButtonFormField] product lists (long product
/// names overflowed the dialog/page). Searches by name/barcode through
/// [ProductDao.searchProducts], always excludes soft-deleted products, and
/// keeps the results list height-constrained so it cannot overflow.
///
/// Participates in [Form] validation via [FormField].
class SearchableProductPicker extends StatefulWidget {
  final AppDatabase db;
  final String label;
  final int? initialProductId;
  final ValueChanged<Product?> onChanged;
  final String? Function(Product?)? validator;
  final bool enabled;
  final String? helperText;

  const SearchableProductPicker({
    super.key,
    required this.db,
    required this.label,
    required this.onChanged,
    this.initialProductId,
    this.validator,
    this.enabled = true,
    this.helperText,
  });

  @override
  State<SearchableProductPicker> createState() =>
      _SearchableProductPickerState();
}

class _SearchableProductPickerState extends State<SearchableProductPicker> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Product> _results = [];
  Product? _selected;
  bool _loading = false;
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void didUpdateWidget(SearchableProductPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialProductId != widget.initialProductId) {
      _loadInitial();
    }
  }

  Future<void> _loadInitial() async {
    final id = widget.initialProductId;
    if (id == null) {
      if (mounted && _selected != null) {
        setState(() => _selected = null);
      }
      return;
    }
    if (_selected?.id == id) return;
    try {
      final p = await widget.db.productDao.getProductById(id);
      if (mounted) setState(() => _selected = p);
    } catch (_) {
      // keep previous selection on error
    }
  }

  Future<void> _search(String query) async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted || !widget.enabled) return;
      setState(() => _loading = true);
      try {
        final found = await widget.db.productDao.searchProducts(query);
        if (!mounted) return;
        setState(() {
          _results =
              found.where((p) => p.status != 'Deleted').toList();
          _loading = false;
          _searchOpen = true;
        });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _select(FormFieldState<Product?> field, Product p) {
    setState(() {
      _selected = p;
      _searchOpen = false;
      _searchCtrl.clear();
      _results = [];
    });
    field.didChange(p);
    widget.onChanged(p);
  }

  void _clear(FormFieldState<Product?> field) {
    setState(() {
      _selected = null;
      _results = [];
      _searchOpen = false;
    });
    _searchCtrl.clear();
    field.didChange(null);
    widget.onChanged(null);
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
    return FormField<Product?>(
      initialValue: _selected,
      validator: widget.validator,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selected != null)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: widget.label,
                  border: const OutlineInputBorder(),
                  helperText: widget.helperText,
                  errorText: field.errorText,
                  suffixIcon: widget.enabled
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'تغيير المنتج',
                          onPressed: () => _clear(field),
                        )
                      : null,
                ),
                child: Text(
                  _selected!.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              )
            else
              TextField(
                controller: _searchCtrl,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: 'ابحث بالاسم أو الباركود…',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  helperText: widget.helperText,
                  errorText: field.errorText,
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _search,
                onTap: () {
                  if (_results.isEmpty && widget.enabled) {
                    _search(_searchCtrl.text);
                  } else if (widget.enabled) {
                    setState(() => _searchOpen = true);
                  }
                },
              ),
            if (_selected == null && _searchOpen && widget.enabled) ...[
              const Gap(4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _results.isEmpty && !_loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('لا توجد نتائج مطابقة',
                              textAlign: TextAlign.center),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _results.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = _results[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${p.quantity} ${p.unit ?? ''}'
                                '${p.barcode != null && p.barcode!.isNotEmpty ? ' • ${p.barcode}' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _select(field, p),
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
