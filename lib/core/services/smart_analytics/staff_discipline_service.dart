import 'package:drift/drift.dart';
import '../../database/app_database.dart';

class StaffDisciplineItem {
  final String staffId;
  final String staffName;
  final String issueType; // 'consecutive_absence' | 'frequent_absence' | 'frequent_tardiness'
  final int count; // number of days absent or times late
  final int totalLateMinutes;
  final String severity; // 'critical' | 'warning' | 'info'
  final String title;
  final String recommendation;

  const StaffDisciplineItem({
    required this.staffId,
    required this.staffName,
    required this.issueType,
    required this.count,
    this.totalLateMinutes = 0,
    required this.severity,
    required this.title,
    required this.recommendation,
  });
}

/// Service that analyzes employee attendance, absences, and tardiness patterns.
class StaffDisciplineService {
  final AppDatabase _db;

  StaffDisciplineService(this._db);

  /// Analyzes the last 14 days of attendance for all active staff members.
  Future<List<StaffDisciplineItem>> analyzeStaffDiscipline({
    DateTime? referenceDate,
    int lookbackDays = 14,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final lookbackStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: lookbackDays));

    // 1. Fetch all active employees
    final activeStaff = await (_db.select(_db.staffTable)
          ..where((s) => s.isActive.equals(true) & s.status.equals('active')))
        .get();

    if (activeStaff.isEmpty) return [];

    final results = <StaffDisciplineItem>[];

    for (final staff in activeStaff) {
      // 2. Fetch attendance rows in lookback window
      final attendances = await (_db.select(_db.attendanceTable)
            ..where((a) =>
                a.staffId.equals(staff.staffId) &
                a.date.isBiggerOrEqualValue(lookbackStart))
            ..orderBy([(a) => OrderingTerm(expression: a.date, mode: OrderingMode.asc)]))
          .get();

      if (attendances.isEmpty) continue;

      // Group unexcused absences and tardiness
      final unexcusedAbsences = attendances.where((a) {
        return a.status == 'absent' && !a.excused;
      }).toList();

      final tardyRows = attendances.where((a) {
        final isLateStatus = a.status == 'late';
        final hasLateMinutes = a.lateMinutes >= 15;
        return (isLateStatus || hasLateMinutes) && !a.excused;
      }).toList();

      // Check consecutive absences ending recently
      int consecutiveAbsenceStreak = 0;
      for (int i = attendances.length - 1; i >= 0; i--) {
        final row = attendances[i];
        if (row.status == 'absent' && !row.excused) {
          consecutiveAbsenceStreak++;
        } else if (row.status == 'present' || row.status == 'late' || row.excused) {
          break;
        }
      }

      // Rule A: Consecutive absences (>= 2 days)
      if (consecutiveAbsenceStreak >= 2) {
        results.add(StaffDisciplineItem(
          staffId: staff.staffId,
          staffName: staff.name,
          issueType: 'consecutive_absence',
          count: consecutiveAbsenceStreak,
          severity: consecutiveAbsenceStreak >= 3 ? 'critical' : 'warning',
          title: 'غياب متتالي: ${staff.name}',
          recommendation:
              'الموظف غائب منذ $consecutiveAbsenceStreak أيام متتالية دون تسجيل عذر مسبق. يُرجى مراجعته والتأكد من انتظام العمل.',
        ));
      }
      // Rule B: High aggregate unexcused absences in lookback window (>= 3 days)
      else if (unexcusedAbsences.length >= 3) {
        results.add(StaffDisciplineItem(
          staffId: staff.staffId,
          staffName: staff.name,
          issueType: 'frequent_absence',
          count: unexcusedAbsences.length,
          severity: 'warning',
          title: 'تكرار غياب: ${staff.name}',
          recommendation:
              'الموظف تغيب ${unexcusedAbsences.length} أيام خلال آخر $lookbackDays يوماً بدون عذر رسمي.',
        ));
      }

      // Rule C: Frequent tardiness (>= 3 times)
      if (tardyRows.length >= 3) {
        final totalLateMinutes =
            tardyRows.fold<int>(0, (sum, a) => sum + (a.lateMinutes > 0 ? a.lateMinutes : 15));
        results.add(StaffDisciplineItem(
          staffId: staff.staffId,
          staffName: staff.name,
          issueType: 'frequent_tardiness',
          count: tardyRows.length,
          totalLateMinutes: totalLateMinutes,
          severity: tardyRows.length >= 5 ? 'warning' : 'info',
          title: 'تأخير متكرر: ${staff.name}',
          recommendation:
              'تأخر الموظف ${tardyRows.length} مرات بإجمالي $totalLateMinutes دقيقة مهدرة خلال آخر $lookbackDays يوماً.',
        ));
      }
    }

    // Sort: critical first, then warning, then info
    results.sort((a, b) {
      final prioA = a.severity == 'critical' ? 0 : (a.severity == 'warning' ? 1 : 2);
      final prioB = b.severity == 'critical' ? 0 : (b.severity == 'warning' ? 1 : 2);
      return prioA.compareTo(prioB);
    });

    return results;
  }
}
