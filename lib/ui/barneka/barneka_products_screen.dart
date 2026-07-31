import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/barneka/barneka_tracking_screen.dart';

class BarnekaProductsScreen extends StatefulWidget {
  final AppDatabase db;

  const BarnekaProductsScreen({super.key, required this.db});

  @override
  State<BarnekaProductsScreen> createState() => _BarnekaProductsScreenState();
}

class _BarnekaProductsScreenState extends State<BarnekaProductsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البرنيكه (العبوات القابلة للاسترجاع)')),
      body: StreamBuilder<List<Product>>(
        stream: widget.db.productDao.watchAllProducts(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final products =
              snapshot.data!.where((p) => p.barneka).toList();

          if (products.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد منتجات برنيكه بعد.\nأضف منتجاً وفعّل خيار «منتج برنيكه» من نموذج المنتج.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (_, _) => const Gap(12),
            itemBuilder: (context, index) {
              final product = products[index];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.eco, color: Colors.white),
                  ),
                  title: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('السعر: ${product.price}'),
                  trailing: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => BarnekaTrackingScreen(
                            db: widget.db,
                            product: product,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.people_alt_outlined),
                    label: const Text('العملاء'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
