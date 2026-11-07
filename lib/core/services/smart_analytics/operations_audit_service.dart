import 'package:drift/drift.dart';
import '../../database/app_database.dart';

class OperationsAuditItem {
  final String category; // 'custody' | 'manufacturing' | 'cash_session'
  final String referenceId; // Custody Number, MO Number, Session ID
  final String title;
  final String description;
  final int ageInDaysOrHours;
  final String severity; // 'critical' | 'warning' | 'info'
  final String actionRequired;

  const OperationsAuditItem({
    required this.category,
    required this.referenceId,
    required this.title,
    required this.description,
    required this.ageInDaysOrHours,
    required this.severity,
    required this.actionRequired,
  });
}

/// Service that audits unclosed operations: open custodies, lingering manufacturing stages, and forgotten open shifts.
class OperationsAuditService {
  final AppDatabase _db;

  OperationsAuditService(this._db);

  /// Runs the full operational audit.
  Future<List<OperationsAuditItem>> checkUnclosedOperations({
    DateTime? referenceDate,
    int custodyDaysThreshold = 3,
    int stageDaysThreshold = 3,
    int sessionHoursThreshold = 18,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final results = <OperationsAuditItem>[];

    // 1. Audit Cash Custodies (العهد المالية المفتوحة)
    try {
      final openCustodies = await (_db.select(_db.cashCustodies)
            ..where((c) => c.status.equals('open'))
            ..orderBy([(c) => OrderingTerm(expression: c.date, mode: OrderingMode.asc)]))
          .get();

      for (final custody in openCustodies) {
        final ageDays = now.difference(custody.date).inDays;
        if (ageDays >= custodyDaysThreshold) {
          final isCritical = ageDays >= 7 || custody.remainingAmount >= 5000;
          results.add(OperationsAuditItem(
            category: 'custody',
            referenceId: custody.custodyNumber,
            title: 'عهدة مالية معلقة: ${custody.custodyNumber}',
            description:
                'العهدة باسم (${custody.staffName}) بقيمة ${custody.amount.toStringAsFixed(0)} ج ومتبقي منها ${custody.remainingAmount.toStringAsFixed(0)} ج مفتوحة منذ $ageDays يوماً.',
            ageInDaysOrHours: ageDays,
            severity: isCritical ? 'critical' : 'warning',
            actionRequired: 'يُرجى استلام فواتير المصروفات وإجراء تسوية وإغلاق للعهدة المالية.',
          ));
        }
      }
    } catch (_) {
      // Ignore if table not present in some builds
    }

    // 2. Audit Manufacturing Stages & Orders (مراحل وأوامر التصنيع المعلقة)
    try {
      final inProgressStages = await (_db.select(_db.manufacturingStages)
            ..where((s) => s.status.equals('in_progress'))
            ..orderBy([(s) => OrderingTerm(expression: s.createdAt, mode: OrderingMode.asc)]))
          .get();

      for (final stage in inProgressStages) {
        final startTime = stage.startedAt ?? stage.createdAt;
        final ageDays = now.difference(startTime).inDays;
        if (ageDays >= stageDaysThreshold) {
          // Fetch parent order number if available
          final order = await (_db.select(_db.manufacturingOrders)
                ..where((o) => o.id.equals(stage.manufacturingOrderId)))
              .getSingleOrNull();

          final orderNumber = order?.orderNumber ?? 'MO-${stage.manufacturingOrderId}';
          final assigned = stage.assignedTo != null ? ' (${stage.assignedTo})' : '';

          results.add(OperationsAuditItem(
            category: 'manufacturing',
            referenceId: '$orderNumber-${stage.stageName}',
            title: 'مرحلة تصنيع متأخرة: ${stage.stageName}',
            description:
                'المرحلة التابعة للأمر $orderNumber$assigned جارية منذ $ageDays يوماً ولم تُقفل بعد.',
            ageInDaysOrHours: ageDays,
            severity: ageDays >= 7 ? 'critical' : 'warning',
            actionRequired: 'متابعة الورشة لتسجيل المخرجات وإغلاق المرحلة للانتقال للمرحلة التالية.',
          ));
        }
      }
    } catch (_) {
      // Ignore if manufacturing tables not active
    }

    // 3. Audit Cash Sessions (الورديات النقدية المنسية المفتوحة)
    try {
      final openSessions = await (_db.select(_db.cashSessions)
            ..where((s) => s.status.equals('open'))
            ..orderBy([(s) => OrderingTerm(expression: s.openedAt, mode: OrderingMode.asc)]))
          .get();

      for (final session in openSessions) {
        final hoursOpen = now.difference(session.openedAt).inHours;
        if (hoursOpen >= sessionHoursThreshold) {
          results.add(OperationsAuditItem(
            category: 'cash_session',
            referenceId: 'SESSION-${session.id}',
            title: 'وردية كاشير مفتوحة منذ $hoursOpen ساعة',
            description:
                'الوردية رقم ${session.id} التي فتحها (${session.openedBy ?? "الكاشير"}) مفتوحة منذ مدة غير طبيعية دون إغلاق.',
            ageInDaysOrHours: hoursOpen,
            severity: 'critical',
            actionRequired: 'يجب على الكاشير أو المشرف إغلاق الوردية ومطابقة النقدية.',
          ));
        }
      }
    } catch (_) {
      // Ignore if cash sessions not available
    }

    // Sort: critical first
    results.sort((a, b) {
      if (a.severity == 'critical' && b.severity != 'critical') return -1;
      if (a.severity != 'critical' && b.severity == 'critical') return 1;
      return b.ageInDaysOrHours.compareTo(a.ageInDaysOrHours);
    });

    return results;
  }
}
