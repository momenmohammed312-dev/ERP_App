import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_offline_desktop/widgets/brand/madar_logo.dart';

const String kMadarSupportPhone = '01025545211';
const String kMadarSupportEmail = 'momenmohammed253@gmail.com';
const String kMadarDeveloperName = 'MO2';
const String kMadarAppTitleAr = 'مِدار — MADAR ERP';
const String kMadarAppVersion = 'الإصدار 1.0.0';

Future<void> _copyAndNotify(
  BuildContext context,
  String value,
  String label,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'تم نسخ $label: $value',
        style: const TextStyle(fontFamily: 'NotoSansArabic'),
      ),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Inline support contact card used inside dialogs (e.g. pre-auth admin gate).
Widget buildMadarContactInlineBox(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark
      ? MadarColors.lightPrimary.withValues(alpha: 0.14)
      : MadarColors.lightBabyBlueContainer.withValues(alpha: 0.7);
  final borderColor = isDark
      ? MadarColors.gold.withValues(alpha: 0.35)
      : MadarColors.lightPrimary.withValues(alpha: 0.35);
  final textColor = isDark ? Colors.white : MadarColors.lightTextPrimary;
  final mutedColor = isDark ? Colors.white70 : MadarColors.lightTextSecondary;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: borderColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.support_agent,
              size: 16,
              color: isDark ? MadarColors.gold : MadarColors.lightPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              'الدعم الفني وطرق التواصل ($kMadarDeveloperName)',
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _copyAndNotify(context, kMadarSupportPhone, 'رقم الهاتف'),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.phone_outlined, size: 15, color: mutedColor),
                const SizedBox(width: 6),
                const Text(
                  kMadarSupportPhone,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.copy_rounded, size: 14, color: mutedColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () =>
              _copyAndNotify(context, kMadarSupportEmail, 'البريد الإلكتروني'),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.email_outlined, size: 15, color: mutedColor),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    kMadarSupportEmail,
                    textDirection: TextDirection.ltr,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.copy_rounded, size: 14, color: mutedColor),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shows the MADAR support contact dialog (and optional About header).
Future<void> showMadarContactDialog(
  BuildContext context, {
  bool showAboutHeader = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;
      final accent = isDark ? MadarColors.gold : MadarColors.lightPrimary;
      final muted = isDark ? Colors.white70 : MadarColors.lightTextSecondary;

      return Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              if (showAboutHeader) ...[
                const MadarOrbitLogo(size: 40),
                const SizedBox(width: 12),
              ] else ...[
                Icon(Icons.support_agent, color: accent),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      showAboutHeader ? kMadarAppTitleAr : 'طرق التواصل والدعم الفني',
                      style: const TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      showAboutHeader
                          ? '$kMadarAppVersion • تطوير $kMadarDeveloperName'
                          : 'للمساعدة أو استعادة الحساب تواصل مع $kMadarDeveloperName',
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 12,
                        color: muted,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAboutHeader) ...[
                  Text(
                    'نظام نقاط البيع والمحاسبة وإدارة المخزون المتكامل — يعمل محلياً بكفاءة وسرعة عالية.',
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 13,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _ContactTile(
                  icon: Icons.phone_in_talk_rounded,
                  title: 'رقم الهاتف / واتساب',
                  value: kMadarSupportPhone,
                  accent: accent,
                  onCopy: () => _copyAndNotify(ctx, kMadarSupportPhone, 'رقم الهاتف'),
                ),
                const SizedBox(height: 10),
                _ContactTile(
                  icon: Icons.email_rounded,
                  title: 'البريد الإلكتروني',
                  value: kMadarSupportEmail,
                  accent: accent,
                  onCopy: () =>
                      _copyAndNotify(ctx, kMadarSupportEmail, 'البريد الإلكتروني'),
                ),
                const SizedBox(height: 12),
                Text(
                  'اضغط على أي وسيلة تواصل لنسخها مباشرة.',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 11.5,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'إغلاق',
                style: TextStyle(fontFamily: 'NotoSansArabic'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color accent;
  final VoidCallback onCopy;

  const _ContactTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.accent,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : MadarColors.lightBabyBlueContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : MadarColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      value,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCopy,
                tooltip: 'نسخ',
                icon: Icon(Icons.copy_rounded, size: 18, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
