import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/enhanced_backup_service.dart';
import '../../services/cloud/google_drive_auth_service.dart';
import '../../services/cloud/cloud_backup_encryption_service.dart';
import '../../core/models/user_model.dart';
import '../../core/provider/auth_provider.dart';
import '../../core/provider/app_database_provider.dart';
import '../../widgets/permission_guard.dart';
import 'widgets/google_drive_connection_card.dart';
import 'widgets/cloud_folder_sync_card.dart';

class EnhancedBackupScreen extends StatefulWidget {
  const EnhancedBackupScreen({super.key});

  @override
  State<EnhancedBackupScreen> createState() => _EnhancedBackupScreenState();
}

class _EnhancedBackupScreenState extends State<EnhancedBackupScreen>
    with SingleTickerProviderStateMixin {
  final EnhancedBackupService _backupService = EnhancedBackupService();
  final GoogleDriveAuthService _driveAuthService = GoogleDriveAuthService();
  final CloudBackupEncryptionService _encryptionService =
      CloudBackupEncryptionService();

  late final TabController _tabController;

  List<EnhancedBackupInfo> _backups = [];
  bool _isLoading = false;
  Map<String, dynamic>? _statistics;
  Map<String, dynamic>? _autoBackupStatus;

  bool _isGoogleDriveConnected = false;
  String? _googleDriveEmail;
  String? _disasterRecoveryKey;
  String? _backupDirectoryPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final backups = await _backupService.listBackups();

      bool isAuto(EnhancedBackupInfo b) => b.type.contains('auto');
      bool isManual(EnhancedBackupInfo b) => b.type.contains('manual');

      final statistics = {
        'total_backups': backups.length,
        'automatic_backups': backups.where(isAuto).length,
        'manual_backups': backups.where(isManual).length,
        'total_size_mb': (backups.fold<int>(0, (sum, b) => sum + b.size) /
                (1024 * 1024))
            .toStringAsFixed(1),
      };

      final autoStatus = {
        'enabled': true,
        'interval': '24 ساعة (يومي)',
        'last_backup':
            backups.isNotEmpty ? backups.first.formattedDate : 'لم يتم بعد',
      };

      // Check Google Drive status
      bool gdriveConnected = false;
      String? gdriveEmail;
      try {
        gdriveConnected = await _driveAuthService.isSignedIn();
        if (gdriveConnected) {
          gdriveEmail = await _driveAuthService.getUserEmail();
        }
      } catch (_) {}

      // Load recovery key
      String? recKey;
      try {
        recKey = await _encryptionService.getRecoveryKey();
        recKey ??= await _encryptionService.getOrCreateLocalMasterKey();
      } catch (_) {}

      // Load local backup directory path
      String? localBackupPath;
      try {
        localBackupPath = await _backupService.getBackupDirectoryPath();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _backups = backups;
          _statistics = statistics;
          _autoBackupStatus = autoStatus;
          _isGoogleDriveConnected = gdriveConnected;
          _googleDriveEmail = gdriveEmail;
          _disasterRecoveryKey = recKey;
          _backupDirectoryPath = localBackupPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('تعذر تحميل بيانات النسخ الاحتياطي: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor =
        isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final borderColor =
        isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final goldColor = const Color(0xFFC9A84C);
    final blueColor = const Color(0xFF58A6FF);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي والاستعادة'),
        backgroundColor: cardBg,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث البيانات',
            color: subTextColor,
          ),
          const Gap(8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. بطاقات المؤشرات العلوية KPI
                  _buildMetricCardsRow(isDark),
                  const Gap(20),

                  // 2. شريط التبويبات العصري
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: isDark ? const Color(0xFF21262D) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: goldColor.withValues(alpha: 0.6),
                        ),
                      ),
                      labelColor: isDark ? Colors.white : Colors.black,
                      unselectedLabelColor: subTextColor,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.cloud_sync_rounded, size: 20),
                          text: 'المزامنة السحابية (Google Drive)',
                        ),
                        Tab(
                          icon: Icon(Icons.save_rounded, size: 20),
                          text: 'النسخ المحلي والأرشيف',
                        ),
                        Tab(
                          icon: Icon(Icons.security_rounded, size: 20),
                          text: 'الجدولة التلقائية والأمان',
                        ),
                      ],
                    ),
                  ),
                  const Gap(20),

                  // 3. محتوى التبويبات
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      switch (_tabController.index) {
                        case 0:
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CloudFolderSyncCard(
                                onBackupRestored: _loadData,
                                onFolderChanged: _loadData,
                              ),
                              const Gap(16),
                              Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                                    leading: const Icon(Icons.vpn_key_outlined, color: Color(0xFF58A6FF)),
                                    title: const Text(
                                      'الربط المباشر عبر Google Drive OAuth (خيار إضافي متقدم)',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: const Text(
                                      'لربط حساب Google API مباشرة وتخزين النسخ بدون الاعتماد على مجلد مزامنة محلي',
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: GoogleDriveConnectionCard(
                                          onBackupRestored: _loadData,
                                          onStatusChanged: (connected, email) {
                                            setState(() {
                                              _isGoogleDriveConnected = connected;
                                              _googleDriveEmail = email;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        case 1:
                          return _buildLocalBackupsTab(isDark);
                        case 2:
                          return _buildSettingsAndSecurityTab(isDark);
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }

  // صف بطاقات المؤشرات العلوية KPI
  Widget _buildMetricCardsRow(bool isDark) {
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final textColor =
        isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor =
        isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final goldColor = const Color(0xFFC9A84C);
    final blueColor = const Color(0xFF58A6FF);
    final greenColor = const Color(0xFF2EA043);
    final purpleColor = const Color(0xFFA371F7);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 36) / 4;
        final isCompact = constraints.maxWidth < 900;

        final items = [
          // البطاقة 1: Google Drive
          _buildKpiCard(
            cardBg: cardBg,
            borderColor: borderColor,
            textColor: textColor,
            subTextColor: subTextColor,
            accentColor: blueColor,
            icon: Icons.cloud_done_rounded,
            title: 'Google Drive',
            value: _isGoogleDriveConnected
                ? (_googleDriveEmail ?? 'متصل')
                : 'غير مربوط',
            badgeText: _isGoogleDriveConnected ? 'متصل 🟢' : 'غير متصل ⚪',
            badgeColor: _isGoogleDriveConnected ? greenColor : const Color(0xFFD29922),
            onTap: () => _tabController.animateTo(0),
          ),
          // البطاقة 2: النسخ المحلية
          _buildKpiCard(
            cardBg: cardBg,
            borderColor: borderColor,
            textColor: textColor,
            subTextColor: subTextColor,
            accentColor: goldColor,
            icon: Icons.folder_zip_outlined,
            title: 'النسخ المحلية',
            value: '${_statistics?['total_backups'] ?? _backups.length} نسخة',
            badgeText: '${_statistics?['total_size_mb'] ?? "0.0"} MB',
            badgeColor: goldColor,
            onTap: () => _tabController.animateTo(1),
          ),
          // البطاقة 3: النسخ التلقائي
          _buildKpiCard(
            cardBg: cardBg,
            borderColor: borderColor,
            textColor: textColor,
            subTextColor: subTextColor,
            accentColor: greenColor,
            icon: Icons.update_rounded,
            title: 'النسخ التلقائي',
            value: _autoBackupStatus?['enabled'] == true ? 'مفعّل يومياً' : 'معطّل',
            badgeText: 'كل 24 ساعة',
            badgeColor: greenColor,
            onTap: () => _tabController.animateTo(2),
          ),
          // البطاقة 4: التشفير
          _buildKpiCard(
            cardBg: cardBg,
            borderColor: borderColor,
            textColor: textColor,
            subTextColor: subTextColor,
            accentColor: purpleColor,
            icon: Icons.lock_outline_rounded,
            title: 'الأمان والتشفير',
            value: 'AES-256-GCM',
            badgeText: 'Zero-Knowledge',
            badgeColor: purpleColor,
            onTap: () => _tabController.animateTo(2),
          ),
        ];

        if (isCompact) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: items
                .map((w) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: w,
                    ))
                .toList(),
          );
        }

        return Row(
          children: items
              .map((w) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: w,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required Color cardBg,
    required Color borderColor,
    required Color textColor,
    required Color subTextColor,
    required Color accentColor,
    required IconData icon,
    required String title,
    required String value,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const Gap(10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: subTextColor,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const Gap(12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // تبويب النسخ المحلي
  Widget _buildLocalBackupsTab(bool isDark) {
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final innerBg =
        isDark ? const Color(0xFF21262D) : const Color(0xFFF6F8FA);
    final textColor =
        isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor =
        isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final borderColor =
        isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final goldColor = const Color(0xFFC9A84C);
    final blueColor = const Color(0xFF58A6FF);
    final greenColor = const Color(0xFF2EA043);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // بطاقة مسار مجلد النسخ الاحتياطي المحلي والتكامل مع Google Drive
        _buildLocalBackupFolderCard(
          cardBg: cardBg,
          innerBg: innerBg,
          textColor: textColor,
          subTextColor: subTextColor,
          borderColor: borderColor,
          goldColor: goldColor,
          blueColor: blueColor,
          isDark: isDark,
        ),
        const Gap(16),

        // شريط الإجراءات السريعة
        Card(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.flash_on_rounded, color: goldColor, size: 20),
                    const Gap(8),
                    Text(
                      'الإجراءات والعمليات المحلية',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const Gap(14),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    PermissionGuard(
                      permission: Permission.createBackup,
                      showUpgradePrompt: false,
                      child: ElevatedButton.icon(
                        onPressed: _createManualBackup,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('إنشاء نسخة يدوية'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blueColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    PermissionGuard(
                      permission: Permission.createBackup,
                      showUpgradePrompt: false,
                      child: ElevatedButton.icon(
                        onPressed: _createImmediateBackup,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('نسخ فوري سريع'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goldColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    PermissionGuard(
                      permission: Permission.restoreBackup,
                      showUpgradePrompt: false,
                      child: OutlinedButton.icon(
                        onPressed: _importBackup,
                        icon: const Icon(Icons.file_open_outlined, size: 18),
                        label: const Text('استيراد نسخة من ملف'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    PermissionGuard(
                      permission: Permission.createBackup,
                      showUpgradePrompt: false,
                      child: OutlinedButton.icon(
                        onPressed: _exportBackup,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('تصدير نسخة إلى مسار خارجي'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const Gap(16),

        // قائمة النسخ المحلية
        Card(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: blueColor, size: 20),
                    const Gap(8),
                    Text(
                      'النسخ الاحتياطية المتوفرة على القرص الصلب',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        '${_backups.length} نسخة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(14),
                Divider(color: borderColor, height: 1),
                const Gap(10),

                if (_backups.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.folder_open_rounded,
                            size: 48,
                            color: subTextColor.withValues(alpha: 0.5)),
                        const Gap(12),
                        Text(
                          'لا توجد نسخ احتياطية محلية حالياً',
                          style: TextStyle(color: subTextColor, fontSize: 14),
                        ),
                        const Gap(6),
                        Text(
                          'اضغط على زر "إنشاء نسخة يدوية" بالأعلى لحفظ أول نسخة محلية.',
                          style: TextStyle(
                              color: subTextColor.withValues(alpha: 0.7),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _backups.length,
                    separatorBuilder: (context, index) =>
                        Divider(color: borderColor.withValues(alpha: 0.5), height: 1),
                    itemBuilder: (context, index) {
                      final backup = _backups[index];
                      return _buildLocalBackupItem(backup, isDark);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalBackupFolderCard({
    required Color cardBg,
    required Color innerBg,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required Color goldColor,
    required Color blueColor,
    required bool isDark,
  }) {
    final folderPath = _backupDirectoryPath ?? 'جاري تحديد المسار...';

    return Card(
      color: cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: goldColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.folder_special_rounded, color: goldColor, size: 20),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مسار مجلد النسخ الاحتياطي المحلي (Google Drive & Local Storage)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        'المجلد المعتمد لحفظ ملفات النسخ الاحتياطي (.posbackup) على هذا الجهاز',
                        style: TextStyle(
                          fontSize: 12,
                          color: subTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: innerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, color: subTextColor, size: 20),
                  const Gap(10),
                  Expanded(
                    child: SelectableText(
                      folderPath,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  const Gap(10),
                  OutlinedButton.icon(
                    onPressed: _copyBackupPath,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('نسخ المسار'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const Gap(8),
                  ElevatedButton.icon(
                    onPressed: _openBackupFolder,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('فتح المجلد'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF238636),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: blueColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: blueColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cloud_upload_outlined, color: blueColor, size: 18),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      '💡 لمزامنة النسخ الاحتياطية مع Google Drive: اضغط على "فتح المجلد" وانسخ ملفات النسخ (.posbackup) إلى مجلد Google Drive، أو حدد هذا المجلد داخل تطبيق Google Drive Desktop لمزامنته تلقائياً.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalBackupItem(EnhancedBackupInfo backup, bool isDark) {
    final textColor =
        isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor =
        isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final blueColor = const Color(0xFF58A6FF);
    final greenColor = const Color(0xFF2EA043);

    final isManual = backup.type.contains('manual');
    final typeColor = isManual ? blueColor : greenColor;
    final typeIcon = isManual ? Icons.touch_app_rounded : Icons.schedule_rounded;
    final typeLabel = isManual ? 'يدوي' : 'تلقائي';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(typeIcon, color: typeColor, size: 20),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        backup.filename,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                    ),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(4),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: subTextColor),
                    const Gap(4),
                    Text(
                      backup.formattedDate,
                      style: TextStyle(fontSize: 12, color: subTextColor),
                    ),
                    const Gap(16),
                    Icon(Icons.storage, size: 14, color: subTextColor),
                    const Gap(4),
                    Text(
                      backup.formattedSize,
                      style: TextStyle(
                          fontSize: 12,
                          color: subTextColor,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(12),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: subTextColor),
            onSelected: (value) {
              switch (value) {
                case 'show_in_folder':
                  _openBackupFileInExplorer(backup);
                  break;
                case 'verify':
                  _verifyBackup(backup);
                  break;
                case 'restore':
                  _restoreBackup(backup);
                  break;
                case 'export':
                  _exportSpecificBackup(backup);
                  break;
                case 'delete':
                  _deleteBackup(backup);
                  break;
              }
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[
                const PopupMenuItem(
                  value: 'show_in_folder',
                  child: Row(
                    children: [
                      Icon(Icons.folder_open_outlined,
                          color: Color(0xFF2EA043), size: 18),
                      Gap(8),
                      Text('إظهار في مستكشف الملفات'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'verify',
                  child: Row(
                    children: [
                      Icon(Icons.verified_outlined,
                          color: Color(0xFF58A6FF), size: 18),
                      Gap(8),
                      Text('فحص سلامة النسخة'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file,
                          color: Color(0xFFC9A84C), size: 18),
                      Gap(8),
                      Text('تصدير إلى مسار'),
                    ],
                  ),
                ),
              ];

              final user = _getCurrentUser();
              if (user?.hasPermission(Permission.restoreBackup) == true) {
                items.insert(
                  0,
                  const PopupMenuItem(
                    value: 'restore',
                    child: Row(
                      children: [
                        Icon(Icons.restore_rounded,
                            color: Color(0xFF2EA043), size: 18),
                        Gap(8),
                        Text('استعادة هذه النسخة'),
                      ],
                    ),
                  ),
                );
              }

              if (user?.hasPermission(Permission.deleteBackup) == true) {
                items.add(
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            color: Color(0xFFF85149), size: 18),
                        Gap(8),
                        Text('حذف من القرص'),
                      ],
                    ),
                  ),
                );
              }

              return items;
            },
          ),
        ],
      ),
    );
  }

  // تبويب الجدولة التلقائية والأمان
  Widget _buildSettingsAndSecurityTab(bool isDark) {
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final innerBg =
        isDark ? const Color(0xFF21262D) : const Color(0xFFF6F8FA);
    final textColor =
        isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor =
        isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final borderColor =
        isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final goldColor = const Color(0xFFC9A84C);
    final greenColor = const Color(0xFF2EA043);
    final blueColor = const Color(0xFF58A6FF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. بطاقة الجدولة التلقائية
        Card(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: greenColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(Icons.schedule_rounded, color: greenColor, size: 22),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'النسخ الاحتياطي التلقائي المجدول',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const Gap(2),
                          Text(
                            'أخذ لقطات أمان تلقائية دورية وحفظها في مجلد النظام',
                            style: TextStyle(fontSize: 12, color: subTextColor),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _autoBackupStatus?['enabled'] ?? false,
                      activeThumbColor: goldColor,
                      onChanged: (value) {
                        if (value) {
                          EnhancedAutoBackupService.start();
                        } else {
                          EnhancedAutoBackupService.stop();
                        }
                        _loadData();
                      },
                    ),
                  ],
                ),
                const Gap(16),
                Divider(color: borderColor, height: 1),
                const Gap(16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: innerBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      _buildConfigRow('حالة الجدولة',
                          _autoBackupStatus?['enabled'] == true ? 'مفعّل ويعمل في الخلفية' : 'معطّل', textColor,
                          statusColor: _autoBackupStatus?['enabled'] == true ? greenColor : Colors.red),
                      const Gap(10),
                      _buildConfigRow('الفاصل الزمني التلقائي',
                          _autoBackupStatus?['interval'] ?? '24 ساعة', textColor),
                      const Gap(10),
                      _buildConfigRow('آخر عملية نسخ تلقائي',
                          _autoBackupStatus?['last_backup'] ?? 'لم تسجل بعد', textColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const Gap(16),

        // 2. بطاقة الأمان ومفتاح استرداد الكوارث
        Card(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: goldColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.shield_rounded, color: goldColor, size: 22),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الأمان والتشفير الصفري (Zero-Knowledge)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const Gap(2),
                          Text(
                            'خوارزمية التشفير القياسية AES-256-GCM مع مفتاح استرداد خاص بالمنشأة',
                            style: TextStyle(fontSize: 12, color: subTextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                Divider(color: borderColor, height: 1),
                const Gap(16),
                Text(
                  'رمز استرداد الكوارث الخاص بمنشأتك (Disaster Recovery Key):\n'
                  'احتفظ بهذا الرمز في مكان آمن خارج هذا الكمبيوتر. إذا تعرض الجهاز للتلف أو قمت بتثبيت نسخة جديدة على جهاز آخر، هذا الرمز هو الوسيلة الوحيدة لفك تشفير واستعادة بياناتك من Google Drive.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: subTextColor),
                ),
                const Gap(14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: innerBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _disasterRecoveryKey ?? 'تعذر قراءة المفتاح',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: blueColor,
                          ),
                        ),
                      ),
                      if (_disasterRecoveryKey != null)
                        IconButton(
                          icon: Icon(Icons.copy, color: goldColor),
                          tooltip: 'نسخ المفتاح',
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _disasterRecoveryKey!));
                            _showSuccessSnackBar(
                                'تم نسخ مفتاح الاسترداد إلى الحافظة بنجاح');
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigRow(String label, String value, Color textColor,
      {Color? statusColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: statusColor ?? textColor,
          ),
        ),
      ],
    );
  }

  User? _getCurrentUser() {
    try {
      return ProviderScope.containerOf(context).read(authProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _createManualBackup() async {
    try {
      setState(() => _isLoading = true);

      await _backupService.createBackup(
        type: 'manual',
        description: 'نسخة احتياطية يدوية',
      );

      _showSuccessSnackBar('تم إنشاء النسخة الاحتياطية بنجاح');
      await _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في إنشاء النسخة الاحتياطية: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createImmediateBackup() async {
    try {
      setState(() => _isLoading = true);

      await _backupService.createBackup(
        type: 'immediate_auto',
        description: 'نسخة احتياطية فورية',
      );

      _showSuccessSnackBar('تم إنشاء النسخة الفورية بنجاح');
      await _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في إنشاء النسخة الفورية: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportBackup() async {
    try {
      if (PlatformUtils.isMobile) {
        final backup = await _backupService.createBackup(
          type: 'manual_export',
          description: 'نسخة احتياطية مصدرة',
        );
        await Share.shareXFiles([XFile(backup.filePath)]);
        _showSuccessSnackBar('تم تصدير النسخة الاحتياطية بنجاح');
        return;
      }

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة احتياطية',
        fileName:
            'POS_Backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.posbackup',
        type: FileType.custom,
        allowedExtensions: ['posbackup'],
      );

      if (result != null) {
        final backup = await _backupService.createBackup(
          type: 'manual_export',
          description: 'نسخة احتياطية مصدرة',
        );

        await File(backup.filePath).copy(result);
        _showSuccessSnackBar('تم تصدير النسخة الاحتياطية بنجاح');
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في تصدير النسخة الاحتياطية: $e');
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر نسخة احتياطية للاستعادة',
        type: FileType.custom,
        allowedExtensions: ['posbackup', 'zip'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final picked = result.files.first;
      final pickedPath = picked.path;
      final pickedBytes = picked.bytes;
      if (pickedPath == null && pickedBytes == null) {
        _showErrorSnackBar('تعذر الوصول إلى ملف النسخة الاحتياطية');
        return;
      }

      final confirmed = await _showConfirmDialog(
        'هل أنت متأكد من استعادة هذه النسخة؟ سيتم استبدال جميع البيانات الحالية.',
      );

      if (confirmed) {
        setState(() => _isLoading = true);

        final appDir = await getApplicationDocumentsDirectory();
        final backupDir = Directory('${appDir.path}/data/backups');
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
        final sanitizedPickedName = path.basename(picked.name);
        final backupFileName = sanitizedPickedName.isNotEmpty
            ? sanitizedPickedName
            : (pickedPath != null
                ? path.basename(pickedPath)
                : 'imported_backup.posbackup');
        final targetPath = '${backupDir.path}/$backupFileName';
        if (pickedPath != null) {
          await File(pickedPath).copy(targetPath);
        } else {
          await File(targetPath).writeAsBytes(pickedBytes!, flush: true);
        }

        await _backupService.restoreBackup(path.basename(targetPath));
        if (mounted) {
          final container = ProviderScope.containerOf(context);
          container.invalidate(appDatabaseProvider);
          final newDb = container.read(appDatabaseProvider);
          _backupService.init(newDb);

          _showSuccessSnackBar('تم استعادة النسخة الاحتياطية بنجاح');
          await _loadData();
        }
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في استعادة النسخة الاحتياطية: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreBackup(EnhancedBackupInfo backup) async {
    final confirmed = await _showConfirmDialog(
      'هل أنت متأكد من استعادة النسخة الاحتياطية "${backup.filename}"؟\nسيتم استبدال جميع البيانات الحالية.',
    );

    if (confirmed) {
      try {
        setState(() => _isLoading = true);

        await _backupService.restoreBackup(backup.filename);
        if (mounted) {
          final container = ProviderScope.containerOf(context);
          container.invalidate(appDatabaseProvider);
          final newDb = container.read(appDatabaseProvider);
          _backupService.init(newDb);

          _showSuccessSnackBar('تم استعادة النسخة الاحتياطية بنجاح');
          await _loadData();
        }
      } catch (e) {
        _showErrorSnackBar('خطأ في استعادة النسخة الاحتياطية: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyBackup(EnhancedBackupInfo backup) async {
    try {
      setState(() => _isLoading = true);
      final isValid =
          await _backupService.verifyBackupIntegrity(backup.filename);
      setState(() => _isLoading = false);

      if (isValid) {
        _showInfoDialog(
          'معلومات النسخة الاحتياطية',
          '✅ النسخة الاحتياطية سليمة وصالحة للاستعادة بنسبة 100%.\n\n'
              'الملف: ${backup.filename}\n'
              'الحجم: ${backup.formattedSize}\n'
              'التاريخ: ${backup.formattedDate}\n'
              'النوع: ${backup.type}',
        );
      } else {
        _showErrorSnackBar('⚠️ النسخة الاحتياطية غير صالحة أو تالفة');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('خطأ في التحقق من النسخة الاحتياطية: $e');
    }
  }

  Future<void> _exportSpecificBackup(EnhancedBackupInfo backup) async {
    try {
      if (PlatformUtils.isMobile) {
        await Share.shareXFiles([XFile(backup.filePath)]);
        _showSuccessSnackBar('تم تصدير النسخة الاحتياطية بنجاح');
        return;
      }

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة احتياطية',
        fileName: backup.filename,
        type: FileType.custom,
        allowedExtensions: ['posbackup'],
      );

      if (result != null) {
        await File(backup.filePath).copy(result);
        _showSuccessSnackBar('تم تصدير النسخة الاحتياطية بنجاح');
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في تصدير النسخة الاحتياطية: $e');
    }
  }

  Future<void> _deleteBackup(EnhancedBackupInfo backup) async {
    final confirmed = await _showConfirmDialog(
      'هل أنت متأكد من حذف النسخة الاحتياطية "${backup.filename}"؟\nلا يمكن التراجع عن هذا الإجراء.',
    );

    if (confirmed) {
      try {
        await _backupService.deleteBackup(backup.filename);
        _showSuccessSnackBar('تم حذف النسخة الاحتياطية بنجاح');
        await _loadData();
      } catch (e) {
        _showErrorSnackBar('خطأ في حذف النسخة الاحتياطية: $e');
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const Gap(8),
            Text(message),
          ],
        ),
        backgroundColor: const Color(0xFF2EA043),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const Gap(8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFF85149),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'نسخ',
          textColor: Colors.white,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message));
          },
        ),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String message) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: cardBg,
            title: Text('تأكيد',
                style: TextStyle(
                    color: textColor, fontWeight: FontWeight.bold)),
            content: Text(message, style: TextStyle(color: textColor)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF85149),
                  foregroundColor: Colors.white,
                ),
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showInfoDialog(String title, String content) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor =
        isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: Text(title,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        content: Text(content, style: TextStyle(color: textColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  Future<void> _openBackupFolder() async {
    final folderPath = _backupDirectoryPath;
    if (folderPath == null || folderPath.isEmpty) return;

    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      if (Platform.isWindows) {
        await Process.run('explorer.exe', [dir.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
      }
    } catch (e) {
      _showErrorSnackBar('تعذر فتح المجلد في متصفح الملفات: $e');
    }
  }

  Future<void> _copyBackupPath() async {
    final folderPath = _backupDirectoryPath;
    if (folderPath == null || folderPath.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: folderPath));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              Gap(8),
              Expanded(
                child: Text('تم نسخ مسار مجلد النسخ الاحتياطي إلى الحافظة بنجاح.'),
              ),
            ],
          ),
          backgroundColor: Color(0xFF2EA043),
        ),
      );
    }
  }

  Future<void> _openBackupFileInExplorer(EnhancedBackupInfo backup) async {
    try {
      final file = File(backup.filePath);
      if (!await file.exists()) {
        _showErrorSnackBar('ملف النسخة الاحتياطية غير موجود: ${backup.filename}');
        return;
      }
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.parent.path]);
      }
    } catch (e) {
      _showErrorSnackBar('تعذر تحديد موقع الملف: $e');
    }
  }
}
