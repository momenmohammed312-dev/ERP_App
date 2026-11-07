import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import '../../database/app_database.dart';
import '../settings_service.dart';
import 'predictive_stock_service.dart';
import 'financial_anomaly_service.dart';
import 'customer_retention_service.dart';
import 'staff_discipline_service.dart';
import 'supplier_payables_service.dart';
import 'operations_audit_service.dart';

/// Clean model representing a smart alert item displayed in the UI.
class SmartAlert {
  final int id;
  final String entityId;
  final String category; // 'stock' | 'finance' | 'customer' | 'staff' | 'supplier' | 'operations' | 'general'
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String urgency; // 'critical' | 'warning' | 'info'

  const SmartAlert({
    required this.id,
    required this.entityId,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.urgency,
  });
}

/// Central Orchestrator for Smart Analytics, Predictive Insights, and Notifications.
class SmartAdvisorService {
  final AppDatabase _db;
  final PredictiveStockService _stockService;
  final FinancialAnomalyService _anomalyService;
  final CustomerRetentionService _retentionService;
  final StaffDisciplineService _staffService;
  final SupplierPayablesService _supplierService;
  final OperationsAuditService _operationsAuditService;

  static DateTime? _lastRunTime;

  SmartAdvisorService(this._db)
      : _stockService = PredictiveStockService(_db),
        _anomalyService = FinancialAnomalyService(_db),
        _retentionService = CustomerRetentionService(_db),
        _staffService = StaffDisciplineService(_db),
        _supplierService = SupplierPayablesService(_db),
        _operationsAuditService = OperationsAuditService(_db);

  PredictiveStockService get stockService => _stockService;
  FinancialAnomalyService get anomalyService => _anomalyService;
  CustomerRetentionService get retentionService => _retentionService;
  StaffDisciplineService get staffService => _staffService;
  SupplierPayablesService get supplierService => _supplierService;
  OperationsAuditService get operationsAuditService => _operationsAuditService;

