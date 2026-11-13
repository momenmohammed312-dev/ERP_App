import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/arabic_name_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  group('ArabicNameNormalizer', () {
    test('unifies Alef, Ya, Ta Marbuta, strips diacritics/tatweel and الـ prefix', () {
      expect(
        ArabicNameNormalizer.normalize('أحمد إبراهيم'),
        ArabicNameNormalizer.normalize('احمد ابراهيم'),
      );
      expect(
        ArabicNameNormalizer.normalize('آدم مصطفى حمزة'),
        ArabicNameNormalizer.normalize('ادم مصطفي حمزه'),
      );
      expect(
        ArabicNameNormalizer.normalize('الشيخ الحاج العربي'),
        ArabicNameNormalizer.normalize('شيخ حاج عربى'),
      );
      expect(
        ArabicNameNormalizer.normalize('أَحمَد الـمَصْرِيّ'),
        'احمد مصري',
      );
      expect(
        ArabicNameNormalizer.areEquivalent('الحاج إبراهيم', 'حاج ابراهيم'),
        isTrue,
      );
      expect(
        ArabicNameNormalizer.areEquivalent('محمود', 'محمد'),
        isFalse,
      );
      expect(ArabicNameNormalizer.areEquivalent('   ', ''), isFalse);
    });

    test('matchesQuery handles both stripped-ال and partial-ال searches plus phone', () {
      expect(
        ArabicNameNormalizer.matchesQuery(
          candidate: 'الحاج أحمد العربي',
          query: 'احمد عربى',
        ),
        isTrue,
      );
      expect(
        ArabicNameNormalizer.matchesQuery(
          candidate: 'العربي للخضار',
          query: 'العر',
        ),
        isTrue,
      );
      expect(
        ArabicNameNormalizer.matchesQuery(
          candidate: 'سوق العبور',
          query: '0100234',
          candidatePhone: '0100-234-5678',
        ),
        isTrue,
      );
    });
  });

  group('CustomerDao & SupplierDao normalized search & duplicate warnings', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('CustomerDao searchCustomers and findSimilarCustomers match normalized Arabic', () async {
      await db.customerDao.insertCustomer(
        CustomersCompanion.insert(
          id: 'C1',
          name: 'الحاج أحمد مصطفى',
          phone: const Value('01001234567'),
        ),
      );
      await db.customerDao.insertCustomer(
        CustomersCompanion.insert(
          id: 'C2',
          name: 'شركة حمزة',
        ),
      );

      final hits = await db.customerDao.searchCustomers('حاج احمد مصطفي');
      expect(hits.map((c) => c.id), ['C1']);

      final taMarbutaHits = await db.customerDao.searchCustomers('شركه حمزه');
      expect(taMarbutaHits.map((c) => c.id), ['C2']);

      final similar = await db.customerDao.findSimilarCustomers(
        name: 'حاج احمد مصطفي',
      );
      expect(similar.map((c) => c.id), ['C1']);

      final excluded = await db.customerDao.findSimilarCustomers(
        name: 'حاج احمد مصطفي',
        excludeId: 'C1',
      );
      expect(excluded, isEmpty);
    });

    test('SupplierDao searchSuppliers and findSimilarSuppliers match normalized Arabic', () async {
      final s1 = await db.supplierDao.insertSupplier(
        SuppliersCompanion.insert(
          id: '',
          name: 'أبو إبراهيم العربي',
          phone: const Value('01112223334'),
        ),
      );

      final hits = await db.supplierDao.searchSuppliers('ابو ابراهيم عربي');
      expect(hits.map((s) => s.id), [s1.id]);

      final dupes = await db.supplierDao.findSimilarSuppliers(
        name: 'ابو ابراهيم العربى',
      );
      expect(dupes.map((s) => s.id), [s1.id]);

      final dupesExcluded = await db.supplierDao.findSimilarSuppliers(
        name: 'ابو ابراهيم العربى',
        excludeId: s1.id,
      );
      expect(dupesExcluded, isEmpty);
    });
  });
}
