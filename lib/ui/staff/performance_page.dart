import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import 'package:intl/intl.dart';

class PerformancePage extends ConsumerStatefulWidget {
  final Staff staff;

  const PerformancePage({super.key, required this.staff});

  @override
  ConsumerState<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends ConsumerState<PerformancePage> {
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
    final db = ref.read(appDatabaseProvider);
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

  Future<void> _addNewReview() async {
    final formKey = GlobalKey<FormState>();
    final periodCtrl = TextEditingController(
      text: DateFormat('yyyy-MM').format(DateTime.now()),
    );
    final strengthsCtrl = TextEditingController();
    final weaknessesCtrl = TextEditingController();
    final goalsCtrl = TextEditingController();
    final recommendationsCtrl = TextEditingController();
    double workQuality = 3.0, productivity = 3.0, teamwork = 3.0;
    double punctuality = 3.0, initiative = 3.0;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        double wq = workQuality, prod = productivity, team = teamwork;
        double punct = punctuality, init = initiative;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('إضافة تقييم جديد'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: periodCtrl,
                      decoration: const InputDecoration(
                        labelText: 'فترة التقييم',
                        hintText: 'مثال: 2024-Q1',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'الحقل مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildRatingSlider('جودة العمل', wq, (v) {
                      setDialogState(() => wq = v);
                    }),
                    _buildRatingSlider('الإنتاجية', prod, (v) {
                      setDialogState(() => prod = v);
                    }),
                    _buildRatingSlider('العمل الجماعي', team, (v) {
                      setDialogState(() => team = v);
                    }),
                    _buildRatingSlider('الانتظام', punct, (v) {
                      setDialogState(() => punct = v);
                    }),
                    _buildRatingSlider('المبادرة', init, (v) {
                      setDialogState(() => init = v);
                    }),
                    const SizedBox(height: 8),
                    Text(
                      'المتوسط: ${((wq + prod + team + punct + init) / 5).toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: strengthsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'نقاط القوة',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: weaknessesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'نقاط التحسين',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: goalsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'الأهداف القادمة',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: recommendationsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'التوصيات',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    final avg = (wq + prod + team + punct + init) / 5;
                    Navigator.pop(ctx, {
                      'period': periodCtrl.text.trim(),
                      'workQuality': wq,
                      'productivity': prod,
                      'teamwork': team,
                      'punctuality': punct,
                      'initiative': init,
                      'overall': double.parse(avg.toStringAsFixed(1)),
                      'strengths': strengthsCtrl.text.trim(),
                      'weaknesses': weaknessesCtrl.text.trim(),
                      'goals': goalsCtrl.text.trim(),
                      'recommendations': recommendationsCtrl.text.trim(),
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('حفظ التقييم'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      try {
        await _dao.addPerformanceReview(
          PerformanceReviewsCompanion.insert(
            staffId: widget.staff.staffId,
            reviewPeriod: result['period'] as String,
            reviewDate: DateTime.now(),
            reviewerId: 'admin',
            overallRating: result['overall'] as double,
            workQualityRating: result['workQuality'] as double,
            productivityRating: result['productivity'] as double,
            teamworkRating: result['teamwork'] as double,
            punctualityRating: result['punctuality'] as double,
            initiativeRating: result['initiative'] as double,
            strengths: (result['strengths'] as String).isNotEmpty
                ? drift.Value(result['strengths'] as String)
                : const drift.Value.absent(),
            weaknesses: (result['weaknesses'] as String).isNotEmpty
                ? drift.Value(result['weaknesses'] as String)
                : const drift.Value.absent(),
            goals: (result['goals'] as String).isNotEmpty
                ? drift.Value(result['goals'] as String)
                : const drift.Value.absent(),
            recommendations: (result['recommendations'] as String).isNotEmpty
                ? drift.Value(result['recommendations'] as String)
                : const drift.Value.absent(),
            status: 'submitted',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إضافة التقييم بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    periodCtrl.dispose();
    strengthsCtrl.dispose();
    weaknessesCtrl.dispose();
    goalsCtrl.dispose();
    recommendationsCtrl.dispose();
  }

  Widget _buildRatingSlider(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 1.0,
            max: 5.0,
            divisions: 8,
            activeColor: Colors.purple,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
