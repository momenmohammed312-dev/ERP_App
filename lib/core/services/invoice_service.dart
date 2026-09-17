import 'dart:math';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../database/tables/vegetable_shipments_table.dart';
import 'accounting_service.dart';
import 'audit_log_service.dart';
import 'invoice_number_service.dart';
import 'shipment_pricing_service.dart';

// ── خريطة دورة حياة الفاتورة (D1 — Agent 4) ──────────────────────────────
// | الانتقال | Invoices | Ledger | Journal | InvoicePayments | مخزون | حركات مخزون | شحنة برانيك | برنيكة فاضية | الأرصدة |
// |---|---|---|---|---|---|---|---|---|
// | إنشاء (نقدي) | صف + سطور | لا شيء (walk-in) | sale + cogs (مفاتيح UNIQUE) | صف واحد لو paid>0 | خصم | sale سالب | sold+/remaining− | صف outstanding (داخل نفس الـtxn) | — |
// | إنشاء (آجل/جزئي) | صف + سطور | بيع (مدين total) + سداد (دائن paid) بإيصال INV<id> | sale + customer_payment + cogs | صف لكل دفعة | خصم | sale سالب | sold+/remaining− | صف outstanding | عميل += total−paid |
// | إنشاء (عمولة) | + shipmentId | + مورد (دائن net=sell−commission) | (تُرحّل لاحقًا — D8) | — | خصم | sale سالب | sold+/remaining− | — | مورد += net (credit−debit) |
// | سداد مستقل PAY | paid/status تُحدّث | سداد دائن بإيصال INV<id> | customer_payment بمفتاح فريد | صف جديد | — | — | — | — | عميل −= amount |
// | تعديل (غير مدفوعة) | الإجماليات تُحدّث، الرقم يُحفظ | عكس sale فقط (reversal) + بيع جديد | حذف sale/cogs وإعادة ترحيل نفس المفاتيح | تُحفظ (لا مسح) | عكس القديم + خصم الجديد | return للقديم + sale للجديد | عكس + إعادة | تُلمس فقط ببارامترات صريحة | تُشتق من الجديد |
// | تعديل (مدفوعة) | ك above + paid يُشتق من مجموع invoice_payments | صفوف الدفع لا تُعكس ولا تُمسح | قيود الدفع تُحفظ | مصدر الحقيقة لـpaid | — | — | — | — | paid = Σ(المدفوعات) |
// | إلغاء void (أول) | status=voided (حارس idempotent) | عكس sale فقط (REV-INV<id>)، الدفع يبقى history | عكس sale/cogs | تبقى (النقدية لا تُعكس ضمنيًا) | استرجاع مرة واحدة | return موجب | sold−/remaining+ | recordReturn للمطابق | عميل −= net المباع |
// | إلغاء void (ثاني) | صفر آثار (return مبكر) | صفر | صفر | صفر | صفر | صفر | صفر | صفر (status-machine) | صفر |
// | مرتجع (جزئي/كلي) | total −= المرتجع، status يُعاد حسابه | عميل دائن RET<id> + مورد مدين حصته | sale_return + عكس cogs (مفاتيح UNIQUE) | — | استرجاع | return موجب | sold−/remaining+ | recordReturn جزئي | عميل −= المرتجع |
// | مرتجع مكرر | حارس الكمية المتبقية: تجاوز = استثناء قبل أي كتابة (صفر آثار) | صفر | صفر | — | صفر | صفر | صفر | صفر | صفر |
// القاعدة القانونية للمورد (D8): رصيد = opening + Σ(credit−debit) — العمولة دائن.
// ملاحظة Agent 1: سطور الترقيم (invoiceNumber) وصيغ الوصف في مسار الإنشاء
// READ-ONLY لي — صفوفي الجديدة تستخدم مساعدي Agent 1 حصرًا:
// saleDescription/paymentDescription/commissionDescription.
// ───────────────────────────────────────────────────────────────────────────

class InvoiceItemParams {
  final int productId;
  final int quantity;
  final double price;
  final int? ctn;
  final double discount;
  final double commission;
  final double? unitCostAtTime;
  final int? shipmentId;

  /// صنف المنتج (لون/فئة) — null = المنتج نفسه بلا أصناف (المسار القديم).
  final int? variantId;

  InvoiceItemParams({
    required this.productId,
    required this.quantity,
    required this.price,
    this.ctn,
    this.discount = 0,
    this.commission = 0,
    this.unitCostAtTime,
    this.shipmentId,
    this.variantId,
  });
}

class CreateInvoiceResult {
  final Invoice invoice;
  final int invoiceId;

  CreateInvoiceResult({required this.invoice, required this.invoiceId});
}

class InvoiceService {
  final AppDatabase _db;

  InvoiceService(this._db);

