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

  /// Diagnostics of the most recent fetch (records/rawBytes/dropped/fetchOk).
  /// Null before the first fetch. Used by the sync service to distinguish
  /// fetchFailed from fetchOkEmpty and to log parser mismatch.
  ZkFetchReport? get lastFetchReport => _client.lastFetchReport;

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
      // Throws ZkTransportException on timeout/truncation: propagates as
      // fetchFailed and must never be converted to an empty list here.
      final report = await _client.fetchAttendanceReport(since: since);
      _status = AttendanceSourceStatus.connected;

      return report.records.map((r) {
        // Truncate to seconds: dedupHash is second-precision, ms jitter
        // would break idempotent re-ingest of the same device event.
        final t = r.timestamp;
        final eventTime = DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
        // NOTE: r.eventType (device status 0/1) is preserved for audit only.
        // It is NOT trusted for check-in/out decisions (parser byte-overlap
        // makes it unreliable) — see the processor policy in
        // attendance_sync_service.dart.
        return RawAttendanceEvent(
          externalUserId: r.userId,
          eventTime: eventTime,
          eventType: r.eventType,
          rawPayload:
              '{"userId":"${r.userId}","time":"${eventTime.toIso8601String()}","status":${r.status},"verifyType":${r.verifyType}}',
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
