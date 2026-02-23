class DatabaseConfig {
  // ⚠️ CRITICAL: Change this password before release!
  // Must be exactly 32 characters (256-bit)
  static String get encryptionPassword {
    // Split password across multiple strings for obfuscation
    final p1 = 'K9#mP2\$x';
    final p2 = 'Q7@nR4%h';
    final p3 = 'T6&jW8!c';
    final p4 = 'Y0^vL5*';
    return p1 + p2 + p3 + p4;
  }

  // Database name
  static const String databaseName = 'pos_offline_desktop_database.sqlite';

  // Version
  static const int databaseVersion = 35; // Incremented for encryption
}
