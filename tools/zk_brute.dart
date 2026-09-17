import '../lib/services/attendance/zkteco/zkteco_client.dart';
void main() async {
  final keys = [0, 12345, 1234, 5678, 9999, 11111, 123456, 1, 123, 0000, 8888, 54321];
  for (final k in keys) {
    final c = ZKTecoClient(host: '192.168.1.201', port: 4370, commKey: k, timeout: Duration(seconds: 5));
    final ok = await c.connect();
    print('key $k -> ${ok ? "SUCCESS" : "fail: ${c.lastError}"}');
    if (ok) { 
      try { final info = await c.getDeviceInfo(); print('  info: $info'); } catch(e){ print('  info err $e');}
      await c.disconnect(); 
      print('FOUND KEY $k'); 
      break;
    }
    await c.disconnect();
  }
}
