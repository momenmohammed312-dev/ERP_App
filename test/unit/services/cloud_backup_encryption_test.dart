import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pos_offline_desktop/services/cloud/cloud_backup_encryption_service.dart';
import 'package:path/path.dart' as p;

class MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CloudBackupEncryptionService service;
  late MockSecureStorage mockStorage;
  late Directory tempDir;

  setUp(() async {
    mockStorage = MockSecureStorage();
    service = CloudBackupEncryptionService(secureStorage: mockStorage);
    tempDir = await Directory.systemTemp.createTemp('madar_enc_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('generates and formats readable recovery key', () async {
    final recoveryKey = await service.getRecoveryKey();
    expect(recoveryKey, isNull);

    // Initialize master key
    final masterKey = await service.getOrCreateLocalMasterKey();
    expect(masterKey.isNotEmpty, isTrue);

    final generatedKey = await service.getRecoveryKey();
    expect(generatedKey, isNotNull);
    expect(generatedKey!.startsWith('MDR-'), isTrue);
    expect(generatedKey.split('-').length, 5); // MDR-XXXX-XXXX-XXXX-XXXX
  });

  test('encryptBytes and decryptBytes roundtrip with local master key', () async {
    final originalText = 'قاعدة بيانات مِدار المحاسبية - نسخة سحابية مؤمنة 2026';
    final rawBytes = Uint8List.fromList(utf8.encode(originalText));

    final encrypted = await service.encryptBytes(rawBytes: rawBytes);
    expect(encrypted.length, greaterThan(rawBytes.length + 60));

    // Verify magic header "MDRC"
    expect(encrypted[0], 0x4D); // 'M'
    expect(encrypted[1], 0x44); // 'D'
    expect(encrypted[2], 0x52); // 'R'
    expect(encrypted[3], 0x43); // 'C'
    expect(encrypted[4], 0x01); // Version 1

    final decrypted = await service.decryptBytes(encryptedBytes: encrypted);
    expect(utf8.decode(decrypted), originalText);
  });

  test('replacement device scenario: decrypts with recovery key alone on fresh device', () async {
    // 1. Device A: create backup and note recovery key
    final deviceAService = CloudBackupEncryptionService(secureStorage: mockStorage);
    await deviceAService.getOrCreateLocalMasterKey();
    final recoveryKey = (await deviceAService.getRecoveryKey())!;

    final originalData = 'بيانات منقولة لجهاز بديل بعد حادث طارئ';
    final rawBytes = Uint8List.fromList(utf8.encode(originalData));
    final encryptedEnvelope = await deviceAService.encryptBytes(rawBytes: rawBytes);

    // 2. Device B (Empty storage - fresh installation)
    final freshStorage = MockSecureStorage();
    final deviceBService = CloudBackupEncryptionService(secureStorage: freshStorage);

    // Attempting without recovery key fails
    expect(
      () => deviceBService.decryptBytes(encryptedBytes: encryptedEnvelope),
      throwsA(isA<CloudBackupInvalidKeyException>()),
    );

    // With recovery key: succeeds perfectly
    final decrypted = await deviceBService.decryptBytes(
      encryptedBytes: encryptedEnvelope,
      recoveryKeyOrPassphrase: recoveryKey,
    );
    expect(utf8.decode(decrypted), originalData);

    // Case-insensitive & normalized recovery key also succeeds
    final lowercaseRecoveryKey = recoveryKey.toLowerCase().replaceAll('-', ' ');
    final decryptedWithSpaces = await deviceBService.decryptBytes(
      encryptedBytes: encryptedEnvelope,
      recoveryKeyOrPassphrase: lowercaseRecoveryKey,
    );
    expect(utf8.decode(decryptedWithSpaces), originalData);
  });

  test('tampering with any byte fails authentication and throws exception', () async {
    final rawBytes = Uint8List.fromList(utf8.encode('بيانات سرية للتحقق من عدم التلاعب'));
    final encrypted = await service.encryptBytes(rawBytes: rawBytes);

    // Tamper with payload byte
    final tamperedPayload = Uint8List.fromList(encrypted);
    tamperedPayload[tamperedPayload.length - 5] ^= 0xFF;

    expect(
      () => service.decryptBytes(encryptedBytes: tamperedPayload),
      throwsA(isA<CloudBackupSecurityException>()),
    );

    // Tamper with magic header
    final tamperedHeader = Uint8List.fromList(encrypted);
    tamperedHeader[0] = 0x00;
    expect(
      () => service.decryptBytes(encryptedBytes: tamperedHeader),
      throwsA(isA<CloudBackupSecurityException>()),
    );
  });

  test('file-based encryption and decryption roundtrip', () async {
    final sourceFile = File(p.join(tempDir.path, 'source_test.sqlite'));
    await sourceFile.writeAsString('Test SQLite Database binary simulation content');

    final encryptedFile = File(p.join(tempDir.path, 'backup.poscloudbackup'));
    final decryptedFile = File(p.join(tempDir.path, 'restored.sqlite'));

    await service.encryptBackupFile(
      sourceFile: sourceFile,
      targetEncryptedFile: encryptedFile,
    );

    expect(await encryptedFile.exists(), isTrue);
    expect(await encryptedFile.length(), greaterThan(await sourceFile.length()));

    await service.decryptBackupFile(
      encryptedFile: encryptedFile,
      targetDecryptedFile: decryptedFile,
    );

    expect(await decryptedFile.exists(), isTrue);
    expect(await decryptedFile.readAsString(), await sourceFile.readAsString());
  });
}
