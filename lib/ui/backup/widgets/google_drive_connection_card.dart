import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../../core/provider/app_database_provider.dart';
import '../../../models/cloud_backup_metadata.dart';
import '../../../services/cloud/cloud_backup_encryption_service.dart';
import '../../../services/cloud/google_drive_auth_service.dart';
import '../../../services/cloud/google_drive_backup_service.dart';

/// بطاقة إدارة الاتصال والنسخ الاحتياطي السحابي عبر Google Drive
/// مع التشفير الصفري التام من طرف العميل (Zero-Knowledge AES-256-GCM)
/// بتصميم عصري متوافق تماماً مع ثيم مدار الداكن (MADAR Dark Theme)
class GoogleDriveConnectionCard extends StatefulWidget {
  final VoidCallback? onBackupRestored;
  final void Function(bool isConnected, String? email)? onStatusChanged;

  const GoogleDriveConnectionCard({
    super.key,
    this.onBackupRestored,
    this.onStatusChanged,
  });

  @override
  State<GoogleDriveConnectionCard> createState() => _GoogleDriveConnectionCardState();
}

class _GoogleDriveConnectionCardState extends State<GoogleDriveConnectionCard> {
  late final GoogleDriveAuthService _authService;
  late final CloudBackupEncryptionService _encryptionService;
  late final GoogleDriveBackupService _driveBackupService;

  bool _isConnected = false;
  String? _userEmail;
  String? _userName;
  List<CloudBackupMetadata> _cloudBackups = [];
  bool _isLoading = false;
  bool _isActionInProgress = false;
  String _actionMessage = '';

