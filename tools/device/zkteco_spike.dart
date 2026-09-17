import 'dart:io';
import 'package:pos_offline_desktop/services/attendance/zkteco/zkteco_client.dart';

void main(List<String> args) async {
  print('====================================================');
  print('    ZKTeco Standalone Protocol Spike & Test Tool    ');
  print('====================================================\n');

  String ip = '192.168.1.201';
  int port = 4370;
  int commKey = 0;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--ip' && i + 1 < args.length) {
      ip = args[i + 1];
    } else if (args[i] == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[i + 1]) ?? 4370;
    } else if (args[i] == '--key' && i + 1 < args.length) {
      commKey = int.tryParse(args[i + 1]) ?? 0;
    }
  }

  print('Target Terminal: $ip:$port (Comm Key: $commKey)');
  print('Attempting TCP socket handshake...\n');

  final client = ZKTecoClient(
    host: ip,
    port: port,
    commKey: commKey,
    timeout: const Duration(seconds: 5),
  );

  final stopwatch = Stopwatch()..start();

  try {
    // 1. Connect
    final connected = await client.connect();
    if (!connected) {
      print('❌ FAILED to connect to ZKTeco terminal at $ip:$port');
      print('   Please verify:');
      print('   - The device is powered ON and connected to the same LAN.');
      print('   - Port 4370 is open and not blocked by firewall.');
      print('   - The Communication Key ($commKey) matches terminal settings.\n');
      exit(1);
    }

    print('✅ CONNECTED! Handshake completed in ${stopwatch.elapsedMilliseconds} ms.');
    print('   Session ID: ${client.sessionId}\n');

    // 2. Fetch Device Info
    print('--- [1] Device Information ---');
    try {
      final info = await client.getDeviceInfo();
      print('   Firmware Version: ${info.firmwareVersion ?? 'Unknown'}');
      print('   Device Name:      ${info.deviceName ?? 'Unknown'}');
      print('   Serial Number:    ${info.serialNumber ?? 'Unknown'}');
      print('   Platform:         ${info.platform ?? 'Unknown'}');
      print('   Device Time:      ${info.deviceTime != null ? info.deviceTime!.toIso8601String() : 'Unknown'}');
    } catch (e) {
      print('   ⚠️ Could not read full device info: $e');
    }
    print('');

    // 3. Fetch Enrolled Users
    print('--- [2] Reading Enrolled Users ---');
    try {
      final users = await client.getUsers();
      print('   Found ${users.length} enrolled users on device:');
      for (final user in users.take(10)) {
        print('   - UID: ${user.uid} | External User ID: "${user.userId}" | Name: "${user.name}" | Role: ${user.isAdmin ? "Admin" : "User"} | Enabled: ${user.enabled}');
      }
      if (users.length > 10) {
        print('   ... and ${users.length - 10} more users.');
      }
    } catch (e) {
      print('   ⚠️ Failed to read users: $e');
    }
    print('');

    // 4. Fetch Attendance Logs
    print('--- [3] Reading Attendance Logs ---');
    try {
      final records = await client.getAttendanceRecords();
      print('   Found ${records.length} total attendance records in device memory:');
      for (final r in records.reversed.take(10)) {
        print('   - [${r.timestamp.toIso8601String()}] User: "${r.userId}" | Event: ${r.eventType} (status: ${r.status}) | VerifyType: ${r.verifyType}');
      }
      if (records.length > 10) {
        print('   ... and ${records.length - 10} earlier records.');
      }
    } catch (e) {
      print('   ⚠️ Failed to read attendance logs: $e');
    }
    print('');

    // 5. Disconnect
    print('Closing session cleanly...');
    await client.disconnect();
    print('✅ Session closed. Spike test finished successfully.');
  } catch (e, stack) {
    print('❌ Unexpected error during spike test: $e');
    print(stack);
    await client.disconnect();
    exit(1);
  }
}
