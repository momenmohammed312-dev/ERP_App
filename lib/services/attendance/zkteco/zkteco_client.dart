import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'zkteco_models.dart';
import 'zkteco_packet_codec.dart';

/// Minimal ZKTeco client for K50 Pro — only what attendance sync needs
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
    this.timeout = const Duration(seconds: 15),
  });

  bool get isConnected => _isConnected;
  int get sessionId => _sessionId;

  String? _lastError;
  String? get lastError => _lastError;

  Future<bool> connect() async {
    _lastError = null;
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (await _connectOnce()) return true;
        if (_lastError != null && _lastError!.contains('CommKey')) return false;
      } catch (e) {
        _lastError = e.toString();
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
      await _sockSub?.cancel();
      _sockSub = _socket!.listen((c) => _recvBuffer.addAll(c), onError: (_) {}, onDone: () {}, cancelOnError: false);
      _sessionId = 0;
      _replyId = 0;
      final reply = await _sendCommand(ZkCommand.cmdConnect);
      if (reply == null) {
        _lastError = 'انتهت مهلة الاتصال (timeout ${timeout.inSeconds}ث) — الشبكة غير مستقرة أو الجهاز مشغول';
        await disconnect();
        return false;
      }
      if (!reply.isSuccess && reply.command != ZkCommand.ackUnauthorized) {
        _lastError = 'الجهاز رفض الاتصال (code ${reply.command})';
        await disconnect();
        return false;
      }
      _sessionId = reply.sessionId;
      _replyId = reply.replyId;
      _isConnected = true;
      // لا نعتمد على CommKey — نحاول المصادقة لكن لا نفشل الاتصال لو رفضها
      // بعض أجهزة K50 ترد 2005 حتى مع key=0 لكنها تسمح بسحب الحضور بدون مصادقة
      if (reply.command == ZkCommand.ackUnauthorized || commKey > 0) {
        final authOk = await _authenticate(commKey);
        if (!authOk) {
          // تحذير فقط، نكمل — السحب قد ينجح بدونها
          _lastError = null; // لا نعتبره فشل اتصال
        } else {
          _lastError = null;
        }
        // حتى لو فشلت المصادقة، نترك isConnected=true ونجرب سحب البيانات
      } else {
        _lastError = null;
      }
      return true;
    } catch (e) {
      _lastError = 'خطأ شبكة: $e';
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_isConnected && _socket != null) {
      try { await _sendCommand(ZkCommand.cmdDisconnect); } catch (_) {}
    }
    try { await _sockSub?.cancel(); } catch (_) {}
    _sockSub = null;
    _recvBuffer.clear();
    try { await _socket?.close(); } catch (_) {}
    _socket = null;
    _isConnected = false;
    _sessionId = 0;
    _replyId = 0;
  }

  /// Single correct ZKTeco scramble: bit-reverse(key) + sessionId
  Future<bool> _authenticate(int key) async {
    int reversed = 0;
    for (int i = 0; i < 32; i++) {
      if ((key & (1 << i)) != 0) {
        reversed = (reversed << 1) | 1;
      } else {
        reversed = (reversed << 1);
      }
    }
    final scrambled = reversed + _sessionId;
    final payload = ByteData(4)..setUint32(0, scrambled, Endian.little);
    final reply = await _sendCommand(ZkCommand.cmdAuth, payload: payload.buffer.asUint8List());
    return reply != null && reply.isSuccess;
  }

  /// Minimal device info — used only for connection test
  Future<ZkDeviceInfo> getDeviceInfo() async {
    _ensureConnected();
    String? version;
    DateTime? deviceTime;
    try {
      final r = await _sendCommand(ZkCommand.cmdVersion);
      if (r != null && r.payload.isNotEmpty) version = _cleanString(r.payload);
    } catch (_) {}
    try {
      final r = await _sendCommand(ZkCommand.cmdGetTime);
      if (r != null && r.payload.length >= 4) {
        final raw = ByteData.sublistView(r.payload, 0, 4).getUint32(0, Endian.little);
        deviceTime = ZkPacketCodec.decodeZkTimestamp(raw);
      }
    } catch (_) {}
    return ZkDeviceInfo(firmwareVersion: version, deviceTime: deviceTime);
  }

  Future<bool> setDeviceTime(DateTime dt) async {
    _ensureConnected();
    final encoded = ZkPacketCodec.encodeZkTimestamp(dt);
    final payload = ByteData(4)..setUint32(0, encoded, Endian.little);
    final reply = await _sendCommand(ZkCommand.cmdSetTime, payload: payload.buffer.asUint8List());
    return reply != null && reply.isSuccess;
  }

  Future<List<ZkUser>> getUsers() async {
    _ensureConnected();
    final data = await _fetchDataCommand(command: ZkCommand.cmdUserTempRrq, payload: Uint8List.fromList([0x05]));
    if (data.isEmpty) return [];
    final users = <ZkUser>[];
    if (data.length >= 72 && data.length % 72 == 0) {
      for (int off = 0; off + 72 <= data.length; off += 72) {
        final u = _parse72ByteUser(Uint8List.sublistView(data, off, off+72));
        if (u != null) users.add(u);
      }
    }
    return users;
  }

  Future<List<ZkAttendanceRecord>> getAttendanceRecords({DateTime? since}) async {
    _ensureConnected();
    var data = await _fetchDataCommand(command: ZkCommand.cmdAttLogRrq);
    if (data.isEmpty) return [];
    // K50 Pro sometimes prefixes 4-byte totalSize; skip it if present
    if (data.length % 40 == 4) {
      final possibleSize = ByteData.sublistView(data, 0, 4).getUint32(0, Endian.little);
      if (possibleSize == data.length - 4) data = Uint8List.sublistView(data, 4);
    }
    final records = <ZkAttendanceRecord>[];
    if (data.length >= 40 && data.length % 40 == 0) {
      for (int offset = 0; offset + 40 <= data.length; offset += 40) {
        final chunk = Uint8List.sublistView(data, offset, offset + 40);
        final rec = _parse40ByteAttendance(chunk);
        if (rec != null && (since == null || rec.timestamp.isAfter(since))) records.add(rec);
      }
    } else if (data.length >= 8 && (data.length % 8 == 0 || data.length % 16 == 0)) {
      final rs = (data.length % 16 == 0) ? 16 : 8;
      for (int offset = 0; offset + rs <= data.length; offset += rs) {
        final chunk = Uint8List.sublistView(data, offset, offset + rs);
        final rec = _parseLegacyAttendance(chunk);
        if (rec != null && (since == null || rec.timestamp.isAfter(since))) records.add(rec);
      }
    } else {
      for (int offset = 0; offset + 40 <= data.length; offset += 40) {
        final chunk = Uint8List.sublistView(data, offset, offset + 40);
        final rec = _parse40ByteAttendance(chunk);
        if (rec != null && (since == null || rec.timestamp.isAfter(since))) records.add(rec);
      }
    }
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return records;
  }

  // --- Core ---

  Future<ZkPacket?> _sendCommand(int command, {Uint8List? payload}) async {
    if (_socket == null) return null;
    _replyId = (_replyId + 1) & 0xFFFF;
    final pkt = ZkPacketCodec.encodeTcpPacket(command: command, sessionId: _sessionId, replyId: _replyId, payload: payload);
    _socket!.add(pkt);
    await _socket!.flush();
    return await _receivePacket();
  }

  Future<ZkPacket?> _receivePacket() async {
    if (_socket == null) return null;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_recvBuffer.length >= 8) {
        int magicOffset = -1;
        for (int i = 0; i <= _recvBuffer.length - 4; i++) {
          if (_recvBuffer[i] == 0x50 && _recvBuffer[i+1] == 0x50 && _recvBuffer[i+2] == 0x82 && _recvBuffer[i+3] == 0x7D) { magicOffset = i; break; }
        }
        if (magicOffset > 0) _recvBuffer.removeRange(0, magicOffset);
        if (_recvBuffer.length >= 8 && _recvBuffer[0]==0x50 && _recvBuffer[1]==0x50) {
          final expectedLen = ByteData.sublistView(Uint8List.fromList(_recvBuffer), 4, 8).getUint32(0, Endian.little);
          final totalLen = 8 + expectedLen;
          if (_recvBuffer.length >= totalLen) {
            final raw = Uint8List.fromList(_recvBuffer.sublist(0, totalLen));
            _recvBuffer.removeRange(0, totalLen);
            return ZkPacketCodec.decodeTcpPacket(raw);
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 20));
      if (_socket == null) return null;
    }
    return null;
  }

  Future<Uint8List> _fetchDataCommand({required int command, Uint8List? payload}) async {
    final firstReply = await _sendCommand(command, payload: payload);
    if (firstReply == null) return Uint8List(0);
    if (firstReply.command == ZkCommand.ackData) return firstReply.payload;
    if (firstReply.command == ZkCommand.cmdPrepareData) {
      final totalSize = firstReply.payload.length >= 4 ? ByteData.sublistView(firstReply.payload, 0, 4).getUint32(0, Endian.little) : 0;
      final acc = <int>[];
      while (acc.length < totalSize) {
        final p = await _receivePacket();
        if (p == null) break;
        if (p.command == ZkCommand.cmdData || p.command == ZkCommand.ackData) acc.addAll(p.payload);
        else if (p.command == ZkCommand.ackOk) break;
      }
      await _sendCommand(ZkCommand.cmdFreeData);
      return Uint8List.fromList(acc);
    }
    if (firstReply.isSuccess && firstReply.payload.isNotEmpty) return firstReply.payload;
    return Uint8List(0);
  }

  void _ensureConnected() {
    if (!_isConnected || _socket == null) throw StateError('ZKTeco client is not connected');
  }

  String _cleanString(Uint8List b) {
    try { return _extractNullTerminatedString(b); } catch (_) { return latin1.decode(b).trim(); }
  }

  String _extractNullTerminatedString(Uint8List bytes) {
    int end = bytes.indexOf(0);
    if (end == -1) end = bytes.length;
    return utf8.decode(bytes.sublist(0, end), allowMalformed: true).trim();
  }

  ZkUser? _parse72ByteUser(Uint8List bytes) {
    if (bytes.length < 72) return null;
    final view = ByteData.sublistView(bytes);
    final uid = view.getUint16(0, Endian.little);
    final role = bytes[2];
    final name = _extractNullTerminatedString(bytes.sublist(11, 35));
    final userId = _extractNullTerminatedString(bytes.sublist(48, 72));
    if (userId.isEmpty && uid == 0) return null;
    return ZkUser(uid: uid, userId: userId.isNotEmpty ? userId : uid.toString(), name: name.isNotEmpty ? name : 'User $userId', role: role);
  }

  ZkAttendanceRecord? _parse40ByteAttendance(Uint8List bytes) {
    if (bytes.length < 40) return null;
    final view = ByteData.sublistView(bytes);
    // K50 Pro: uid at 0 (2 bytes), userId string at 2, fallback to 0
    String userId = _extractNullTerminatedString(bytes.sublist(2, 26));
    if (userId.isEmpty || userId.codeUnitAt(0) < 0x20) {
      userId = _extractNullTerminatedString(bytes.sublist(0, 24));
    }
    if (userId.isEmpty) userId = _extractNullTerminatedString(bytes.sublist(4, 28));
    // Clean non-printable prefix
    userId = userId.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (userId.isEmpty) {
      final uid = view.getUint16(0, Endian.little);
      if (uid != 0) userId = uid.toString();
    }
    // Try multiple timestamp offsets for K50 variability
    DateTime? time;
    for (final off in [27, 28, 29, 32, 36, 26]) {
      if (off + 4 > bytes.length) continue;
      final raw = view.getUint32(off, Endian.little);
      final dt = ZkPacketCodec.decodeZkTimestamp(raw);
      if (dt.year >= 2020 && dt.year <= 2027) { time = dt; break; }
    }
    time ??= ZkPacketCodec.decodeZkTimestamp(view.getUint32(32, Endian.little));
    final status = bytes[26] < 10 ? bytes[26] : (bytes.length > 30 ? bytes[30] : 0);
    final verifyType = bytes[27] < 20 ? bytes[27] : (bytes.length > 31 ? bytes[31] : 1);
    if (userId.isEmpty && (time.year < 2000 || time.year > 2099)) return null;
    return ZkAttendanceRecord(userId: userId, timestamp: time, status: status, verifyType: verifyType);
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
    return ZkAttendanceRecord(userId: uid.toString(), timestamp: time, status: status, verifyType: verifyType);
  }
}
