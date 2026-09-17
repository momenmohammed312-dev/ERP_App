import '../lib/services/attendance/zkteco/zkteco_client.dart';
import 'dart:typed_data';
void main() async {
  final c = ZKTecoClient(host: '192.168.1.201', port: 4370, commKey: 0, timeout: Duration(seconds: 15));
  if (!await c.connect()) { print('connect fail ${c.lastError}'); return; }
  print('connected session ${c.sessionId}');
  final data = await c.getAttendanceRecords();
  print('parsed ${data.length} records');
  for (var r in data.take(10)) print(r);
  // raw dump via private _fetchDataCommand not accessible, so use direct client call with debug
  await c.disconnect();
}
