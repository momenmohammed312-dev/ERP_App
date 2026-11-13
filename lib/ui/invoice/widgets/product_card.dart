import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inStock = product.quantity > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: MadarColors.gold.withValues(alpha: 0.08),
        splashColor: MadarColors.gold.withValues(alpha: 0.15),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? MadarColors.bgCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? MadarColors.border
                  : Theme.of(context).primaryColor.withAlpha(80),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Enhanced product header with icon and name
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF21262D)
                      : Theme.of(context).primaryColor.withAlpha(204),
                  borderRadius: BorderRadius.circular(8),
                  border: isDark
                      ? Border.all(
                          color: MadarColors.border.withValues(alpha: 0.7),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: isDark ? MadarColors.gold : Colors.white,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        product.name,
                        style: TextStyle(
                          color: isDark ? MadarColors.textLight : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Category and Unit row
              Row(
                children: [
                  // Category
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? MadarColors.bgDark
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? MadarColors.border
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        product.category ?? 'غير مصنف',
                        style: TextStyle(
                          color: isDark
                              ? MadarColors.textSecondary
                              : Colors.grey.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Unit
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? MadarColors.info.withValues(alpha: 0.15)
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? MadarColors.info.withValues(alpha: 0.35)
                            : Colors.blue.shade200,
                      ),
                    ),
                    child: Text(
                      product.unit ?? 'قطعة',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFF79C0FF)
                            : Colors.blue.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Stock status with enhanced styling
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: inStock
                      ? (isDark
                          ? MadarColors.success.withValues(alpha: 0.15)
                          : Colors.green.shade50)
                      : (isDark
                          ? MadarColors.error.withValues(alpha: 0.15)
                          : Colors.red.shade50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: inStock
                        ? (isDark
                            ? MadarColors.success.withValues(alpha: 0.4)
                            : Colors.green.shade300)
                        : (isDark
                            ? MadarColors.error.withValues(alpha: 0.4)
                            : Colors.red.shade300),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      inStock
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: inStock
                          ? (isDark
                              ? const Color(0xFF56D364)
                              : Colors.green.shade600)
                          : (isDark
                              ? const Color(0xFFF85149)
                              : Colors.red.shade600),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${product.quantity} ${product.unit ?? 'قطعة'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: inStock
                              ? (isDark
                                  ? const Color(0xFF56D364)
                                  : Colors.green.shade700)
                              : (isDark
                                  ? const Color(0xFFF85149)
                                  : Colors.red.shade700),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Enhanced price display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? MadarColors.gold.withValues(alpha: 0.12)
                      : Theme.of(context).primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? MadarColors.gold.withValues(alpha: 0.35)
                        : Theme.of(context).primaryColor.withAlpha(51),
                  ),
                ),
                child: Text(
                  '${product.price.toStringAsFixed(2)} ج.م',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark
                        ? MadarColors.goldLight
                        : Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
