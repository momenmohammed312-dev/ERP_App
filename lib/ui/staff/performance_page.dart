import 'package:flutter/material.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/database/database_singleton.dart';
import 'package:intl/intl.dart';

class PerformancePage extends StatefulWidget {
  final Staff staff;

  const PerformancePage({super.key, required this.staff});

  @override
  State<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<PerformancePage> {
  late StaffManagementDao _dao;
  List<PerformanceReview> _reviews = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseSingleton.getInstance();
    _dao = StaffManagementDao(db);
    try {
      final reviews = await _dao.getReviewsByStaff(widget.staff.staffId);
      setState(() {
        _reviews = reviews.reversed.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل التقييم: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final averageRating = _calculateAverageRating();

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_reviews.isNotEmpty) _buildRatingSummary(averageRating),
                Expanded(
                  child: _reviews.isEmpty
                      ? _buildEmptyState()
                      : _buildReviewsList(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewReview,
        backgroundColor: Colors.purple,
        tooltip: 'إضافة تقييم',
        child: const Icon(Icons.rate_review, color: Colors.white),
      ),
    );
  }

  double _calculateAverageRating() {
    if (_reviews.isEmpty) return 0.0;
    final sum = _reviews.fold<double>(0, (sum, r) => sum + (r.overallRating));
    return sum / _reviews.length;
  }

  Widget _buildRatingSummary(double average) {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple[100]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(
                average.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple[700],
                ),
              ),
              const Text(
                'متوسط التقييم العام',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildStarRating(average),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating.floor()
              ? Icons.star
              : (index < rating ? Icons.star_half : Icons.star_outline),
          color: Colors.amber,
          size: 24,
        );
      }),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد تقييمات لهذا الموظف',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      itemCount: _reviews.length,
      itemBuilder: (context, index) {
        final review = _reviews[index];
        return _buildReviewCard(review);
      },
    );
  }

  Widget _buildReviewCard(PerformanceReview review) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: ExpansionTile(
        title: Row(
          children: [
            Text(
              review.reviewPeriod,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _buildStarRating(review.overallRating),
          ],
        ),
        subtitle: Text(
          'تاريخ التقييم: ${DateFormat('yyyy/MM/dd').format(review.reviewDate)}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRatingBar('جودة العمل', review.workQualityRating),
                _buildRatingBar('الإنتاجية', review.productivityRating),
                _buildRatingBar('العمل الجماعي', review.teamworkRating),
                _buildRatingBar('الانتظام', review.punctualityRating),
                const Divider(),
                if (review.strengths != null) ...[
                  const Text(
                    'نقاط القوة:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(review.strengths!),
                  const SizedBox(height: 8),
                ],
                if (review.weaknesses != null) ...[
                  const Text(
                    'نقاط التحسين:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(review.weaknesses!),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBar(String label, double rating) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: rating / 5.0,
              backgroundColor: Colors.grey[200],
              color: Colors.purple,
              minHeight: 8,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _addNewReview() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة تقييم جديد'),
        content: const Text('هذه الميزة ستمكن من تقييم الموظف في عدة معايير.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
