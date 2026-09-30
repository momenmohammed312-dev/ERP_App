import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'zkteco_models.dart';
import 'zkteco_packet_codec.dart';

class ZkTransportException implements Exception {
  final String message;

  const ZkTransportException(this.message);

  @override
  String toString() => 'ZkTransportException: $message';
}

class ZkFetchReport {
  final List<ZkAttendanceRecord> records;
  final int rawBytes;
  final int droppedChunks;
  final bool fetchOk;
  final String? debugSample;

  const ZkFetchReport({
    required this.records,
    required this.rawBytes,
    required this.droppedChunks,
    required this.fetchOk,
    this.debugSample,
  });
}

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

  String? _lastError;

  /// Last connection/fetch failure in Arabic (for UI + sync logs).
  /// Restored: silent failures made sync look "successful with 0 events".
  String? get lastError => _lastError;

  ZkFetchReport? _lastFetchReport;

  ZkFetchReport? get lastFetchReport => _lastFetchReport;

  /// Connects to the ZKTeco terminal over TCP and initiates session handshake.
  /// Restored: 3 attempts with backoff — a single packet loss no longer kills
  /// the whole sync (unstable Wi-Fi at client sites).
  Future<bool> connect() async {
    _lastError = null;
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (await _connectOnce()) {
          _lastError = null;
          return true;
        }
        if (_lastError != null && _lastError!.contains('CommKey')) return false;
      } catch (e) {
        _lastError = 'خطأ شبكة: $e';
      }
      if (attempt < maxAttempts) {
        await disconnect();
        await Future.delayed(Duration(milliseconds: 800 * attempt));
      }
    }
    await disconnect();
    return false;
  }

  Future<bool> _connectOnce() async {
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
        _lastError =
            'انتهت مهلة الاتصال (timeout ${timeout.inSeconds}ث) — الشبكة غير مستقرة أو الجهاز مشغول';
        await disconnect();
        return false;
      }
      // 2000=OK أو 2005=يحتاج مصادقة — في الحالتين بناخد sessionId ونكمل للمصادقة
      if (!reply.isSuccess && reply.command != ZkCommand.ackUnauthorized) {
        _lastError = 'الجهاز رفض الاتصال (code ${reply.command})';
        await disconnect();
        return false;
      }
      _sessionId = reply.sessionId;
      _replyId = reply.replyId;
      _isConnected = true;

      // 2. لو الجهاز طلب مصادقة (2005) أو فيه CommKey مدخل — نعمل AUTH
      if (reply.command == ZkCommand.ackUnauthorized || commKey > 0) {
        var authSuccess = await _authenticate(commKey);
        if (!authSuccess && commKey != 0) {
          authSuccess = await _authenticate(0);
        }
        if (!authSuccess) {
          _lastError = 'فشل مصادقة الجهاز (CommKey غير صحيح؟)';
          await disconnect();
          return false;
        }
      }

      return true;
    } catch (e) {
      _lastError = 'خطأ شبكة: $e';
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
    final payload = ZkPacketCodec.makeCommKey(key, _sessionId);
    final reply = await _sendCommand(ZkCommand.cmdAuth, payload: payload);
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
        final rawTime = ByteData.sublistView(
          reply.payload,
          0,
          4,
        ).getUint32(0, Endian.little);
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

  /// Sets the terminal clock. Restored: a drifting device clock shifts every
  /// event timestamp, which then falls outside the `since` filter and the
  /// import silently misses check-ins/check-outs.
  Future<bool> setDeviceTime(DateTime dt) async {
    _ensureConnected();
    final encoded = ZkPacketCodec.encodeZkTimestamp(dt);
    final payload = ByteData(4)..setUint32(0, encoded, Endian.little);
    final reply = await _sendCommand(
      ZkCommand.cmdSetTime,
      payload: payload.buffer.asUint8List(),
    );
    return reply != null && reply.isSuccess;
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
  Future<ZkFetchReport> fetchAttendanceReport({DateTime? since}) async {
    _ensureConnected();
    _lastFetchReport = null;

    late Uint8List data;
    try {
      data = await _fetchDataCommand(command: ZkCommand.cmdAttLogRrq);
    } on ZkTransportException catch (error) {
      if (!error.message.contains('unauthorized') &&
          !error.message.contains('timeout')) {
        rethrow;
      }
      final reconnected = await connect();
      if (!reconnected) {
        throw ZkTransportException(
          'reconnect failed before fetch retry: $lastError',
        );
      }
      _ensureConnected();
      data = await _fetchDataCommand(command: ZkCommand.cmdAttLogRrq);
    }

    final rawBytes = data.length;
    if (data.isEmpty) {
      const report = ZkFetchReport(
        records: [],
        rawBytes: 0,
        droppedChunks: 0,
        fetchOk: true,
      );
      _lastFetchReport = report;
      return report;
    }

    var payload = data;
    if (payload.length % 40 == 4) {
      final possibleSize = ByteData.sublistView(
        payload,
        0,
        4,
      ).getUint32(0, Endian.little);
      if (possibleSize == payload.length - 4) {
        payload = Uint8List.sublistView(payload, 4);
      }
    }

    final records = <ZkAttendanceRecord>[];
    var droppedChunks = 0;
    String? debugSample;

    void handleChunk(
      Uint8List chunk,
      ZkAttendanceRecord? Function(Uint8List) parse,
    ) {
      final record = parse(chunk);
      if (record == null) {
        droppedChunks++;
        debugSample ??= chunk
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        if (debugSample!.length > 80) {
          debugSample = debugSample!.substring(0, 80);
        }
      } else if (since == null || record.timestamp.isAfter(since)) {
        records.add(record);
      }
    }

    if (payload.length >= 40 && payload.length % 40 == 0) {
      for (int offset = 0; offset + 40 <= payload.length; offset += 40) {
        handleChunk(
          Uint8List.sublistView(payload, offset, offset + 40),
          _parse40ByteAttendance,
        );
      }
    } else if (payload.length >= 8 &&
        (payload.length % 8 == 0 || payload.length % 16 == 0)) {
      final recordSize = payload.length % 16 == 0 ? 16 : 8;
      for (
        int offset = 0;
        offset + recordSize <= payload.length;
        offset += recordSize
      ) {
        handleChunk(
          Uint8List.sublistView(payload, offset, offset + recordSize),
          _parseLegacyAttendance,
        );
      }
    } else {
      for (int offset = 0; offset + 40 <= payload.length; offset += 40) {
        handleChunk(
          Uint8List.sublistView(payload, offset, offset + 40),
          _parse40ByteAttendance,
        );
      }
      if (payload.length % 40 != 0) {
        droppedChunks++;
      }
    }

    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final report = ZkFetchReport(
      records: records,
      rawBytes: rawBytes,
      droppedChunks: droppedChunks,
      fetchOk: true,
      debugSample: debugSample,
    );
    _lastFetchReport = report;
    return report;
  }

  Future<List<ZkAttendanceRecord>> getAttendanceRecords({
    DateTime? since,
  }) async {
    final report = await fetchAttendanceReport(since: since);
    return report.records;
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
    final uid = view.getUint16(0, Endian.little);
    final encodedUserId = _extractNullTerminatedString(bytes.sublist(2, 26));
    final userId = encodedUserId.isEmpty ? uid.toString() : encodedUserId;
    final rawTime = view.getUint32(27, Endian.little);
    final timestamp = _decodeZkTimestampStrict(rawTime);

    if (userId.isEmpty || timestamp == null) {
      return null;
    }

    return ZkAttendanceRecord(
      userId: userId,
      timestamp: timestamp,
      status: bytes[31],
      verifyType: bytes[26],
    );
  }

  ZkAttendanceRecord? _parseLegacyAttendance(Uint8List bytes) {
    if (bytes.length < 8) return null;
    final view = ByteData.sublistView(bytes);

    final uid = view.getUint16(0, Endian.little);
    final rawTime = view.getUint32(4, Endian.little);
    final timestamp = _decodeZkTimestampStrict(rawTime);

    if (uid == 0 || timestamp == null) return null;

    return ZkAttendanceRecord(
      userId: uid.toString(),
      timestamp: timestamp,
      status: bytes[2],
      verifyType: bytes[3],
    );
  }

  DateTime? _decodeZkTimestampStrict(int value) {
    if (value <= 0) return null;
    final second = value % 60;
    value ~/= 60;
    final minute = value % 60;
    value ~/= 60;
    final hour = value % 24;
    value ~/= 24;
    final day = (value % 31) + 1;
    value ~/= 31;
    final month = (value % 12) + 1;
    value ~/= 12;
    final year = value + 2000;

    if (year < 2000 || year > 2099) return null;
    final lastDay = DateTime(year, month + 1, 0).day;
    if (day < 1 || day > lastDay) return null;
    return DateTime(year, month, day, hour, minute, second);
  }

  // --- Socket Communication Core ---

  Future<ZkPacket?> _sendCommand(int command, {Uint8List? payload}) async {
    if (_socket == null) return null;

    _replyId = (_replyId + 1) & 0xFFFF;
    final requestReplyId = _replyId;
    final encodedPacket = ZkPacketCodec.encodeTcpPacket(
      command: command,
      sessionId: _sessionId,
      replyId: requestReplyId,
      payload: payload,
    );

    _socket!.add(encodedPacket);
    await _socket!.flush();

    return _receivePacket(expectedReplyId: requestReplyId);
  }

  Future<ZkPacket?> _receivePacket({int? expectedReplyId}) async {
    if (_socket == null) return null;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_recvBuffer.length >= 8) {
        var magicOffset = -1;
        for (var index = 0; index <= _recvBuffer.length - 4; index++) {
          if (_recvBuffer[index] == ZkPacketCodec.tcpMagic[0] &&
              _recvBuffer[index + 1] == ZkPacketCodec.tcpMagic[1] &&
              _recvBuffer[index + 2] == ZkPacketCodec.tcpMagic[2] &&
              _recvBuffer[index + 3] == ZkPacketCodec.tcpMagic[3]) {
            magicOffset = index;
            break;
          }
        }
        if (magicOffset > 0) {
          _recvBuffer.removeRange(0, magicOffset);
        }
        if (_recvBuffer.length >= 16 &&
            magicOffset >= 0 &&
            _recvBuffer[0] == ZkPacketCodec.tcpMagic[0] &&
            _recvBuffer[1] == ZkPacketCodec.tcpMagic[1] &&
            _recvBuffer[2] == ZkPacketCodec.tcpMagic[2] &&
            _recvBuffer[3] == ZkPacketCodec.tcpMagic[3]) {
          final expectedLen = ByteData.sublistView(
            Uint8List.fromList(_recvBuffer),
            4,
            8,
          ).getUint32(0, Endian.little);
          final totalLen = 8 + expectedLen;
          if (totalLen >= 16 && _recvBuffer.length >= totalLen) {
            final raw = Uint8List.fromList(_recvBuffer.sublist(0, totalLen));
            _recvBuffer.removeRange(0, totalLen);
            final packet = ZkPacketCodec.decodeTcpPacket(raw);
            if (packet != null &&
                (expectedReplyId == null ||
                    packet.replyId == expectedReplyId)) {
              return packet;
            }
          }
        }
      }
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
    if (firstReply == null) {
      throw const ZkTransportException(
        'timeout waiting for device reply — weak network or busy device',
      );
    }
    if (firstReply.command == ZkCommand.ackUnauthorized) {
      throw const ZkTransportException(
        'unauthorized: device rejected command (CommKey?)',
      );
    }
    if (firstReply.command == ZkCommand.ackData) {
      return firstReply.payload;
    }
    if (firstReply.command == ZkCommand.cmdPrepareData) {
      if (firstReply.payload.length < 4) {
        throw const ZkTransportException(
          'invalid prepare-data response: missing total size',
        );
      }
      final totalSize = ByteData.sublistView(
        firstReply.payload,
        0,
        4,
      ).getUint32(0, Endian.little);
      final accumulatedData = <int>[];
      final budgetEnd = DateTime.now().add(const Duration(seconds: 60));
      late Uint8List result;
      try {
        while (accumulatedData.length < totalSize) {
          if (!DateTime.now().isBefore(budgetEnd)) {
            throw ZkTransportException(
              'truncated data: received ${accumulatedData.length} '
              'of $totalSize bytes within 60s',
            );
          }
          final dataPacket = await _receivePacket();
          if (dataPacket == null) {
            throw ZkTransportException(
              'truncated data: stream stalled at ${accumulatedData.length} '
              'of $totalSize bytes',
            );
          }
          if (dataPacket.command == ZkCommand.cmdData ||
              dataPacket.command == ZkCommand.ackData) {
            accumulatedData.addAll(dataPacket.payload);
            if (accumulatedData.length > totalSize) {
              throw ZkTransportException(
                'stream overflow: received ${accumulatedData.length} '
                'for $totalSize bytes',
              );
            }
          } else if (dataPacket.command == ZkCommand.ackOk) {
            if (accumulatedData.length < totalSize) {
              throw ZkTransportException(
                'truncated data: device ended at ${accumulatedData.length} '
                'of $totalSize bytes',
              );
            }
            break;
          } else {
            throw ZkTransportException(
              'stream failed: unexpected packet ${dataPacket.command}',
            );
          }
        }
        if (accumulatedData.length != totalSize) {
          throw ZkTransportException(
            'truncated data: received ${accumulatedData.length} '
            'of $totalSize bytes',
          );
        }
        result = Uint8List.fromList(accumulatedData);
      } catch (_) {
        try {
          await _sendCommand(ZkCommand.cmdFreeData);
        } catch (_) {}
        rethrow;
      }

      late ZkPacket? freeReply;
      try {
        freeReply = await _sendCommand(ZkCommand.cmdFreeData);
      } catch (error) {
        throw ZkTransportException('failed to free device data buffer: $error');
      }
      if (freeReply == null) {
        throw const ZkTransportException('timeout freeing device data buffer');
      }
      if (!freeReply.isSuccess) {
        throw ZkTransportException(
          'device rejected free-data command ${freeReply.command}',
        );
      }
      return result;
    }
    if (firstReply.isSuccess) {
      return firstReply.payload;
    }
    throw ZkTransportException('device rejected command ${firstReply.command}');
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
