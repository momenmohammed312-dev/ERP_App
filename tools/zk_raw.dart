import 'dart:io';
import 'dart:typed_data';
import '../lib/services/attendance/zkteco/zkteco_packet_codec.dart';
void main() async {
  final host = '192.168.1.201';
  final port = 4370;
  for (final key in [0, 12345]) {
    print('=== Try key $key ===');
    Socket? s;
    try {
      s = await Socket.connect(host, port, timeout: Duration(seconds: 5));
      s.setOption(SocketOption.tcpNoDelay, true);
      final pkt = ZkPacketCodec.encodeTcpPacket(command: 1000, sessionId: 0, replyId: 0);
      s.add(pkt); await s.flush();
      final data = await s.first.timeout(Duration(seconds: 5));
      print('Reply hex: ${data.map((b)=>b.toRadixString(16).padLeft(2,"0")).join(" ")} len ${data.length}');
      if (data.length >= 8) {
        final v = ByteData.sublistView(data);
        final cmd = data.length >= 16 ? ByteData.sublistView(data, 8).getUint16(0, Endian.little) : -1;
        print('  Inner cmd: $cmd (${cmd==2000?"OK":cmd==2005?"UNAUTH":cmd}) session ${ByteData.sublistView(data,8).getUint16(4,Endian.little)} reply ${ByteData.sublistView(data,8).getUint16(6,Endian.little)}');
      }
      // try auth
      // need sessionId from reply
      int sessionId = 0;
      if (data.length >= 16) sessionId = ByteData.sublistView(data, 8).getUint16(4, Endian.little);
      // scramble
      int reversed=0; for(int i=0;i<32;i++){ if((key & (1<<i))!=0) reversed=(reversed<<1)|1; else reversed=(reversed<<1); }
      final scrambled = reversed + sessionId;
      final payload = ByteData(4)..setUint32(0, scrambled, Endian.little);
      final authPkt = ZkPacketCodec.encodeTcpPacket(command: 1102, sessionId: sessionId, replyId: 1, payload: payload.buffer.asUint8List());
      s.add(authPkt); await s.flush();
      final data2 = await s.first.timeout(Duration(seconds: 5));
      print('Auth reply hex: ${data2.map((b)=>b.toRadixString(16).padLeft(2,"0")).join(" ")} len ${data2.length}');
      if (data2.length >= 16) {
        final cmd2 = ByteData.sublistView(data2, 8).getUint16(0, Endian.little);
        print('  Auth inner cmd: $cmd2 ${cmd2==2000?"OK":"fail"}');
      }
      await s.close();
    } catch(e){ print('err $e'); try{ await s?.close(); }catch(_){}}
    await Future.delayed(Duration(milliseconds: 500));
  }
}
