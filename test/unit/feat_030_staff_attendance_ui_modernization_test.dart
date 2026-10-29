import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FEAT-030: Staff & Attendance UI Modernization Tests', () {
    test('StaffListPage: Redundant "لوحة الموظفين" button is removed', () {
      final file = File('lib/ui/staff/staff_list_page.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Ensure the redundant tooltip and navigation to EmployeeDashboardPage are removed from the AppBar
      expect(source.contains("tooltip: 'لوحة الموظفين'"), isFalse);
      expect(source.contains("import 'employee_dashboard_page.dart';"), isFalse);
    });

    test('EmployeeDashboardPage: Modern KPI metric cards, attendance status pills & quick actions', () {
      final file = File('lib/ui/staff/employee_dashboard_page.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Check MadarColors integration
      expect(source.contains('MadarColors'), isTrue);

      // Check modern metric card improvements (rounded 16px, icon container, indicator pill)
      expect(source.contains('BorderRadius.circular(16)'), isTrue);
      expect(source.contains('LinearGradient'), isTrue);
      expect(source.contains('BoxShadow'), isTrue);

      // Check attendance status cards with distinct icons & colored containers
      expect(source.contains('Icons.check_circle_outline'), isTrue);
      expect(source.contains('Icons.cancel_outlined'), isTrue);
      expect(source.contains('Icons.access_time'), isTrue);

      // Check quick actions modernized buttons
      expect(source.contains('Icons.people_alt_outlined'), isTrue);
      expect(source.contains('Icons.person_add_alt_1_outlined'), isTrue);
      expect(source.contains('Icons.fingerprint_rounded'), isTrue);
    });

    test('StaffDetailsPage: Modern dark header replaces harsh blue block & styled dark tabs', () {
      final file = File('lib/ui/staff/staff_details_page.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Ensure harsh light blue block is removed
      expect(source.contains('Colors.blue[700]'), isFalse);
      expect(source.contains('Colors.blue[500]'), isFalse);

      // Ensure MadarColors is used
      expect(source.contains('MadarColors.bgDark'), isTrue);
      expect(source.contains('MadarColors.bgCard'), isTrue);
      expect(source.contains('MadarColors.gold'), isTrue);

      // Check header chips & status badge
      expect(source.contains('_buildHeaderChip'), isTrue);
      expect(source.contains('MadarColors.success'), isTrue);
      expect(source.contains('MadarColors.textLight'), isTrue);
    });

    test('StaffFormPage: Modern form cards, dark input decoration & styled action buttons', () {
      final file = File('lib/ui/staff/staff_form_page.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Ensure muddy grey cards are removed
      expect(source.contains('Color(0xFF3A3A3A)'), isFalse);
      expect(source.contains('Color(0xFF2D2D2D)'), isFalse);

      // Ensure form cards use modern container & MadarColors
      expect(source.contains('_buildFormCard'), isTrue);
      expect(source.contains('MadarColors.bgCard'), isTrue);
      expect(source.contains('MadarColors.border'), isTrue);
      expect(source.contains('MadarColors.success'), isTrue);

      // Check input decoration uses dark fill and gold focus border
      expect(source.contains('fillColor: MadarColors.bgDark.withValues(alpha: 0.6)'), isTrue);
      expect(source.contains('borderSide: const BorderSide(color: MadarColors.gold, width: 1.5)'), isTrue);
    });

    test('DeviceManagementPage: Card-based device layout, status pills & clean action toolbar', () {
      final file = File('lib/ui/staff/device_management_page.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Check device card helper
      expect(source.contains('_buildDeviceCard'), isTrue);
      expect(source.contains('_buildDeviceBadge'), isTrue);
      expect(source.contains('MadarColors.bgCard'), isTrue);
      expect(source.contains('MadarColors.bgDark'), isTrue);

      // Check device connection badges (TCP/IP, file_import)
      expect(source.contains('Icons.router_outlined'), isTrue);
      expect(source.contains('Icons.description_outlined'), isTrue);
    });

    test('AttendanceSettingsPage: Grouped modern cards, day selector pills & styled save action', () {
      final file = File('lib/ui/staff/attendance_settings_page.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Check modern section container with icon badge
      expect(source.contains('MadarColors.bgCard'), isTrue);
      expect(source.contains('MadarColors.border'), isTrue);
      expect(source.contains('MadarColors.gold'), isTrue);

      // Check day chip styling
      expect(source.contains('MadarColors.success.withValues(alpha: 0.25)'), isTrue);

      // Check styled save button in AppBar
      expect(source.contains("'حفظ الإعدادات'"), isTrue);
      expect(source.contains('ElevatedButton.icon'), isTrue);
    });
  });
}
