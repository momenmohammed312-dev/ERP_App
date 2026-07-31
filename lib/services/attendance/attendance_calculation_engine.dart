import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';

/// Work schedule configuration for an employee
class ScheduleConfig {
  final int workStartHour;
  final int workStartMinute;
  final int workEndHour;
  final int workEndMinute;
  final List<int> workDays; // 0=Sunday ... 6=Saturday
  final int weekendDay; // 0=Sunday ... 6=Saturday
  final int gracePeriodMinutes;
  final double standardHoursPerDay;
  final double overtimeRateMultiplier;

  const ScheduleConfig({
    required this.workStartHour,
    required this.workStartMinute,
    required this.workEndHour,
    required this.workEndMinute,
    required this.workDays,
    required this.weekendDay,
    required this.gracePeriodMinutes,
    required this.standardHoursPerDay,
    required this.overtimeRateMultiplier,
  });

  DateTime get workStartToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, workStartHour, workStartMinute);
  }

  DateTime get workEndToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, workEndHour, workEndMinute);
  }

  int get workStartMinutesSinceMidnight => workStartHour * 60 + workStartMinute;
  int get workEndMinutesSinceMidnight => workEndHour * 60 + workEndMinute;
  int get standardMinutesPerDay => workEndMinutesSinceMidnight - workStartMinutesSinceMidnight;
  int get standardMinutesTotal => standardMinutesPerDay; // alias for clarity
}

/// Result of attendance status calculation
class AttendanceCalcResult {
  final String status; // 'present', 'late', 'early_leave', 'absent'
  final double workingHours;
  final double overtimeHours;
  final int lateMinutes;
  final bool isWorkDay;

  const AttendanceCalcResult({
    required this.status,
    required this.workingHours,
    required this.overtimeHours,
    required this.lateMinutes,
    required this.isWorkDay,
  });
}

/// Engine that calculates attendance status, working hours, overtime, and late penalties
class AttendanceCalculationEngine {
  final AppDatabase _db;
  final AttendanceDeviceDao _deviceDao;
  final StaffManagementDao _staffDao;

  AttendanceCalculationEngine(this._db, this._deviceDao, this._staffDao);

