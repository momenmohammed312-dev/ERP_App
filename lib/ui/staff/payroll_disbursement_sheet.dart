import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';
import 'package:pos_offline_desktop/ui/staff/services/staff_payroll_statement_generator.dart';

/// شيت مستند الصرف — مختصر: المستحق + سطرا الاستبعاد (مدفوع/منتهٍ) فقط.
/// الاعتماد ثم الصرف بقيد إجمالي واحد، مع طباعة الوثيقة والقسائم.
class PayrollDisbursementSheet extends ConsumerStatefulWidget {
  final String period;
  final Map<String, Staff> staffMap;
  final Set<int> selectedIds;
  final VoidCallback onChanged;
  final VoidCallback onPrintSlips;

  const PayrollDisbursementSheet({
    super.key,
    required this.period,
    required this.staffMap,
    this.selectedIds = const {},
    required this.onChanged,
    required this.onPrintSlips,
  });

  @override
  ConsumerState<PayrollDisbursementSheet> createState() =>
      _PayrollDisbursementSheetState();
}

class _PayrollDisbursementSheetState
    extends ConsumerState<PayrollDisbursementSheet> {
  String _method = 'cash';
  bool _busy = false;
  bool _loading = true;
  DisbursementBreakdown? _breakdown;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      final b = await service.getDisbursementBreakdown(
        widget.period,
        onlyIds: widget.selectedIds,
      );
      if (mounted) setState(() => _breakdown = b);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _methodLabel {
    switch (_method) {
      case 'bank_transfer':
        return 'تحويل بنكي';
      case 'check':
        return 'شيك';
      default:
        return 'نقداً';
    }
  }

  Future<void> _approveAll() async {
    final user = ref.read(authProvider);
    setState(() => _busy = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      final n = await service.approvePayrollsForPeriod(
        user,
        widget.period,
        onlyIds: widget.selectedIds,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0 ? 'لا توجد مرتبات تحتاج اعتماداً' : 'تم اعتماد $n مرتب',
          ),
          backgroundColor: Colors.blue,
        ),
      );
      widget.onChanged();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payAll() async {
    final user = ref.read(authProvider);
    setState(() => _busy = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      final result = await service.payPayrollsForPeriod(
        user,
        widget.period,
        _method,
        onlyIds: widget.selectedIds,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: result.count == 0
              ? const Text('لا توجد مرتبات مستحقة للصرف')
              : Text(
                  '${result.voucherNo}: صرف ${result.count} — ${result.total.toStringAsFixed(0)} ($_methodLabel)',
                ),
          backgroundColor: Colors.green,
        ),
      );
      widget.onChanged();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printVoucher() async {
    final b = _breakdown;
    if (b == null) return;
    try {
      final db = ref.read(appDatabaseProvider);
      await StaffPayrollStatementGenerator.generateAndPrintBatchVoucher(
        context: context,
        db: db,
        period: widget.period,
        voucherNo: b.voucherNo,
        payrolls: b.payable,
        staffMap: widget.staffMap,
        paidCount: b.paidCount,
        paidTotal: b.paidTotal,
        excludedCount: b.excludedCount,
        excludedTotal: b.excludedTotal,
        methodLabel: _methodLabel,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _breakdown;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'مستند صرف ${widget.period}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            if (b != null)
              Text(
                b.voucherNo,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            if (widget.selectedIds.isNotEmpty)
              Text(
                'نطاق المحدد بالشيك بوكس: ${widget.selectedIds.length}',
                style: TextStyle(
                  color: Colors.teal.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (b != null) ...[
              Text(
                b.payableTotal.toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              Text(
                'المستحق: ${b.payableCount} موظف',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'مدفوع مسبقاً (مستبعد): ${b.paidCount} • ${b.paidTotal.toStringAsFixed(0)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              Text(
                'منتهية خدمتهم (مستبعد): ${b.excludedCount} • ${b.excludedTotal.toStringAsFixed(0)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('نقداً')),
                ButtonSegment(value: 'bank_transfer', label: Text('تحويل')),
                ButtonSegment(value: 'check', label: Text('شيك')),
              ],
              selected: {_method},
              onSelectionChanged: (_busy || _loading)
                  ? null
                  : (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (_busy || _loading || (b?.payableCalculated ?? 0) == 0)
                        ? null
                        : _approveAll,
                    icon: const Icon(Icons.verified),
                    label: Text('اعتماد (${b?.payableCalculated ?? 0})'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (_busy || _loading || (b?.payableCount ?? 0) == 0)
                        ? null
                        : _payAll,
                    icon: const Icon(Icons.payments, color: Colors.white),
                    label: const Text(
                      'صرف المستحق',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: (_busy || _loading || b == null)
                        ? null
                        : _printVoucher,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('طباعة المستند'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: (_busy || _loading)
                        ? null
                        : () {
                            Navigator.pop(context);
                            widget.onPrintSlips();
                          },
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة القسائم'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
