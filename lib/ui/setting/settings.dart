import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';

// ignore_for_file: deprecated_member_use

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkModeEnabled = false;
  CalendarThemeMode _calendarTheme = CalendarThemeMode.light;
  List<Map<String, dynamic>> _printers = [];
  String? _selectedThermalPrinter;
  String? _selectedA4Printer;

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
    // load printers and saved choices
    PrinterService.getAvailablePrinters().then((list) async {
      final thermal = await SettingsService.getThermalPrinter();
      final a4 = await SettingsService.getA4Printer();
      setState(() {
        _printers = list;
        _selectedThermalPrinter = thermal;
        _selectedA4Printer = a4;
      });
    });

    // load business info
    SettingsService.getBusinessInfo().then((info) {
      setState(() {
        _nameController.text = info['name'] ?? '';
        _phoneController.text = info['phone'] ?? '';
        _addressController.text = info['address'] ?? '';
        _taxController.text = info['taxNumber'] ?? '';
        _footerController.text = info['footer'] ?? '';
      });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Preferences',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Gap(10),

          // Dark Mode Toggle
          SwitchListTile(
            title: Text(context.l10n.dark_mode),
            value: _darkModeEnabled,
            onChanged: (value) {
              setState(() {
                _darkModeEnabled = value;
              });
            },
            secondary: const Icon(Icons.dark_mode),
          ),

          const SizedBox(height: 12),
          Text(
            'Calendar Theme',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                      onChanged: (CalendarThemeMode? v) {
                        if (v == null) return;
                        SettingsService.setCalendarTheme(v);
                        setState(() => _calendarTheme = v);
                      },
                    ),
                    const Text('Light'),
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
                      onChanged: (CalendarThemeMode? v) {
                        if (v == null) return;
                        SettingsService.setCalendarTheme(v);
                        setState(() => _calendarTheme = v);
                      },
                    ),
                    const Text('Gray'),
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
                      onChanged: (CalendarThemeMode? v) {
                        if (v == null) return;
                        SettingsService.setCalendarTheme(v);
                        setState(() => _calendarTheme = v);
                      },
                    ),
                    const Text('Dark'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Default Invoice Type',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          FutureBuilder<String>(
            future: SettingsService.getDefaultInvoiceType(),
            builder: (context, snapshot) {
              final current = snapshot.data ?? 'cash';
              return Column(
                children: [
                  InkWell(
                    onTap: () async {
                      await SettingsService.setDefaultInvoiceType('cash');
                      setState(() {});
                    },
                    child: Row(
                      children: [
                        Radio<String>(
                          value: 'cash',
                          groupValue: current,
                          onChanged: (String? v) async {
                            if (v == null) return;
                            await SettingsService.setDefaultInvoiceType(v);
                            setState(() {});
                          },
                        ),
                        const Text('Cash (نقدي)'),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      await SettingsService.setDefaultInvoiceType('credit');
                      setState(() {});
                    },
                    child: Row(
                      children: [
                        Radio<String>(
                          value: 'credit',
                          groupValue: current,
                          onChanged: (String? v) async {
                            if (v == null) return;
                            await SettingsService.setDefaultInvoiceType(v);
                            setState(() {});
                          },
                        ),
                        const Text('Credit (آجل)'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const Divider(height: 32),
          Text(
            'Printer Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Gap(10),
          if (_printers.isEmpty) ...[
            const Text('No printers detected yet.'),
            const Gap(8),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedThermalPrinter,
              decoration: const InputDecoration(
                labelText: 'Default Thermal Printer',
                border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'Default A4 Printer',
                border: OutlineInputBorder(),
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
                // Refresh printer list
                final list = await PrinterService.getAvailablePrinters();
                setState(() => _printers = list);
              },
              child: const Text('Refresh Printers'),
            ),
            const Divider(height: 32),
          ],

          const Divider(height: 32),
          Text(
            'معلومات النشاط التجاري (للتحكم في شكل الفاتورة)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Gap(15),
          _buildBusinessInfoSection(),
          const Divider(height: 32),

          Text(
            context.l10n.other_settings,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Gap(10),

          // About
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.l10n.about),
            onTap: () {
              // Show about app info
              showAboutDialog(
                context: context,
                applicationName: 'POS System',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.store),
                children: [
                  const Text('This is a simple POS system built with Flutter.'),
                ],
              );
            },
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          ),
          const Divider(height: 32),
          Center(
            child: Text(
              "${context.l10n.version} 1.0.0",
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildBusinessInfoSection() {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'اسم النشاط التجاري',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.store),
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _addressController,
          decoration: const InputDecoration(
            labelText: 'العنوان',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on),
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _taxController,
          decoration: const InputDecoration(
            labelText: 'الرقم الضريبي (اختياري)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.receipt),
          ),
        ),
        const Gap(10),
        TextFormField(
          controller: _footerController,
          decoration: const InputDecoration(
            labelText: 'رسالة أسفل الفاتورة',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.message),
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
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
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
          SnackBar(content: Text('خطأ في الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
