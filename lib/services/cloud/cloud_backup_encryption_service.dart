import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart' as crypto;

class CloudBackupSecurityException implements Exception {
  final String message;
  CloudBackupSecurityException(this.message);
  @override
  String toString() => message;
}

class CloudBackupTamperedException extends CloudBackupSecurityException {
  CloudBackupTamperedException([super.message = 'فشل التحقق من صحة التشفير (Auth Tag Mismatch): الملف تالف أو تم التلاعب به في السحابة']);
}

class CloudBackupInvalidKeyException extends CloudBackupSecurityException {
  CloudBackupInvalidKeyException([super.message = 'مفتاح الاسترداد أو كلمة المرور غير صحيحة، تعذر فك تشفير النسخة السحابية']);
}

class CloudBackupEncryptionService {
  static const List<int> _magicHeader = [0x4D, 0x44, 0x52, 0x43]; // "MDRC"
  static const int _formatVersion = 0x01;
  static const int _saltLength = 32; // 256 bits salt
  static const int _ivLength = 12; // 96 bits nonce for GCM
  static const int _authTagLength = 16; // 128 bits tag
  static const int _pbkdf2Iterations = 10000;
  static const int _keyLength = 32; // 256 bits AES key

  static const String _storageKeyMasterKey = 'madar_cloud_backup_master_key';
  static const String _storageKeyRecoveryKey = 'madar_cloud_backup_recovery_key';

  final FlutterSecureStorage _secureStorage;

  CloudBackupEncryptionService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ════════════════════════════════════════════════════════════════════════
  // 1. إدارة مفاتيح المنشأة واسترداد الكوارث (Key Management & Recovery)
  // ════════════════════════════════════════════════════════════════════════

  /// الحصول على أو إنشاء المفتاح الرئيسي المحلي المشفر في خزنة النظام
  Future<String> getOrCreateLocalMasterKey() async {
    try {
      final existingKey = await _secureStorage.read(key: _storageKeyMasterKey);
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    } catch (_) {}

    // إنشاء كود استرداد موحد كأساس للتشفير: MDR-XXXX-XXXX-XXXX-XXXX
    final randomBytes = _generateSecureRandomBytes(16);
    final recoveryKey = generateFormattedRecoveryKey(randomBytes);
    await _secureStorage.write(key: _storageKeyMasterKey, value: recoveryKey);
    await _secureStorage.write(key: _storageKeyRecoveryKey, value: recoveryKey);

    return recoveryKey;
  }

  /// قراءة كود الاسترداد الحالي للعميل لحفظه أو طباعته
  Future<String?> getRecoveryKey() async {
    try {
      final key = await _secureStorage.read(key: _storageKeyRecoveryKey);
      if (key != null && key.isNotEmpty) return key;

      final master = await _secureStorage.read(key: _storageKeyMasterKey);
      if (master != null && master.isNotEmpty) {
        final bytes = base64Url.decode(master);
        final formatted = generateFormattedRecoveryKey(bytes);
        await _secureStorage.write(key: _storageKeyRecoveryKey, value: formatted);
        return formatted;
      }
    } catch (_) {}
    return null;
  }

  /// توليد كود استرداد بتنسيق واضح وسهل الكتابة: MDR-XXXX-XXXX-XXXX-XXXX
  static String generateFormattedRecoveryKey([List<int>? sourceBytes]) {
    final bytes = sourceBytes ?? _generateSecureRandomBytes(16);
    final hexStr = crypto.sha256.convert(bytes).toString().toUpperCase();
    final p1 = hexStr.substring(0, 4);
    final p2 = hexStr.substring(4, 8);
    final p3 = hexStr.substring(8, 12);
    final p4 = hexStr.substring(12, 16);
    return 'MDR-$p1-$p2-$p3-$p4';
  }

