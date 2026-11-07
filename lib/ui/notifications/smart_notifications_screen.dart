import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../core/provider/smart_advisor_provider.dart';
import '../../core/services/smart_analytics/smart_advisor_service.dart';
import '../../core/theme/madar_colors.dart';

/// Dedicated screen for displaying and managing smart business notifications.
/// Fully responsive across mobile, tablet, and desktop with official Madar Light & Dark mode tokens.
/// Designed with a clean, minimalist typography layout without cluttering item icons.
class SmartNotificationsScreen extends ConsumerStatefulWidget {
  const SmartNotificationsScreen({super.key});

  @override
  ConsumerState<SmartNotificationsScreen> createState() =>
      _SmartNotificationsScreenState();
}

class _SmartNotificationsScreenState
    extends ConsumerState<SmartNotificationsScreen> {
  String _selectedCategory = 'all'; // 'all' | 'unread' | 'stock' | 'finance' | 'customer'

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartAdvisorProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final isDark = context.isDarkMode;

    final filteredAlerts = state.alerts.where((alert) {
      if (_selectedCategory == 'unread') return !alert.isRead;
      if (_selectedCategory == 'stock') return alert.category == 'stock';
      if (_selectedCategory == 'finance') return alert.category == 'finance';
      if (_selectedCategory == 'customer') return alert.category == 'customer';
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: context.bgCanvas,
      appBar: AppBar(
        backgroundColor: context.bgCard,
        elevation: 0,
        title: Text(
          'مركز الإشعارات الذكية',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: context.textPrimary,
          ),
        ),
        centerTitle: false,
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () =>
                  ref.read(smartAdvisorProvider.notifier).markAllAsRead(),
              child: Text(
                'تحديد الكل كمقروء',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? MadarColors.gold : MadarColors.lightPrimary,
                ),
              ),
            ),
          IconButton(
            tooltip: 'تحديث الفحص الآن',
            onPressed: () => ref
                .read(smartAdvisorProvider.notifier)
                .refresh(runAnalysis: true),
            icon: Icon(Icons.refresh, size: 20, color: context.textPrimary),
          ),
          const Gap(8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Filter Chips Strip
              _buildFilterChips(state),
              Divider(height: 1, color: context.borderColor),

              // List of Notifications
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredAlerts.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.separated(
                            padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 24 : 14,
                              vertical: 14,
                            ),
                            itemCount: filteredAlerts.length,
                            separatorBuilder: (_, _) => const Gap(10),
                            itemBuilder: (context, index) {
                              final alert = filteredAlerts[index];
                              return _buildNotificationCard(alert, context);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(SmartAdvisorState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _buildFilterChip('الكل (${state.alerts.length})', 'all'),
          const Gap(8),
          _buildFilterChip('غير مقروء (${state.unreadCount})', 'unread'),
          const Gap(8),
          _buildFilterChip('المخزون', 'stock'),
          const Gap(8),
          _buildFilterChip('الأمان المالي', 'finance'),
          const Gap(8),
          _buildFilterChip('العملاء', 'customer'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String key) {
    final isSelected = _selectedCategory == key;
    final isDark = context.isDarkMode;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (isDark ? MadarColors.textSecondary : MadarColors.lightTextSecondary),
        ),
      ),
      selected: isSelected,
      selectedColor: isDark ? MadarColors.gold : MadarColors.lightPrimary,
      backgroundColor: isDark ? MadarColors.bgCard : MadarColors.lightBgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : (isDark ? MadarColors.border : MadarColors.lightBorder),
        ),
      ),
      onSelected: (_) => setState(() => _selectedCategory = key),
    );
  }

  Widget _buildNotificationCard(SmartAlert alert, BuildContext context) {
    final isDark = context.isDarkMode;

    // Determine status tag style based on urgency
    Color tagColor;
    String tagLabel;
    switch (alert.urgency) {
      case 'critical':
        tagColor = isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F);
        tagLabel = 'عاجل وحرج';
        break;
      case 'warning':
        tagColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
        tagLabel = 'تنبيه';
        break;
      case 'info':
      default:
        tagColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0288D1);
        tagLabel = 'ملاحظة';
        break;
    }

    String categoryLabel;
    switch (alert.category) {
      case 'stock':
        categoryLabel = 'مخزون';
        break;
      case 'finance':
        categoryLabel = 'أمان مالي';
        break;
      case 'customer':
        categoryLabel = 'عملاء';
        break;
      default:
        categoryLabel = 'عام';
        break;
    }

    final cardBg = isDark
        ? (alert.isRead ? MadarColors.bgCard : const Color(0xFF21262D))
        : (alert.isRead ? MadarColors.lightBgCard : MadarColors.lightBgSurface);

    final timeStr = _formatRelativeTime(alert.createdAt);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: alert.isRead
              ? context.borderColor
              : tagColor.withValues(alpha: 0.5),
          width: alert.isRead ? 1 : 1.5,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top metadata row: tags + time (Strictly NO icons)
          Row(
            children: [
              // Urgency Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  tagLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: tagColor,
                  ),
                ),
              ),
              const Gap(6),
              // Category Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF333A48) : const Color(0xFFE2EFF9),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  categoryLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? MadarColors.textSecondary : MadarColors.lightTextSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
          const Gap(10),

          // Title
          Text(
            alert.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: alert.isRead ? FontWeight.w600 : FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const Gap(6),

          // Body Text
          Text(
            alert.body,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: context.textSecondary,
            ),
          ),
          const Gap(12),

          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!alert.isRead)
                TextButton(
                  onPressed: () => ref
                      .read(smartAdvisorProvider.notifier)
                      .markAsRead(alert.id),
                  child: Text(
                    'تمييز كمقروء',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? MadarColors.gold : MadarColors.lightPrimary,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => ref
                    .read(smartAdvisorProvider.notifier)
                    .deleteAlert(alert.id),
                child: Text(
                  'حذف',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'لا توجد تنبيهات جديدة حالياً',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const Gap(6),
          Text(
            'مؤشرات المخزون والورديات والعملاء في حالة منتظمة ومستقرة.',
            style: TextStyle(
              fontSize: 13,
              color: context.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else {
      return 'منذ ${diff.inDays} يوم';
    }
  }
}
