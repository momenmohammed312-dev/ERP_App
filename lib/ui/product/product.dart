import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

import 'widgets/widgets.dart';

class ProductScreen extends StatefulWidget {
  final AppDatabase db;

  const ProductScreen({super.key, required this.db});

  @override
  ProductScreenState createState() => ProductScreenState();
}

class ProductScreenState extends State<ProductScreen>
    with AutomaticKeepAliveClientMixin {
  late final AppDatabase db;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    db = widget.db;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: ProductContainer(db: db),
      ),
    );
  }
}
