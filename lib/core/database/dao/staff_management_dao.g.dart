// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff_management_dao.dart';

// ignore_for_file: type=lint
mixin _$StaffManagementDaoMixin on DatabaseAccessor<AppDatabase> {
  $StaffTableTable get staffTable => attachedDatabase.staffTable;
  $AttendanceTableTable get attendanceTable => attachedDatabase.attendanceTable;
  $VacationsTable get vacations => attachedDatabase.vacations;
  $StaffAdvancesTable get staffAdvances => attachedDatabase.staffAdvances;
  $PayrollTableTable get payrollTable => attachedDatabase.payrollTable;
  $RewardsPenaltiesTable get rewardsPenalties =>
      attachedDatabase.rewardsPenalties;
  $PerformanceReviewsTable get performanceReviews =>
      attachedDatabase.performanceReviews;
  $StaffDocumentsTable get staffDocuments => attachedDatabase.staffDocuments;
  StaffManagementDaoManager get managers => StaffManagementDaoManager(this);
}

class StaffManagementDaoManager {
  final _$StaffManagementDaoMixin _db;
  StaffManagementDaoManager(this._db);
  $$StaffTableTableTableManager get staffTable =>
      $$StaffTableTableTableManager(_db.attachedDatabase, _db.staffTable);
  $$AttendanceTableTableTableManager get attendanceTable =>
      $$AttendanceTableTableTableManager(
        _db.attachedDatabase,
        _db.attendanceTable,
      );
  $$VacationsTableTableManager get vacations =>
      $$VacationsTableTableManager(_db.attachedDatabase, _db.vacations);
  $$StaffAdvancesTableTableManager get staffAdvances =>
      $$StaffAdvancesTableTableManager(_db.attachedDatabase, _db.staffAdvances);
  $$PayrollTableTableTableManager get payrollTable =>
      $$PayrollTableTableTableManager(_db.attachedDatabase, _db.payrollTable);
  $$RewardsPenaltiesTableTableManager get rewardsPenalties =>
      $$RewardsPenaltiesTableTableManager(
        _db.attachedDatabase,
        _db.rewardsPenalties,
      );
  $$PerformanceReviewsTableTableManager get performanceReviews =>
      $$PerformanceReviewsTableTableManager(
        _db.attachedDatabase,
        _db.performanceReviews,
      );
  $$StaffDocumentsTableTableManager get staffDocuments =>
      $$StaffDocumentsTableTableManager(
        _db.attachedDatabase,
        _db.staffDocuments,
      );
}