  @override
  void initState() {
    super.initState();
    _authService = GoogleDriveAuthService();
    _encryptionService = CloudBackupEncryptionService();
    _driveBackupService = GoogleDriveBackupService(
      authService: _authService,
      encryptionService: _encryptionService,
    );
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final signedIn = await _authService.isSignedIn();
      if (signedIn) {
        final email = await _authService.getUserEmail();
        final name = await _authService.getUserDisplayName();
        final backups = await _driveBackupService.listCloudBackups();
        if (mounted) {
          setState(() {
            _isConnected = true;
            _userEmail = email;
            _userName = name;
            _cloudBackups = backups;
            _isLoading = false;
          });
          widget.onStatusChanged?.call(true, email);
        }
      } else {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _userEmail = null;
            _userName = null;
            _cloudBackups = [];
            _isLoading = false;
          });
          widget.onStatusChanged?.call(false, null);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري فتح المتصفح وربط حساب Google Drive...';
    });
    try {
      await _authService.signIn();
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const Gap(8),
                Text('تم ربط حساب Google Drive بنجاح: ${_userEmail ?? ""}'),
              ],
            ),
            backgroundColor: const Color(0xFF2EA043),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const Gap(8),
                Expanded(child: Text('تعذر ربط حساب Google: $e')),
              ],
            ),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Text('فصل حساب Google Drive', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        content: Text(
          'هل تريد بالتأكيد فصل حساب Google Drive؟ لن يتم حذف أي نسخ احتياطية مسجلة بالفعل على السحابة.',
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF85149),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('فصل الحساب'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري فصل الحساب...';
    });
    try {
      await _authService.signOut();
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فصل حساب Google بنجاح'),
            backgroundColor: Color(0xFFD29922),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء فصل الحساب: $e'),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _handleUploadCloudBackup() async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري إنشاء لقطة ذرية وتشفيرها ورفعها إلى Google Drive...';
    });
    try {
      final meta = await _driveBackupService.uploadBackup(
        description: 'نسخة سحابية يدوية - ${_formatCurrentDate()}',
      );
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_done, color: Colors.white),
                const Gap(8),
                Text('تم رفع النسخة المشفرة (${meta.formattedSize}) بنجاح إلى Google Drive'),
              ],
            ),
            backgroundColor: const Color(0xFF2EA043),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const Gap(8),
                Expanded(child: Text('فشل الرفع السحابي: $e')),
              ],
            ),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _handleRestoreCloudBackup(CloudBackupMetadata backup) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final borderColor = isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    final keyController = TextEditingController();
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD29922)),
            Gap(8),
            Text('تأكيد الاستعادة من السحابة'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'أنت على وشك استعادة النسخة السحابية:\n"${backup.name}"\n'
                'التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(backup.createdTime)}\n'
                'الحجم: ${backup.formattedSize}',
                style: TextStyle(height: 1.5, color: textColor),
              ),
              const Gap(16),
              const Text(
                '⚠️ تحذير: ستستبدل هذه العملية البيانات الحالية ببيانات النسخة السحابية بعد أخذ لقطة أمان احتياطية تلقائية.',
                style: TextStyle(color: Color(0xFFF85149), fontWeight: FontWeight.bold),
              ),
              const Gap(16),
              Text(
                'رمز استرداد الكوارث (Disaster Recovery Key):\n'
                'إذا كنت تستعيد النسخة على نفس الجهاز الأصلي، يمكنك ترك هذا الحقل فارغاً. '
                'أما في حال استبدال الجهاز أو نقله، أدخل الرمز الخاص بك:',
                style: TextStyle(fontSize: 12, color: subTextColor),
              ),
              const Gap(8),
              TextField(
                controller: keyController,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  labelText: 'MDR-XXXX-XXXX-XXXX-XXXX (اختياري على نفس الجهاز)',
                  labelStyle: TextStyle(color: subTextColor),
                  border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  prefixIcon: const Icon(Icons.key, color: Color(0xFFC9A84C)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2EA043),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('بدء الاستعادة'),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري تنزيل النسخة وفك تشفيرها والتحقق من سلامتها...';
    });

    try {
      final customKey = keyController.text.trim();
      final success = await _driveBackupService.restoreCloudBackup(
        fileId: backup.id,
        recoveryKeyOrPassphrase: customKey.isNotEmpty ? customKey : null,
      );

      if (success && mounted) {
        // تحديث مزود قاعدة البيانات في تطبيق Riverpod
        final container = ProviderScope.containerOf(context);
        container.invalidate(appDatabaseProvider);
        container.read(appDatabaseProvider);

        widget.onBackupRestored?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                Gap(8),
                Text('✅ تمت استعادة النسخة السحابية بنجاح وتحديث قاعدة البيانات'),
              ],
            ),
            backgroundColor: Color(0xFF2EA043),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const Gap(8),
                Expanded(child: Text('❌ فشل استعادة النسخة السحابية: $e')),
              ],
            ),
            backgroundColor: const Color(0xFFF85149),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _handleDeleteCloudBackup(CloudBackupMetadata backup) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Text('حذف نسخة سحابية', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        content: Text(
          'هل تريد بالتأكيد حذف النسخة "${backup.name}" من Google Drive؟\n'
          'ملاحظة: هذا الحذف يمسح النسخة من السحابة فقط ولا يؤثر نهائياً على النسخ الاحتياطية المحلية الموجودة على القرص الصلب.',
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF85149),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف من السحابة'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري حذف النسخة من Google Drive...';
    });

    try {
      await _driveBackupService.deleteCloudBackup(backup.id);
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف النسخة السحابية بنجاح من Google Drive'),
            backgroundColor: Color(0xFFD29922),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حذف النسخة السحابية: $e'),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _showRecoveryKeyDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final innerBg = isDark ? const Color(0xFF21262D) : Colors.grey.shade100;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final borderColor = isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    setState(() => _isLoading = true);
    String? recoveryKey;
    try {
      recoveryKey = await _encryptionService.getRecoveryKey();
      recoveryKey ??= await _encryptionService.getOrCreateLocalMasterKey();
    } catch (_) {}
    setState(() => _isLoading = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Row(
          children: const [
            Icon(Icons.shield, color: Color(0xFFC9A84C)),
            Gap(8),
            Text('مفتاح استرداد الكوارث (Recovery Key)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هذا المفتاح المشفر مخصص لمنشأتك حصرياً، وهو الوسيلة الوحيدة لفك تشفير نسخك السحابية عند تلف هذا الجهاز أو الرغبة في الانتقال إلى جهاز جديد.',
              style: TextStyle(fontSize: 13, height: 1.4, color: textColor),
            ),
            const Gap(16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: innerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      recoveryKey ?? 'تعذر قراءة المفتاح',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Color(0xFF58A6FF),
                      ),
                    ),
                  ),
                  if (recoveryKey != null)
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFFC9A84C)),
                      tooltip: 'نسخ المفتاح',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: recoveryKey!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ مفتاح الاسترداد إلى الحافظة بنجاح'),
                            backgroundColor: Color(0xFF2EA043),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const Gap(16),
            Text(
              '🔒 الأمان: النسخ الاحتياطية السحابية مشفرة محلياً بخوارزمية AES-256-GCM، ولا يستطيع أي طرف ثالث ولا حتى Google قراءة أي بيان من بياناتك بدون هذا المفتاح.',
              style: TextStyle(fontSize: 12, color: subTextColor),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF21262D),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  String _formatCurrentDate() {
    return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final innerBg = isDark ? const Color(0xFF21262D) : const Color(0xFFF6F8FA);
    final textColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final borderColor = isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final goldColor = const Color(0xFFC9A84C);
    final blueColor = const Color(0xFF58A6FF);
    final greenColor = const Color(0xFF2EA043);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. بطاقة حساب Google Drive والاتصال
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
                // ترويسة البطاقة
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: blueColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.cloud_sync_rounded,
                        color: blueColor,
                        size: 28,
                      ),
                    ),
                    const Gap(14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'حساب Google Drive (النسخ السحابي المشفر)',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const Gap(8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: greenColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: greenColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  'AES-256-GCM',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: greenColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Gap(4),
                          Text(
                            'تشفير صفري تام من طرف العميل (Zero-Knowledge) — النسخ مشفرة قبل مغادرة جهازك',
                            style: TextStyle(fontSize: 13, color: subTextColor),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoading)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.refresh, color: subTextColor),
                        tooltip: 'تحديث حالة السحابة',
                        onPressed: _checkStatus,
                      ),
                  ],
                ),
                const Gap(16),
                Divider(color: borderColor, height: 1),
                const Gap(16),

                if (_isActionInProgress) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: blueColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const Gap(14),
                        Expanded(
                          child: Text(
                            _actionMessage,
                            style: TextStyle(fontSize: 14, color: blueColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!_isConnected) ...[
                  // حالة عدم الاتصال - واجهة إضافة الإيميل وربط الحساب
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(10),
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
                                color: const Color(0xFFD29922).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.link_off_rounded,
                                color: Color(0xFFD29922),
                                size: 22,
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'البريد الإلكتروني غير مربوط حالياً',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: textColor,
                                    ),
                                  ),
                                  const Gap(2),
                                  Text(
                                    'اربط حسابك الشخصي أو التجاري على Google لحفظ النسخ السحابية التلقائية وحماية بياناتك من التلف.',
                                    style: TextStyle(fontSize: 13, color: subTextColor),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _handleSignIn,
                              icon: const Icon(Icons.add_link_rounded, size: 20),
                              label: const Text('إضافة / ربط إيميل Google Drive الآن'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blueColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _showRecoveryKeyDialog,
                              icon: Icon(Icons.vpn_key_outlined, size: 18, color: goldColor),
                              label: Text('عرض رمز الاسترداد (Recovery Key)', style: TextStyle(color: textColor)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: borderColor),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // حالة الاتصال الفعال - عرض الإيميل والمعلومات وأزرار الرفع
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: greenColor.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: blueColor.withValues(alpha: 0.2),
                              child: Text(
                                (_userName?.isNotEmpty == true ? _userName![0] : (_userEmail?.isNotEmpty == true ? _userEmail![0] : 'G')).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: blueColor,
                                ),
                              ),
                            ),
                            const Gap(14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _userName ?? 'حساب Google متصل',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                                      ),
                                      const Gap(8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: greenColor.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: greenColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const Gap(4),
                                            Text(
                                              'متصل',
                                              style: TextStyle(
                                                color: greenColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Gap(3),
                                  SelectableText(
                                    _userEmail ?? '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: blueColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _showRecoveryKeyDialog,
                              icon: Icon(Icons.key, size: 16, color: goldColor),
                              label: Text('رمز الاسترداد', style: TextStyle(color: textColor, fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: borderColor),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const Gap(8),
                            IconButton(
                              icon: const Icon(Icons.logout, color: Color(0xFFF85149)),
                              tooltip: 'فصل الحساب',
                              onPressed: _handleSignOut,
                            ),
                          ],
                        ),
                        const Gap(14),
                        Divider(color: borderColor, height: 1),
                        const Gap(14),
                        // شريط الإجراءات السحابية
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _handleUploadCloudBackup,
                              icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                              label: const Text('رفع نسخة احتياطية سحابية الآن'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: greenColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'النسخ المحفوظة على السحابة: ${_cloudBackups.length} من 5 (الحد الأقصى)',
                              style: TextStyle(fontSize: 12, color: subTextColor, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const Gap(16),

        // 2. قائمة النسخ السحابية المتوفرة
        if (_isConnected) ...[
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
                      Icon(Icons.cloud_done_rounded, color: blueColor, size: 22),
                      const Gap(10),
                      Text(
                        'النسخ السحابية المتوفرة في Google Drive',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'مجلد MADAR ERP Backups',
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                    ],
                  ),
                  const Gap(16),
                  Divider(color: borderColor, height: 1),
                  const Gap(12),

                  if (_cloudBackups.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                      child: Column(
                        children: [
                          Icon(Icons.cloud_queue_rounded, size: 48, color: subTextColor.withValues(alpha: 0.5)),
                          const Gap(12),
                          Text(
                            'لا توجد نسخ سحابية محفوظة حتى الآن في Google Drive',
                            style: TextStyle(color: subTextColor, fontSize: 14),
                          ),
                          const Gap(6),
                          Text(
                            'اضغط على زر "رفع نسخة احتياطية سحابية الآن" أعلاه لرفع أول نسخة مشفرة.',
                            style: TextStyle(color: subTextColor.withValues(alpha: 0.7), fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cloudBackups.length,
                      separatorBuilder: (context, index) => Divider(color: borderColor.withValues(alpha: 0.5), height: 1),
                      itemBuilder: (context, index) {
                        final b = _cloudBackups[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: blueColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.folder_zip_rounded, color: blueColor, size: 22),
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
                                            b.name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: textColor,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: greenColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '🔒 مشفر AES-256-GCM',
                                            style: TextStyle(
                                              color: greenColor,
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
                                          DateFormat('yyyy/MM/dd - hh:mm a').format(b.createdTime),
                                          style: TextStyle(fontSize: 12, color: subTextColor),
                                        ),
                                        const Gap(16),
                                        Icon(Icons.storage, size: 14, color: subTextColor),
                                        const Gap(4),
                                        Text(
                                          b.formattedSize,
                                          style: TextStyle(fontSize: 12, color: subTextColor, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: greenColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                icon: const Icon(Icons.restore, size: 18),
                                label: const Text('استعادة', style: TextStyle(fontSize: 12)),
                                onPressed: () => _handleRestoreCloudBackup(b),
                              ),
                              const Gap(8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFF85149), size: 20),
                                tooltip: 'حذف من السحابة',
                                onPressed: () => _handleDeleteCloudBackup(b),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
