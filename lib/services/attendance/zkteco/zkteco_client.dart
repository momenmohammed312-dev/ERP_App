import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'zkteco_models.dart';
import 'zkteco_packet_codec.dart';

/// Client implementation for communicating with ZKTeco Standalone biometric terminals over TCP/IP
class ZKTecoClient {
  final String host;
  final int port;
  final int commKey;
  final Duration timeout;

  Socket? _socket;
  StreamSubscription<Uint8List>? _sockSub;
  final List<int> _recvBuffer = [];
  int _sessionId = 0;
  int _replyId = 0;
  bool _isConnected = false;

  ZKTecoClient({
    required this.host,
    this.port = 4370,
    this.commKey = 0,
    this.timeout = const Duration(seconds: 8),
  });

  bool get isConnected => _isConnected;
  int get sessionId => _sessionId;

  /// Connects to the ZKTeco terminal over TCP and initiates session handshake
  Future<bool> connect() async {
    await disconnect();

    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _recvBuffer.clear();
      _sockSub?.cancel();
      _sockSub = _socket!.listen(
        (chunk) => _recvBuffer.addAll(chunk),
        onError: (_) {},
        onDone: () {},
        cancelOnError: false,
      );

      _sessionId = 0;
      _replyId = 0;

      // 1. Send CMD_CONNECT (1000) — الجهاز قد يرجع 2005 Unauthorized لو له CommKey
      final reply = await _sendCommand(ZkCommand.cmdConnect);
      if (reply == null) {
        await disconnect();
        return false;
      }
      // 2000=OK أو 2005=يحتاج مصادقة — في الحالتين بناخد sessionId ونكمل للمصادقة
      if (!reply.isSuccess && reply.command != ZkCommand.ackUnauthorized) {
        await disconnect();
        return false;
      }
      _sessionId = reply.sessionId;
      _replyId = reply.replyId;
      _isConnected = true;

      // 2. لو الجهاز طلب مصادقة (2005) أو فيه CommKey مدخل — نعمل AUTH
      if (reply.command == ZkCommand.ackUnauthorized || commKey > 0) {
        // لو التوكن 0 والجهاز طالب كلمة سر — جرّب 0 أولاً، لو فشل هيرجع false ويظهر للعميل
        final keyToTry = commKey;
        final authSuccess = await _authenticate(keyToTry);
        if (!authSuccess) {
          await disconnect();
          return false;
        }
      }

      return true;
    } catch (e) {
      await disconnect();
      return false;
    }
  }

  /// Disconnects from the terminal and frees socket resources
  Future<void> disconnect() async {
    if (_isConnected && _socket != null) {
      try {
        await _sendCommand(ZkCommand.cmdDisconnect);
      } catch (_) {}
    }
    try {
      await _sockSub?.cancel();
    } catch (_) {}
    _sockSub = null;
    _recvBuffer.clear();
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _isConnected = false;
    _sessionId = 0;
    _replyId = 0;
  }

  /// Authenticates with the device using Communication Key
  Future<bool> _authenticate(int key) async {
    // Scramble comm key
    int scrambled = 0;
    for (int i = 0; i < 32; i++) {
      if ((key & (1 << i)) != 0) {
        scrambled = (scrambled << 1) | 1;
      } else {
        scrambled = (scrambled << 1);
      }
    }
    scrambled += _sessionId;

    final payload = ByteData(4);
    payload.setUint32(0, scrambled, Endian.little);

    final reply = await _sendCommand(
      ZkCommand.cmdAuth,
      payload: payload.buffer.asUint8List(),
    );
    return reply != null && reply.isSuccess;
  }

  /// Fetches terminal hardware and firmware details
  Future<ZkDeviceInfo> getDeviceInfo() async {
    _ensureConnected();

    String? version;
    String? name;
    String? sn;
    String? platform;
    DateTime? deviceTime;

    // Get Firmware Version
    try {
      final reply = await _sendCommand(ZkCommand.cmdVersion);
      if (reply != null && reply.payload.isNotEmpty) {
        version = _cleanString(reply.payload);
      }
    } catch (_) {}

    // Get Device Time
    try {
      final reply = await _sendCommand(ZkCommand.cmdGetTime);
      if (reply != null && reply.payload.length >= 4) {
        final rawTime = ByteData.sublistView(reply.payload, 0, 4)
            .getUint32(0, Endian.little);
        deviceTime = ZkPacketCodec.decodeZkTimestamp(rawTime);
      }
    } catch (_) {}

    // Get Serial Number
    try {
      sn = await getOption('~SerialNumber');
    } catch (_) {}

    // Get Platform
    try {
      platform = await getOption('~Platform');
    } catch (_) {}

    // Get Device Name
    try {
      name = await getOption('~DeviceName') ?? await getOption('DeviceName');
    } catch (_) {}

    return ZkDeviceInfo(
      firmwareVersion: version,
      deviceName: name,
      serialNumber: sn,
      platform: platform,
      deviceTime: deviceTime,
    );
  }

  /// Reads a specific configuration parameter from the device
  Future<String?> getOption(String optionName) async {
    _ensureConnected();
    final payload = Uint8List.fromList(utf8.encode('$optionName\x00'));
    final reply = await _sendCommand(ZkCommand.cmdGetOption, payload: payload);
    if (reply != null && reply.payload.isNotEmpty) {
      final str = _cleanString(reply.payload);
      if (str.startsWith('$optionName=')) {
        return str.substring('$optionName='.length).trim();
      }
      return str.trim();
    }
    return null;
  }

  /// Fetches all users registered on the terminal
  Future<List<ZkUser>> getUsers() async {
    _ensureConnected();

    final data = await _fetchDataCommand(
      command: ZkCommand.cmdUserTempRrq,
      payload: Uint8List.fromList([0x05]), // 0x05 = fetch user info
    );

    if (data.isEmpty) return [];

    final users = <ZkUser>[];

    // Try 72-byte SSR format first (Modern ZK format)
    if (data.length >= 72 && data.length % 72 == 0) {
      for (int offset = 0; offset + 72 <= data.length; offset += 72) {
        final chunk = Uint8List.sublistView(data, offset, offset + 72);
        final user = _parse72ByteUser(chunk);
        if (user != null) users.add(user);
      }
    } else if (data.length >= 28 && data.length % 28 == 0) {
      // 28-byte legacy format
      for (int offset = 0; offset + 28 <= data.length; offset += 28) {
        final chunk = Uint8List.sublistView(data, offset, offset + 28);
        final user = _parse28ByteUser(chunk);
        if (user != null) users.add(user);
      }
    } else {
      // Best-effort adaptive parser
      int offset = 0;
      while (offset + 72 <= data.length) {
        final chunk = Uint8List.sublistView(data, offset, offset + 72);
        final user = _parse72ByteUser(chunk);
        if (user != null && user.userId.isNotEmpty) {
          users.add(user);
          offset += 72;
        } else {
          offset += 28;
        }
      }
    }

    return users;
  }

  /// Fetches attendance records from terminal (optionally filtered by date)
  Future<List<ZkAttendanceRecord>> getAttendanceRecords({DateTime? since}) async {
    _ensureConnected();

    final data = await _fetchDataCommand(
      command: ZkCommand.cmdAttLogRrq,
    );

    if (data.isEmpty) return [];

    final records = <ZkAttendanceRecord>[];

    // 1. Try 40-byte SSR attendance log record (Modern ZK format)
    if (data.length >= 40 && data.length % 40 == 0) {
      for (int offset = 0; offset + 40 <= data.length; offset += 40) {
        final chunk = Uint8List.sublistView(data, offset, offset + 40);
        final record = _parse40ByteAttendance(chunk);
        if (record != null) {
          if (since == null || record.timestamp.isAfter(since)) {
            records.add(record);
          }
        }
      }
    } else if (data.length >= 8 && (data.length % 8 == 0 || data.length % 16 == 0)) {
      // Legacy 8 or 16-byte record
      final recordSize = (data.length % 16 == 0) ? 16 : 8;
      for (int offset = 0; offset + recordSize <= data.length; offset += recordSize) {
        final chunk = Uint8List.sublistView(data, offset, offset + recordSize);
        final record = _parseLegacyAttendance(chunk);
        if (record != null) {
          if (since == null || record.timestamp.isAfter(since)) {
            records.add(record);
          }
        }
      }
    } else {
      // Adaptive chunk scanning
      for (int offset = 0; offset + 40 <= data.length; offset += 40) {
        final chunk = Uint8List.sublistView(data, offset, offset + 40);
        final record = _parse40ByteAttendance(chunk);
        if (record != null && record.userId.isNotEmpty) {
          if (since == null || record.timestamp.isAfter(since)) {
            records.add(record);
          }
        }
      }
    }

    // Sort chronologically
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return records;
  }

  /// Disables terminal input (useful during batch downloads to prevent race conditions)
  Future<bool> disableDevice() async {
    _ensureConnected();
    final reply = await _sendCommand(ZkCommand.cmdDisableDevice);
    return reply != null && reply.isSuccess;
  }

  /// Re-enables terminal input
  Future<bool> enableDevice() async {
    _ensureConnected();
    final reply = await _sendCommand(ZkCommand.cmdEnableDevice);
    return reply != null && reply.isSuccess;
  }

  // --- Parsing Helpers ---

  ZkUser? _parse72ByteUser(Uint8List bytes) {
    if (bytes.length < 72) return null;
    final view = ByteData.sublistView(bytes);

    final uid = view.getUint16(0, Endian.little);
    final role = bytes[2];
    final password = _extractNullTerminatedString(bytes.sublist(3, 11));
    final name = _extractNullTerminatedString(bytes.sublist(11, 35));
    final card = _extractNullTerminatedString(bytes.sublist(35, 40));
    final userId = _extractNullTerminatedString(bytes.sublist(48, 72));

    if (userId.isEmpty && uid == 0) return null;

    return ZkUser(
      uid: uid,
      userId: userId.isNotEmpty ? userId : uid.toString(),
      name: name.isNotEmpty ? name : 'User $userId',
      password: password.isNotEmpty ? password : null,
      card: card.isNotEmpty ? card : null,
      role: role,
      enabled: bytes[7] != 0, // In standard SSR, bit 0 determines enabled
    );
  }

  ZkUser? _parse28ByteUser(Uint8List bytes) {
    if (bytes.length < 28) return null;
    final view = ByteData.sublistView(bytes);

    final uid = view.getUint16(0, Endian.little);
    final role = view.getUint16(2, Endian.little);
    final password = _extractNullTerminatedString(bytes.sublist(4, 12));
    final name = _extractNullTerminatedString(bytes.sublist(12, 20));
    final card = view.getUint32(20, Endian.little).toString();

    if (uid == 0) return null;

    return ZkUser(
      uid: uid,
      userId: uid.toString(),
      name: name.isNotEmpty ? name : 'User $uid',
      password: password.isNotEmpty ? password : null,
      card: card != '0' ? card : null,
      role: role,
    );
  }

  ZkAttendanceRecord? _parse40ByteAttendance(Uint8List bytes) {
    if (bytes.length < 40) return null;
    final view = ByteData.sublistView(bytes);

    // Format: userId (24 bytes at offset 0 or offset 4)
    String userId = _extractNullTerminatedString(bytes.sublist(0, 24));
    if (userId.isEmpty) {
      userId = _extractNullTerminatedString(bytes.sublist(4, 28));
    }

    final status = bytes[26] < 10 ? bytes[26] : bytes[30];
    final verifyType = bytes[27] < 20 ? bytes[27] : bytes[31];

    // Timestamp is 32-bit packed integer around offset 32 or 36
    int rawTime = view.getUint32(bytes.length >= 36 ? 32 : 28, Endian.little);
    DateTime time = ZkPacketCodec.decodeZkTimestamp(rawTime);

    if (time.year < 2000 || time.year > 2099) {
      // Try offset 36
      if (bytes.length >= 40) {
        rawTime = view.getUint32(36, Endian.little);
        time = ZkPacketCodec.decodeZkTimestamp(rawTime);
      }
    }

    if (userId.isEmpty && time.year < 2000) return null;

    return ZkAttendanceRecord(
      userId: userId,
      timestamp: time,
      status: status,
      verifyType: verifyType,
    );
  }

  ZkAttendanceRecord? _parseLegacyAttendance(Uint8List bytes) {
    if (bytes.length < 8) return null;
    final view = ByteData.sublistView(bytes);

    final uid = view.getUint16(0, Endian.little);
    final status = bytes[2];
    final verifyType = bytes[3];
    final rawTime = view.getUint32(4, Endian.little);
    final time = ZkPacketCodec.decodeZkTimestamp(rawTime);

    if (uid == 0) return null;

    return ZkAttendanceRecord(
      userId: uid.toString(),
      timestamp: time,
      status: status,
      verifyType: verifyType,
    );
  }

  // --- Socket Communication Core ---

  Future<ZkPacket?> _sendCommand(int command, {Uint8List? payload}) async {
    if (_socket == null) return null;

    _replyId = (_replyId + 1) & 0xFFFF;
    final encodedPacket = ZkPacketCodec.encodeTcpPacket(
      command: command,
      sessionId: _sessionId,
      replyId: _replyId,
      payload: payload,
    );

    _socket!.add(encodedPacket);
    await _socket!.flush();

    return await _receivePacket();
  }

  Future<ZkPacket?> _receivePacket() async {
    if (_socket == null) return null;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_recvBuffer.length >= 16) {
        final expectedLen = ByteData.sublistView(
          Uint8List.fromList(_recvBuffer),
          4,
          8,
        ).getUint32(0, Endian.little);
        final totalLen = 8 + expectedLen;
        if (_recvBuffer.length >= totalLen) {
          final raw = Uint8List.fromList(_recvBuffer.sublist(0, totalLen));
          _recvBuffer.removeRange(0, totalLen);
          return ZkPacketCodec.decodeTcpPacket(raw);
        }
      }
      // لو الجهاز لسه هيبعت — نستنى شوية ونفحص تاني، لحد ما يوصل الوقت
      await Future.delayed(const Duration(milliseconds: 10));
      if (_socket == null) return null;
    }
    return null;
  }

  /// Sends a data command and reads all chunked data packets until completion
  Future<Uint8List> _fetchDataCommand({
    required int command,
    Uint8List? payload,
  }) async {
    final firstReply = await _sendCommand(command, payload: payload);
    if (firstReply == null) return Uint8List(0);

    // Case 1: Data fits directly in the first response
    if (firstReply.command == ZkCommand.ackData) {
      return firstReply.payload;
    }

    // Case 2: CMD_PREPARE_DATA (Streamed multi-packet data transmission)
    if (firstReply.command == ZkCommand.cmdPrepareData) {
      final totalSize = firstReply.payload.length >= 4
          ? ByteData.sublistView(firstReply.payload, 0, 4)
              .getUint32(0, Endian.little)
          : 0;

      final accumulatedData = <int>[];

      while (accumulatedData.length < totalSize) {
        final dataPacket = await _receivePacket();
        if (dataPacket == null) break;

        if (dataPacket.command == ZkCommand.cmdData ||
            dataPacket.command == ZkCommand.ackData) {
          accumulatedData.addAll(dataPacket.payload);
        } else if (dataPacket.command == ZkCommand.ackOk) {
          break;
        }
      }

      // Free buffer on device
      await _sendCommand(ZkCommand.cmdFreeData);
      return Uint8List.fromList(accumulatedData);
    }

    if (firstReply.isSuccess && firstReply.payload.isNotEmpty) {
      return firstReply.payload;
    }

    return Uint8List(0);
  }

  void _ensureConnected() {
    if (!_isConnected || _socket == null) {
      throw StateError('ZKTeco client is not connected');
    }
  }

  String _cleanString(Uint8List bytes) {
    try {
      return _extractNullTerminatedString(bytes);
    } catch (_) {
      return latin1.decode(bytes).trim();
    }
  }

  String _extractNullTerminatedString(Uint8List bytes) {
    int end = bytes.indexOf(0);
    if (end == -1) end = bytes.length;
    return utf8.decode(bytes.sublist(0, end), allowMalformed: true).trim();
  }
}