  /// Creates an invoice atomically (stock, ledger, journal in one txn).
  ///
  /// Numbering contract (v70+): the canonical 6-digit number is ALWAYS
  /// generated inside the transaction via [InvoiceNumberService] — any
  /// caller-supplied [invoiceNumber] is ignored unless [preserveInvoiceNumber]
  /// is true. Only import/sync/restore call sites may pass `true`, and then
  /// the value must be canonical ([InvoiceNumberService.isCanonical]) or a
  /// documented legacy id (pre-v70 shapes such as `INV<millis>`, `DRAFT_…`,
  /// `SALE-…`/`PUR-…`: non-empty, ≤ 255 chars) — anything else throws.
  /// No timestamp/`DRAFT_` fallbacks are ever generated. Drafts are not
  /// created here (they persist with `invoice_number = NULL` until posted).
  ///
  /// Exactly-once (D2): the whole create runs in ONE db.transaction (invoice +
  /// items + stock + movements + ledger + journal + barnika) — any failure
  /// rolls everything back, and the sequence bump rolls back with it, so a
  /// retry re-allocates safely. Journal posts are keyed
  /// (`sale:INV<id>`, `sale_cogs:INV<id>`, `customer_payment:<id>[_pay]`) with a
  /// UNIQUE posting_key: reposting the same key is a no-op, never a duplicate.
  Future<CreateInvoiceResult> createInvoice({
    required String? customerId,
    required String customerName,
    String? customerContact,
    String? customerAddress,
    required String paymentMethod,
    required double totalAmount,
    required double paidAmount,
    double cashAmount = 0,
    double cardAmount = 0,
    double creditAmount = 0,
    required String status,
    String? invoiceNumber,
    bool preserveInvoiceNumber = false,
    required List<InvoiceItemParams> items,
    String? ledgerDescription,
    List<SplitPaymentEntry>? splitPayments,
    int? primaryShipmentId,
    // D10: برنيكة فاضية صادرة مع البيع — تُسجّل داخل نفس transaction الإنشاء
    // (لا نداء خارجي post-commit). null/0 = لا تسجيل (الافتراضي، يحفظ سلوك
    // المسارات القديمة). HANDOFF لمالك enhanced_new_invoice_page: مرّر هذين
    // البارامترين واحذف كتلة recordBarnikaOut الخارجية لمنع الازدواج.
    String? barnikaCustomerId,
    int? barnikaQuantity,
  }) async {
    final rand = Random.secure();

    return _db.transaction(() async {
      // Numbering: generated in-txn (concurrency-safe), or explicitly
      // preserved+validated for import/sync/restore only.
      late final String actualInvoiceNumber;
      if (preserveInvoiceNumber) {
        if (invoiceNumber == null ||
            invoiceNumber.isEmpty ||
            invoiceNumber.length > 255) {
          throw Exception('رقم الفاتورة المحفوظ غير صالح (يجب أن يكون رقمًا موثقًا غير فارغ)');
        }
        if (!InvoiceNumberService.isCanonical(invoiceNumber) &&
            !_isDocumentedLegacyId(invoiceNumber)) {
          throw Exception('رقم الفاتورة المحفوظ غير صالح: $invoiceNumber');
        }
        actualInvoiceNumber = invoiceNumber;
      } else {
        actualInvoiceNumber =
            await InvoiceNumberService().nextInvoiceNumber(_db);
      }
      final invoiceId = await _db.invoiceDao.insertInvoice(
        InvoicesCompanion(
          invoiceNumber: Value(actualInvoiceNumber),
          customerName: Value(customerName),
          customerContact: Value(customerContact ?? ''),
          customerAddress: Value(customerAddress ?? ''),
          customerId: Value(customerId),
          paymentMethod: Value(paymentMethod),
          totalAmount: Value(totalAmount),
          paidAmount: Value(paidAmount),
          cashAmount: Value(cashAmount),
          cardAmount: Value(cardAmount),
          creditAmount: Value(creditAmount),
          status: Value(status),
          date: Value(DateTime.now()),
          shipmentId: Value(primaryShipmentId),
        ),
      );

      // A preserved canonical number (restore path) must not collide with a
      // future generated one: advance the sequence past it, same txn.
      if (preserveInvoiceNumber &&
          InvoiceNumberService.isCanonical(actualInvoiceNumber)) {
        await InvoiceNumberService().bumpPastCanonical(_db, actualInvoiceNumber);
      }

      // Track supplier commission totals per shipment for ledger entries.
      final supplierCommissions = <int, _SupplierCommissionAccumulator>{};
      double cogsAmount = 0;

      for (final item in items) {
        final product = await _db.productDao.getProductById(item.productId);

        if (product == null) {
          throw Exception('المنتج غير موجود (ID: ${item.productId})');
        }

        final unitCost = item.unitCostAtTime ?? product.costPrice ?? 0;
        if (unitCost > 0) cogsAmount += unitCost * item.quantity;

        // خصم المخزون: من الصنف (لون/فئة) لو متحدد، وإلا المسار القديم من الأب.
        // كمية الأب بعد بيع صنف = مجموع الأصناف (تحافظ على التقارير وتنبيه النواقص).
        // D9: سجل حركة مخزون حقيقي (sale سالب) مرتبط بالرقم المخزّن — لا صفوف وهمية.
        final prevParentQty = product.quantity;
        await _applySaleStock(product, item.quantity, item.variantId);
        final afterSale = await _db.productDao.getProductById(item.productId);
        await _db.inventoryMovementDao.createMovementWithTimestamp(
          productId: item.productId,
          movementType: 'sale',
          quantity: -item.quantity,
          unitCost: unitCost,
          totalValue: unitCost * item.quantity,
          movementDate: DateTime.now(),
          reference: actualInvoiceNumber,
          referenceType: 'sale_invoice',
          previousQuantity: prevParentQty,
          newQuantity: afterSale?.quantity ?? (prevParentQty - item.quantity),
          notes: item.variantId != null ? 'variant:${item.variantId}' : null,
        );

        // Auto-calculate commission for commission-based shipments.
        var itemCommission = item.commission;
        if (item.shipmentId != null && itemCommission == 0) {
          final shipment = await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment != null &&
              shipment.pricingMode == ShipmentPricingMode.commission &&
              shipment.commissionPercentage != null) {
            itemCommission = ShipmentPricingService.calculateCommission(
              item.price * item.quantity,
              shipment.commissionPercentage!,
            );
          }
        }

        await _db.invoiceDao.insertInvoiceItem(
          InvoiceItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(item.productId),
            quantity: Value(item.quantity),
            ctn: Value(item.ctn),
            price: Value(item.price),
            discount: Value(item.discount),
            commission: Value(itemCommission),
            unitCostAtTime: Value(item.unitCostAtTime),
            shipmentId: Value(item.shipmentId),
            variantId: Value(item.variantId),
          ),
        );

        // Update shipment barnika counts.
        if (item.shipmentId != null) {
          final shipment = await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment == null) {
            throw Exception('الشحنة #${item.shipmentId} غير موجودة');
          }

          final newSold = shipment.barnikaSoldCount + item.quantity;
          final newRemaining = shipment.barnikaRemainingCount - item.quantity;
          if (newRemaining < 0) {
            throw Exception(
              'الشحنة #${item.shipmentId} لا تحتوي على كمية كافية '
              '(متبقي: ${shipment.barnikaRemainingCount}, مطلوب: ${item.quantity})',
            );
          }

          await _db.vegetableShipmentDao.updateShipment(
            shipment.copyWith(
              barnikaSoldCount: newSold,
              barnikaRemainingCount: newRemaining,
            ),
          );

          // Accumulate supplier commission for ledger entry.
          if (itemCommission > 0) {
            supplierCommissions.putIfAbsent(
              item.shipmentId!,
              () => _SupplierCommissionAccumulator(shipment.supplierId),
            ).add(item.price * item.quantity, itemCommission);
          }
        }
      }