  /// Runs the full automatic analysis suite with a 2-hour throttle unless [force] is true.
  /// Returns a list of newly discovered alerts that can trigger non-intrusive notifications.
  Future<List<SmartAlert>> runAutomaticAnalysis({bool force = false}) async {
    final isEnabled = await SettingsService.isSmartAnalyticsEnabled();
    if (!isEnabled) return [];

    final now = DateTime.now();
    if (!force && _lastRunTime != null) {
      final hoursSinceLast = now.difference(_lastRunTime!).inHours;
      if (hoursSinceLast < 2) {
        return []; // Throttled to protect battery & CPU
      }
    }

    final newAlerts = <SmartAlert>[];

    try {
      _lastRunTime = now;

      // 1. Stock run-rate analysis
      final stockItems = await _stockService.analyzeStockRunRate();
      for (final item in stockItems) {
        if (item.urgency == 'out_of_stock') {
          final alert = await _upsertNotification(
            entityId: 'smart:stock:${item.productId}:${item.variantId ?? 0}',
            title: 'نفاد مخزون: ${item.productName}${item.variantName != null ? " (${item.variantName})" : ""}',
            body: 'رصيد الصنف حالياً 0. يُقترح طلب ${item.suggestedReorderQuantity} قطعة لتغطية مبيعات الأسبوعين القادمين.',
            urgency: 'critical',
          );
          if (alert != null) newAlerts.add(alert);
        } else if (item.urgency == 'critical') {
          final alert = await _upsertNotification(
            entityId: 'smart:stock:${item.productId}:${item.variantId ?? 0}',
            title: 'تنبيه وشيك: ${item.productName}${item.variantName != null ? " (${item.variantName})" : ""}',
            body: 'متبقي ${item.currentStock} قطعة. بمعدل بيعك (${item.dailyVelocity} ق/يوم)، سينفد المخزون خلال ${item.daysUntilStockout} يوم. يُقترح طلب ${item.suggestedReorderQuantity} قطعة.',
            urgency: 'critical',
          );
          if (alert != null) newAlerts.add(alert);
        } else if (item.urgency == 'warning') {
          final alert = await _upsertNotification(
            entityId: 'smart:stock:${item.productId}:${item.variantId ?? 0}',
            title: 'مخزون منخفض: ${item.productName}',
            body: 'الرصيد المتبقي يكفي قرابة ${item.daysUntilStockout} أيام بمعدل الاستهلاك الحالي.',
            urgency: 'warning',
          );
          if (alert != null) newAlerts.add(alert);
        }
      }

      // 2. Financial anomalies in shift / daily sales
      final anomalies = await _anomalyService.checkSessionAnomalies();
      for (final anomaly in anomalies) {
        final alert = await _upsertNotification(
          entityId: 'smart:finance:${anomaly.type}:${now.year}-${now.month}-${now.day}',
          title: anomaly.title,
          body: anomaly.description,
          urgency: anomaly.severity,
        );
        if (alert != null) newAlerts.add(alert);
      }

      // 3. Customer retention & broken purchase cadences
      final atRiskCustomers = await _retentionService.analyzeCustomerCadences();
      for (final customer in atRiskCustomers.take(5)) {
        final alert = await _upsertNotification(
          entityId: 'smart:customer:${customer.customerId}',
          title: 'عميل منقطع: ${customer.customerName}',
          body: 'انقطع عن الشراء منذ ${customer.daysSinceLastPurchase} يوماً (معدل تردده السابق كل ${customer.averageCadenceDays} يوم). ${customer.suggestedAction}.',
          urgency: customer.riskLevel == 'high' ? 'warning' : 'info',
        );
        if (alert != null) newAlerts.add(alert);
      }

      // 4. Customer credit accumulation without payment (سحب بضاعة بالآجل بدون سداد)
      final creditStagnantCustomers =
          await _retentionService.analyzeCreditAccumulationWithoutPayment();
      for (final customer in creditStagnantCustomers.take(5)) {
        final alert = await _upsertNotification(
          entityId: 'smart:customer:stagnation:${customer.customerId}',
          title: customer.title,
          body: customer.recommendation,
          urgency: customer.severity,
        );
        if (alert != null) newAlerts.add(alert);
      }

      // 5. Staff discipline (غياب متتالي أو تكرار تأخير الموظفين)
      final staffIssues = await _staffService.analyzeStaffDiscipline();
      for (final staff in staffIssues.take(5)) {
        final alert = await _upsertNotification(
          entityId: 'smart:staff:${staff.staffId}:${staff.issueType}',
          title: staff.title,
          body: staff.recommendation,
          urgency: staff.severity,
        );
        if (alert != null) newAlerts.add(alert);
      }

      // 6. Supplier overdue payables (مستحقات الموردين المتأخرة)
      final supplierPayables = await _supplierService.analyzeOverduePayables();
      for (final supplier in supplierPayables.take(5)) {
        final alert = await _upsertNotification(
          entityId: 'smart:supplier:${supplier.supplierId}',
          title: supplier.title,
          body: supplier.recommendation,
          urgency: supplier.severity,
        );
        if (alert != null) newAlerts.add(alert);
      }

      // 7. Operations Audit (العهد المالية المفتوحة، مراحل التصنيع المعلقة، الورديات المنسية)
      final operationsIssues =
          await _operationsAuditService.checkUnclosedOperations();
      for (final op in operationsIssues.take(5)) {
        final alert = await _upsertNotification(
          entityId: 'smart:operations:${op.category}:${op.referenceId}',
          title: op.title,
          body: '${op.description} - ${op.actionRequired}',
          urgency: op.severity,
        );
        if (alert != null) newAlerts.add(alert);
      }
    } catch (e, st) {
      debugPrint('Error in runAutomaticAnalysis: $e\n$st');
    }

    return newAlerts;
  }

  /// Upserts a notification without creating duplicate rows for the same issue.
  /// Returns the [SmartAlert] if newly created, or null if only updated.
  Future<SmartAlert?> _upsertNotification({
    required String entityId,
    required String title,
    required String body,
    required String urgency,
  }) async {
    // Check if an unread notification with this entityId already exists
    final existing = await (_db.select(_db.appNotifications)
          ..where((t) => t.entityId.equals(entityId))
          ..where((t) => t.sent.equals(0)))
        .get();

    final parts = entityId.split(':');
    final cat = parts.length > 1 ? parts[1] : 'general';

    if (existing.isNotEmpty) {
      // Update body and title in-place so user sees the freshest numbers
      await (_db.update(_db.appNotifications)
            ..where((t) => t.id.equals(existing.first.id)))
          .write(
        AppNotificationsCompanion(
          title: Value(title),
          body: Value(body),
          sendAt: Value(DateTime.now()),
        ),
      );
      return null;
    } else {
      final insertedId = await _db.into(_db.appNotifications).insert(
            AppNotificationsCompanion.insert(
              entityId: Value(entityId),
              title: title,
              body: body,
              sendAt: DateTime.now(),
              sent: const Value(0),
            ),
          );

      return SmartAlert(
        id: insertedId,
        entityId: entityId,
        category: cat,
        title: title,
        body: body,
        createdAt: DateTime.now(),
        isRead: false,
        urgency: urgency,
      );
    }
  }

