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
class GoogleDriveConnectionCard extends StatefulWidget {
  final VoidCallback? onBackupRestored;

  const GoogleDriveConnectionCard({
    super.key,
    this.onBackupRestored,
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
      _actionMessage = 'جاري ربط حساب Google Drive...';
    });
    try {
      await _authService.signIn();
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم ربط حساب Google Drive بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر ربط حساب Google: $e'),
            backgroundColor: Colors.red,
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فصل حساب Google Drive'),
        content: const Text(
          'هل تريد بالتأكيد فصل حساب Google Drive؟ لن يتم حذف أي نسخ احتياطية مسجلة بالفعل على السحابة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء فصل الحساب: $e'),
            backgroundColor: Colors.red,
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
            content: Text('تم رفع النسخة المشفرة (${meta.formattedSize}) بنجاح إلى Google Drive'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الرفع السحابي: $e'),
            backgroundColor: Colors.red,
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
    final keyController = TextEditingController();
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
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
                style: const TextStyle(height: 1.5),
              ),
              const Gap(16),
              const Text(
                '⚠️ تحذير: ستستبدل هذه العملية البيانات الحالية ببيانات النسخة السحابية بعد أخذ لقطة أمان احتياطية تلقائية.',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const Gap(16),
              const Text(
                'رمز استرداد الكوارث (Disaster Recovery Key):\n'
                'إذا كنت تستعيد النسخة على نفس الجهاز الأصلي، يمكنك ترك هذا الحقل فارغاً. '
                'أما في حال استبدال الجهاز أو نقله، أدخل الرمز الخاص بك:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Gap(8),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'MDR-XXXX-XXXX-XXXX-XXXX (اختياري على نفس الجهاز)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
            content: Text('✅ تمت استعادة النسخة السحابية بنجاح وتحديث قاعدة البيانات'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل استعادة النسخة السحابية: $e'),
            backgroundColor: Colors.red,
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف نسخة سحابية'),
        content: Text(
          'هل تريد بالتأكيد حذف النسخة "${backup.name}" من Google Drive؟\n'
          'ملاحظة: هذا الحذف يمسح النسخة من السحابة فقط ولا يؤثر نهائياً على النسخ الاحتياطية المحلية الموجودة على القرص الصلب.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
            content: Text('تم حذف النسخة السحابية بنجاح'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حذف النسخة السحابية: $e'),
            backgroundColor: Colors.red,
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
        title: Row(
          children: const [
            Icon(Icons.shield, color: Colors.blue),
            Gap(8),
            Text('مفتاح استرداد الكوارث (Recovery Key)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'هذا المفتاح المشفر مخصص لمنشأتك حصرياً، وهو الوسيلة الوحيدة لفك تشفير نسخك السحابية عند تلف هذا الجهاز أو الرغبة في الانتقال إلى جهاز جديد.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const Gap(16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
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
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                  if (recoveryKey != null)
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.blue),
                      tooltip: 'نسخ المفتاح',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: recoveryKey!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ مفتاح الاسترداد إلى الحافظة بنجاح'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const Gap(16),
            const Text(
              '🔒 الأمان: النسخ الاحتياطية السحابية مشفرة محلياً بخوارزمية AES-256-GCM، ولا يستطيع أي طرف ثالث ولا حتى Google قراءة أي بيان من بياناتك بدون هذا المفتاح.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
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
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ترويسة البطاقة
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_sync_rounded,
                    color: Colors.indigo.shade700,
                    size: 28,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'النسخ الاحتياطي السحابي (Google Drive)',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                          const Gap(8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: const Text(
                              'AES-256-GCM',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                      const Gap(2),
                      const Text(
                        'تشفير صفري تام من طرف العميل (Zero-Knowledge)',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تحديث حالة السحابة',
                    onPressed: _checkStatus,
                  ),
              ],
            ),
            const Divider(height: 24),

            if (_isActionInProgress) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Text(
                        _actionMessage,
                        style: TextStyle(fontSize: 13, color: Colors.indigo.shade700, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!_isConnected) ...[
              // حالة عدم الاتصال
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'احمِ بيانات منشأتك من مخاطر تلف الجهاز أو الفقدان بربط حسابك الشخصي على Google Drive.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _handleSignIn,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('ربط حساب Google Drive'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                        const Gap(12),
                        OutlinedButton.icon(
                          onPressed: _showRecoveryKeyDialog,
                          icon: const Icon(Icons.vpn_key_outlined),
                          label: const Text('عرض رمز الاسترداد'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              // حالة الاتصال الفعال
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const Gap(8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName ?? 'حساب Google متصل',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            _userEmail ?? '',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showRecoveryKeyDialog,
                      icon: const Icon(Icons.key, size: 16),
                      label: const Text('رمز الاسترداد'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo.shade800,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const Gap(8),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.red),
                      tooltip: 'فصل الحساب',
                      onPressed: _handleSignOut,
                    ),
                  ],
                ),
              ),
              const Gap(16),

              // إجراء الرفع
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _handleUploadCloudBackup,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('رفع نسخة احتياطية سحابية الآن'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'النسخ المحفوظة: ${_cloudBackups.length} (الحد الأقصى: 5)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const Gap(16),

              // قائمة النسخ السحابية
              if (_cloudBackups.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'لا توجد نسخ سحابية محفوظة حتى الآن في Google Drive',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _cloudBackups.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final b = _cloudBackups[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade50,
                        child: Icon(Icons.cloud_done, color: Colors.indigo.shade700, size: 20),
                      ),
                      title: Text(
                        b.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        'التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(b.createdTime)} • الحجم: ${b.formattedSize}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restore, color: Colors.green),
                            tooltip: 'استعادة هذه النسخة',
                            onPressed: () => _handleRestoreCloudBackup(b),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'حذف من السحابة',
                            onPressed: () => _handleDeleteCloudBackup(b),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
