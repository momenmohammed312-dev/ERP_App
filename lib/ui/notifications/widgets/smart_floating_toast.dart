import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../../../core/services/smart_analytics/smart_advisor_service.dart';
import '../../../core/theme/madar_colors.dart';

/// A sleek, non-intrusive floating toast banner for displaying smart alerts.
/// Minimalist typography-focused design without cluttering icons.
/// Auto-dismisses after [duration] and does not block background interaction.
class SmartFloatingToast extends StatefulWidget {
  final SmartAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onView;
  final Duration duration;

  const SmartFloatingToast({
    super.key,
    required this.alert,
    required this.onDismiss,
    required this.onView,
    this.duration = const Duration(seconds: 6),
  });

  @override
  State<SmartFloatingToast> createState() => _SmartFloatingToastState();
}

class _SmartFloatingToastState extends State<SmartFloatingToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();

    _dismissTimer = Timer(widget.duration, () {
      if (mounted) {
        _animController.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _manualDismiss() {
    _dismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    Color accentColor;
    String badgeText;
    switch (widget.alert.urgency) {
      case 'critical':
        accentColor = isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F);
        badgeText = 'تنبيه عاجل';
        break;
      case 'warning':
        accentColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
        badgeText = 'تنبيه مهم';
        break;
      case 'info':
      default:
        accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0288D1);
        badgeText = 'ملاحظة ذكية';
        break;
    }

    final bgColor = isDark ? const Color(0xFF1E2228) : Colors.white;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.12);

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Accent colored strip on the right (RTL start)
                    Container(
                      width: 4.5,
                      color: accentColor,
                    ),
                    const Gap(12),

                    // Content Area
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                                const Gap(8),
                                Expanded(
                                  child: Text(
                                    widget.alert.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Gap(4),
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                widget.alert.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.4,
                                  color: context.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Action buttons (عرض / إغلاق)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              _manualDismiss();
                              widget.onView();
                            },
                            child: Text(
                              'عرض',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? MadarColors.gold
                                    : MadarColors.lightPrimary,
                              ),
                            ),
                          ),
                          const Gap(4),
                          IconButton(
                            iconSize: 16,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'إغلاق',
                            onPressed: _manualDismiss,
                            icon: Icon(
                              Icons.close,
                              color: context.textSecondary.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
