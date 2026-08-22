import 'dart:typed_data';

/// Constants for ZKTeco Standalone protocol commands and replies
class ZkCommand {
  // Connection commands
  static const int cmdConnect = 1000;
  static const int cmdDisconnect = 1001;
  static const int cmdAuth = 1102;

  // Device control
  static const int cmdEnableDevice = 1008;
  static const int cmdDisableDevice = 1009;
  static const int cmdRestart = 1004;
  static const int cmdPowerOff = 1005;

  // Information & Time
  static const int cmdGetTime = 201;
  static const int cmdSetTime = 202;
  static const int cmdVersion = 1100;
  static const int cmdGetFreeSizes = 1014;
  static const int cmdGetDeviceName = 11;
  static const int cmdGetOption = 1011;

  // Users & Attendance data
  static const int cmdUserTempRrq = 9; // Read users
  static const int cmdAttLogRrq = 13;  // Read attendance logs
  static const int cmdClearAttLog = 15; // Clear attendance log

  // Response codes
  static const int ackOk = 2000;
  static const int ackError = 2001;
  static const int ackData = 2002;
  static const int ackRetry = 2003;
  static const int ackRepeat = 2004;
  static const int ackUnauthorized = 2005;
  static const int ackUnknown = 65535;

  // Data transmission
  static const int cmdPrepareData = 1500;
  static const int cmdData = 1501;
  static const int cmdFreeData = 1502;
}

/// Represents a parsed ZKTeco packet
class ZkPacket {
  final int command;
  final int checksum;
  final int sessionId;
  final int replyId;
  final Uint8List payload;

  const ZkPacket({
    required this.command,
    required this.checksum,
    required this.sessionId,
    required this.replyId,
    required this.payload,
  });

  bool get isSuccess => command == ZkCommand.ackOk;
  bool get isData => command == ZkCommand.ackData;
  bool get isPrepareData => command == ZkCommand.cmdPrepareData;
}

/// Packet encoding and decoding helper for ZKTeco TCP/IP standalone protocol
class ZkPacketCodec {
  /// TCP Magic header bytes [0x50, 0x50, 0x82, 0x7D]
  static const List<int> tcpMagic = [0x50, 0x50, 0x82, 0x7D];

  /// Builds a complete TCP packet containing the framed ZK command
  static Uint8List encodeTcpPacket({
    required int command,
    required int sessionId,
    required int replyId,
    Uint8List? payload,
  }) {
    final payloadBytes = payload ?? Uint8List(0);
    final zkPacketLen = 8 + payloadBytes.length;

    final zkBuffer = ByteData(zkPacketLen);
    zkBuffer.setUint16(0, command, Endian.little);
    zkBuffer.setUint16(2, 0, Endian.little); // Checksum placeholder
    zkBuffer.setUint16(4, sessionId, Endian.little);
    zkBuffer.setUint16(6, replyId, Endian.little);

    if (payloadBytes.isNotEmpty) {
      zkBuffer.buffer.asUint8List(8).setAll(0, payloadBytes);
    }

    final rawZkBytes = zkBuffer.buffer.asUint8List();
    final checksum = calculateChecksum(rawZkBytes);
    zkBuffer.setUint16(2, checksum, Endian.little);

    // Frame with TCP header: 4 bytes magic + 4 bytes length (little endian)
    final tcpPacket = Uint8List(8 + zkPacketLen);
    tcpPacket.setAll(0, tcpMagic);

    final tcpHeaderData = ByteData.view(tcpPacket.buffer, 4, 4);
    tcpHeaderData.setUint32(0, zkPacketLen, Endian.little);

    tcpPacket.setAll(8, rawZkBytes);
    return tcpPacket;
  }

  /// Calculates the 16-bit 1's complement checksum for a ZK packet
  static int calculateChecksum(Uint8List packet) {
    int sum = 0;
    final len = packet.length;

    for (int i = 0; i < len - 1; i += 2) {
      if (i == 2) continue; // Skip the 2-byte checksum field itself
      sum += packet[i] + (packet[i + 1] << 8);
    }

    if (len % 2 != 0) {
      sum += packet[len - 1];
    }

    while (sum > 0xFFFF) {
      sum = (sum & 0xFFFF) + (sum >> 16);
    }

    return (~sum) & 0xFFFF;
  }

  /// Extracts ZkPacket from raw bytes received from TCP stream
  static ZkPacket? decodeTcpPacket(Uint8List rawBytes) {
    if (rawBytes.length < 8) return null;

    int zkOffset = 0;
    // Check if packet starts with TCP magic
    if (rawBytes.length >= 8 &&
        rawBytes[0] == tcpMagic[0] &&
        rawBytes[1] == tcpMagic[1] &&
        rawBytes[2] == tcpMagic[2] &&
        rawBytes[3] == tcpMagic[3]) {
      zkOffset = 8;
    }

    if (rawBytes.length < zkOffset + 8) return null;

    final view = ByteData.sublistView(rawBytes, zkOffset);
    final command = view.getUint16(0, Endian.little);
    final checksum = view.getUint16(2, Endian.little);
    final sessionId = view.getUint16(4, Endian.little);
    final replyId = view.getUint16(6, Endian.little);

    final payloadLen = rawBytes.length - (zkOffset + 8);
    final payload = payloadLen > 0
        ? Uint8List.fromList(rawBytes.sublist(zkOffset + 8))
        : Uint8List(0);

    return ZkPacket(
      command: command,
      checksum: checksum,
      sessionId: sessionId,
      replyId: replyId,
      payload: payload,
    );
  }

  /// Decodes ZKTeco 32-bit packed timestamp into standard DateTime
  static DateTime decodeZkTimestamp(int t) {
    if (t <= 0) return DateTime.fromMillisecondsSinceEpoch(0);
    int second = t % 60;
    t ~/= 60;
    int minute = t % 60;
    t ~/= 60;
    int hour = t % 24;
    t ~/= 24;
    int day = (t % 31) + 1;
    t ~/= 31;
    int month = (t % 12) + 1;
    t ~/= 12;
    int year = t + 2000;

    // Safety checks for malformed clock data
    year = year.clamp(1970, 2099);
    month = month.clamp(1, 12);
    day = day.clamp(1, 31);
    hour = hour.clamp(0, 23);
    minute = minute.clamp(0, 59);
    second = second.clamp(0, 59);

    return DateTime(year, month, day, hour, minute, second);
  }

  /// Encodes standard DateTime into ZKTeco 32-bit packed integer
  static int encodeZkTimestamp(DateTime dt) {
    final yearPart = (dt.year % 100) * 12 * 31;
    final monthPart = (dt.month - 1) * 31;
    final dayPart = dt.day - 1;
    final dateDays = (yearPart + monthPart + dayPart) * 86400;
    final timeSeconds = dt.hour * 3600 + dt.minute * 60 + dt.second;
    return dateDays + timeSeconds;
  }
}
