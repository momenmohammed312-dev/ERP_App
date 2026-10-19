import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/provider/license_provider.dart';
import '../../services/license_manager.dart';
import '../../services/online_license_service.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _licenseKeyController = TextEditingController();
  final _serverUrlController = TextEditingController();
  final _licenseManager = LicenseManager();
  bool _isLoading = false;
  bool _showServerSettings = false;
  String? _errorMessage;
  String? _successMessage;
  String _deviceFingerprint = '';

  @override
  void initState() {
    super.initState();
    _getDeviceFingerprint();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('custom_license_api_url');
    if (saved != null && saved.isNotEmpty) {
      _serverUrlController.text = saved;
      OnlineLicenseService.apiUrlOverride = saved;
    } else {
      _serverUrlController.text = 'http://192.168.0.16:8000/license_api';
      OnlineLicenseService.apiUrlOverride ??=
          'http://192.168.0.16:8000/license_api';
    }
  }

  Future<void> _saveServerUrl() async {
    final url = _serverUrlController.text.trim();
    if (url.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_license_api_url', url);
      OnlineLicenseService.apiUrlOverride = url;
    }
  }

  Future<void> _getDeviceFingerprint() async {
    try {
      final fingerprint = await _licenseManager.generateDeviceFingerprint();
      setState(() {
        _deviceFingerprint = fingerprint;
      });
    } catch (e) {
      setState(() {
        _deviceFingerprint = 'Error generating fingerprint';
      });
    }
  }

  Future<void> _activateLicense() async {
    final key = _licenseKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال مفتاح الترخيص';
      });
      return;
    }

    await _saveServerUrl();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final fbService = OnlineLicenseService();
      final result = await fbService.activateLicense(key);

      if (result.isAllowed) {
        ref.read(licenseRefreshProvider.notifier).state++;
        ref.invalidate(currentLicenseProvider);
        ref.invalidate(licenseStateProvider);

        setState(() {
          _successMessage = result.message;
          _isLoading = false;
        });

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          context.go('/activation-success');
        }
      } else {
        setState(() {
          _errorMessage = result.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ غير متوقع: $e';
        _isLoading = false;
      });
    }
  }

  /// FEAT-012 — offline activation: import a signed `.madarlicense` document.
  ///
  /// This is the path for a customer who has no server and no internet. The
  /// document is verified locally against the public key baked into the build,
  /// so the button works with the network cable unplugged.
  Future<void> _importLicenseFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.any,
        dialogTitle: 'اختر ملف الترخيص ‎(.madarlicense)‎',
      );
      if (picked == null || picked.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final bytes = picked.files.first.bytes;
      if (bytes == null) {
        setState(() {
          _errorMessage = 'تعذّر قراءة الملف. تأكد أنه غير تالف.';
          _isLoading = false;
        });
        return;
      }

      final document = utf8.decode(bytes, allowMalformed: true);
      final result = await LicenseManager().importLicenseDocument(document);

      if (result.isValid) {
        ref.read(licenseRefreshProvider.notifier).state++;
        ref.invalidate(currentLicenseProvider);
        ref.invalidate(licenseStateProvider);

        setState(() {
          _successMessage =
              'تم تفعيل الترخيص بنجاح: ${result.license?.type.name ?? ''}';
          _isLoading = false;
        });

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/activation-success');
      } else {
        setState(() {
          _errorMessage =
              result.errorMessage ?? 'تعذّر تفعيل الترخيص من الملف.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'تعذّر قراءة ملف الترخيص: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade900,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(28),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_open, size: 56, color: Colors.blue.shade900),
                  const SizedBox(height: 18),
                  const Text(
                    'تفعيل الرخصة',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أدخل مفتاح الترخيص لتفعيل نظام نقاط البيع',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'معرف الجهاز:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _deviceFingerprint.isEmpty
                              ? 'جاري التحميل...'
                              : _deviceFingerprint,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _licenseKeyController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'مفتاح الترخيص',
                      hintText: 'الصق مفتاح الترخيص هنا...',
                      border: const OutlineInputBorder(),
                      errorText: _errorMessage,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Expandable server configuration for mobile testing
                  InkWell(
                    onTap: () => setState(
                      () => _showServerSettings = !_showServerSettings,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tune,
                            size: 16,
                            color: Colors.blue.shade900,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showServerSettings
                                ? 'إخفاء إعدادات السيرفر'
                                : 'إعدادات عنوان السيرفر (IP / URL)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          Icon(
                            _showServerSettings
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 18,
                            color: Colors.blue.shade900,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showServerSettings) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _serverUrlController,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        labelText: 'عنوان سيرفر الترخيص السحابي',
                        hintText: 'http://192.168.0.16:8000/license_api',
                        prefixIcon: const Icon(Icons.dns, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (val) {
                        if (val.trim().isNotEmpty) {
                          OnlineLicenseService.apiUrlOverride = val.trim();
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_successMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(color: Colors.green),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_successMessage != null) const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _activateLicense,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('جاري التفعيل...'),
                              ],
                            )
                          : const Text(
                              'تفعيل الرخصة',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _importLicenseFile,
                      icon: const Icon(Icons.upload_file, size: 20),
                      label: const Text(
                        'استيراد رخصة من ملف (بدون إنترنت)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _licenseKeyController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }
}
