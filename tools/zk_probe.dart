import 'dart:io';
import '../lib/services/attendance/zkteco/zkteco_client.dart';

void main() async {
  final client = ZKTecoClient(host: '192.168.1.201', port: 4370, commKey: 0, timeout: Duration(seconds: 15));
  print('Connecting to 192.168.1.201:4370 with commKey 0 (timeout 15s, 3 retries)...');
  final ok = await client.connect();
  print('Connect result: $ok');
  print('LastError: ${client.lastError}');
  print('isConnected: ${client.isConnected} sessionId: ${client.sessionId}');
  if (ok) {
    try {
      final info = await client.getDeviceInfo();
      print('DeviceInfo: $info');
    } catch (e) { print('getDeviceInfo error: $e'); }
    try {
      final records = await client.getAttendanceRecords();
      print('Attendance records: ${records.length}');
      for (var r in records.take(5)) print('  $r');
    } catch (e) { print('getAttendance error: $e'); }
    await client.disconnect();
    print('Disconnected');
  }
  exit(ok ? 0 : 1);
}
