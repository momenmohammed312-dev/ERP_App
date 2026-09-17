import 'dart:typed_data';
import '../lib/services/attendance/zkteco/zkteco_packet_codec.dart';
void main() async {
  final hex = '010031000000000000000000000000000000000000000000010028c709330000000000000002003100000000000000000000000000000000000000000001dcc909330500000000'.replaceAll(' ', '');
  // Actually use first 40 from earlier dump: 01 00 31 00 00 00 ... 01 28 c7 09 33 ...
  final bytes = Uint8List.fromList([0x01,0x00,0x31,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01,0x28,0xc7,0x09,0x33,0x00,0x00,0x00,0x00,0x00,0x00,0x00]);
  for(int off=0;off<=36;off++){
    if(off+4>bytes.length) break;
    final raw = ByteData.sublistView(bytes, off, off+4).getUint32(0, Endian.little);
    final dt = ZkPacketCodec.decodeZkTimestamp(raw);
    print('off $off raw 0x${raw.toRadixString(16).padLeft(8,"0")} $raw -> $dt');
  }
}
