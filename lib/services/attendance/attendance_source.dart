import 'package:pos_offline_desktop/core/database/app_database.dart';

enum AttendanceSourceStatus {
  idle,
  connecting,
  connected,
  fetching,
  error,
}

/// A generic interface for any physical attendance capture device
abstract class AttendanceSource {
  /// Unique identifier or IP of the device
  final String deviceIdentifier;

  AttendanceSourceStatus get status;

  AttendanceSource({required this.deviceIdentifier});

  /// Connects to the device. Returns true if successful.
  Future<bool> connect();

  /// Disconnects from the device.
  Future<void> disconnect();

  /// Fetches raw attendance events from the device.
  /// If [since] is provided, should ideally only fetch events after that time.
  Future<List<RawAttendanceEvent>> fetchEvents({DateTime? since});

  /// Optional: fetches enrolled users from the device for mapping purposes
  Future<List<DeviceEnrolledUser>> fetchEnrolledUsers() async => [];
}

/// A normalized representation of an event pulled from a device
class RawAttendanceEvent {
  final String externalUserId;
  final DateTime eventTime;
  final String? eventType; // 'check_in', 'check_out', or null if device doesn't specify
  final String? rawPayload; // the original data string/json for debugging

  RawAttendanceEvent({
    required this.externalUserId,
    required this.eventTime,
    this.eventType,
    this.rawPayload,
  });
}

class DeviceEnrolledUser {
  final String externalUserId;
  final String? name;
  final String? cardNumber;
  
  DeviceEnrolledUser({
    required this.externalUserId,
    this.name,
    this.cardNumber,
  });
}
