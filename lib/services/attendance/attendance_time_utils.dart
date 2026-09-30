import 'package:flutter/material.dart' show TimeOfDay;

/// Pairs a check-in and a check-out clock reading onto one attendance [date].
///
/// Both readings are stamped on the *same* calendar day by the dialogs that
/// collect them, because that is the work date. When the check-out clock reads
/// earlier than the check-in clock the employee worked **past midnight**, so the
/// check-out is rolled onto the following calendar day. That is the only
/// interpretation consistent with "checked in, then left": a same-day pair whose
/// out-time precedes its in-time is never a real punch sequence.
///
/// This helper exists because two dialogs implemented it differently:
/// `attendance_page.dart` rolled the check-out forward, while
/// `manual_override_dialog.dart` did not and therefore wrote negative
/// `working_hours` (e.g. -17h for a 17:00 -> 00:00 shift).
///
/// For a normal same-day shift (`out >= in`) this returns exactly the pair both
/// call sites previously built, so it changes nothing for them.
({DateTime? checkIn, DateTime? checkOut}) pairCheckInOut(
  DateTime date,
  TimeOfDay? checkIn,
  TimeOfDay? checkOut,
) {
  final checkInTime = checkIn == null
      ? null
      : DateTime(date.year, date.month, date.day, checkIn.hour, checkIn.minute);

  var checkOutTime = checkOut == null
      ? null
      : DateTime(date.year, date.month, date.day, checkOut.hour, checkOut.minute);

  if (checkOutTime != null &&
      checkInTime != null &&
      checkOutTime.isBefore(checkInTime)) {
    checkOutTime = checkOutTime.add(const Duration(days: 1));
  }
  return (checkIn: checkInTime, checkOut: checkOutTime);
}

/// Worked span in hours for an already-paired check-in/check-out, or `null` when
/// the pair is incomplete. Mirrors the engine rule: never negative.
double? workedHoursFrom(DateTime? checkInTime, DateTime? checkOutTime) {
  if (checkInTime == null || checkOutTime == null) return null;
  final minutes = checkOutTime.difference(checkInTime).inMinutes;
  return minutes < 0 ? 0.0 : minutes / 60.0;
}
