/// Shared bounds for recognising an **off-schedule shift that crosses midnight**.
///
/// A day on which the employee worked *past the end of the shift that began on
/// the attendance date* is not a late day and not an early-leave day: she
/// finished after the scheduled end, so there is nothing left to dock, and the
/// hours after the scheduled end are overtime rather than absence.
///
/// These two predicates are the single source of truth for that judgement. They
/// are pure, dependency-free and DB-free on purpose, so both
/// `AttendanceDeductionRules` (which works on persisted `Attendance` rows) and
/// `AttendanceCalculationEngine` (which only ever sees two `DateTime`s) apply
/// the exact same rule instead of drifting apart.
///
/// **Why the bounds exist.** A naive "the check-out is on a later calendar day"
/// test would also swallow a normal employee who simply forgot to clock out and
/// whose stale punch only reached the device the next morning. Two independent
/// guards keep that case fully deducted:
///   * the check-out must land before [latestCrossMidnightClockMinutes] (06:00,
///     exclusive) — a next-morning 08:30 punch can never satisfy it;
///   * the elapsed span must be at most [maxCrossMidnightElapsed] (14h,
///     inclusive) — a 21h or 45h stale-sync gap can never satisfy it.
///
/// 06:00 is deliberately more permissive than the 04:00 boundary the sync
/// service already uses for the same concept
/// (`attendance_sync_service.dart` `_resolveWorkDate` and the next-day checkout
/// window), so the deduction rule never rejects a shift the sync service
/// accepted.
class AttendanceShiftBounds {
  const AttendanceShiftBounds._();

  /// Latest clock time on the *next* calendar day that still counts as "worked
  /// through the night" rather than "clocked in the next morning". Exclusive.
  static const int latestCrossMidnightClockMinutes = 6 * 60; // 06:00

  /// Longest plausible single shift across midnight. Inclusive.
  static const Duration maxCrossMidnightElapsed = Duration(hours: 14);

  /// Local calendar day of [t], dropping the time-of-day.
  static DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Minutes since local midnight.
  static int clockMinutes(DateTime t) => t.hour * 60 + t.minute;

  /// Clause (a): a bounded, real shift that crossed midnight.
  ///
  /// True only when the check-out is on the **immediately following** calendar
  /// day, before [latestCrossMidnightClockMinutes], and the elapsed span is in
  /// `(0, maxCrossMidnightElapsed]`.
  ///
  /// The day comparison uses calendar arithmetic rather than
  /// `inDays` so a daylight-saving transition between the two timestamps cannot
  /// shift the result by one day.
  static bool isBoundedMidnightCrossing({
    required DateTime co,
    required DateTime ci,
  }) {
    final coDay = dateOnly(co);
    final ciDay = dateOnly(ci);
    if (!coDay.isAfter(ciDay)) return false;

    // Exactly the next calendar day - never two or more days later.
    if (coDay != ciDay.add(const Duration(days: 1))) return false;
    if (clockMinutes(co) >= latestCrossMidnightClockMinutes) return false;

    final elapsed = co.difference(ci);
    return elapsed > Duration.zero && elapsed <= maxCrossMidnightElapsed;
  }

  /// Clause (a) OR clause (b).
  ///
  /// Clause (b) covers the *corrupt* row shape produced by a missing midnight
  /// rollover: both timestamps sit on one calendar day while the check-out clock
  /// reads earlier than the check-in clock (e.g. `D 17:00` -> `D 00:00`). That is
  /// never a real punch pair, only a data defect, so it needs no upper bound -
  /// its raw elapsed span is negative by definition.
  ///
  /// A missing [co] or [ci] yields `false`: with no check-in there is no
  /// evidence of a real shift, so no exemption is granted (decision Q6=(a)).
  static bool isOffScheduleMidnightCrossing({
    required DateTime? co,
    required DateTime? ci,
  }) {
    if (co == null || ci == null) return false;
    if (isBoundedMidnightCrossing(co: co, ci: ci)) return true;

    // Clause (b): same calendar day, check-out clock before check-in clock.
    if (dateOnly(co).isAfter(dateOnly(ci))) return false;
    return clockMinutes(co) < clockMinutes(ci);
  }
}