import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // استخدام Firebase Authentication
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _usernameController.text.trim(),
            password: _passwordController.text,
          );

      if (userCredential.user != null && mounted) {
        context.go('/'); // الصفحة الرئيسية
      }
    } on FirebaseAuthException catch (e) {
      String errorMsg;
      switch (e.code) {
        case 'user-not-found':
          errorMsg = 'المستخدم غير موجود';
          break;
        case 'wrong-password':
          errorMsg = 'كلمة المرور خاطئة';
          break;
        case 'invalid-email':
          errorMsg = 'البريد الإلكتروني غير صالح';
          break;
        case 'user-disabled':
          errorMsg = 'الحساب معطل';
          break;
        default:
          errorMsg = 'خطأ في تسجيل الدخول: ${e.message}';
      }
      setState(() {
        _errorMessage = errorMsg;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ غير متوقع: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(
                    Icons.point_of_sale,
                    size: 64,
                    color: Color(0xFF4ECDC4),
                  ),
                  const Gap(16),
                  const Text(
                    'نظام نقاط البيع',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    'قم بتسجيل الدخول للمتابعة',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const Gap(32),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (_errorMessage != null) const Gap(16),
                  // Username Field
                  TextFormField(
                    controller: _usernameController,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'اسم المستخدم',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(
                        Icons.person,
                        color: Color(0xFF4ECDC4),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF4ECDC4),
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        v?.isEmpty == true ? 'أدخل اسم المستخدم' : null,
                  ),
                  const Gap(16),
                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(
                        Icons.lock,
                        color: Color(0xFF4ECDC4),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white54,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF4ECDC4),
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v?.length ?? 0) < 4 ? 'كلمة المرور قصيرة جداً' : null,
                  ),
                  const Gap(24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ECDC4),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'تسجيل الدخول',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const Gap(16),
                  Text(
                    'المستخدم الافتراضي: admin / admin123',
                    style: TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
