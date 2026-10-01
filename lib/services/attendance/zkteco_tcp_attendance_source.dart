import 'attendance_source.dart';
import 'zkteco/zkteco_client.dart';
import 'zkteco/zkteco_models.dart';

/// Real implementation of AttendanceSource for ZKTeco Standalone TCP/IP terminals
class ZKTecoTcpAttendanceSource extends AttendanceSource {
  final String ipAddress;
  final int port;
  final String? authToken;
  final ZKTecoClient _client;

  AttendanceSourceStatus _status = AttendanceSourceStatus.idle;

  @override
  AttendanceSourceStatus get status => _status;

  /// Last client failure detail (Arabic) — restored for truthful sync errors.
  String? get lastError => _client.lastError;

  ZkFetchReport? get lastFetchReport => _client.lastFetchReport;

  ZKTecoTcpAttendanceSource({
    required this.ipAddress,
    required this.port,
    this.authToken,
    Duration timeout = const Duration(seconds: 8),
  }) : _client = ZKTecoClient(
         host: ipAddress,
         port: port,
         commKey: int.tryParse(authToken ?? '') ?? 0,
         timeout: timeout,
       ),
       super(deviceIdentifier: '$ipAddress:$port');

  @override
  Future<bool> connect() async {
    _status = AttendanceSourceStatus.connecting;
    try {
      final success = await _client.connect();
      if (success) {
        _status = AttendanceSourceStatus.connected;
        return true;
      } else {
        _status = AttendanceSourceStatus.error;
        return false;
      }
    } catch (_) {
      _status = AttendanceSourceStatus.error;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _client.disconnect();
    } finally {
      _status = AttendanceSourceStatus.idle;
    }
  }

  @override
  Future<List<RawAttendanceEvent>> fetchEvents({DateTime? since}) async {
    _status = AttendanceSourceStatus.fetching;
    try {
      final report = await _client.fetchAttendanceReport(since: since);
      _status = AttendanceSourceStatus.connected;

      return report.records.map((record) {
        final timestamp = record.timestamp;
        final eventTime = DateTime(
          timestamp.year,
          timestamp.month,
          timestamp.day,
          timestamp.hour,
          timestamp.minute,
          timestamp.second,
        );
        return RawAttendanceEvent(
          externalUserId: record.userId,
          eventTime: eventTime,
          eventType: record.eventType,
          rawPayload:
              '{"userId":"${record.userId}","time":"${eventTime.toIso8601String()}","status":${record.status},"verifyType":${record.verifyType}}',
        );
      }).toList();
    } catch (_) {
      _status = AttendanceSourceStatus.error;
      rethrow;
    }
  }

  @override
  Future<List<DeviceEnrolledUser>> fetchEnrolledUsers() async {
    // Restored: never swallow into an empty list — an empty-looking device
    // ("nothing happens" on import) is indistinguishable from a fetch
    // failure unless the error surfaces.
    try {
      final users = await _client.getUsers();
      return users.map((u) {
        return DeviceEnrolledUser(
          externalUserId: u.userId,
          name: u.name,
          cardNumber: u.card,
        );
      }).toList();
    } catch (e) {
      final detail = _client.lastError;
      if (detail != null && detail.isNotEmpty) throw Exception(detail);
      throw Exception('تعذر قراءة مستخدمي الجهاز: $e');
    }
  }

  /// Direct access to device info (Firmware, serial number, device time)
  Future<ZkDeviceInfo> getDeviceInfo() => _client.getDeviceInfo();

  /// Corrects a drifting terminal clock (restored — clock skew shifts event
  /// timestamps outside the `since` filter and imports silently miss).
  Future<bool> setDeviceTime(DateTime dt) => _client.setDeviceTime(dt);
}
