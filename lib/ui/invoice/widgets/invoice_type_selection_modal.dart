import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/ui/invoice/models/invoice_models.dart';

class InvoiceTypeSelectionModal extends StatelessWidget {
  final Function(InvoiceType) onSelectType;

  const InvoiceTypeSelectionModal({super.key, required this.onSelectType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'نوع الفاتورة',
          style: TextStyle(
            fontSize: isDesktop ? 20 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 650 : 450),
            child: Container(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'اختر نوع الفاتورة',
                    style: TextStyle(
                      fontSize: isDesktop ? 22 : 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Gap(6),
                  Text(
                    'اختر نوع الفاتورة التي تريد إنشاءها لمتابعة الحسابات',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isDesktop ? 14 : 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  Gap(isDesktop ? 28 : 20),
                  if (isDesktop)
                    Row(
                      children: [
                        Expanded(
                          child: _buildDesktopCard(
                            theme: theme,
                            type: InvoiceType.cash,
                            title: 'نقدي',
                            subtitle: 'دفع فوري\nإيصال حراري',
                            icon: Icons.attach_money,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Gap(14),
                        Expanded(
                          child: _buildDesktopCard(
                            theme: theme,
                            type: InvoiceType.credit,
                            title: 'آجل',
                            subtitle: 'دفع على الحساب\nفاتورة A4',
                            icon: Icons.credit_card,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                        const Gap(14),
                        Expanded(
                          child: _buildDesktopCard(
                            theme: theme,
                            type: InvoiceType.supply,
                            title: 'توريد',
                            subtitle: 'فاتورة شراء\nمن المورد',
                            icon: Icons.local_shipping,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildMobileCard(
                          theme: theme,
                          type: InvoiceType.cash,
                          title: 'نقدي (كاش)',
                          subtitle: 'دفع فوري مع إيصال حراري',
                          icon: Icons.attach_money,
                          color: theme.colorScheme.primary,
                        ),
                        const Gap(12),
                        _buildMobileCard(
                          theme: theme,
                          type: InvoiceType.credit,
                          title: 'آجل (على الحساب)',
                          subtitle: 'تسجيل على حساب العميل / فاتورة A4',
                          icon: Icons.credit_card,
                          color: theme.colorScheme.secondary,
                        ),
                        const Gap(12),
                        _buildMobileCard(
                          theme: theme,
                          type: InvoiceType.supply,
                          title: 'توريد (شراء)',
                          subtitle: 'فاتورة توريد وشراء بضاعة من المورد',
                          icon: Icons.local_shipping,
                          color: Colors.orange,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopCard({
    required ThemeData theme,
    required InvoiceType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      onTap: () => onSelectType(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 42, color: color),
            const Gap(10),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Gap(6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCard({
    required ThemeData theme,
    required InvoiceType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      onTap: () => onSelectType(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.08),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
