import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/staff_management_tables.dart' as staff_tables;

part 'staff_management_dao.g.dart';

@DriftAccessor(
  tables: [
    staff_tables.StaffTable,
    staff_tables.AttendanceTable,
    staff_tables.Vacations,
    staff_tables.StaffAdvances,
    staff_tables.PayrollTable,
    staff_tables.RewardsPenalties,
    staff_tables.PerformanceReviews,
    staff_tables.StaffDocuments,
  ],
)
class StaffManagementDao extends DatabaseAccessor<AppDatabase>
    with _$StaffManagementDaoMixin {
  StaffManagementDao(super.db);

  // STAFF MANAGEMENT

  Future<List<Staff>> getAllStaff() => select(staffTable).get();

  Future<Staff?> getStaffById(String staffId) => (select(
    staffTable,
  )..where((s) => s.staffId.equals(staffId))).getSingleOrNull();

  Future<List<Staff>> getActiveStaff() => (select(
    staffTable,
  )..where((s) => s.isActive.equals(true) & s.status.equals('active'))).get();

  Future<void> addStaff(StaffTableCompanion entry) =>
      into(staffTable).insert(entry);

  Future<void> updateStaff(Staff entry) => update(staffTable).replace(entry);

  Future<void> deleteStaff(String staffId) =>
      (delete(staffTable)..where((s) => s.staffId.equals(staffId))).go();

  Future<int> getStaffCount() async {
    final countExp = staffTable.id.count();
    final result = await (selectOnly(staffTable)..addColumns([countExp]))
        .getSingle();
    return result.read(countExp) ?? 0;
  }

  // WATCH STREAMS FOR REAL-TIME UPDATES

  Stream<List<Staff>> watchAllStaff() => select(staffTable).watch();

  Stream<List<Staff>> watchActiveStaff() => (select(
    staffTable,
  )..where((s) => s.isActive.equals(true) & s.status.equals('active'))).watch();

  // ATTENDANCE MANAGEMENT

  Future<List<Attendance>> getAttendanceByStaff(
    String staffId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final query = select(attendanceTable)
      ..where((a) => a.staffId.equals(staffId));

    if (startDate != null) {
      query.where((a) => a.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((a) => a.date.isSmallerOrEqualValue(endDate));
    }

    return query.get();
  }

  Future<void> addAttendance(AttendanceTableCompanion entry) =>
      into(attendanceTable).insert(entry);

  Future<void> updateAttendance(Attendance entry) =>
      update(attendanceTable).replace(entry);

  Future<void> checkIn(String staffId, {String? location}) async {
    final now = DateTime.now();
    await addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(now.year, now.month, now.day),
        status: 'present',
        checkInTime: Value(now),
        checkInLocation: Value(location),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> checkOut(String staffId, {String? location}) async {
    final now = DateTime.now();
    // Find today's attendance record
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final attendanceRecords =
        await (select(attendanceTable)
              ..where((a) => a.staffId.equals(staffId))
              ..where((a) => a.date.isBetweenValues(today, tomorrow)))
            .get();

    if (attendanceRecords.isNotEmpty) {
      final record = attendanceRecords.first;
      await updateAttendance(
        record.copyWith(
          checkOutTime: Value(now),
          checkOutLocation: Value(location),
          updatedAt: now,
        ),
      );
    }
  }

  // VACATION MANAGEMENT

  Future<List<Vacation>> getVacationsByStaff(String staffId) =>
      (select(vacations)..where((v) => v.staffId.equals(staffId))).get();

  Future<void> addVacation(VacationsCompanion entry) =>
      into(vacations).insert(entry);

  Future<void> approveVacation(int vacationId, String approvedBy) =>
      (update(vacations)..where((v) => v.id.equals(vacationId))).write(
        VacationsCompanion(
          status: const Value('approved'),
          approvedBy: Value(approvedBy),
          approvedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> rejectVacation(int vacationId, String approvedBy, String reason) =>
      (update(vacations)..where((v) => v.id.equals(vacationId))).write(
        VacationsCompanion(
          status: const Value('rejected'),
          approvedBy: Value(approvedBy),
          approvedAt: Value(DateTime.now()),
          rejectionReason: Value(reason),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<List<Vacation>> getPendingVacations() =>
      (select(vacations)..where((v) => v.status.equals('pending'))).get();

  Stream<List<Vacation>> watchPendingVacations() =>
      (select(vacations)..where((v) => v.status.equals('pending'))).watch();

  // ADVANCE MANAGEMENT

  Future<List<StaffAdvance>> getAdvancesByStaff(String staffId) =>
      (select(staffAdvances)..where((a) => a.staffId.equals(staffId))).get();

  Future<void> addAdvance(StaffAdvancesCompanion entry) =>
      into(staffAdvances).insert(entry);

  // PAYROLL MANAGEMENT

  Future<void> addPayroll(PayrollTableCompanion entry) =>
      into(payrollTable).insert(entry);

  Future<List<Payroll>> getPayrollByStaff(String staffId) =>
      (select(payrollTable)..where((p) => p.staffId.equals(staffId))).get();

  Future<void> updatePayroll(Payroll entry) =>
      update(payrollTable).replace(entry);

  Future<void> approvePayroll(int payrollId, String approvedBy) =>
      (update(payrollTable)..where((p) => p.id.equals(payrollId))).write(
        PayrollTableCompanion(
          status: const Value('approved'),
          approvedBy: Value(approvedBy),
          approvedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> markPayrollPaid(int payrollId, {
    required DateTime paymentDate,
    required String paymentMethod,
  }) =>
      (update(payrollTable)..where((p) => p.id.equals(payrollId))).write(
        PayrollTableCompanion(
          status: const Value('paid'),
          paymentDate: Value(paymentDate),
          paymentMethod: Value(paymentMethod),
          updatedAt: Value(DateTime.now()),
        ),
      );

  // PERFORMANCE MANAGEMENT

  Future<List<PerformanceReview>> getReviewsByStaff(String staffId) => (select(
    performanceReviews,
  )..where((pr) => pr.staffId.equals(staffId))).get();

  Future<void> addPerformanceReview(PerformanceReviewsCompanion entry) =>
      into(performanceReviews).insert(entry);
}