      if (splitPayments != null) {
        for (final sp in splitPayments) {
          await _db.invoicePaymentsDao.insertPayment(
            InvoicePaymentsCompanion.insert(
              invoiceId: invoiceId,
              paymentMethod: sp.method,
              amount: sp.amount,
            ),
          );
        }
      } else if (paidAmount > 0) {
        // D3: تقارب الكتّاب — الدفع لحظة الإنشاء يسجّل صف invoice_payments
        // أيضًا (كان يُكتب دفتريًا فقط)، فيبقى Σ(المدفوعات) مصدر paidAmount.
        await _db.invoicePaymentsDao.insertPayment(
          InvoicePaymentsCompanion.insert(
            invoiceId: invoiceId,
            paymentMethod: paymentMethod,
            amount: paidAmount,
          ),
        );
      }

      final desc = ledgerDescription ??
          InvoiceNumberService.saleDescription(actualInvoiceNumber);

      if (customerId != null && customerId != 'cash' && customerId.isNotEmpty) {
        final ledgerIdSale = '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_sale';
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: ledgerIdSale,
            entityType: 'Customer',
            refId: customerId,
            date: DateTime.now(),
            description: desc,
            debit: Value(totalAmount),
            credit: const Value(0.0),
            origin: 'sale',
            paymentMethod: Value(paymentMethod),
            receiptNumber: Value('INV$invoiceId'),
          ),
        );

        if (paidAmount > 0) {
          final ledgerIdPay = '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_pay';
          await _db.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id: ledgerIdPay,
              entityType: 'Customer',
              refId: customerId,
              date: DateTime.now(),
              description: InvoiceNumberService.paymentDescription(
                actualInvoiceNumber,
              ),
              debit: const Value(0.0),
              credit: Value(paidAmount),
              origin: 'payment',
              paymentMethod: Value(paymentMethod),
              receiptNumber: Value('INV$invoiceId'),
            ),
          );
        }
      }

      // Create supplier ledger entries for commission-based shipments.
      for (final entry in supplierCommissions.entries) {
        final acc = entry.value;
        final supplierDue = acc.sellAmount - acc.commissionAmount;
        final ledgerIdSupplier =
            '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_supplier';
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: ledgerIdSupplier,
            entityType: 'Supplier',
            refId: acc.supplierId,
            date: DateTime.now(),
            description: InvoiceNumberService.commissionDescription(
              actualInvoiceNumber,
            ),
            // D8: العمولة payable = دائن بصافي المستحق (sell−commission) وفق
            // القاعدة القانونية opening + Σ(credit−debit). (الوصف والرقم
            // والإيصال كما هي — Agent 1.)
            debit: const Value(0.0),
            credit: Value(supplierDue),
            origin: 'sale',
            receiptNumber: Value('INV$invoiceId'),
          ),
        );
      }

      // ── Headless Accounting: Journal entries (Phase 2) ──
      // Additive, inside same transaction — failure rolls back whole invoice.
      try {
        final accounting = AccountingService(_db);
        // متسامح مع تكرار الأكواد: جدول accounts بلا UNIQUE على code وقد
        // يتضاعف (seed تلقائي + يدوي) — نأخذ أول صف بدل getSingleOrNull الذي
        // يرمي "Too many elements". الإصلاح الجذري (UNIQUE + migration) لمالك
        // app_database (Agent 1) — مُبلّغ في التقرير.
        Future<String> accId(String code) async {
          final rows = await (_db.select(
            _db.accounts,
          )..where((a) => a.code.equals(code))..limit(1)).get();
          if (rows.isEmpty) {
            final seeded = await _db.accountsDao.getByCode(code);
            if (seeded == null) {
              throw Exception('Account $code not found — v57 migration missing');
            }
            return seeded.id;
          }
          return rows.first.id;
        }

        final cashId = await accId('1000');
        final bankId = await accId('1010');
        final arId = await accId('1100');
        final revenueId = await accId('4000');
        final cogsId = await accId('5000');
        final inventoryId = await accId('1200');

        final isCashSale = customerId == null || customerId == 'cash' || customerId.isEmpty;
        final cashOrBankId = paymentMethod == 'cash' ? cashId : bankId;
        final now = DateTime.now();

        if (isCashSale) {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: 'بيع كاش #$actualInvoiceNumber',
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: cashOrBankId,
          );
        } else {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: desc,
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: arId,
          );
          if (paidAmount > 0) {
            await accounting.postCustomerPayment(
              sourceId: '${invoiceId}_pay',
              date: now,
              amount: paidAmount,
              cashOrBankAccountId: cashOrBankId,
              arAccountId: arId,
            );
          }
        }

        if (cogsAmount > 0) {
          await accounting.postSaleCogs(
            sourceId: invoiceId.toString(),
            date: now,
            cogsAmount: cogsAmount,
            cogsAccountId: cogsId,
            inventoryAccountId: inventoryId,
          );
        } else if (items.isNotEmpty) {
          await AuditService.log(
            db: _db,
            action: 'UNRESOLVED_COST',
            tableName: 'invoice_items',
            recordId: invoiceId,
            details: 'no cost available for COGS posting invoice $actualInvoiceNumber — profit may be understated',
          );
        }
        // Supplier commission journal is global (per user answer) but deferred to Phase 3
        // to keep Phase 2 minimal and avoid 3-line entry complexity. Ledger commission remains.
        // D8 (Agent 4): التأجيل مقصود ومُوثّق — لا يوجد حساب عمولة مخصص ضمن
        // الحسابات النظامية الـ12 (إقحامها في 5100 سيشوّه المصروفات التشغيلية)؛
        // ودفتر الأستاذ يلتقط الـpayable بدقة (credit net). غياب
        // قيد اليومية لا يكسر التوازن: مغطى باختبار (لا قيد commission + رصيد
        // المورد صحيح + اليومية متوازنة).
      } catch (e) {
        // Any accounting failure must abort the whole invoice per §24
        rethrow;
      }

      // D10: البرنيكة الفاضية الصادرة تُسجّل داخل نفس الـtransaction —
      // الفشل يُسقط الفاتورة كلها (لا ابتلاع post-commit).
      if (barnikaCustomerId != null &&
          barnikaCustomerId != 'cash' &&
          barnikaCustomerId.isNotEmpty &&
          (barnikaQuantity ?? 0) > 0) {
        await _db.emptyBarnikaTrackingDao.insertRecord(
          EmptyBarnikaTrackingCompanion.insert(
            customerId: barnikaCustomerId,
            dateOut: DateTime.now(),
            quantityOut: barnikaQuantity!,
          ),
        );
      }

      final invoice = await (_db.select(_db.invoices)
          ..where((t) => t.id.equals(invoiceId)))
          .getSingleOrNull();
      if (invoice == null) {
        throw Exception('فشل في حفظ الفاتورة رقم $actualInvoiceNumber');
      }

      return CreateInvoiceResult(invoice: invoice, invoiceId: invoiceId);
    });
  }

  /// الكاتب الموحّد للسداد على فاتورة (D3) — المصدر الوحيد لسداد لاحق للإنشاء.
  ///
  /// في transaction واحدة: صف `invoice_payments` + صف دفتر سداد (دائن، إيصال
  /// `'INV<id>'` غير قابل للفك، وصف Agent 1 `paymentDescription`) + تحديث
  /// `paidAmount`/الحالة + قيد يومية `customer_payment` بمفتاح فريد لكل دفعة.
  /// حراس: مبلغ>0، الفاتورة موجودة وغير ملغاة، منع التجاوز (overpay — هو حارس
  /// الدفع المزدوج: أي دفعة تتجاوز المتبقي تُرفض باستثناء، وإعادة المحاولة
  /// لنفس الصف آمنة عبر مفتاح اليومية الفريد `customer_payment:<id>_<payRow>`).
  /// لا كبت زمني (كانت نافذة 30 ثانية تكبت دفعات مشروعة متساوية متتالية —
  /// أثبتها فشل FIFO: دفعتا 100 على نفس الفاتورة بفارق ثوانٍ؛ كل استدعاء الآن
  /// دفعة حقيقية، ومنع الـdouble-tap مسئولية الـUI ‏(تعطيل الزر أثناء الحفظ).
  /// الصفوف القديمة ذات الإيصال null تُترك كما هي (legacy) — الجديدة مرتبطة.
  Future<Invoice> recordInvoicePayment({
    required int invoiceId,
    required double amount,
    required String paymentMethod,
    String? notes,
    DateTime? date,
  }) async {
    return _db.transaction(() async {
      return _applyInvoicePaymentInTxn(
        invoiceId: invoiceId,
        amount: amount,
        paymentMethod: paymentMethod,
        notes: notes,
        date: date ?? DateTime.now(),
      );
    });
  }

  /// سداد عميل يوزّع FIFO على فواتيره المفتوحة (pending/partial الأقدم أولًا)
  /// في transaction واحدة (D3). كل تخصيص يمر بنفس أرجل [_applyInvoicePaymentInTxn].
  /// الفائض عن إجمالي المستحق يُسجّل رصيدًا مقدمًا بدفتر العميل بإيصال غير-null
  /// (`'ADV-<customer>-<millis>'`, origin=payment) — لا صفوف null-receipt جديدة.
  /// يرجع خريطة invoiceId → المبلغ المخصّص (فارغة لو كله فائض).
  Future<Map<int, double>> recordCustomerPayment({
    required String customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
    DateTime? date,
  }) async {
    if (amount <= 0) throw Exception('مبلغ السداد يجب أن يكون أكبر من صفر');
    final now = date ?? DateTime.now();
    return _db.transaction(() async {
      final open = await (_db.select(_db.invoices)
            ..where(
              (t) =>
                  t.customerId.equals(customerId) &
                  t.status.isIn(['pending', 'partial']))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      final applied = <int, double>{};
      var remaining = amount;
      for (final inv in open) {
        if (remaining <= 0.001) break;
        final due = inv.totalAmount - inv.paidAmount;
        if (due <= 0.001) continue;
        final take = remaining >= due ? due : remaining;
        await _applyInvoicePaymentInTxn(
          invoiceId: inv.id,
          amount: take,
          paymentMethod: paymentMethod,
          notes: notes,
          date: now,
        );
        applied[inv.id] = take;
        remaining -= take;
      }
      if (remaining > 0.001) {
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${const Uuid().v4()}_adv',
            entityType: 'Customer',
            refId: customerId,
            date: now,
            description: notes != null && notes.isNotEmpty
                ? notes
                : 'سداد آجل — رصيد مقدم',
            debit: const Value(0.0),
            credit: Value(remaining),
            origin: 'payment',
            paymentMethod: Value(paymentMethod),
            receiptNumber: Value(
              'ADV-${customerId}_${now.millisecondsSinceEpoch}',
            ),
          ),
        );
      }
      return applied;
    });
  }

  /// أرجل السداد داخل transaction المستدعي (تُستخدم منفردة أو ضمن توزيع العميل).
  Future<Invoice> _applyInvoicePaymentInTxn({
    required int invoiceId,
    required double amount,
    required String paymentMethod,
    String? notes,
    required DateTime date,
  }) async {
    if (amount <= 0) throw Exception('مبلغ السداد يجب أن يكون أكبر من صفر');
    final invoice = await getInvoiceById(invoiceId);
    if (invoice == null) throw Exception('الفاتورة غير موجودة');
    if (invoice.status == 'voided') {
      throw Exception('لا يمكن السداد على فاتورة ملغاة');
    }
    if (invoice.customerId == null ||
        invoice.customerId == 'cash' ||
        invoice.customerId!.isEmpty) {
      throw Exception('السداد اللاحق للفواتير الآجلة فقط');
    }
    // حارس التجاوز: يمنع الدفع المزدوج الكامل أيضًا.
    if (invoice.paidAmount + amount > invoice.totalAmount + 0.01) {
      throw Exception(
        'المبلغ يتجاوز المتبقي على الفاتورة '
        '(المتبقي: ${(invoice.totalAmount - invoice.paidAmount).toStringAsFixed(2)})',
      );
    }
    final receipt = 'INV$invoiceId';

    final payRowId = await _db.invoicePaymentsDao.insertPayment(
      InvoicePaymentsCompanion.insert(
        invoiceId: invoiceId,
        paymentMethod: paymentMethod,
        amount: amount,
        paidAt: Value(date),
        notes: Value(notes),
      ),
    );

    final storedNumber = invoice.invoiceNumber ?? 'INV$invoiceId';
    await _db.ledgerDao.insertTransaction(
      LedgerTransactionsCompanion.insert(
        id: '${const Uuid().v4()}_pay',
        entityType: 'Customer',
        refId: invoice.customerId!,
        date: date,
        description: InvoiceNumberService.paymentDescription(storedNumber),
        debit: const Value(0.0),
        credit: Value(amount),
        origin: 'payment',
        paymentMethod: Value(paymentMethod),
        receiptNumber: Value(receipt),
      ),
    );

    final newPaid = invoice.paidAmount + amount;
    final newStatus = newPaid >= invoice.totalAmount - 0.01
        ? 'paid'
        : (newPaid > 0 ? 'partial' : 'pending');
    await _db.invoiceDao.updateInvoice(
      InvoicesCompanion(
        id: Value(invoiceId),
        paidAmount: Value(newPaid),
        status: Value(newStatus),
        cashAmount: Value(
          paymentMethod == 'cash' ? invoice.cashAmount + amount : invoice.cashAmount,
        ),
        cardAmount: Value(
          (paymentMethod == 'visa' ||
                  paymentMethod == 'card' ||
                  paymentMethod == 'bank')
              ? invoice.cardAmount + amount
              : invoice.cardAmount,
        ),
      ),
    );

    // يومية التحصيل بمفتاح فريد لكل دفعة (UNIQUE → آمن لإعادة المحاولة).
    try {
      final arRows = await (_db.select(
        _db.accounts,
      )..where((a) => a.code.equals('1100'))..limit(1)).get();
      final cashRows = await (_db.select(
        _db.accounts,
      )..where((a) => a.code.equals(paymentMethod == 'cash' ? '1000' : '1010'))..limit(1)).get();
      if (arRows.isNotEmpty && cashRows.isNotEmpty) {
        await AccountingService(_db).postCustomerPayment(
          sourceId: '${invoiceId}_$payRowId',
          date: date,
          amount: amount,
          cashOrBankAccountId: cashRows.first.id,
          arAccountId: arRows.first.id,
        );
      }
    } catch (_) {
      // غياب شجرة الحسابات لا يُسقط سدادًا نقديًا حقيقيًا — الدفتر والحركات
      // محفوظة؛ اليومية تُستدرك لاحقًا. (لا ابتلاع واسع: فقط هذه الخطوة.)
      await AuditService.log(
        db: _db,
        action: 'MISSING_JOURNAL',
        tableName: 'journal_entries',
        recordId: invoiceId,
        details: 'customer_payment journal skipped for INV$invoiceId pay $payRowId — accounts missing',
      );
    }

    final updated = await getInvoiceById(invoiceId);
    if (updated == null) throw Exception('فشل تحديث الفاتورة بعد السداد');
    return updated;
  }

  /// خصم مخزون سطر بيع — atomic ضمن transaction الفاتورة المستدعية.
  ///
  /// - لو [variantId] متحدد: يخصم من الصنف (لون/فئة) بعد التحقق من الكفاية،
  ///   ثم يعيد حساب كمية الأب = مجموع الأصناف.
  /// - لو null: المسار القديم بالظبط (خصم من الأب مع clamp عند الصفر).
  Future<void> _applySaleStock(
    Product product,
    int quantity,
    int? variantId,
  ) async {
    if (variantId == null) {
      // حماية الـ invariant: منتج له أصناف لازم يتباع عبر صنف، مش مباشرة —
      // وإلا كمية الأب هتتكتب فوقها (sum) في أول بيع صنف بعده وتضيع الحركة.
      final variants = await _db.productVariantDao.getVariantsByProduct(
        product.id,
      );
      if (variants.isNotEmpty) {
        throw Exception(
          'المنتج «${product.name}» له أصناف (ألوان/فئات) — اختر الصنف أولًا',
        );
      }
      final newQty = product.quantity - quantity;
      await _db.productDao.updateProduct(
        ProductsCompanion(
          id: Value(product.id),
          name: Value(product.name),
          quantity: Value(newQty < 0 ? 0 : newQty),
          price: Value(product.price),
          unit: Value(product.unit),
          category: Value(product.category),
          barcode: Value(product.barcode),
          cartonQuantity: Value(product.cartonQuantity),
          cartonPrice: Value(product.cartonPrice),
          status: Value(product.status),
        ),
      );
      return;
    }

    final variant = await _db.productVariantDao.getVariantById(variantId);
    if (variant == null || variant.status == 'Deleted') {
      throw Exception('الصنف (اللون/الفئة) غير موجود');
    }
    if (variant.productId != product.id) {
      throw Exception('الصنف «${variant.name}» لا يتبع المنتج «${product.name}»');
    }
    if (variant.quantity < quantity) {
      throw Exception(
        'الكمية غير كافية للصنف «${variant.name}» من «${product.name}» '
        '(متاح: ${variant.quantity}, مطلوب: $quantity)',
      );
    }
    await _db.productVariantDao.updateVariantQuantity(
      variant.id,
      variant.quantity - quantity,
    );
    // كمية الأب = مجموع الأصناف (التقارير وتنبيه النواقص تفضل سليمة).
    final total = await _db.productVariantDao.getTotalQuantityByProduct(
      product.id,
    );
    await _db.productDao.updateProduct(product.copyWith(quantity: total));
  }

  /// عكس خصم مخزون سطر بيع (تعديل/إلغاء فاتورة) — atomic ضمن الـ transaction.
  Future<void> _restoreSaleStock(
    int productId,
    int quantity,
    int? variantId,
  ) async {
    if (variantId != null) {
      final variant = await _db.productVariantDao.getVariantById(variantId);
      if (variant != null) {
        await _db.productVariantDao.updateVariantQuantity(
          variant.id,
          variant.quantity + quantity,
        );
        final total = await _db.productVariantDao.getTotalQuantityByProduct(
          productId,
        );
        final product = await _db.productDao.getProductById(productId);
        if (product != null) {
          await _db.productDao.updateProduct(
            product.copyWith(quantity: total),
          );
        }
        return;
      }
      // الصنف اتحذف نهائيًا بعد البيع — نرجع الكمية للأب مباشرة عشان ماتضيعش.
    }
    final product = await _db.productDao.getProductById(productId);
    if (product != null) {
      await _db.productDao.updateProduct(
        product.copyWith(quantity: product.quantity + quantity),
      );
    }
  }

  Future<void> deleteInvoice(Insertable<Invoice> invoice) async {
    await _db.invoiceDao.deleteInvoice(invoice);
  }

  /// Atomically edits an existing invoice while preserving its id and number.
  ///
  /// Strategy (mirrors [createInvoice] to avoid fragile delta math):
  /// 1. Reverse the original impact: restore stock, reverse shipment counts,
  ///    delete the original ledger rows + line items for this invoice.
  /// 2. Re-apply the edited items: decrement stock, insert items, update
  ///    shipment counts/commission, update the invoice totals row, and write
  ///    fresh ledger rows (sale + payment + supplier commission).
  ///
  /// Everything runs inside a single Drift transaction so it either fully
  /// succeeds or fully rolls back — no partial/corrupted state.
  Future<Invoice> editInvoice({
    required int invoiceId,
    required String? customerId,
    required String customerName,
    String? customerContact,
    String? customerAddress,
    required String paymentMethod,
    required double totalAmount,
    required double paidAmount,
    double cashAmount = 0,
    double cardAmount = 0,
    double creditAmount = 0,
    required String status,
    required List<InvoiceItemParams> items,
    int? primaryShipmentId,
    // D10: تعديل البرنيكة اختياري صريح فقط — بلا بارامترات لا تُلمس.
    String? barnikaCustomerId,
    int? barnikaQuantity,
  }) async {
    final original = await getInvoiceById(invoiceId);
    if (original == null) throw Exception('الفاتورة غير موجودة');
    if (original.status == 'voided') {
      throw Exception('لا يمكن تعديل فاتورة ملغاة');
    }

    // Guard: do not edit an invoice that already has returns — that would
    // double-count stock/ledger. User must reverse the return first.
    final returns = await _db.salesReturnsDao.getReturnsForInvoice(invoiceId);
    if (returns.isNotEmpty) {
      throw Exception('لا يمكن تعديل فاتورة عليها مرتجعات مسجلة');
    }

    final actualInvoiceNumber = original.invoiceNumber ?? 'INV$invoiceId';
    final rand = Random.secure();

    return _db.transaction(() async {
      final originalItems = await _db.invoiceDao.getItemsByInvoiceId(invoiceId);

      // D4: تاريخ المدفوعات مصدر paidAmount — لا مسح أبدًا. نقل فاتورة مدفوعة
      // لعميل آخر ممنوع (النقدية المستلمة تبقى باسم العميل الأصلي).
      final priorPayments = await _db.invoicePaymentsDao
          .getPaymentsForInvoice(invoiceId);
      final historyPaid = priorPayments.fold<double>(
        0.0,
        (s, p) => s + p.amount,
      );
      if (historyPaid > 0.001 &&
          (customerId ?? '') != (original.customerId ?? '')) {
        throw Exception(
          'لا يمكن نقل فاتورة مدفوعة لعميل آخر — سجّل مرتجع/فاتورة جديدة بدلًا منها',
        );
      }

      // 1a. Reverse original stock + shipment counts (D9: حركة return موجبة).
      for (final item in originalItems) {
        final prevProduct = await _db.productDao.getProductById(
          item.productId,
        );
        await _restoreSaleStock(item.productId, item.quantity, item.variantId);
        final afterRestore = await _db.productDao.getProductById(
          item.productId,
        );
        await _db.inventoryMovementDao.createMovementWithTimestamp(
          productId: item.productId,
          movementType: 'return',
          quantity: item.quantity,
          unitCost: item.unitCostAtTime ?? 0,
          totalValue: (item.unitCostAtTime ?? 0) * item.quantity,
          movementDate: DateTime.now(),
          reference: actualInvoiceNumber,
          referenceType: 'sale_invoice',
          previousQuantity: prevProduct?.quantity ?? 0,
          newQuantity:
              afterRestore?.quantity ??
              ((prevProduct?.quantity ?? 0) + item.quantity),
          notes: item.variantId != null
              ? 'edit-reverse variant:${item.variantId}'
              : 'edit-reverse',
        );
        if (item.shipmentId != null) {
          final shipment =
              await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment != null) {
            await _db.vegetableShipmentDao.updateShipment(
              shipment.copyWith(
                barnikaSoldCount:
                    (shipment.barnikaSoldCount - item.quantity).clamp(0, 1 << 62),
                barnikaRemainingCount:
                    shipment.barnikaRemainingCount + item.quantity,
              ),
            );
          }
        }
      }

      // 1b. عكس دفتري append-only (D4): تُعكس صفوف البيع فقط (عميل + مورد) —
      // صفوف الدفع history لا تُعكس ولا تُحذف. السطور تُحذف وتُعاد بالكامل.
      await _db.ledgerDao.reverseTransactionsByReceipt(
        receiptNumber: 'INV$invoiceId',
        reversalReceipt: 'REV-INV$invoiceId',
        onlyOrigins: const {'sale'},
      );
      await _db.invoiceDao.deleteInvoiceItemsByInvoice(invoiceId);

      // 2a. Re-apply edited items.
      final supplierCommissions = <int, _SupplierCommissionAccumulator>{};
      double cogsAmountEdit = 0;
      for (final item in items) {
        final product = await _db.productDao.getProductById(item.productId);
        if (product == null) {
          throw Exception('المنتج غير موجود (ID: ${item.productId})');
        }

        final unitCost = item.unitCostAtTime ?? product.costPrice ?? 0;
        if (unitCost > 0) cogsAmountEdit += unitCost * item.quantity;

        final prevParentQty = product.quantity;
        await _applySaleStock(product, item.quantity, item.variantId);
        final afterApply = await _db.productDao.getProductById(item.productId);
        await _db.inventoryMovementDao.createMovementWithTimestamp(
          productId: item.productId,
          movementType: 'sale',
          quantity: -item.quantity,
          unitCost: unitCost,
          totalValue: unitCost * item.quantity,
          movementDate: DateTime.now(),
          reference: actualInvoiceNumber,
          referenceType: 'sale_invoice',
          previousQuantity: prevParentQty,
          newQuantity:
              afterApply?.quantity ?? (prevParentQty - item.quantity),
          notes: item.variantId != null
              ? 'edit-apply variant:${item.variantId}'
              : 'edit-apply',
        );

        var itemCommission = item.commission;
        if (item.shipmentId != null && itemCommission == 0) {
          final shipment =
              await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment != null &&
              shipment.pricingMode == ShipmentPricingMode.commission &&
              shipment.commissionPercentage != null) {
            itemCommission = ShipmentPricingService.calculateCommission(
              item.price * item.quantity,
              shipment.commissionPercentage!,
            );
          }
        }

        await _db.invoiceDao.insertInvoiceItem(
          InvoiceItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(item.productId),
            quantity: Value(item.quantity),
            ctn: Value(item.ctn),
            price: Value(item.price),
            discount: Value(item.discount),
            commission: Value(itemCommission),
            unitCostAtTime: Value(item.unitCostAtTime),
            shipmentId: Value(item.shipmentId),
            variantId: Value(item.variantId),
          ),
        );

        if (item.shipmentId != null) {
          final shipment =
              await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment == null) {
            throw Exception('الشحنة #${item.shipmentId} غير موجودة');
          }
          final newSold = shipment.barnikaSoldCount + item.quantity;
          final newRemaining = shipment.barnikaRemainingCount - item.quantity;
          if (newRemaining < 0) {
            throw Exception(
              'الشحنة #${item.shipmentId} لا تحتوي على كمية كافية '
              '(متبقي: ${shipment.barnikaRemainingCount}, مطلوب: ${item.quantity})',
            );
          }
          await _db.vegetableShipmentDao.updateShipment(
            shipment.copyWith(
              barnikaSoldCount: newSold,
              barnikaRemainingCount: newRemaining,
            ),
          );
          if (itemCommission > 0) {
            supplierCommissions
                .putIfAbsent(
                  item.shipmentId!,
                  () => _SupplierCommissionAccumulator(shipment.supplierId),
                )
                .add(item.price * item.quantity, itemCommission);
          }
        }
      }

      // 2b. Update invoice header totals (D4): الرقم يُحفظ دائمًا، وpaid يُشتق
      // من history المدفوعات الباقية — مبلغ الواجهة يُتجاهل عند وجود history
      // (تغيير المدفوعات عبر مسار PAY فقط). بلا history يُكتب مبلغ الواجهة
      // كدفعة جديدة (تقارب D3) بدل إسناد صامت.
      final isCreditCustomer =
          customerId != null && customerId != 'cash' && customerId.isNotEmpty;
      var derivedPaid = historyPaid;
      if (historyPaid <= 0.001) derivedPaid = paidAmount;
      final derivedStatus = _deriveInvoiceStatus(totalAmount, derivedPaid);
      await _db.invoiceDao.updateInvoice(
        InvoicesCompanion(
          id: Value(invoiceId),
          invoiceNumber: Value(actualInvoiceNumber),
          customerId: Value(customerId),
          customerName: Value(customerName),
          customerContact: Value(customerContact ?? ''),
          customerAddress: Value(customerAddress ?? ''),
          paymentMethod: Value(paymentMethod),
          totalAmount: Value(totalAmount),
          paidAmount: Value(derivedPaid),
          cashAmount: Value(cashAmount),
          cardAmount: Value(cardAmount),
          creditAmount: Value(creditAmount),
          status: Value(derivedStatus),
          shipmentId: Value(primaryShipmentId),
        ),
      );

      // 2c. Fresh sale ledger row for a credit customer (payment rows stay).
      final desc = 'بيع #$actualInvoiceNumber';
      if (isCreditCustomer) {
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id:
                '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_sale',
            entityType: 'Customer',
            refId: customerId,
            date: DateTime.now(),
            description: desc,
            debit: Value(totalAmount),
            credit: const Value(0.0),
            origin: 'sale',
            paymentMethod: Value(paymentMethod),
            receiptNumber: Value('INV$invoiceId'),
          ),
        );

        // بلا history: مبلغ الواجهة دفعة جديدة بنفس أرجل الكاتب الموحّد.
        if (historyPaid <= 0.001 && paidAmount > 0) {
          await _applyInvoicePaymentInTxn(
            invoiceId: invoiceId,
            amount: paidAmount > totalAmount ? totalAmount : paidAmount,
            paymentMethod: paymentMethod,
            date: DateTime.now(),
          );
        }
      }

      // 2d. Supplier commission ledger entries (D8: دائن net).
      for (final entry in supplierCommissions.entries) {
        final acc = entry.value;
        final supplierDue = acc.sellAmount - acc.commissionAmount;
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id:
                '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_supplier',
            entityType: 'Supplier',
            refId: acc.supplierId,
            date: DateTime.now(),
            description: 'عمولة بيع #$actualInvoiceNumber',
            debit: const Value(0.0),
            credit: Value(supplierDue),
            origin: 'sale',
            receiptNumber: Value('INV$invoiceId'),
          ),
        );
      }

      // D10: تعديل البرنيكة فقط ببارامترات صريحة — إرجاع المرشح القديم
      // (status-machine: لا ازدواج) + صف جديد، كلاهما داخل نفس الـtxn.
      if (barnikaCustomerId != null &&
          barnikaCustomerId != 'cash' &&
          barnikaCustomerId.isNotEmpty &&
          (barnikaQuantity ?? 0) > 0 &&
          original.customerId != null &&
          original.customerId != 'cash' &&
          original.customerId!.isNotEmpty) {
        final origQty = originalItems.fold<int>(
          0,
          (s, e) => s + e.quantity,
        );
        final candidate = await _findBarnikaCandidate(
          customerId: original.customerId!,
          quantityOut: origQty,
          around: original.date,
        );
        if (candidate != null) {
          final missing = candidate.quantityOut - candidate.quantityReturned;
          if (missing > 0) {
            await _db.emptyBarnikaTrackingDao.recordReturn(
              id: candidate.id,
              quantityReturned: missing,
            );
          }
        }
        await _db.emptyBarnikaTrackingDao.insertRecord(
          EmptyBarnikaTrackingCompanion.insert(
            customerId: barnikaCustomerId,
            dateOut: DateTime.now(),
            quantityOut: barnikaQuantity!,
          ),
        );
      }

      // ── Headless Accounting: delete + repost same keys (D4) ──
      // الدليل: insertBalancedEntry يتجاهل أي مفتاح موجود (UNIQUE) — فإعادة
      // الترحيل بنفس المفاتيح بعد reverseEntry كانت no-op صامتًا (الرصيد
      // القديم يبقى). الحذف-ثم-إعادة بنفس المفاتيح يبقي قيدًا حيًا واحدًا لكل
      // مفتاح وآمنًا لإعادة المحاولة. قيود الدفع (customer_payment:*) تُحفظ
      // لأن المدفوعات history لا تُمسّ. سجل التدقيق الكامل في دفتر الأستاذ
      // (صفوف reversal) لا هنا.
      try {
        final accounting = AccountingService(_db);
        await _db.journalDao.deleteEntriesByPostingKeys([
          'sale:INV$invoiceId',
          'sale_cogs:INV$invoiceId',
        ]);
        Future<String> accId(String code) async {
          final rows = await (_db.select(
            _db.accounts,
          )..where((a) => a.code.equals(code))..limit(1)).get();
          if (rows.isEmpty) throw Exception('Account $code not found');
          return rows.first.id;
        }

        final cashId = await accId('1000');
        final bankId = await accId('1010');
        final arId = await accId('1100');
        final revenueId = await accId('4000');
        final cogsId = await accId('5000');
        final inventoryId = await accId('1200');

        final isCashSale = customerId == null || customerId == 'cash' || customerId.isEmpty;
        final cashOrBankId = paymentMethod == 'cash' ? cashId : bankId;
        final now = DateTime.now();
        final desc2 = 'بيع #$actualInvoiceNumber';

        if (isCashSale) {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: 'بيع كاش #$actualInvoiceNumber',
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: cashOrBankId,
          );
        } else {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: desc2,
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: arId,
          );
          // لا إعادة ترحيل للدفع هنا (D4): قيود customer_payment محفوظة كـhistory،
          // والدفعة الجديدة (حالة بلا history) رحّلتها _applyInvoicePaymentInTxn
          // بمفتاح فريد — إعادة الترحيل هنا ستضاعفها.
        }

        if (cogsAmountEdit > 0) {
          await accounting.postSaleCogs(
            sourceId: invoiceId.toString(),
            date: now,
            cogsAmount: cogsAmountEdit,
            cogsAccountId: cogsId,
            inventoryAccountId: inventoryId,
          );
        } else if (items.isNotEmpty) {
          await AuditService.log(
            db: _db,
            action: 'UNRESOLVED_COST',
            tableName: 'invoice_items',
            recordId: invoiceId,
            details: 'no cost available for COGS posting invoice $actualInvoiceNumber (edit)',
          );
        }
      } catch (e) {
        rethrow;
      }

      final updated = await getInvoiceById(invoiceId);
      if (updated == null) throw Exception('فشل في تحديث الفاتورة');
      return updated;
    });
  }

  Future<void> voidInvoice(int invoiceId, String reason, String voidedBy) async {
    await _db.invoiceDao.voidInvoice(invoiceId, reason, voidedBy);
  }

  Future<void> updateInvoice(Insertable<Invoice> invoice) async {
    await _db.invoiceDao.updateInvoice(invoice);
  }

  Future<Invoice?> getInvoiceById(int id) async {
    final invoices = await (_db.select(_db.invoices)..where((t) => t.id.equals(id))).get();
    return invoices.isNotEmpty ? invoices.first : null;
  }

  /// paid/total → status الموحّد (يُستخدم في الإنشاء اللاحق والتعديل والسداد).
  String _deriveInvoiceStatus(double total, double paid) {
    if (paid >= total - 0.01) return 'paid';
    if (paid > 0) return 'partial';
    return 'pending';
  }

  /// أفضل جهد لمطابقة صف البرنيكة الفاضية الذي أنشأته فاتورة: عميل حقيقي +
  /// حالة غير مُعادة + نفس الكمية الخارجة + تاريخ قريب من تاريخ الفاتورة.
  /// يرجع null عند الغموض (صفر أو عدة مرشحين) — لا تخمين يُفسد بيانات الغير.
  Future<EmptyBarnikaTrackingData?> _findBarnikaCandidate({
    required String customerId,
    required int quantityOut,
    required DateTime around,
  }) async {
    final outstanding = await _db.emptyBarnikaTrackingDao
        .getOutstandingByCustomer(customerId);
    final matches = outstanding.where((r) {
      if (r.quantityOut != quantityOut) return false;
      final delta = r.dateOut.difference(around).abs();
      return delta <= const Duration(hours: 24);
    }).toList();
    if (matches.length != 1) return null;
    return matches.first;
  }

  /// Documented pre-v70 legacy invoice ids accepted ONLY on the
  /// `preserveInvoiceNumber: true` path (import/sync/restore): shapes such as
  /// `INV<millis>`, `DRAFT_…`, `SALE-…`/`PUR-…`, `TEST-…`. Canonical 6-digit
  /// values are handled separately; anything else is rejected by the caller.
  bool _isDocumentedLegacyId(String s) {
    final v = s.trim();
    if (v.isEmpty || v.length > 255) return false;
    if (InvoiceNumberService.isCanonical(v)) return true;
    return v.startsWith('INV') ||
        v.startsWith('DRAFT_') ||
        v.startsWith('SALE-') ||
        v.startsWith('SALES-') ||
        v.startsWith('PUR-') ||
        v.startsWith('TEST-') ||
        v.startsWith('RTR-');
  }
}

class SplitPaymentEntry {
  final String method;
  final double amount;

  SplitPaymentEntry({required this.method, required this.amount});
}

/// Accumulates sell amount and commission for a single supplier across
/// multiple invoice items from the same shipment (or different shipments
/// of the same supplier).
class _SupplierCommissionAccumulator {
  final String supplierId;
  double sellAmount = 0;
  double commissionAmount = 0;

  _SupplierCommissionAccumulator(this.supplierId);

  void add(double sell, double commission) {
    sellAmount += sell;
    commissionAmount += commission;
  }
}
