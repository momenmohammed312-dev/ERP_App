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
      });
    });

    SettingsService.getBusinessLogoPath().then((path) {
      setState(() => _logoPath = path);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _taxController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);
    final borderColor = isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('الإعدادات'),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('التفضيلات', goldColor),
          const Gap(10),

          SwitchListTile(
            title: Text(context.l10n.dark_mode, style: TextStyle(color: textColor)),
            value: _darkModeEnabled,
            activeColor: goldColor,
            onChanged: (value) {
              setState(() {
                _darkModeEnabled = value;
              });
            },
            secondary: Icon(Icons.dark_mode, color: goldColor),
          ),

          const SizedBox(height: 12),
          Text(
            'Calendar Theme',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () {
                  SettingsService.setCalendarTheme(CalendarThemeMode.light);
                  setState(() => _calendarTheme = CalendarThemeMode.light);
                },
                child: Row(
                  children: [
                    Radio<CalendarThemeMode>(
                      value: CalendarThemeMode.light,
                      groupValue: _calendarTheme,
                      activeColor: goldColor,
                      onChanged: (CalendarThemeMode? v) {
                        if (v == null) return;
                        SettingsService.setCalendarTheme(v);
                        setState(() => _calendarTheme = v);
                      },
                    ),
                    Text('Light', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  SettingsService.setCalendarTheme(CalendarThemeMode.gray);
                  setState(() => _calendarTheme = CalendarThemeMode.gray);
                },
                child: Row(
                  children: [
                    Radio<CalendarThemeMode>(
                      value: CalendarThemeMode.gray,
                      groupValue: _calendarTheme,
                      activeColor: goldColor,
                      onChanged: (CalendarThemeMode? v) {
                        if (v == null) return;
                        SettingsService.setCalendarTheme(v);
                        setState(() => _calendarTheme = v);
                      },
                    ),
                    Text('Gray', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  SettingsService.setCalendarTheme(CalendarThemeMode.dark);
                  setState(() => _calendarTheme = CalendarThemeMode.dark);
                },
                child: Row(
                  children: [
                    Radio<CalendarThemeMode>(
                      value: CalendarThemeMode.dark,
                      groupValue: _calendarTheme,
                      activeColor: goldColor,
                      onChanged: (CalendarThemeMode? v) {
                        if (v == null) return;
                        SettingsService.setCalendarTheme(v);
                        setState(() => _calendarTheme = v);
                      },
                    ),
                    Text('Dark', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
            ],
          ),
          Divider(color: borderColor, height: 32),
          _buildSectionTitle('إعدادات الطابعة', goldColor),
          const Gap(10),
          if (_printers.isEmpty) ...[
            Text('لا توجد طابعات متاحة', style: TextStyle(color: subTextColor)),
            const Gap(8),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedThermalPrinter,
              style: TextStyle(color: textColor),
              dropdownColor: cardBg,
              decoration: InputDecoration(
                labelText: 'Default Thermal Printer',
                labelStyle: TextStyle(color: subTextColor),
                border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
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
            const Gap(8),
            DropdownButtonFormField<String>(
              initialValue: _selectedA4Printer,
              style: TextStyle(color: textColor),
              dropdownColor: cardBg,
              decoration: InputDecoration(
                labelText: 'Default A4 Printer',
                labelStyle: TextStyle(color: subTextColor),
                border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
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
            const Gap(12),
            ElevatedButton(
              onPressed: () async {
                final list = await PrinterService.getAvailablePrinters();
                setState(() => _printers = list);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: goldColor,
                foregroundColor: const Color(0xFF0D1117),
              ),
              child: const Text('Refresh Printers'),
            ),
          ],

          Divider(color: borderColor, height: 32),
          _buildSectionTitle('معلومات النشاط التجاري (للتحكم في شكل الفاتورة)', goldColor),
        const Gap(15),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.image),
                label: Text(
                  _logoPath != null ? 'تغيير الشعار' : 'إضافة شعار',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  backgroundColor: goldColor,
                  foregroundColor: const Color(0xFF0D1117),
                ),
              ),
            ),
            if (_logoPath != null) ...[
              const Gap(12),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_logoPath!),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 48),
                    ),
                  ),
                  Positioned(
                    top: -4,
                    right: -4,
                    child: InkWell(
                      onTap: () async {
                        await SettingsService.setBusinessLogoPath(null);
                        setState(() => _logoPath = null);
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const Gap(15),
          _buildBusinessInfoSection(textColor, subTextColor, goldColor, cardBg, borderColor, isDark),
          Divider(color: borderColor, height: 32),

          _buildSectionTitle('إدارة المستخدمين', goldColor),
          const Gap(10),

          ListTile(
            leading: Icon(Icons.people_outline, color: goldColor),
            title: Text('المستخدمون والصلاحيات', style: TextStyle(color: textColor)),
            subtitle: Text('إضافة وتعديل صلاحيات المستخدمين', style: TextStyle(color: subTextColor, fontSize: 13)),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: subTextColor),
            onTap: () {
              final db = ref.read(appDatabaseProvider);
              final authService = ref.read(authServiceProvider);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UserManagementPage(database: db, authService: authService)),
              );
            },
          ),
          Divider(color: borderColor, height: 32),

          _buildSectionTitle(context.l10n.other_settings, goldColor),
          const Gap(10),

          ListTile(
            leading: Icon(Icons.info_outline, color: goldColor),
            title: Text(context.l10n.about, style: TextStyle(color: textColor)),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'POS System',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.store, color: Color(0xFFC9A84C)),
                children: [
                  const Text('This is a simple POS system built with Flutter.'),
                ],
              );
            },
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: subTextColor),
          ),
          Divider(color: borderColor, height: 32),
          Center(
            child: Text(
              "${context.l10n.version} 1.0.0",
              style: TextStyle(fontSize: 14, color: subTextColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color goldColor) {
    return Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: goldColor),
    );
  }

  Widget _buildBusinessInfoSection(Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: 'اسم النشاط التجاري',
            labelStyle: TextStyle(color: subTextColor),
            border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            prefixIcon: Icon(Icons.store, color: goldColor),
            filled: true,
            fillColor: cardBg,
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _phoneController,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: 'رقم الهاتف',
            labelStyle: TextStyle(color: subTextColor),
            border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            prefixIcon: Icon(Icons.phone, color: goldColor),
            filled: true,
            fillColor: cardBg,
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _addressController,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: 'العنوان',
            labelStyle: TextStyle(color: subTextColor),
            border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            prefixIcon: Icon(Icons.location_on, color: goldColor),
            filled: true,
            fillColor: cardBg,
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _taxController,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: 'الرقم الضريبي (اختياري)',
            labelStyle: TextStyle(color: subTextColor),
            border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            prefixIcon: Icon(Icons.receipt, color: goldColor),
            filled: true,
            fillColor: cardBg,
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _footerController,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: 'رسالة أسفل الفاتورة',
            labelStyle: TextStyle(color: subTextColor),
            border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            prefixIcon: Icon(Icons.message, color: goldColor),
            filled: true,
            fillColor: cardBg,
          ),
        ),
        const Gap(15),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saveBusinessInfo,
            icon: const Icon(Icons.save),
            label: const Text('حفظ معلومات النشاط'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              backgroundColor: goldColor,
              foregroundColor: const Color(0xFF0D1117),
            ),
          ),
        ),
      ],
    );
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ البيانات بنجاح'),
            backgroundColor: Colors.green,
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
