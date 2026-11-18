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
  String _selectedCategory =
      'all'; // 'all' | 'unread' | 'stock' | 'finance' | 'customer' | 'supplier' | 'staff' | 'operations'

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
      if (_selectedCategory == 'supplier') return alert.category == 'supplier';
      if (_selectedCategory == 'staff') return alert.category == 'staff';
      if (_selectedCategory == 'operations') return alert.category == 'operations';
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
          _buildFilterChip('العملاء والائتمان', 'customer'),
          const Gap(8),
          _buildFilterChip('الموردين', 'supplier'),
          const Gap(8),
          _buildFilterChip('الموظفين', 'staff'),
          const Gap(8),
          _buildFilterChip('العمليات والعهد', 'operations'),
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
        categoryLabel = 'عملاء وائتمان';
        break;
      case 'supplier':
        categoryLabel = 'موردين';
        break;
      case 'staff':
        categoryLabel = 'موظفين';
        break;
      case 'operations':
        categoryLabel = 'عمليات وعهد';
        break;
      default:
        categoryLabel = 'عام';
        break;
    }

    final cardBg = isDark
        ? (alert.isRead ? MadarColors.bgCard : const Color(0xFF21262D))
        : (alert.isRead ? MadarColors.lightBgCard : MadarColors.lightBgSurface);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: alert.isRead
              ? context.borderColor
              : (isDark ? MadarColors.gold.withValues(alpha: 0.4) : MadarColors.lightPrimary.withValues(alpha: 0.4)),
          width: alert.isRead ? 1 : 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (!alert.isRead) {
              ref.read(smartAdvisorProvider.notifier).markAsRead(alert.id);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Badges + Timestamp + Delete button
                Row(
                  children: [
                    // Urgency Tag (Textual Badge, No Icon)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: tagColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: tagColor.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
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
                    const Gap(8),

                    // Category Tag
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        categoryLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ),

                    if (!alert.isRead) ...[
                      const Gap(8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark ? MadarColors.gold : MadarColors.lightPrimary)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'جديد',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? MadarColors.gold : MadarColors.lightPrimary,
                          ),
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Timestamp
                    Text(
                      _formatDate(alert.createdAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textMuted,
                      ),
                    ),
                    const Gap(4),

                    // Action: Delete notification
                    IconButton(
                      iconSize: 17,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'حذف الإشعار',
                      onPressed: () => ref
                          .read(smartAdvisorProvider.notifier)
                          .deleteAlert(alert.id),
                      icon: Icon(
                        Icons.close,
                        color: context.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const Gap(8),

                // Notification Title (Minimalist Typography)
                Text(
                  alert.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: alert.isRead ? FontWeight.w600 : FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const Gap(4),

                // Notification Body
                Text(
                  alert.body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'لا توجد تنبيهات حالياً في هذا القسم',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const Gap(6),
            Text(
              'كافة المؤشرات في هذا النطاق تعمل بشكل طبيعي ومستقر.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else {
      return '${dt.year}/${dt.month}/${dt.day}';
    }
  }
}