  /// Fetches all active smart alerts formatted for display.
  Future<List<SmartAlert>> getActiveAlerts() async {
    final rows = await (_db.select(_db.appNotifications)
          ..where((t) => t.entityId.like('smart:%'))
          ..orderBy([(t) => OrderingTerm.desc(t.sendAt)]))
        .get();

    return rows.map((r) {
      final parts = (r.entityId ?? '').split(':');
      final cat = parts.length > 1 ? parts[1] : 'general';
      String urgency = 'info';
      if (r.title.contains('حرج') ||
          r.title.contains('نفاد') ||
          r.title.contains('وشيك') ||
          r.title.contains('مفتوحة منذ')) {
        urgency = 'critical';
      } else if (r.title.contains('تحذير') ||
          r.title.contains('منخفض') ||
          r.title.contains('منقطع') ||
          r.title.contains('غياب') ||
          r.title.contains('متأخرة') ||
          r.title.contains('معلقة')) {
        urgency = 'warning';
      }

      return SmartAlert(
        id: r.id,
        entityId: r.entityId ?? '',
        category: cat,
        title: r.title,
        body: r.body,
        createdAt: r.sendAt,
        isRead: r.sent == 1,
        urgency: urgency,
      );
    }).toList();
  }

  /// Returns total count of unread smart alerts.
  Future<int> getUnreadCount() async {
    final result = await _db.customSelect(
      '''
      SELECT COUNT(*) as unread_count 
      FROM app_notifications 
      WHERE entity_id LIKE 'smart:%' AND sent = 0
      ''',
    ).getSingle();

    return (result.data['unread_count'] as num?)?.toInt() ?? 0;
  }

  /// Marks a specific alert as read.
  Future<void> markAlertAsRead(int notificationId) async {
    await (_db.update(_db.appNotifications)
          ..where((t) => t.id.equals(notificationId)))
        .write(const AppNotificationsCompanion(sent: Value(1)));
  }

  /// Marks all smart alerts as read.
  Future<void> markAllAlertsAsRead() async {
    await (_db.update(_db.appNotifications)
          ..where((t) => t.entityId.like('smart:%')))
        .write(const AppNotificationsCompanion(sent: Value(1)));
  }

  /// Deletes a specific alert.
  Future<void> deleteAlert(int notificationId) async {
    await (_db.delete(_db.appNotifications)
          ..where((t) => t.id.equals(notificationId)))
        .go();
  }

  /// Generates a structured executive business summary (100% offline fallback, with optional Gemini enhancement).
  Future<String> generateExecutiveBrief() async {
    try {
      final stockItems = await _stockService.analyzeStockRunRate();
      final atRiskStock = stockItems.where((s) => s.urgency != 'healthy').toList();

      final anomalies = await _anomalyService.checkSessionAnomalies();
      final churnCustomers = await _retentionService.analyzeCustomerCadences();
      final creditStagnant = await _retentionService.analyzeCreditAccumulationWithoutPayment();
      final staffIssues = await _staffService.analyzeStaffDiscipline();
      final supplierPayables = await _supplierService.analyzeOverduePayables();
      final openOps = await _operationsAuditService.checkUnclosedOperations();

      // Check today's sales
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final salesResult = await _db.customSelect(
        '''
        SELECT COALESCE(SUM(total_amount), 0) as sales, COUNT(*) as invoices_count 
        FROM invoices WHERE date >= ? AND status != 'voided'
        ''',
        variables: [Variable.withDateTime(start)],
      ).getSingle();

      final todaySales = (salesResult.data['sales'] as num?)?.toDouble() ?? 0;
      final invoicesCount = (salesResult.data['invoices_count'] as num?)?.toInt() ?? 0;

      // Check if user has an optional free Gemini API key configured
      final geminiKey = await SettingsService.getGeminiApiKey();
      if (geminiKey != null && geminiKey.trim().isNotEmpty) {
        final aiSummary = await _callGeminiBrief(
          apiKey: geminiKey.trim(),
          todaySales: todaySales,
          invoicesCount: invoicesCount,
          atRiskStockCount: atRiskStock.length,
          anomaliesCount: anomalies.length,
          churnCount: churnCustomers.length + creditStagnant.length,
          staffIssuesCount: staffIssues.length,
          supplierPayablesCount: supplierPayables.length,
          openOpsCount: openOps.length,
        );
        if (aiSummary != null && aiSummary.isNotEmpty) {
          return aiSummary;
        }
      }

      // Default: High-quality local Arabic template (instant, 0 cost, 100% offline)
      return _buildLocalArabicBrief(
        todaySales: todaySales,
        invoicesCount: invoicesCount,
        atRiskStock: atRiskStock,
        anomalies: anomalies,
        churnCustomers: churnCustomers,
        creditStagnant: creditStagnant,
        staffIssues: staffIssues,
        supplierPayables: supplierPayables,
        openOps: openOps,
      );
    } catch (e) {
      debugPrint('Error generating executive brief: $e');
      return 'تعذر إعداد الملخص التنفيذي حالياً.';
    }
  }