  /// Parses a time string like '09:00' into (hour, minute)
  static (int hour, int minute) _parseTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return (9, 0);
    final h = int.tryParse(parts[0]) ?? 9;
    final m = int.tryParse(parts[1]) ?? 0;
    return (h, m);
  }

  /// Parses work days string like 'sun,mon,tue,wed,thu' into list of day indices
  static List<int> _parseWorkDays(String? daysStr) {
    if (daysStr == null || daysStr.isEmpty) {
      return [0, 1, 2, 3, 4]; // Default: Sun-Thu
    }
    final dayMap = {
      'sun': 0, 'mon': 1, 'tue': 2, 'wed': 3,
      'thu': 4, 'fri': 5, 'sat': 6,
    };
    return daysStr
        .split(',')
        .map((d) => dayMap[d.trim().toLowerCase()])
        .whereType<int>()
        .toList();
  }

  /// Parses weekend day string like 'fri' into day index
  static int _parseWeekendDay(String? dayStr) {
    if (dayStr == null || dayStr.isEmpty) return 5; // Default: Friday
    final dayMap = {
      'sun': 0, 'mon': 1, 'tue': 2, 'wed': 3,
      'thu': 4, 'fri': 5, 'sat': 6,
    };
    return dayMap[dayStr.trim().toLowerCase()] ?? 5;
  }

  /// Fetches a setting value from attendance_settings table
  Future<String> _getSetting(String key, String defaultValue) async {
    try {
      final result = await (_db.select(_db.attendanceSettings)
            ..where((s) => s.settingKey.equals(key)))
          .getSingleOrNull();
      return result?.settingValue ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// Gets the schedule configuration for a specific staff member
  /// Falls back to default settings if the employee has no custom schedule
  Future<ScheduleConfig> getScheduleForStaff(String staffId) async {
    final staff = await _staffDao.getStaffById(staffId);

    // Check if employee has custom schedule
    if (staff != null && !staff.useDefaultSchedule) {
      final start = staff.workScheduleStart != null
          ? _parseTime(staff.workScheduleStart!)
          : (9, 0);
      final end = staff.workScheduleEnd != null
          ? _parseTime(staff.workScheduleEnd!)
          : (17, 0);
      final days = _parseWorkDays(staff.workDays);
      final weekend = _parseWeekendDay(staff.weekendDay);

      return ScheduleConfig(
        workStartHour: start.$1,
        workStartMinute: start.$2,
        workEndHour: end.$1,
        workEndMinute: end.$2,
        workDays: days.isEmpty ? [0, 1, 2, 3, 4] : days,
        weekendDay: weekend,
        gracePeriodMinutes: int.tryParse(await _getSetting('grace_period_minutes', '15')) ?? 15,
        standardHoursPerDay: double.tryParse(await _getSetting('overtime_threshold_hours', '8')) ?? 8.0,
        overtimeRateMultiplier: double.tryParse(await _getSetting('overtime_rate_multiplier', '1.5')) ?? 1.5,
      );
    }

    // Use default settings
    final startStr = await _getSetting('default_work_start', '09:00');
    final endStr = await _getSetting('default_work_end', '17:00');
    final workDaysStr = await _getSetting('default_work_days', 'sun,mon,tue,wed,thu');
    final weekendStr = await _getSetting('default_weekend', 'fri');
    final graceStr = await _getSetting('grace_period_minutes', '15');
    final hoursStr = await _getSetting('overtime_threshold_hours', '8');
    final rateStr = await _getSetting('overtime_rate_multiplier', '1.5');

    final start = _parseTime(startStr);
    final end = _parseTime(endStr);

    return ScheduleConfig(
      workStartHour: start.$1,
      workStartMinute: start.$2,
      workEndHour: end.$1,
      workEndMinute: end.$2,
      workDays: _parseWorkDays(workDaysStr),
      weekendDay: _parseWeekendDay(weekendStr),
      gracePeriodMinutes: int.tryParse(graceStr) ?? 15,
      standardHoursPerDay: double.tryParse(hoursStr) ?? 8.0,
      overtimeRateMultiplier: double.tryParse(rateStr) ?? 1.5,
    );
  }

  /// Checks if a given date is a work day for the employee
  bool isWorkDay(DateTime date, ScheduleConfig schedule) {
    // DateTime.weekday: 1=Monday ... 7=Sunday
    // Our mapping: 0=Sunday ... 6=Saturday
    final dartWeekday = date.weekday; // 1-7
    // Convert to our format: Sunday=0, Monday=1, ... Saturday=6
    final dayIndex = dartWeekday % 7; // Sunday(7)%7=0, Monday(1)%7=1, ... Saturday(6)%7=6
    return schedule.workDays.contains(dayIndex);
  }

  /// Calculates attendance status and working hours for a check-in/check-out pair
  AttendanceCalcResult calculateAttendance({
    required DateTime checkInTime,
    DateTime? checkOutTime,
    required ScheduleConfig schedule,
  }) {
    final checkInMinutes = checkInTime.hour * 60 + checkInTime.minute;
    final scheduleStart = schedule.workStartMinutesSinceMidnight;
    final scheduleEnd = schedule.workEndMinutesSinceMidnight;
    final graceEnd = scheduleStart + schedule.gracePeriodMinutes;

    // Determine status
    String status;
    int lateMinutes = 0;

    if (checkInMinutes <= scheduleStart) {
      status = 'present';
    } else if (checkInMinutes <= graceEnd) {
      status = 'present'; // Within grace period
    } else {
      status = 'late';
      lateMinutes = checkInMinutes - scheduleStart;
    }

    // Calculate working hours and overtime
    double workingHours = 0;
    double overtimeHours = 0;

    if (checkOutTime != null) {
      final totalMinutes = checkOutTime.difference(checkInTime).inMinutes;
      final standardMinutes = schedule.standardMinutesPerDay; // already in minutes

      if (totalMinutes <= standardMinutes) {
        workingHours = totalMinutes / 60.0;
        overtimeHours = 0;
      } else {
        workingHours = schedule.standardHoursPerDay;
        overtimeHours = (totalMinutes - standardMinutes) / 60.0;
      }

      // Early leave: checked out before scheduled end
      final checkOutMinutes = checkOutTime.hour * 60 + checkOutTime.minute;
      if (checkOutMinutes < scheduleEnd && status != 'late') {
        // If they left early but were present, mark as early leave
        // (but keep 'present' if they worked enough hours)
        if (totalMinutes < standardMinutes * 0.5) {
          status = 'early_leave';
        }
      }
    }

    return AttendanceCalcResult(
      status: status,
      workingHours: workingHours,
      overtimeHours: overtimeHours,
      lateMinutes: lateMinutes,
      isWorkDay: true,
    );
  }

  /// Generates absence records for employees who didn't check in on a work day
  /// Returns the number of absence records created
  Future<int> generateAbsencesForDate(DateTime date) async {
    int created = 0;
    final activeStaff = await _staffDao.getActiveStaff();
    final dateOnly = DateTime(date.year, date.month, date.day);
    final nextDay = dateOnly.add(const Duration(days: 1));

    // Batch: fetch all attendance records for all staff for this date in one query
    final allStaffIds = activeStaff.map((s) => s.staffId).toList();
    final allRecords = await Future.wait(
      allStaffIds.map((id) => _staffDao.getAttendanceByStaff(id, startDate: dateOnly, endDate: nextDay)),
    );

    // Build a set of staff IDs that already have attendance for this date
    final staffWithAttendance = <String>{};
    for (int i = 0; i < allRecords.length; i++) {
      final todayRecord = allRecords[i].where((a) {
        final aDate = DateTime(a.date.year, a.date.month, a.date.day);
        return aDate == dateOnly;
      }).toList();
      if (todayRecord.isNotEmpty) {
        staffWithAttendance.add(allStaffIds[i]);
      }
    }

    // Create absences only for staff without records
    for (final staff in activeStaff) {
      if (staffWithAttendance.contains(staff.staffId)) continue;

      final schedule = await getScheduleForStaff(staff.staffId);
      if (!isWorkDay(date, schedule)) continue;

      await _staffDao.addAttendance(AttendanceTableCompanion.insert(
        staffId: staff.staffId,
        date: dateOnly,
        status: 'absent',
        source: const Value('auto_generated'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      created++;
    }

    return created;
  }

  /// Processes a check-in with smart status detection
  /// Returns the calculated status ('present' or 'late')
  Future<String> processCheckIn(String staffId, {DateTime? checkInTime}) async {
    final time = checkInTime ?? DateTime.now();
    final schedule = await getScheduleForStaff(staffId);
    final result = calculateAttendance(checkInTime: time, schedule: schedule);
    return result.status;
  }

  /// Processes a check-out with working hours and overtime calculation
  /// Returns the calculated result
  Future<AttendanceCalcResult> processCheckOut(
    String staffId, {
    required DateTime checkInTime,
    DateTime? checkOutTime,
  }) async {
    final time = checkOutTime ?? DateTime.now();
    final schedule = await getScheduleForStaff(staffId);
    return calculateAttendance(
      checkInTime: checkInTime,
      checkOutTime: time,
      schedule: schedule,
    );
  }
}
