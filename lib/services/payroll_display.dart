import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Centralized display math for payroll figures (locked rules).
/// Fixes the old disease of every screen recomputing absence as
/// `absentDays × (basic/30)` — which ignores the ×mult and the weekly ÷6.
class PayrollDisplay {
  /// Effective base pay + daily divisor: weekly staff use their independent
  /// weekly salary ÷ 6, everyone else basic salary ÷ 30.
  static ({double base, double divisor}) baseOf(Staff staff) {
    if (staff.payFrequency == 'weekly' && staff.weeklySalary != null) {
      return (base: staff.weeklySalary!, divisor: 6);
    }
    return (base: staff.basicSalary, divisor: 30);
  }

  /// Absence deduction as stored in payroll_table (includes ×mult).
  /// Falls back to recompute only for legacy rows with zero deductions.
  static double absenceDeduction(Payroll p, {bool weekly = false}) {
    var absentDed = p.deductions -
        p.lateDeduction -
        p.permissionDeduction -
        p.advances -
        p.penaltiesTotal;
    if (absentDed < 0) absentDed = 0;
    if (p.deductions == 0 && p.absentDays > 0) {
      absentDed = p.absentDays * (p.basicSalary / (weekly ? 6 : 30));
    }
    return absentDed;
  }

  /// Hourly rate for previews, honoring an explicit hourlyRate first.
  static double hourlyOf(Staff staff, double standardHoursPerDay) {
    final b = baseOf(staff);
    return staff.hourlyRate ?? (b.base / b.divisor / standardHoursPerDay);
  }
}
