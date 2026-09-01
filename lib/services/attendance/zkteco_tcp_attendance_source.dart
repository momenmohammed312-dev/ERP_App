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

  String? _lastError;
  String? get lastError => _lastError ?? _client.lastError;

  ZKTecoTcpAttendanceSource({
    required this.ipAddress,
    required this.port,
    this.authToken,
    Duration timeout = const Duration(seconds: 15),
  })  : _client = ZKTecoClient(
          host: ipAddress,
          port: port,
          commKey: int.tryParse(authToken ?? '') ?? 0,
          timeout: timeout,
        ),
        super(deviceIdentifier: '$ipAddress:$port');

  @override
  Future<bool> connect() async {
    _status = AttendanceSourceStatus.connecting;
    _lastError = null;
    try {
      final success = await _client.connect();
      if (success) {
        _status = AttendanceSourceStatus.connected;
        return true;
      } else {
        _status = AttendanceSourceStatus.error;
        _lastError = _client.lastError ?? 'فشل الاتصال بالجهاز $ipAddress:$port (تحقق من الشبكة وفقد الحزم)';
        return false;
      }
    } catch (e) {
      _status = AttendanceSourceStatus.error;
      _lastError = e.toString();
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
      final records = await _client.getAttendanceRecords(since: since);
      _status = AttendanceSourceStatus.connected;

      return records.map((r) {
        return RawAttendanceEvent(
          externalUserId: r.userId,
          eventTime: r.timestamp,
          eventType: r.eventType,
          rawPayload:
              '{"userId":"${r.userId}","time":"${r.timestamp.toIso8601String()}","status":${r.status},"verifyType":${r.verifyType}}',
        );
      }).toList();
    } catch (e) {
      _status = AttendanceSourceStatus.error;
      rethrow;
    }
  }

  @override
  Future<List<DeviceEnrolledUser>> fetchEnrolledUsers() async => [];

  Future<ZkDeviceInfo> getDeviceInfo() => _client.getDeviceInfo();
  Future<bool> setDeviceTime(DateTime dt) => _client.setDeviceTime(dt);
}
