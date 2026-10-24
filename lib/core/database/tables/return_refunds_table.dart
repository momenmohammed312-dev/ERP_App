import 'package:drift/drift.dart';
import 'sales_returns_table.dart';
import 'invoice_table.dart';

/// جدول استرداد أموال المرتجعات.
///
/// الفكرة: المرتجع (بضاعة رجعت) ≠ الاسترداد (فلوس خرجت). قبل v78 ماكانش
/// في أي concept للاسترداد خالص — مرتجع العميل الآجل كان بيعمل credit في
/// الـledger، ومرتجع العميل النقدي كان بياكل المخزون وخلاص (الفلوس كانت
/// بتختفي من الدنيا ومن رصيد اليوم).
///
/// كل سطر هنا = دفعة واحدة من الاسترداد. المرتجع الواحد ممكن يتقسم على
/// أكتر من سطر (مثلاً 60 نقدي + 40 رصيد للعميل).
///
/// [method] values:
///   'cash'            — خرج كاش من الصندوق (المتداولي بيخصمه من رصيد اليوم)
///   'credit_balance'  — رصيد للعميل (بيانته بتقل، وهو يصرفه وقت ما يحب)
///   'original'        — نفس طريقة الدفع الأصلية (كارت/بنك)
///   'store_credit'    — كوبون رصيد مؤجل (نفس أثر credit_balance لكن صريح)
@DataClassName('ReturnRefund')
class ReturnRefunds extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get returnId => integer().references(
    SalesReturns,
    #id,
    onDelete: KeyAction.cascade,
  )();

  DateTimeColumn get refundDate => dateTime()();

  /// قيمة الدفعة المستردة.
  RealColumn get amount => real()();

  /// 'cash' | 'credit_balance' | 'original' | 'store_credit'
  TextColumn get method => text()();

  /// رقم العملية المرجعي (كارت/بنك/تحويل) — مهم للمطابقة البنكية.
  TextColumn get referenceNumber => text().nullable()();

  /// لو الرصيد اتحمّل على فاتورة معينة بدل ما يفضل رصيد مفتوح.
  IntColumn get applyToInvoiceId =>
      integer().nullable().references(Invoices, #id)();

  TextColumn get notes => text().nullable()();

  /// اسم المستخدم اللي نفّذ الاسترداد — لازم يتسجل دايماً (audit).
  TextColumn get processedBy => text().nullable()();

  /// إلغاء الاسترداد (soft) — السجل يفضل موجود للأرشيف بس بيبقى صفري الأثر.
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidedBy => text().nullable()();
  TextColumn get voidReason => text().nullable()();

  ///Soft delete guard — كل الاستعلامات لازم تفلتر عليها.
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();

  TextColumn get syncId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}