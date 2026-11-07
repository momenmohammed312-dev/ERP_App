import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import '../../database/app_database.dart';
import '../settings_service.dart';
import 'predictive_stock_service.dart';
import 'financial_anomaly_service.dart';
import 'customer_retention_service.dart';

/// Clean model representing a smart alert item displayed in the UI.
class SmartAlert {
  final int id;
  final String entityId;
  final String category; // 'stock' | 'finance' | 'customer' | 'general'
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

  static DateTime? _lastRunTime;

  SmartAdvisorService(this._db)
      : _stockService = PredictiveStockService(_db),
        _anomalyService = FinancialAnomalyService(_db),
        _retentionService = CustomerRetentionService(_db);

  PredictiveStockService get stockService => _stockService;
  FinancialAnomalyService get anomalyService => _anomalyService;
  CustomerRetentionService get retentionService => _retentionService;

  /// Runs the full automatic analysis suite with a 2-hour throttle unless [force] is true.
  Future<void> runAutomaticAnalysis({bool force = false}) async {
    final isEnabled = await SettingsService.isSmartAnalyticsEnabled();
    if (!isEnabled) return;

    final now = DateTime.now();
    if (!force && _lastRunTime != null) {
      final hoursSinceLast = now.difference(_lastRunTime!).inHours;
      if (hoursSinceLast < 2) {
        return; // Throttled to protect battery & CPU
      }
    }

    try {
      _lastRunTime = now;

      // 1. Stock run-rate analysis
      final stockItems = await _stockService.analyzeStockRunRate();
      for (final item in stockItems) {
        if (item.urgency == 'out_of_stock') {
          await _upsertNotification(
            entityId: 'smart:stock:${item.productId}:${item.variantId ?? 0}',
            title: 'نفاد مخزون: ${item.productName}${item.variantName != null ? " (${item.variantName})" : ""}',
            body: 'رصيد الصنف حالياً 0. يُقترح طلب ${item.suggestedReorderQuantity} قطعة لتغطية مبيعات الأسبوعين القادمين.',
            urgency: 'critical',
          );
        } else if (item.urgency == 'critical') {
          await _upsertNotification(
            entityId: 'smart:stock:${item.productId}:${item.variantId ?? 0}',
            title: 'تنبيه وشيك: ${item.productName}${item.variantName != null ? " (${item.variantName})" : ""}',
            body: 'متبقي ${item.currentStock} قطعة. بمعدل بيعك (${item.dailyVelocity} ق/يوم)، سينفد المخزون خلال ${item.daysUntilStockout} يوم. يُقترح طلب ${item.suggestedReorderQuantity} قطعة.',
            urgency: 'critical',
          );
        } else if (item.urgency == 'warning') {
          await _upsertNotification(
            entityId: 'smart:stock:${item.productId}:${item.variantId ?? 0}',
            title: 'مخزون منخفض: ${item.productName}',
            body: 'الرصيد المتبقي يكفي قرابة ${item.daysUntilStockout} أيام بمعدل الاستهلاك الحالي.',
            urgency: 'warning',
          );
        }
      }

      // 2. Financial anomalies in shift / daily sales
      final anomalies = await _anomalyService.checkSessionAnomalies();
      for (final anomaly in anomalies) {
        await _upsertNotification(
          entityId: 'smart:finance:${anomaly.type}:${now.year}-${now.month}-${now.day}',
          title: anomaly.title,
          body: anomaly.description,
          urgency: anomaly.severity,
        );
      }

      // 3. Customer retention & cadence analysis
      final atRiskCustomers = await _retentionService.analyzeCustomerCadences();
      for (final customer in atRiskCustomers.take(5)) {
        await _upsertNotification(
          entityId: 'smart:customer:${customer.customerId}',
          title: 'عميل منقطع: ${customer.customerName}',
          body: 'انقطع عن الشراء منذ ${customer.daysSinceLastPurchase} يوماً (معدل تردده السابق كل ${customer.averageCadenceDays} يوم). ${customer.suggestedAction}.',
          urgency: customer.riskLevel == 'high' ? 'warning' : 'info',
        );
      }
    } catch (e, st) {
      debugPrint('Error in runAutomaticAnalysis: $e\n$st');
    }
  }

  /// Upserts a notification without creating duplicate rows for the same issue.
  Future<void> _upsertNotification({
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
    } else {
      await _db.into(_db.appNotifications).insert(
            AppNotificationsCompanion.insert(
              entityId: Value(entityId),
              title: title,
              body: body,
              sendAt: DateTime.now(),
              sent: const Value(0),
            ),
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
      if (r.title.contains('حرج') || r.title.contains('نفاد') || r.title.contains('وشيك')) {
        urgency = 'critical';
      } else if (r.title.contains('تحذير') || r.title.contains('منخفض') || r.title.contains('منقطع')) {
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
          churnCount: churnCustomers.length,
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
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📊 ملخص الأداء والمستشار الذكي للمتجر');
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
    } else {
      buffer.writeln('\n🛡️ الأمان المالي: معدلات المرتجعات والإلغاءات ضمن الحدود الطبيعية.');
    }

    if (churnCustomers.isNotEmpty) {
      buffer.writeln('\n👥 متابعة العملاء:');
      buffer.writeln('هناك ${churnCustomers.length} عملاء كسروا وتيرة شرائهم المعتادة، نوصي بالتواصل معهم.');
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
  }) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
      );

      final prompt = '''
أنت مستشار أعمال ذكي لنظام نقاط بيع ERP.
اكتب تقريراً تنفيذياً صباحياً مختصراً باللغة العربية (3-4 أسطر فقط) لمدير المحل بناءً على هذه الأرقام المجردة:
- مبيعات اليوم: $todaySales ج
- عدد الفواتير: $invoicesCount
- أصناف معرضة للنفاد قريباً: $atRiskStockCount
- تنبيهات شذوذ مالي أو مرتجعات: $anomaliesCount
- عملاء متوقفين عن الشراء: $churnCount

اجعل الأسلوب تشجيعياً، عملياً، واختتم بنصيحة تركيز محددة لليوم. لا تذكر أي تفاصيل فنية.
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
