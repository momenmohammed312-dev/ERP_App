// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/widgets/brand/madar_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/license_config.dart';
import '../../core/provider/license_provider.dart';
import '../../services/license_manager.dart';
import '../../services/online_license_service.dart';
import '../../widgets/brand/madar_contact_dialog.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  final bool allowBack;

  const ActivationScreen({super.key, this.allowBack = false});

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
      if (!mounted) return;
      setState(() {
        _deviceFingerprint = fingerprint;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deviceFingerprint = 'Error generating fingerprint';
      });
    }
  }

  Future<void> _copyDeviceFingerprint() async {
    if (_deviceFingerprint.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _deviceFingerprint));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم نسخ معرف الجهاز',
          style: TextStyle(fontFamily: 'NotoSansArabic'),
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

        await Future.delayed(Duration(seconds: widget.allowBack ? 1 : 2));

        if (!mounted) return;
        if (widget.allowBack && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
          return;
        }
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.go('/activation-success');
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
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

      final document = LicenseManager.decodeDocumentBytes(bytes);
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

        await Future.delayed(Duration(seconds: widget.allowBack ? 1 : 2));
        if (!mounted) return;
        if (widget.allowBack && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
          return;
        }
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.go('/activation-success');
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final license = ref.watch(currentLicenseProvider).valueOrNull;
    final isExpiredTrial =
        license?.type == LicenseType.trial && license!.isExpired;
    final isExpiredPaid =
        license != null && license.type != LicenseType.trial && license.isExpired;
    final isUpgradeMode =
        widget.allowBack && license != null && !license.isExpired;
    final String trialDaysLabel;
    if (LicenseConfig.freeTrialMinutes > 0) {
      trialDaysLabel = ' (${LicenseConfig.freeTrialMinutes} دقيقة)';
    } else {
      final displayTrialDays = license == null
          ? 0
          : (LicenseConfig.isTimeLimitedTrial
              ? LicenseConfig.freeTrialDays
              : license.expiryDate.difference(license.issueDate).inDays);
      trialDaysLabel =
          (displayTrialDays > 0 &&
              displayTrialDays < LicenseConfig.permanentFreeThresholdDays)
          ? ' ($displayTrialDays أيام)'
          : '';
    }

    final titleText = isUpgradeMode ? 'ترقية وتفعيل الرخصة' : 'تفعيل الرخصة';
    final subtitleText = isUpgradeMode
        ? 'أدخل مفتاح الترخيص أو استورد ملف (.madarlicense) للترقية مع الحفاظ على جميع بياناتك'
        : (isExpiredTrial || isExpiredPaid)
        ? 'اختر طريقة التفعيل لاستئناف العمل على بياناتك المحفوظة'
        : 'أدخل مفتاح الترخيص أو استورد ملف التفعيل للمتابعة';

    final cardBg = isDark ? MadarColors.bgCard : MadarColors.lightBgCard;
    final inputBg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? MadarColors.border : const Color(0xFFCBD5E1);
    final accentColor = isDark ? MadarColors.gold : MadarColors.lightPrimary;
    final primaryBtnFg = isDark ? MadarColors.bgDark : Colors.white;
    final textPrimary =
        isDark ? MadarColors.textLight : MadarColors.lightDeepCobalt;
    final textSecondary =
        isDark ? MadarColors.textSecondary : MadarColors.lightTextSecondary;

    return PopScope(
      canPop: widget.allowBack,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor:
              isDark ? MadarColors.bgDark : const Color(0xFFF1F5F9),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [
                        Color(0xFF0D1117),
                        Color(0xFF161B22),
                        Color(0xFF0D1117),
                      ]
                    : const [
                        Color(0xFFF8FAFC),
                        Color(0xFFEDF2F7),
                        Color(0xFFE2E8F0),
                      ],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 840;
                  final formPane = _buildFormPane(
                    context: context,
                    isDark: isDark,
                    inputBg: inputBg,
                    borderColor: borderColor,
                    accentColor: accentColor,
                    primaryBtnFg: primaryBtnFg,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    license: license,
                    isExpiredTrial: isExpiredTrial,
                    isExpiredPaid: isExpiredPaid,
                    isUpgradeMode: isUpgradeMode,
                    trialDaysLabel: trialDaysLabel,
                    titleText: titleText,
                    subtitleText: subtitleText,
                  );

                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 24 : 16,
                        vertical: 20,
                      ),
                      child: isDesktop
                          ? _buildDesktopSplitCard(
                              context: context,
                              isDark: isDark,
                              cardBg: cardBg,
                              borderColor: borderColor,
                              accentColor: accentColor,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                              formPane: formPane,
                            )
                          : _buildMobileCard(
                              context: context,
                              isDark: isDark,
                              cardBg: cardBg,
                              borderColor: borderColor,
                              accentColor: accentColor,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                              formPane: formPane,
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSplitCard({
    required BuildContext context,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color accentColor,
    required Color textPrimary,
    required Color textSecondary,
    required Widget formPane,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 940),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.06),
                    blurRadius: 10,
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.08),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Right Pane (RTL): Activation & Upgrade Form
              Expanded(
                flex: 12,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: formPane,
                ),
              ),

              // Left Pane (RTL): Brand Identity & Support Contact
              Expanded(
                flex: 9,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: isDark
                        ? const RadialGradient(
                            center: Alignment(0, -0.25),
                            radius: 1.15,
                            colors: [Color(0xFF1E2A3A), Color(0xFF0D1117)],
                          )
                        : const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFE2F0FD), Color(0xFFD3E7FA)],
                          ),
                    border: BorderDirectional(
                      start: BorderSide(
                        color: isDark
                            ? borderColor.withValues(alpha: 0.85)
                            : const Color(0xFFBAE6FD),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const MadarOrbitLogo(size: 72),
                      const SizedBox(height: 14),
                      Text(
                        'مِدار',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : MadarColors.lightDeepCobalt,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'MADAR ERP',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'إدارة. تشغيل. نمو.',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 12.5,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.white.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? borderColor
                                : const Color(0xFFBAE6FD),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 18,
                              color: isDark
                                  ? MadarColors.goldLight
                                  : MadarColors.lightPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'جميع بياناتك وفواتيرك محفوظة بأمان محلياً',
                                style: TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      buildMadarContactInlineBox(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCard({
    required BuildContext context,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color accentColor,
    required Color textPrimary,
    required Color textSecondary,
    required Widget formPane,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const MadarOrbitLogo(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مِدار — MADAR ERP',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'إدارة. تشغيل. نمو.',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 11.5,
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: borderColor, height: 1),
            const SizedBox(height: 16),
            formPane,
            const SizedBox(height: 16),
            buildMadarContactInlineBox(context),
          ],
        ),
      ),
    );
  }

  Widget _buildFormPane({
    required BuildContext context,
    required bool isDark,
    required Color inputBg,
    required Color borderColor,
    required Color accentColor,
    required Color primaryBtnFg,
    required Color textPrimary,
    required Color textSecondary,
    required License? license,
    required bool isExpiredTrial,
    required bool isExpiredPaid,
    required bool isUpgradeMode,
    required String trialDaysLabel,
    required String titleText,
    required String subtitleText,
  }) {
    final isExpired = isExpiredTrial || isExpiredPaid;
    final badgeColor = isExpired ? MadarColors.error : accentColor;
    final badgeLabel = isExpiredTrial
        ? 'انتهت التجربة'
        : isExpiredPaid
        ? 'انتهت الرخصة'
        : isUpgradeMode
        ? 'ترقية الرخصة'
        : 'تفعيل النظام';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.allowBack) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text(
                'رجوع',
                style: TextStyle(fontFamily: 'NotoSansArabic'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                titleText,
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: badgeColor.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpired
                        ? Icons.timer_off_outlined
                        : Icons.workspace_premium_outlined,
                    size: 14,
                    color: badgeColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    badgeLabel,
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitleText,
          style: TextStyle(
            fontFamily: 'NotoSansArabic',
            fontSize: 13,
            color: textSecondary,
            height: 1.4,
          ),
        ),
        if (isExpiredTrial) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'انتهت الفترة التجريبية$trialDaysLabel',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'انتهت صلاحية النسخة التجريبية بتاريخ ${license!.expiryDate.toString().split(' ')[0]}. جميع بياناتك وفواتيرك محفوظة بأمان — قم بتفعيل الرخصة للمتابعة.',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 12,
                    color: isDark ? Colors.red.shade100 : Colors.red.shade900,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ] else if (isExpiredPaid) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'انتهت صلاحية الرخصة',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'انتهت صلاحية الترخيص${license?.expiryDate != null ? ' بتاريخ ${license!.expiryDate.toString().split(' ')[0]}' : ''}. يرجى تجديد الرخصة أو استيراد ملف تفعيل جديد للمتابعة.',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 12,
                    color: isDark ? Colors.red.shade100 : Colors.red.shade900,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Device ID Card with Copy Action
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'معرف الجهاز',
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _deviceFingerprint.isEmpty
                          ? 'جاري التحميل...'
                          : _deviceFingerprint,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed:
                    _deviceFingerprint.isEmpty ? null : _copyDeviceFingerprint,
                tooltip: 'نسخ معرف الجهاز',
                icon: Icon(Icons.copy_rounded, size: 18, color: accentColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // License Key Field
        TextField(
          controller: _licenseKeyController,
          maxLines: 2,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: textPrimary,
            fontSize: 13.5,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            labelText: 'مفتاح الترخيص',
            hintText: 'الصق مفتاح الترخيص هنا...',
            labelStyle: TextStyle(
              fontFamily: 'NotoSansArabic',
              color: textSecondary,
              fontSize: 13,
            ),
            hintStyle: TextStyle(
              fontFamily: 'NotoSansArabic',
              color: textSecondary.withValues(alpha: 0.65),
              fontSize: 12.5,
            ),
            filled: true,
            fillColor: inputBg,
            errorText: _errorMessage,
            prefixIcon: Icon(
              Icons.vpn_key_outlined,
              color: accentColor,
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: accentColor, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Expandable server configuration
        InkWell(
          onTap: () => setState(
            () => _showServerSettings = !_showServerSettings,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  _showServerSettings
                      ? 'إخفاء إعدادات السيرفر'
                      : 'إعدادات عنوان السيرفر (IP / URL)',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                Icon(
                  _showServerSettings
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: accentColor,
                ),
              ],
            ),
          ),
        ),
        if (_showServerSettings) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _serverUrlController,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 12.5,
              fontFamily: 'monospace',
              color: textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'عنوان سيرفر الترخيص السحابي',
              hintText: 'http://192.168.0.16:8000/license_api',
              labelStyle: TextStyle(
                fontFamily: 'NotoSansArabic',
                color: textSecondary,
                fontSize: 12.5,
              ),
              hintStyle: TextStyle(
                color: textSecondary.withValues(alpha: 0.65),
                fontSize: 12,
              ),
              filled: true,
              fillColor: inputBg,
              prefixIcon: Icon(
                Icons.dns_outlined,
                size: 18,
                color: accentColor,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (val) {
              if (val.trim().isNotEmpty) {
                OnlineLicenseService.apiUrlOverride = val.trim();
              }
            },
          ),
        ],
        const SizedBox(height: 14),

        if (_successMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MadarColors.success.withValues(alpha: isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: MadarColors.success.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              _successMessage!,
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
        ],

        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _activateLicense,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: primaryBtnFg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(primaryBtnFg),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'جاري التفعيل...',
                        style: TextStyle(fontFamily: 'NotoSansArabic'),
                      ),
                    ],
                  )
                : const Text(
                    'تفعيل الرخصة',
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _importLicenseFile,
            style: OutlinedButton.styleFrom(
              foregroundColor: accentColor,
              side: BorderSide(color: accentColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.upload_file_rounded, size: 19),
            label: const Text(
              'استيراد رخصة من ملف (بدون إنترنت)',
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _licenseKeyController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }
}
