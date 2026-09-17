import '../lib/services/attendance/zkteco/zkteco_client.dart';
void main() async {
  for (int k=0;k<=5000;k++) {
    final c = ZKTecoClient(host: '192.168.1.201', port: 4370, commKey: k, timeout: Duration(seconds: 3));
    final ok = await c.connect();
    if (ok) { print('FOUND $k'); try{ final info=await c.getDeviceInfo(); print(info); }catch(e){} await c.disconnect(); return; }
    await c.disconnect();
    if (k%500==0) print('tried $k');
  }
  print('not found 0-5000');
}