  /// مسح المفاتيح المخزنة محلياً عند إلغاء الربط التام
  Future<void> clearStoredKeys() async {
    try {
      await _secureStorage.delete(key: _storageKeyMasterKey);
      await _secureStorage.delete(key: _storageKeyRecoveryKey);
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════
  // 2. التشفير المصادق للنسخ السحابية (AES-256-GCM Encryption)
  // ════════════════════════════════════════════════════════════════════════

  /// تشفير ملف محلي لإنتاج ملف سحابي مصادق (.poscloudbackup)
  Future<File> encryptBackupFile({
    required File sourceFile,
    required File targetEncryptedFile,
    String? customPassphrase,
  }) async {
    if (!await sourceFile.exists()) {
      throw FileSystemException('الملف المراد تشفيره غير موجود', sourceFile.path);
    }

    final rawBytes = await sourceFile.readAsBytes();
    final encryptedEnvelope = await encryptBytes(
      rawBytes: rawBytes,
      customPassphrase: customPassphrase,
    );

    if (await targetEncryptedFile.exists()) {
      await targetEncryptedFile.delete();
    }
    await targetEncryptedFile.writeAsBytes(encryptedEnvelope, flush: true);
    return targetEncryptedFile;
  }

  /// تشفير مصفوفة بايتات باستخدام AES-256-GCM وتوليد غلاف الحماية
  Future<Uint8List> encryptBytes({
    required List<int> rawBytes,
    String? customPassphrase,
  }) async {
    // 1. توليد Salt عشوائي فريد لكل نسخة
    final salt = _generateSecureRandomBytes(_saltLength);

    // 2. الحصول على المفتاح الأساسي
    final masterKey = customPassphrase ?? await getOrCreateLocalMasterKey();
    final derivedKey = _deriveKey(masterKey, salt);

    // 3. توليد Nonce/IV فريد (12 بايت) خاص بهذه العملية فقط
    final iv = _generateSecureRandomBytes(_ivLength);

    // 4. تشفير البيانات بـ GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(derivedKey),
      _authTagLength * 8, // 128 bits tag
      iv,
      Uint8List.fromList([..._magicHeader, _formatVersion]), // Additional Authenticated Data (AAD)
    );
    cipher.init(true, params);

    final inputBytes = Uint8List.fromList(rawBytes);
    final cipherTextWithTag = cipher.process(inputBytes);

    // 5. بناء الحزمة السحابية الكاملة
    // الترويسة: [MDRC (4)] [Version (1)] [Salt (32)] [IV (12)] [Ciphertext + Tag]
    final totalLength = _magicHeader.length + 1 + _saltLength + _ivLength + cipherTextWithTag.length;
    final envelope = Uint8List(totalLength);

    var offset = 0;
    envelope.setRange(offset, offset + _magicHeader.length, _magicHeader);
    offset += _magicHeader.length;

    envelope[offset] = _formatVersion;
    offset += 1;

    envelope.setRange(offset, offset + _saltLength, salt);
    offset += _saltLength;

    envelope.setRange(offset, offset + _ivLength, iv);
    offset += _ivLength;

    envelope.setRange(offset, offset + cipherTextWithTag.length, cipherTextWithTag);

    return envelope;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 3. فك التشفير المصادق والتحقق من التلاعب (Decryption & Verification)
  // ════════════════════════════════════════════════════════════════════════

  /// فك تشفير ملف سحابي مرشح إلى ملف محلي صالح
  Future<File> decryptBackupFile({
    required File encryptedFile,
    required File targetDecryptedFile,
    String? recoveryKeyOrPassphrase,
  }) async {
    if (!await encryptedFile.exists()) {
      throw FileSystemException('الملف المشفر غير موجود', encryptedFile.path);
    }

    final encryptedBytes = await encryptedFile.readAsBytes();
    final decryptedBytes = await decryptBytes(
      encryptedBytes: encryptedBytes,
      recoveryKeyOrPassphrase: recoveryKeyOrPassphrase,
    );

    if (await targetDecryptedFile.exists()) {
      await targetDecryptedFile.delete();
    }
    await targetDecryptedFile.writeAsBytes(decryptedBytes, flush: true);
    return targetDecryptedFile;
  }

  /// فك تشفير حزمة سحابية مع التحقق الصارم من الترويسة وسلامة المصادقة
  Future<Uint8List> decryptBytes({
    required List<int> encryptedBytes,
    String? recoveryKeyOrPassphrase,
  }) async {
    final minLength = _magicHeader.length + 1 + _saltLength + _ivLength + _authTagLength;
    if (encryptedBytes.length < minLength) {
      throw CloudBackupSecurityException('حجم الملف أصغر من الحد الأدنى للنسخة السحابية المشفرة');
    }

    // 1. التحقق من ترويسة Magic Bytes "MDRC"
    for (int i = 0; i < _magicHeader.length; i++) {
      if (encryptedBytes[i] != _magicHeader[i]) {
        throw CloudBackupSecurityException('صيغة الملف السحابي غير صالحة (Missing MDRC Magic Header)');
      }
    }

    // 2. التحقق من إصدار التنسيق
    final version = encryptedBytes[_magicHeader.length];
    if (version != _formatVersion) {
      throw CloudBackupSecurityException('إصدار تنسيق التشفير السحابي غير مدعوم ($version)');
    }

    var offset = _magicHeader.length + 1;
    final salt = Uint8List.fromList(encryptedBytes.sublist(offset, offset + _saltLength));
    offset += _saltLength;

    final iv = Uint8List.fromList(encryptedBytes.sublist(offset, offset + _ivLength));
    offset += _ivLength;

    final cipherTextWithTag = Uint8List.fromList(encryptedBytes.sublist(offset));

    // 3. تحديد المفتاح المناسب لفك التشفير
    // جرب المفتاح المدخل (كود استرداد/كلمة مرور) أولاً، ثم المفتاح المخزن محلياً
    final candidateKeys = <String>[];
    if (recoveryKeyOrPassphrase != null && recoveryKeyOrPassphrase.trim().isNotEmpty) {
      candidateKeys.add(recoveryKeyOrPassphrase.trim());
    }
    try {
      final localMaster = await _secureStorage.read(key: _storageKeyMasterKey);
      if (localMaster != null && localMaster.isNotEmpty && !candidateKeys.contains(localMaster)) {
        candidateKeys.add(localMaster);
      }
      final localRecovery = await _secureStorage.read(key: _storageKeyRecoveryKey);
      if (localRecovery != null && localRecovery.isNotEmpty && !candidateKeys.contains(localRecovery)) {
        candidateKeys.add(localRecovery);
      }
    } catch (_) {}

    if (candidateKeys.isEmpty) {
      throw CloudBackupInvalidKeyException(
        'لا يوجد مفتاح تشفير مسجل على هذا الجهاز. يرجى إدخال كود استرداد المنشأة (Recovery Key) لفك تشفير النسخة.',
      );
    }

    // 4. محاولة فك التشفير عبر المفاتيح المرشحة
    for (final keyStr in candidateKeys) {
      try {
        final derivedKey = _deriveKey(keyStr, salt);
        final decipher = GCMBlockCipher(AESEngine());
        final params = AEADParameters(
          KeyParameter(derivedKey),
          _authTagLength * 8,
          iv,
          Uint8List.fromList([..._magicHeader, _formatVersion]), // AAD
        );
        decipher.init(false, params);
        final decrypted = decipher.process(cipherTextWithTag);
        return decrypted;
      } on InvalidCipherTextException {
        // Tag mismatch or wrong key
        continue;
      } catch (e) {
        debugPrint('Decryption attempt with candidate key failed: $e');
        continue;
      }
    }

    throw CloudBackupInvalidKeyException(
      'فشل فك تشفير النسخة السحابية: كود الاسترداد غير مطابق، أو تم التلاعب بمحتويات النسخة في Google Drive.',
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // 4. دوال التشفير المساعدة (Cryptographic Helpers)
  // ════════════════════════════════════════════════════════════════════════

  /// اشتقاق مفتاح 256 بت باستخدام PBKDF2-HMAC-SHA256
  Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final cleanPass = normalizeKeyString(passphrase);
    final passBytes = Uint8List.fromList(utf8.encode(cleanPass));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    return pbkdf2.process(passBytes);
  }

  /// تنظيف توحيد كود الاسترداد بإزالة المسافات والشرطات الزائدة
  static String normalizeKeyString(String input) {
    return input.trim().replaceAll('-', '').replaceAll(' ', '').toUpperCase();
  }

  /// توليد بايتات عشوائية مشفرة CSPRNG
  static Uint8List _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