  String _buildLocalArabicBrief({
    required double todaySales,
    required int invoicesCount,
    required List<StockPredictionItem> atRiskStock,
    required List<FinancialAnomalyItem> anomalies,
    required List<CustomerRetentionItem> churnCustomers,
    required List<CustomerCreditStagnationItem> creditStagnant,
    required List<StaffDisciplineItem> staffIssues,
    required List<SupplierPayableItem> supplierPayables,
    required List<OperationsAuditItem> openOps,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📊 ملخص الأداء والمستشار الذكي الشامل للمتجر');
    buffer.writeln('────────────────────────');
    buffer.writeln('• مبيعات اليوم: ${todaySales.toStringAsFixed(1)} ج عبر $invoicesCount فاتورة.');

    if (atRiskStock.isNotEmpty) {
      buffer.writeln('\n📦 استشراف المخزون:');
      buffer.writeln('هناك ${atRiskStock.length} أصناف تتطلب الانتباه السريع:');
      for (final s in atRiskStock.take(3)) {
        buffer.writeln('  - ${s.productName}: سينفد خلال ${s.daysUntilStockout} يوم (الرصيد: ${s.currentStock}).');
      }
    } else {
      buffer.writeln('\n📦 استشراف المخزون: حالة المخزون متزنة ولا توجد نواقص وشيكة.');
    }

    if (anomalies.isNotEmpty) {
      buffer.writeln('\n🛡️ الأمان المالي والورديات:');
      for (final a in anomalies) {
        buffer.writeln('  - ${a.title}: ${a.description}');
      }
    }

    if (creditStagnant.isNotEmpty || churnCustomers.isNotEmpty) {
      buffer.writeln('\n👥 العملاء والائتمان:');
      if (creditStagnant.isNotEmpty) {
        buffer.writeln('  - ${creditStagnant.length} عملاء يسحبون بالآجل دون سداد منذ فترة.');
      }
      if (churnCustomers.isNotEmpty) {
        buffer.writeln('  - ${churnCustomers.length} عملاء كسروا وتيرة شرائهم المعتادة.');
      }
    }

    if (supplierPayables.isNotEmpty) {
      buffer.writeln('\n🚚 مستحقات الموردين:');
      buffer.writeln('  - ${supplierPayables.length} موردين لديهم مستحقات متأخرة تجاوزت 15 يوماً دون سداد.');
    }

    if (staffIssues.isNotEmpty) {
      buffer.writeln('\n👔 الموظفين والحضور:');
      for (final s in staffIssues.take(2)) {
        buffer.writeln('  - ${s.title}: ${s.recommendation}');
      }
    }

    if (openOps.isNotEmpty) {
      buffer.writeln('\n⚙️ العمليات المفتوحة والعهد:');
      for (final op in openOps.take(3)) {
        buffer.writeln('  - ${op.title}: ${op.description}');
      }
    }

    return buffer.toString();
  }

  Future<String?> _callGeminiBrief({
    required String apiKey,
    required double todaySales,
    required int invoicesCount,
    required int atRiskStockCount,
    required int anomaliesCount,
    required int churnCount,
    required int staffIssuesCount,
    required int supplierPayablesCount,
    required int openOpsCount,
  }) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
      );

      final prompt = '''
أنت مستشار أعمال تنفيذي ذكي لنظام إدارة متجر ونقاط بيع ERP.
اكتب تقريراً صباحياً ذكياً مختصراً باللغة العربية (4-5 أسطر فقط) لمدير المنشأة بناءً على هذه الأرقام المجردة:
- مبيعات اليوم: $todaySales ج ($invoicesCount فاتورة)
- أصناف قاربت على النفاد: $atRiskStockCount
- انحرافات ورديات وأمان مالي: $anomaliesCount
- عملاء متوقفين أو ساحبين آجل بدون سداد: $churnCount
- مستحقات موردين متأخرة: $supplierPayablesCount
- ملاحظات انضباط موظفين (غياب/تأخير): $staffIssuesCount
- عهد مالية أو مراحل تصنيع معلقة: $openOpsCount

اجعل الأسلوب تنفيذياً راقياً، عملياً، واختتم بنصيحة توجيهية محددة لليوم. لا تذكر أي تفاصيل فنية أو برمجية.
''';

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text'] as String?;
          }
        }
      }
    } catch (e) {
      debugPrint('Gemini brief fallback to local template: $e');
    }
    return null;
  }
}
