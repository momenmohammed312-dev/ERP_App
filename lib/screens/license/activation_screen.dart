import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/license_manager.dart';
import '../../services/activation_service.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _licenseKeyController = TextEditingController();
  final _licenseManager = LicenseManager();
  final _activationService = ActivationService();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  String _deviceFingerprint = '';

  @override
  void initState() {
    super.initState();
    _getDeviceFingerprint();
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final result = await _activationService.activate(key);

      if (result.isSuccess) {
        setState(() {
          _successMessage = result.message;
          _isLoading = false;
        });

        // Wait a bit to show success message then navigate
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          // Force app restart or navigate to home
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade900,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.all(20),
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
              Icon(Icons.lock_open, size: 64, color: Colors.blue.shade900),
              const SizedBox(height: 24),
              const Text(
                'تفعيل الرخصة',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'أدخل مفتاح الترخيص لتفعيل نظام نقاط البيع',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
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
                    Text(
                      'معرف الجهاز:',
                      style: TextStyle(
                        fontSize: 14,
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
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _licenseKeyController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'مفتاح الترخيص',
                  hintText: 'الصق مفتاح الترخيص هنا...',
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage,
                ),
              ),
              const SizedBox(height: 24),
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
                height: 50,
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
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _licenseKeyController.dispose();
    super.dispose();
  }
}
