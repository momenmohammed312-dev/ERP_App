/// Represents a user enrolled on the ZKTeco device
class ZkUser {
  /// Internal device UID (numeric index)
  final int uid;

  /// External user/employee ID as string (e.g. "101", "EMP-01")
  final String userId;

  /// Name configured on the terminal
  final String name;

  /// Numeric or string password (if configured)
  final String? password;

  /// RFID card number (if configured)
  final String? card;

  /// User role (0: Normal User, 14: Administrator)
  final int role;

  /// Whether user is enabled on device
  final bool enabled;

  const ZkUser({
    required this.uid,
    required this.userId,
    required this.name,
    this.password,
    this.card,
    this.role = 0,
    this.enabled = true,
  });

  bool get isAdmin => role == 14;

  @override
  String toString() =>
      'ZkUser(uid: $uid, userId: $userId, name: $name, role: $role, enabled: $enabled)';
}

/// Represents an attendance check-in/out record from ZKTeco device
class ZkAttendanceRecord {
  /// User/Employee ID on the device
  final String userId;

  /// Exact timestamp of the event
  final DateTime timestamp;

  /// Status code: 0 = Check-in, 1 = Check-out, 2 = Break-out, 3 = Break-in, 4 = OT-in, 5 = OT-out
  final int status;

  /// Verification type: 1 = Fingerprint, 2 = Password, 3 = Card, 4 = Face, 15 = Other
  final int verifyType;

  const ZkAttendanceRecord({
    required this.userId,
    required this.timestamp,
    this.status = 0,
    this.verifyType = 1,
  });

  /// Normalizes status into standardized string
  String get eventType {
    switch (status) {
      case 0:
        return 'check_in';
      case 1:
        return 'check_out';
      default:
        return 'unknown';
    }
  }

  @override
  String toString() =>
      'ZkAttendanceRecord(userId: $userId, timestamp: $timestamp, status: $status, verifyType: $verifyType)';
}

/// Device information details
class ZkDeviceInfo {
  final String? firmwareVersion;
  final String? deviceName;
  final String? serialNumber;
  final String? platform;
  final String? macAddress;
  final int? userCount;
  final int? attendanceCount;
  final DateTime? deviceTime;

  const ZkDeviceInfo({
    this.firmwareVersion,
    this.deviceName,
    this.serialNumber,
    this.platform,
    this.macAddress,
    this.userCount,
    this.attendanceCount,
    this.deviceTime,
  });

  @override
  String toString() =>
      'ZkDeviceInfo(firmware: $firmwareVersion, name: $deviceName, sn: $serialNumber, time: $deviceTime)';
}
