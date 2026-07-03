import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'range_training_page.dart';
import 'range_temp_feedbacks_page.dart';
import 'widgets/standard_back_button.dart';
import 'main.dart' show currentUser;

/// מסך בחירת סוג מטווח
class RangeSelectionPage extends StatefulWidget {
  const RangeSelectionPage({super.key});

  @override
  State<RangeSelectionPage> createState() => _RangeSelectionPageState();
}

class _RangeSelectionPageState extends State<RangeSelectionPage> {
  int _draftCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDraftCount();
  }

  Future<void> _loadDraftCount() async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) return;
      final isAdmin = currentUser?.role == 'Admin';

      if (isAdmin) {
        // Admin: single count query — 1 read total
        final snap = await FirebaseFirestore.instance
            .collection('feedbacks')
            .where('module', isEqualTo: 'shooting_ranges')
            .where('isTemporary', isEqualTo: true)
            .count()
            .get()
            .timeout(const Duration(seconds: 8));
        if (mounted) setState(() => _draftCount = snap.count ?? 0);
      } else {
        // Non-admin: 2 count queries (by UID + by name) — 2 reads total
        final results = await Future.wait([
          FirebaseFirestore.instance
              .collection('feedbacks')
              .where('module', isEqualTo: 'shooting_ranges')
              .where('isTemporary', isEqualTo: true)
              .where('instructorId', isEqualTo: uid)
              .count()
              .get()
              .timeout(const Duration(seconds: 8)),
          FirebaseFirestore.instance
              .collection('feedbacks')
              .where('module', isEqualTo: 'shooting_ranges')
              .where('isTemporary', isEqualTo: true)
              .where('instructors', arrayContains: currentUser?.name ?? '')
              .count()
              .get()
              .timeout(const Duration(seconds: 8)),
        ]);
        final total = (results[0].count ?? 0) + (results[1].count ?? 0);
        if (mounted) setState(() => _draftCount = total);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מטווחים'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon
              const Icon(Icons.gps_fixed, size: 60, color: Colors.deepOrange),
              const SizedBox(height: 20),

              const Text(
                'בחר סוג מטווח',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // טווח קצר
              _buildRangeTypeButton(
                context,
                title: 'טווח קצר',
                icon: Icons.arrow_forward,
                color: Colors.blue,
                rangeType: 'קצרים',
              ),
              const SizedBox(height: 16),

              // טווח רחוק
              _buildRangeTypeButton(
                context,
                title: 'טווח רחוק',
                icon: Icons.arrow_forward,
                color: Colors.orange,
                rangeType: 'ארוכים',
              ),
              const SizedBox(height: 16),

              // משוב זמני
              _buildTempFeedbackButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeTypeButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required String rangeType,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RangeTrainingPage(rangeType: rangeType),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.7), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: Colors.white),
                  const SizedBox(width: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.arrow_back_ios, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTempFeedbackButton(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RangeTempFeedbacksPage()),
          );
          _loadDraftCount();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.withValues(alpha: 0.7), Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note, size: 32, color: Colors.white),
                  const SizedBox(width: 16),
                  const Text(
                    'משוב זמני',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (_draftCount > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_draftCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Icon(Icons.arrow_back_ios, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
