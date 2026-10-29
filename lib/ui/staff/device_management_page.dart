import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:drift/drift.dart' show Value;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/attendance/zkteco_tcp_attendance_source.dart';
import 'device_user_import_page.dart';
import '../../core/theme/madar_colors.dart';

class DeviceManagementPage extends ConsumerStatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  ConsumerState<DeviceManagementPage> createState() =>
      _DeviceManagementPageState();
}

class _DeviceManagementPageState extends ConsumerState<DeviceManagementPage> {
  List<BiometricDevice> _devices = [];
  bool _isLoading = true;
  bool _autoSync = true;
  bool _syncingAll = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    // Auto-sync runs app-wide from the provider (every 2 min); here we only
    // reflect its state plus one silent catch-up sync on open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _catchUpOnOpen());
  }

  Future<void> _catchUpOnOpen() async {
    if (!mounted) return;
    try {
      final svc = ref.read(attendanceSyncServiceProvider);
      if (mounted) setState(() => _autoSync = svc.isAutoSyncEnabled);
    } catch (_) {}
    // Silent catch-up: pull whatever the devices hold since last sync.
    try {
      final svc = ref.read(attendanceSyncServiceProvider);
      await svc.syncAllDevices(triggeredBy: 'page_open');
      await _loadDevices();
    } catch (_) {}
  }

  Future<void> _toggleAutoSync(bool value) async {
    try {
      final svc = ref.read(attendanceSyncServiceProvider);
      if (value) {
        svc.startAutoSync(interval: const Duration(minutes: 2));
      } else {
        svc.stopAutoSync();
      }
      if (mounted) setState(() => _autoSync = svc.isAutoSyncEnabled);
    } catch (_) {}
  }

  Future<void> _syncAllDevices() async {
    if (_syncingAll) return;
    setState(() => _syncingAll = true);
    try {
      final svc = ref.read(attendanceSyncServiceProvider);
      final user = ref.read(authProvider);
      final result = await svc.syncAllDevices(
        triggeredBy: user?.username ?? 'manual_all',
      );
      await _loadDevices();
      if (mounted) {
        if (result.error != null && result.matched == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.error!.length < 140 ? result.error! : 'فشلت المزامنة',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تمت مزامنة الكل: ${result.fetched} من الأجهزة، ${result.matched} اتسجل حضور'
                '${result.info == null ? '' : '\n${result.info}'}',
              ),
              backgroundColor: result.matched > 0
                  ? Colors.green
                  : Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت مزامنة الكل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingAll = false);
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final dao = ref.read(attendanceDeviceDaoProvider);
    final devices = await dao.getAllDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncDevice(BiometricDevice device) async {    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('جاري مزامنة جهاز ${device.name}...')),
      );
      final syncService = ref.read(attendanceSyncServiceProvider);
      final user = ref.read(authProvider);
      final result = await syncService.syncDevice(
        device,
        triggeredBy: user?.username ?? 'manual',
      );

      await _loadDevices();
      if (mounted) {
        if (result.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.error!.length < 140 ? result.error! : 'فشلت المزامنة',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          final parts = <String>['${result.fetched} من الجهاز'];
          parts.add('${result.matched} اتسجل حضور');
          if (result.unmatched > 0) {
            parts.add('${result.unmatched} بلا موظف');
          }
          if (result.duplicate > 0) {
            parts.add('${result.duplicate} مكرر');
          }
          if (result.info != null) {
            parts.add(result.info!);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تمت المزامنة: ${parts.join('، ')}'),
              backgroundColor: result.matched > 0
                  ? Colors.green
                  : Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// تصفير كيرسور جهاز (سحب كامل من الأول).
  ///
  /// آمن: منع التكرار بالـdedup hash، فإعادة السحب لا تنشئ دوبلكيت.
  /// يُستخدم عند توقف المزامنة الصامت (كيرسور مسموم) أو بعد إصلاح الشبكة.
  Future<void> _resyncDevice(BiometricDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إعادة سحب كامل — ${device.name}؟'),
        content: const Text(
          'سيتم سحب كل سجلات الجهاز من الأول. '
          'البصمات المسجلة قبل كده مش هتتكرر (حماية ضد التكرار). '
          'استخدمها لو المزامنة بتقول "تمت" وصفر رغم وجود بصمات جديدة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تصفير وإعادة السحب'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(attendanceDeviceDaoProvider).resetDeviceSyncCursor(device.id);
      await _loadDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اتصفّر الكيرسور — دوس مزامنة الآن للسحب الكامل'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصفير الكيرسور: $e')),
        );
      }
    }
  }

  Future<void> _testDeviceConnection(BiometricDevice device) async {
    if (device.connectionType != 'tcp_ip' ||
        device.ipAddress == null ||
        device.port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'فحص الاتصال متاح فقط للأجهزة المتصلة عبر الشبكة (TCP/IP)',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final stopwatch = Stopwatch()..start();
    try {
      final source = ZKTecoTcpAttendanceSource(
        ipAddress: device.ipAddress!,
        port: device.port!,
        authToken: device.authToken,
        timeout: const Duration(seconds: 10),
      );

      final connected = await source.connect();
      stopwatch.stop();

      if (!mounted) return;
      Navigator.pop(context);

      if (connected) {
        final info = await source.getDeviceInfo();
        await source.disconnect();

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('الاتصال بالجهاز ناجح'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اسم الجهاز: ${info.deviceName ?? device.name}'),
                Text('عنوان IP: ${device.ipAddress}:${device.port}'),
                Text('وقت الاستجابة: ${stopwatch.elapsedMilliseconds} ms'),
                if (info.firmwareVersion != null)
                  Text('إصدار الفيرموير: ${info.firmwareVersion}'),
                if (info.serialNumber != null)
                  Text('الرقم التسلسلي: ${info.serialNumber}'),
                if (info.deviceTime != null)
                  Text('توقيت الجهاز: ${info.deviceTime}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      } else {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('فشل الاتصال بالجهاز'),
              ],
            ),
            content: Text(
              'تعذر الوصول إلى الجهاز في ${device.ipAddress}:${device.port}.\n'
              'يرجى التأكد من:\n'
              '1. تشغيل الجهاز وتوصيله بالشبكة المحلية.\n'
              '2. صحة الـ IP والمنفذ (4370).\n'
              '3. صحة مفتاح الاتصال (Communication Key) إن وجد.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('خطأ أثناء فحص الاتصال'),
          content: Text('حدث خطأ: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    }
  }

  void _showAddDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddDeviceDialog(onDeviceAdded: _loadDevices),
    );
  }

  void _showEditDeviceDialog(BiometricDevice device) {
    showDialog(
      context: context,
      builder: (context) =>
          _AddDeviceDialog(onDeviceAdded: _loadDevices, device: device),
    );
  }

  void _confirmDeleteDevice(BiometricDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الجهاز'),
        content: Text(
          'هل أنت متأكد من حذف الجهاز "${device.name}"?\nسيتم حذف جميع الحركات المرتبطة به.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                final dao = ref.read(attendanceDeviceDaoProvider);
                await dao.deleteDevice(device.id);
                _loadDevices();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('تم حذف الجهاز'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('خطأ في الحذف: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: Permission.manageAttendanceDevices,
      child: Scaffold(
        backgroundColor: MadarColors.bgDark,
        appBar: AppBar(
          title: const Text('إدارة أجهزة الحضور'),
          backgroundColor: MadarColors.bgDark,
          foregroundColor: MadarColors.textLight,
          elevation: 0,
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: MadarColors.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: MadarColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('مزامنة تلقائية', style: TextStyle(fontSize: 12, color: MadarColors.textSecondary)),
                  const SizedBox(width: 6),
                  Switch(
                    value: _autoSync,
                    onChanged: _toggleAutoSync,
                    activeColor: MadarColors.gold,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: _syncingAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: MadarColors.gold),
                    )
                  : const Icon(Icons.sync, color: MadarColors.gold),
              onPressed: _syncingAll ? null : _syncAllDevices,
              tooltip: 'مزامنة كل الأجهزة الآن',
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: MadarColors.success),
              onPressed: _showAddDeviceDialog,
              tooltip: 'إضافة جهاز',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: MadarColors.gold))
            : _devices.isEmpty
            ? const Center(
                child: Text(
                  'لا توجد أجهزة مضافة. اضغط + لإضافة جهاز.',
                  style: TextStyle(color: MadarColors.textSecondary),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  return _buildDeviceCard(_devices[index]);
                },
              ),
      ),
    );
  }

  Widget _buildDeviceCard(BiometricDevice device) {
    final isTcp = device.connectionType == 'tcp_ip';
    final isSuccess = device.lastSyncStatus == 'success';
    final isPartial = device.lastSyncStatus == 'partial';
    final isUnsynced = device.lastSyncStatus == null;

    final statusColor = isSuccess
        ? MadarColors.success
        : isPartial
            ? MadarColors.warning
            : isUnsynced
                ? MadarColors.textMuted
                : MadarColors.error;

    final statusText = isSuccess
        ? 'متصل'
        : isPartial
            ? 'جزئي — راجع غير المطابق'
            : isUnsynced
                ? 'لم يتم المزامنة'
                : 'مفصول/خطأ';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: MadarColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSuccess ? MadarColors.border : statusColor.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isTcp ? MadarColors.info : MadarColors.gold).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isTcp ? MadarColors.info : MadarColors.gold).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    isTcp ? Icons.router_outlined : Icons.description_outlined,
                    color: isTcp ? MadarColors.info : MadarColors.gold,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              device.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: MadarColors.textLight,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildDeviceBadge(
                            isTcp ? 'TCP/IP' : 'استيراد ملف',
                            Icons.settings_ethernet,
                          ),
                          if (device.ipAddress != null)
                            _buildDeviceBadge(
                              '${device.ipAddress}:${device.port ?? 4370}',
                              Icons.network_check,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: MadarColors.border),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _syncDevice(device),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('مزامنة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: MadarColors.info.withValues(alpha: 0.15),
                    foregroundColor: MadarColors.info,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: MadarColors.info.withValues(alpha: 0.3)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeviceUserImportPage(device: device),
                      ),
                    );
                  },
                  icon: const Icon(Icons.group_add_outlined, size: 16),
                  label: const Text('المستخدمين', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MadarColors.textLight,
                    side: const BorderSide(color: MadarColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.wifi_find, size: 20, color: Colors.tealAccent),
                  onPressed: () => _testDeviceConnection(device),
                  tooltip: 'اختبار الاتصال',
                ),
                if (isTcp)
                  IconButton(
                    icon: const Icon(Icons.restore_page, size: 20, color: Colors.purpleAccent),
                    onPressed: () => _resyncDevice(device),
                    tooltip: 'إعادة سحب كامل (تصفير الكيرسور)',
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20, color: MadarColors.gold),
                  onPressed: () => _showEditDeviceDialog(device),
                  tooltip: 'تعديل البيانات',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: MadarColors.error),
                  onPressed: () => _confirmDeleteDevice(device),
                  tooltip: 'حذف الجهاز',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceBadge(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: MadarColors.bgDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MadarColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: MadarColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: MadarColors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Dialog إضافة / تعديل جهاز =====

class _AddDeviceDialog extends ConsumerStatefulWidget {
  final VoidCallback onDeviceAdded;
  final BiometricDevice? device;
  const _AddDeviceDialog({required this.onDeviceAdded, this.device});

  @override
  ConsumerState<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends ConsumerState<_AddDeviceDialog> {
  final _nameController = TextEditingController();
  final _deviceCodeController = TextEditingController();
  final _vendorController = TextEditingController();
  final _modelController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '4370');
  final _serialController = TextEditingController();
  final _locationController = TextEditingController();
  final _authTokenController = TextEditingController();
  String _connectionType = 'tcp_ip';
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.device != null;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    if (d != null) {
      // وضع التعديل: تعبئة الحقول بالبيانات المحفوظة للجهاز
      _nameController.text = d.name;
      _deviceCodeController.text = d.deviceCode;
      _connectionType = d.connectionType;
      _vendorController.text = d.vendor ?? '';
      _modelController.text = d.model ?? '';
      _ipController.text = d.ipAddress ?? '';
      _portController.text = d.port?.toString() ?? '4370';
      _serialController.text = d.serialNumber ?? '';
      _locationController.text = d.location ?? '';
      _authTokenController.text = d.authToken ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _deviceCodeController.dispose();
    _vendorController.dispose();
    _modelController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _serialController.dispose();
    _locationController.dispose();
    _authTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'تعديل بيانات الجهاز' : 'إضافة جهاز حضور جديد'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الجهاز *',
                  hintText: 'مثال: بوابة الدخول الرئيسية',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceCodeController,
                decoration: const InputDecoration(
                  labelText: 'كود الجهاز *',
                  hintText: 'مثال: BIO-001',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _connectionType,
                decoration: const InputDecoration(labelText: 'نوع الاتصال *'),
                items: const [
                  DropdownMenuItem(value: 'tcp_ip', child: Text('TCP/IP')),
                  DropdownMenuItem(
                    value: 'usb_import',
                    child: Text('استيراد USB'),
                  ),
                  DropdownMenuItem(value: 'sdk', child: Text('SDK')),
                  DropdownMenuItem(
                    value: 'file_import',
                    child: Text('استيراد ملف'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _connectionType = v);
                },
              ),
              if (_connectionType == 'tcp_ip') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان IP *',
                    hintText: '192.168.1.100',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_connectionType == 'tcp_ip' &&
                        (v == null || v.trim().isEmpty)) {
                      return 'مطلوب للاتصال TCP/IP';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'البورت *',
                    hintText: '4370',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_connectionType == 'tcp_ip' &&
                        (v == null || v.trim().isEmpty)) {
                      return 'مطلوب';
                    }
                    if (v != null && v.isNotEmpty && int.tryParse(v) == null) {
                      return 'رقم صحيح مطلوب';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _vendorController,
                decoration: const InputDecoration(
                  labelText: 'الشركة المصنعة',
                  hintText: 'ZKTeco, Hikvision',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelController,
                decoration: const InputDecoration(labelText: 'الموديل'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serialController,
                decoration: const InputDecoration(labelText: 'الرقم التسلسلي'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'الموقع',
                  hintText: 'الفرع الرئيسي، بوابة 1',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _authTokenController,
                decoration: const InputDecoration(
                  labelText: 'Auth Token (اختياري)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final db = ref.read(appDatabaseProvider);
      final dao = db.attendanceDeviceDao;
      final now = DateTime.now();

      // التحقق من عدم تكرار كود الجهاز (مع استثناء الجهاز نفسه في وضع التعديل)
      final existingDevices = await dao.getAllDevices();
      final codeExists = existingDevices.any(
        (d) =>
            d.deviceCode == _deviceCodeController.text.trim() &&
            d.id != widget.device?.id,
      );
      if (codeExists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كود الجهاز موجود بالفعل'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (_isEditing) {
        // تحديث بيانات الجهاز الموجود — copyWith يحافظ على id/createdAt/lastSyncAt تلقائياً
        final updated = widget.device!.copyWith(
          deviceCode: _deviceCodeController.text.trim(),
          name: _nameController.text.trim(),
          connectionType: _connectionType,
          vendor: Value(
            _vendorController.text.trim().isEmpty
                ? null
                : _vendorController.text.trim(),
          ),
          model: Value(
            _modelController.text.trim().isEmpty
                ? null
                : _modelController.text.trim(),
          ),
          ipAddress: _connectionType == 'tcp_ip'
              ? Value(_ipController.text.trim())
              : const Value(null),
          port: _connectionType == 'tcp_ip' && _portController.text.isNotEmpty
              ? Value(int.tryParse(_portController.text.trim()))
              : const Value(null),
          serialNumber: Value(
            _serialController.text.trim().isEmpty
                ? null
                : _serialController.text.trim(),
          ),
          location: Value(
            _locationController.text.trim().isEmpty
                ? null
                : _locationController.text.trim(),
          ),
          authToken: Value(
            _authTokenController.text.trim().isEmpty
                ? null
                : _authTokenController.text.trim(),
          ),
          updatedAt: now,
        );
        await dao.updateDevice(updated);

        if (!mounted) return;
        Navigator.pop(context);
        widget.onDeviceAdded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث بيانات الجهاز بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      // إضافة جهاز جديد
      await dao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: _deviceCodeController.text.trim(),
          name: _nameController.text.trim(),
          connectionType: _connectionType,
          vendor: Value(
            _vendorController.text.trim().isEmpty
                ? null
                : _vendorController.text.trim(),
          ),
          model: Value(
            _modelController.text.trim().isEmpty
                ? null
                : _modelController.text.trim(),
          ),
          ipAddress: _connectionType == 'tcp_ip'
              ? Value(_ipController.text.trim())
              : const Value(null),
          port: _connectionType == 'tcp_ip' && _portController.text.isNotEmpty
              ? Value(int.parse(_portController.text.trim()))
              : const Value(null),
          serialNumber: Value(
            _serialController.text.trim().isEmpty
                ? null
                : _serialController.text.trim(),
          ),
          location: Value(
            _locationController.text.trim().isEmpty
                ? null
                : _locationController.text.trim(),
          ),
          authToken: Value(
            _authTokenController.text.trim().isEmpty
                ? null
                : _authTokenController.text.trim(),
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onDeviceAdded();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إضافة الجهاز بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في حفظ الجهاز: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
