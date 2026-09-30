import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_shift_bounds.dart';

/// Group D (threshold boundaries) + the shared-module contract, as a pure
/// Dart suite with no database.
///
/// The bounds exist for exactly one reason: a normal employee who forgot to
/// clock out, whose punch only reached the device the next morning, must stay
/// fully deducted. Group B in attendance_offschedule_shift_test.dart pins that
/// through the deduction rules; this file pins the primitive itself.
void main() {
  // A Monday, so a "next day" check-out is unambiguous.
  final mon9 = DateTime(2026, 9, 14, 9);
  final mon17 = DateTime(2026, 9, 14, 17);
  final tue = DateTime(2026, 9, 15);

  bool bounded(DateTime co, DateTime ci) =>
      AttendanceShiftBounds.isBoundedMidnightCrossing(co: co, ci: ci);

  bool off(DateTime co, DateTime ci) =>
      AttendanceShiftBounds.isOffScheduleMidnightCrossing(co: co, ci: ci);

  group('constants', () {
    test('the published limits are 06:00 exclusive and 14h inclusive', () {
      expect(AttendanceShiftBounds.latestCrossMidnightClockMinutes, 6 * 60);
      expect(AttendanceShiftBounds.maxCrossMidnightElapsed,
          const Duration(hours: 14));
    });
  });

  group('clause (a): a bounded, real shift that crossed midnight', () {
    test('17:00 -> next day 00:00 is a crossing', () {
      expect(bounded(DateTime(2026, 9, 15), mon17), isTrue);
      expect(bounded(DateTime(2026, 9, 15), mon17), isTrue);
    });

    test('20:00 -> next day 02:30 (a night schedule) is a crossing', () {
      expect(
          bounded(DateTime(2026, 9, 15, 2, 30), DateTime(2026, 9, 14, 20)),
          isTrue);
    });

    test('the 06:00 boundary is EXCLUSIVE: 05:59 passes, 06:00 fails', () {
      expect(bounded(DateTime(2026, 9, 15, 5, 59), mon17), isTrue);
      expect(bounded(DateTime(2026, 9, 15, 6, 0), mon17), isFalse);
    });

    test('the 14h elapsed boundary is INCLUSIVE: exactly 14h passes', () {
      // 17:00 + 14h = next day 07:00, but 07:00 is past the 06:00 clock bound,
      // so the clock bound is the one that rejects it. Use a check-in early
      // enough for the elapsed bound to be the binding constraint:
      // 16:00 + 14h = next day 06:00 -> clock bound rejects. 15:00 + 14h =
      // next day 05:00 -> both satisfied.
      expect(bounded(DateTime(2026, 9, 15, 5), DateTime(2026, 9, 14, 15)),
          isTrue);
    });

    test('one minute over 14h is rejected', () {
      expect(
        bounded(DateTime(2026, 9, 15, 5, 1), DateTime(2026, 9, 14, 15)),
        isFalse,
      );
    });

    test('exactly the next calendar day is required; two days later is not', () {
      expect(bounded(DateTime(2026, 9, 15, 2), mon17), isTrue);
      expect(bounded(DateTime(2026, 9, 16, 2), mon17), isFalse);
      expect(bounded(DateTime(2026, 9, 16, 2), mon9), isFalse);
    });

    test('a same-day span is never clause (a)', () {
      expect(bounded(DateTime(2026, 9, 14, 20), mon9), isFalse);
    });
  });

  group('the forgotten-check-out case must NOT be exempted', () {
    // ci Monday 09:00, co Tuesday 08:30 -> rejected by BOTH bounds.
    test('09:00 Mon -> 08:30 Tue: clock bound rejects', () {
      expect(bounded(tue.add(const Duration(hours: 8, minutes: 30)), mon9),
          isFalse);
    });

    test('09:00 Mon -> 08:30 Tue: elapsed bound rejects too', () {
      final co = tue.add(const Duration(hours: 8, minutes: 30));
      expect(co.difference(mon9) > AttendanceShiftBounds.maxCrossMidnightElapsed,
          isTrue);
    });

    // ci Monday 08:00, co Tuesday 05:00 -> clock bound passes, elapsed fails.
    test('08:00 Mon -> 05:00 Tue passes the clock bound but fails elapsed', () {
      final ci = DateTime(2026, 9, 14, 8);
      final co = DateTime(2026, 9, 15, 5);
      expect(AttendanceShiftBounds.clockMinutes(co),
          lessThan(AttendanceShiftBounds.latestCrossMidnightClockMinutes));
      expect(co.difference(ci), greaterThan(const Duration(hours: 14)));
      expect(bounded(co, ci), isFalse);
      expect(off(co, ci), isFalse);
    });

    test('a stale two-day gap is not exempted', () {
      expect(bounded(DateTime(2026, 9, 16, 5), mon9), isFalse);
    });
  });

  group('clause (b): the corrupt same-day shape', () {
    test('17:00 -> 00:00 on one calendar day is a crossing', () {
      final ci = DateTime(2026, 9, 14, 17);
      final co = DateTime(2026, 9, 14);
      expect(bounded(co, ci), isFalse, reason: 'clause (a) must not match');
      expect(off(co, ci), isTrue, reason: 'clause (b) must carry it');
    });

    test('clause (b) is not bounded by the 14h elapsed limit', () {
      final ci = DateTime(2026, 9, 14, 22);
      final co = DateTime(2026, 9, 14);
      expect(co.difference(ci), const Duration(hours: -22));
      expect(off(co, ci), isTrue);
    });

    test('an ordinary same-day pair is not clause (b)', () {
      expect(off(DateTime(2026, 9, 14, 17), mon9), isFalse);
      expect(off(DateTime(2026, 9, 14, 15), mon9), isFalse);
    });
  });

  group('nulls (decision Q6 = (a): no check-in means no exemption)', () {
    test('a null check-out yields false', () {
      expect(
        AttendanceShiftBounds.isOffScheduleMidnightCrossing(
            co: null, ci: mon17),
        isFalse,
      );
    });

    test('a null check-in yields false even with a past-midnight check-out', () {
      expect(
        AttendanceShiftBounds.isOffScheduleMidnightCrossing(
            co: DateTime(2026, 9, 15, 2), ci: null),
        isFalse,
      );
    });

    test('both null yields false', () {
      expect(
        AttendanceShiftBounds.isOffScheduleMidnightCrossing(
            co: null, ci: null),
        isFalse,
      );
    });
  });

  group('normal same-day shifts are untouched', () {
    test('every same-day in/out pair with out >= in is not a crossing', () {
      const step = 15;
      final violations = <String>[];
      for (var inMin = 0; inMin < 1440; inMin += step) {
        for (var outMin = inMin; outMin < 1440; outMin += step) {
          final ci = DateTime(2026, 9, 14).add(Duration(minutes: inMin));
          final co = DateTime(2026, 9, 14).add(Duration(minutes: outMin));
          if (off(co, ci)) violations.add('in=$inMin out=$outMin');
        }
      }
      expect(violations, isEmpty);
    });
  });

  group('helpers', () {
    test('dateOnly drops the time-of-day', () {
      expect(AttendanceShiftBounds.dateOnly(DateTime(2026, 9, 14, 23, 59)),
          DateTime(2026, 9, 14));
    });

    test('clockMinutes counts minutes since local midnight', () {
      expect(AttendanceShiftBounds.clockMinutes(DateTime(2026, 9, 14, 6)), 360);
      expect(AttendanceShiftBounds.clockMinutes(DateTime(2026, 9, 14)), 0);
    });
  });
}
