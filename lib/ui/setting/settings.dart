import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/ui/user/user_management_page.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/auth_service.dart';
import '../backup/enhanced_backup_screen.dart';

// ignore_for_file: deprecated_member_use

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _darkModeEnabled = false;
  CalendarThemeMode _calendarTheme = CalendarThemeMode.light;
  List<Map<String, dynamic>> _printers = [];
  String? _selectedThermalPrinter;
  String? _selectedA4Printer;

  String? _logoPath;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxController = TextEditingController();
  final _footerController = TextEditingController();
  final _pageUrlController = TextEditingController();
  final _locationIdController = TextEditingController();
  String _lastSyncedText = 'لم تتم المزامنة بعد';
  String _lastPeriodicRunText = 'لم تتم بعد';
  int _pendingCount = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    SettingsService.getCalendarTheme().then((mode) {
      setState(() => _calendarTheme = mode);
    });
    PrinterService.getAvailablePrinters().then((list) async {
      final thermal = await SettingsService.getThermalPrinter();
      final a4 = await SettingsService.getA4Printer();
      setState(() {
        _printers = list;
        _selectedThermalPrinter = thermal;
        _selectedA4Printer = a4;
      });
    });

    SettingsService.getBusinessInfo().then((info) {
      setState(() {
        _nameController.text = info['name'] ?? '';
        _phoneController.text = info['phone'] ?? '';
        _addressController.text = info['address'] ?? '';
        _taxController.text = info['taxNumber'] ?? '';
        _footerController.text = info['footer'] ?? '';
        _pageUrlController.text = info['pageUrl'] ?? '';
      });
    });

    SettingsService.getBusinessLogoPath().then((path) {
      setState(() => _logoPath = path);
    });

    _loadSyncState();

    // Live-update the "آخر مزامنة تلقائية" label whenever the periodic timer
    // fires, with no manual refresh or restart needed.
    ref.read(syncServiceProvider).lastPeriodicRunAt.addListener(_onPeriodicRun);
  }

  void _onPeriodicRun() {
    final last = ref.read(syncServiceProvider).lastPeriodicRunAt.value;
    if (!mounted) return;
    setState(() {
      _lastPeriodicRunText = last != null
          ? 'آخر مزامنة تلقائية: ${last.toLocal()}'
          : 'لم تتم بعد';
    });
  }

  Future<void> _loadSyncState() async {
    final locationId = await SettingsService.getDeviceLocationId();
    final lastSynced = await SettingsService.getLastSyncedAt();
    final pending = await ref.read(syncServiceProvider).pendingCount();
    if (!mounted) return;
    setState(() {
      _locationIdController.text = locationId;
      _lastSyncedText = lastSynced != null
          ? 'آخر مزامنة: ${lastSynced.toLocal()}'
          : 'لم تتم المزامنة بعد';
      _pendingCount = pending;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _taxController.dispose();
    _footerController.dispose();
    _pageUrlController.dispose();
    _locationIdController.dispose();
    ref.read(syncServiceProvider).lastPeriodicRunAt.removeListener(_onPeriodicRun);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final innerBg = isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5);
    final textColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final borderColor = isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final goldColor = const Color(0xFFC9A84C);
    final blueColor = const Color(0xFF58A6FF);
    final greenColor = const Color(0xFF2EA043);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('إعدادات النظام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: cardBg,
        foregroundColor: textColor,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: borderColor)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            children: [
              // 1. التفضيلات والمظهر
              _buildSectionCard(
                cardBg: cardBg,
                borderColor: borderColor,
                title: 'المظهر والتفضيلات',
                icon: Icons.palette_outlined,
                iconColor: goldColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.dark_mode_outlined, color: goldColor, size: 22),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.dark_mode,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                                ),
                                const Gap(2),
                                Text(
                                  'تفعيل المظهر الداكن لتقليل إجهاد العين أثناء العمل',
                                  style: TextStyle(fontSize: 12, color: subTextColor),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _darkModeEnabled,
                            activeColor: goldColor,
                            onChanged: (value) {
                              setState(() {
                                _darkModeEnabled = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const Gap(16),
                    Text(
                      'نمط ألوان التقويم (Calendar Theme)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        _buildCalendarThemeOption(
                          label: 'فاتح (Light)',
                          mode: CalendarThemeMode.light,
                          textColor: textColor,
                          subTextColor: subTextColor,
                          borderColor: borderColor,
                          innerBg: innerBg,
                          goldColor: goldColor,
                        ),
                        const Gap(10),
                        _buildCalendarThemeOption(
                          label: 'رمادي (Gray)',
                          mode: CalendarThemeMode.gray,
                          textColor: textColor,
                          subTextColor: subTextColor,
                          borderColor: borderColor,
                          innerBg: innerBg,
                          goldColor: goldColor,
                        ),
                        const Gap(10),
                        _buildCalendarThemeOption(
                          label: 'داكن (Dark)',
                          mode: CalendarThemeMode.dark,
                          textColor: textColor,
                          subTextColor: subTextColor,
                          borderColor: borderColor,
                          innerBg: innerBg,
                          goldColor: goldColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Gap(20),

              // 2. إعدادات الطابعات
              _buildSectionCard(
                cardBg: cardBg,
                borderColor: borderColor,
                title: 'إعدادات الطابعات والطباعة',
                icon: Icons.print_outlined,
                iconColor: blueColor,
                trailing: OutlinedButton.icon(
                  onPressed: () async {
                    final list = await PrinterService.getAvailablePrinters();
                    setState(() => _printers = list);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('تحديث القائمة', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_printers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: innerBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: subTextColor, size: 20),
                            const Gap(10),
                            Text(
                              'لا توجد طابعات مثبتة على هذا الجهاز حالياً',
                              style: TextStyle(color: subTextColor, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedThermalPrinter,
                              style: TextStyle(color: textColor, fontSize: 13),
                              dropdownColor: cardBg,
                              decoration: InputDecoration(
                                labelText: 'طابعة الفواتير الحرارية الافتراضية (Thermal)',
                                labelStyle: TextStyle(color: subTextColor, fontSize: 12),
                                border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: blueColor)),
                                prefixIcon: Icon(Icons.receipt_rounded, color: blueColor, size: 20),
                                filled: true,
                                fillColor: innerBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              ),
                              items: _printers
                                  .where((p) => p['type'] == 'Thermal')
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p['name'] as String,
                                      child: Text(p['name'] as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) async {
                                setState(() => _selectedThermalPrinter = val);
                                await SettingsService.setThermalPrinter(val);
                              },
                            ),
                          ),
                          const Gap(14),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedA4Printer,
                              style: TextStyle(color: textColor, fontSize: 13),
                              dropdownColor: cardBg,
                              decoration: InputDecoration(
                                labelText: 'طابعة التقارير والفواتير الكبيرة (A4 / PDF)',
                                labelStyle: TextStyle(color: subTextColor, fontSize: 12),
                                border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: blueColor)),
                                prefixIcon: Icon(Icons.description_outlined, color: blueColor, size: 20),
                                filled: true,
                                fillColor: innerBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              ),
                              items: _printers
                                  .where((p) => p['type'] == 'A4' || p['type'] == 'PDF')
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p['name'] as String,
                                      child: Text(p['name'] as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) async {
                                setState(() => _selectedA4Printer = val);
                                await SettingsService.setA4Printer(val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const Gap(20),

              // 3. معلومات النشاط التجاري
              _buildSectionCard(
                cardBg: cardBg,
                borderColor: borderColor,
                title: 'معلومات النشاط التجاري (ترويسة وهوية الفاتورة)',
                icon: Icons.storefront_rounded,
                iconColor: greenColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // قسم الشعار
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          if (_logoPath != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_logoPath!),
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 56,
                                  height: 56,
                                  color: borderColor,
                                  child: const Icon(Icons.broken_image, size: 28),
                                ),
                              ),
                            ),
                            const Gap(14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('شعار المنشأة الحالي', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor)),
                                  const Gap(2),
                                  Text('يظهر أعلى فواتير A4 والحراري', style: TextStyle(fontSize: 11, color: subTextColor)),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickLogo,
                              icon: const Icon(Icons.edit, size: 15),
                              label: const Text('تغيير'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textColor,
                                side: BorderSide(color: borderColor),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            const Gap(8),
                            IconButton(
                              onPressed: () async {
                                await SettingsService.setBusinessLogoPath(null);
                                setState(() => _logoPath = null);
                              },
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              tooltip: 'حذف الشعار',
                            ),
                          ] else ...[
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderColor, style: BorderStyle.solid),
                              ),
                              child: Icon(Icons.image_outlined, color: subTextColor, size: 28),
                            ),
                            const Gap(14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('لم يتم تحديد شعار للمنشأة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor)),
                                  const Gap(2),
                                  Text('أضف شعارك ليظهر بشكل احترافي أعلى الفواتير المطبوعة', style: TextStyle(fontSize: 11, color: subTextColor)),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickLogo,
                              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                              label: const Text('إضافة شعار'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: blueColor,
                                side: BorderSide(color: blueColor.withValues(alpha: 0.4)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Gap(16),

                    // حقول البيانات
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _nameController,
                            label: 'اسم النشاط التجاري',
                            icon: Icons.store,
                            textColor: textColor,
                            subTextColor: subTextColor,
                            innerBg: innerBg,
                            borderColor: borderColor,
                            focusColor: greenColor,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _buildTextField(
                            controller: _phoneController,
                            label: 'رقم الهاتف',
                            icon: Icons.phone_outlined,
                            textColor: textColor,
                            subTextColor: subTextColor,
                            innerBg: innerBg,
                            borderColor: borderColor,
                            focusColor: greenColor,
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _addressController,
                            label: 'العنوان',
                            icon: Icons.location_on_outlined,
                            textColor: textColor,
                            subTextColor: subTextColor,
                            innerBg: innerBg,
                            borderColor: borderColor,
                            focusColor: greenColor,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _buildTextField(
                            controller: _taxController,
                            label: 'الرقم الضريبي (اختياري)',
                            icon: Icons.receipt_long_outlined,
                            textColor: textColor,
                            subTextColor: subTextColor,
                            innerBg: innerBg,
                            borderColor: borderColor,
                            focusColor: greenColor,
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    _buildTextField(
                      controller: _footerController,
                      label: 'رسالة أسفل الفاتورة (شكر أو شروط الاسترجاع)',
                      icon: Icons.notes_outlined,
                      textColor: textColor,
                      subTextColor: subTextColor,
                      innerBg: innerBg,
                      borderColor: borderColor,
                      focusColor: greenColor,
                    ),
                    const Gap(12),
                    _buildTextField(
                      controller: _pageUrlController,
                      label: 'رابط صفحة المحل (للطباعة كـ QR على ملصقات الباركود)',
                      hint: 'https://facebook.com/...',
                      icon: Icons.qr_code_2_rounded,
                      textColor: textColor,
                      subTextColor: subTextColor,
                      innerBg: innerBg,
                      borderColor: borderColor,
                      focusColor: greenColor,
                      textDirection: TextDirection.ltr,
                    ),
                    const Gap(16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveBusinessInfo,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('حفظ معلومات النشاط التجاري', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: greenColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Gap(20),

              // 4. المزامنة السحابية متعددة الأجهزة
              _buildSectionCard(
                cardBg: cardBg,
                borderColor: borderColor,
                title: 'المزامنة السحابية متعددة الأجهزة',
                icon: Icons.sync_alt_rounded,
                iconColor: blueColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مزامنة المنتجات والفواتير والمخزون بصورة لحظية بين فروعك أو أجهزتك المختلفة.',
                      style: TextStyle(color: subTextColor, fontSize: 13),
                    ),
                    const Gap(14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _locationIdController,
                            label: 'معرّف الجهاز / الفرع الحالي',
                            hint: 'مثال: Branch-Main-POS1',
                            icon: Icons.devices_outlined,
                            textColor: textColor,
                            subTextColor: subTextColor,
                            innerBg: innerBg,
                            borderColor: borderColor,
                            focusColor: blueColor,
                          ),
                        ),
                        const Gap(10),
                        OutlinedButton.icon(
                          onPressed: _saveLocationId,
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: const Text('حفظ المعرّف'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textColor,
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const Gap(14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_lastSyncedText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
                                const Gap(3),
                                Text(
                                  '$_lastPeriodicRunText | المعلق: $_pendingCount سجل',
                                  style: TextStyle(fontSize: 11, color: subTextColor),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _syncing ? null : _syncNow,
                            icon: _syncing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.sync, size: 16),
                            label: Text(_syncing ? 'جارٍ المزامنة...' : 'مزامنة يدوية الآن', style: const TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: blueColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Gap(20),

              // 5. إدارة المستخدمين والنظام
              _buildSectionCard(
                cardBg: cardBg,
                borderColor: borderColor,
                title: 'إدارة النظام والبيانات',
                icon: Icons.admin_panel_settings_outlined,
                iconColor: goldColor,
                child: Column(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.people_outline,
                      iconColor: blueColor,
                      title: 'المستخدمون والصلاحيات',
                      subtitle: 'إضافة الكاشير والمديرين وتعيين صلاحيات كل دور بدقة',
                      textColor: textColor,
                      subTextColor: subTextColor,
                      borderColor: borderColor,
                      onTap: () {
                        final db = ref.read(appDatabaseProvider);
                        final authService = ref.read(authServiceProvider);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => UserManagementPage(database: db, authService: authService)),
                        );
                      },
                    ),
                    const Gap(10),
                    _buildSettingsTile(
                      icon: Icons.cloud_sync_outlined,
                      iconColor: greenColor,
                      title: 'النسخ الاحتياطي والاستعادة (Google Drive & محلي)',
                      subtitle: 'تشفير وحفظ قواعد البيانات سحابياً ومحلياً مع مفتاح الاسترداد الآمن',
                      textColor: textColor,
                      subTextColor: subTextColor,
                      borderColor: borderColor,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EnhancedBackupScreen()),
                        );
                      },
                    ),
                    const Gap(10),
                    _buildSettingsTile(
                      icon: Icons.info_outline,
                      iconColor: goldColor,
                      title: 'حول مدار ERP',
                      subtitle: 'الإصدار 1.0.0 — رخصة تشغيل محلية مع حماية البيانات',
                      textColor: textColor,
                      subTextColor: subTextColor,
                      borderColor: borderColor,
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'مدار ERP',
                          applicationVersion: '1.0.0',
                          applicationIcon: const Icon(Icons.store, color: Color(0xFFC9A84C), size: 36),
                          children: const [
                            Text('نظام إدارة العمليات ونقاط البيع المتكامل MADAR ERP.'),
                            Text('تم التطوير بواسطة MO2 مع دعم كامل للعمل بلا إنترنت والتشفير التام.'),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const Gap(30),

              Center(
                child: Column(
                  children: [
                    Text(
                      'مدار ERP — الإصدار 1.0.0',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor),
                    ),
                    const Gap(3),
                    Text(
                      'Developed by MO2',
                      style: TextStyle(fontSize: 10, letterSpacing: 0.8, color: subTextColor.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              const Gap(16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required Color cardBg,
    required Color borderColor,
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const Gap(10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const Gap(14),
          Divider(color: borderColor, height: 1),
          const Gap(14),
          child,
        ],
      ),
    );
  }

  Widget _buildCalendarThemeOption({
    required String label,
    required CalendarThemeMode mode,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required Color innerBg,
    required Color goldColor,
  }) {
    final isSelected = (_calendarTheme == mode);
    return Expanded(
      child: InkWell(
        onTap: () {
          SettingsService.setCalendarTheme(mode);
          setState(() => _calendarTheme = mode);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? goldColor.withValues(alpha: 0.12) : innerBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? goldColor : borderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: isSelected ? goldColor : subTextColor,
              ),
              const Gap(6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? textColor : subTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color textColor,
    required Color subTextColor,
    required Color innerBg,
    required Color borderColor,
    required Color focusColor,
    String? hint,
    TextDirection? textDirection,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: textColor, fontSize: 13),
      textDirection: textDirection,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: subTextColor.withValues(alpha: 0.5), fontSize: 12),
        labelStyle: TextStyle(color: subTextColor, fontSize: 12),
        border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: focusColor)),
        prefixIcon: Icon(icon, color: focusColor, size: 18),
        filled: true,
        fillColor: innerBg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
                  const Gap(2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: subTextColor)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: subTextColor),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLocationId() async {
    await SettingsService.setDeviceLocationId(_locationIdController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ معرّف الجهاز بنجاح'), backgroundColor: Color(0xFF2EA043)),
    );
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final summary = await ref.read(syncServiceProvider).syncNow();
      final pullSummary = await ref.read(syncServiceProvider).pullNow();
      final lastSynced = await SettingsService.getLastSyncedAt();
      final pending = await ref.read(syncServiceProvider).pendingCount();
      if (!mounted) return;
      setState(() {
        _lastSyncedText = lastSynced != null
            ? 'آخر مزامنة: ${lastSynced.toLocal()}'
            : 'لم تتم المزامنة بعد';
        _pendingCount = pending;
      });
      final message = summary.skippedOffline
          ? 'لا يوجد اتصال بالإنترنت — لم تتم المزامنة'
          : 'تم الرفع: ${summary.synced} | تم التحميل: ${pullSummary.pulled} | فشل: ${summary.failed + pullSummary.failed}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: (summary.failed + pullSummary.failed) > 0
              ? Colors.orange
              : const Color(0xFF2EA043),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في المزامنة: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      await SettingsService.setBusinessLogoPath(path);
      setState(() => _logoPath = path);
    }
  }

  Future<void> _saveBusinessInfo() async {
    try {
      await SettingsService.setBusinessName(_nameController.text);
      await SettingsService.setBusinessPhone(_phoneController.text);
      await SettingsService.setBusinessAddress(_addressController.text);
      await SettingsService.setTaxNumber(_taxController.text);
      await SettingsService.setReceiptFooter(_footerController.text);
      await SettingsService.setBusinessPageUrl(_pageUrlController.text);
      if (_pageUrlController.text.trim().isNotEmpty) {
        await SettingsService.setLabelShowQr(true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ معلومات النشاط التجاري بنجاح'),
            backgroundColor: Color(0xFF2EA043),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحفظ: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}
