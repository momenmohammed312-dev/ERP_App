import 'dart:io';
import 'dart:typed_data';

import 'package:pos_offline_desktop/services/attendance/zkteco/zkteco_packet_codec.dart';

Future<void> main() async {
  final socket = await Socket.connect('192.168.1.201', 4370,
      timeout: const Duration(seconds: 5));
  socket.setOption(SocketOption.tcpNoDelay, true);

  for (final replyId in [1, 65535]) {
    final packet = ZkPacketCodec.encodeTcpPacket(
      command: ZkCommand.cmdConnect,
      sessionId: 0,
      replyId: replyId,
    );
    print('Sending connect replyId=$replyId bytes=${packet.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
    socket.add(packet);
    await socket.flush();

    final buffer = <int>[];
    final sub = socket.listen((d) => buffer.addAll(d));
    await Future.delayed(const Duration(seconds: 2));
    await sub.cancel();
    print('Reply (${buffer.length} bytes): ${buffer.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
    if (buffer.length >= 16) {
      final view = ByteData.sublistView(Uint8List.fromList(buffer), 8);
      print('  cmd=${view.getUint16(0, Endian.little)} session=${view.getUint16(4, Endian.little)} reply=${view.getUint16(6, Endian.little)}');
    }
    buffer.clear();
  }

  await socket.close();
}
