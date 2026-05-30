import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'range_training_page.dart';
import 'surprise_drills_temp_feedbacks_page.dart';
import 'main.dart' show currentUser;

/// תרגילי הפתעה - Surprise Drills Entry Screen
///
/// This screen provides TWO options:
/// 1. Add New Feedback - Opens the form (RangeTrainingPage in surprise mode)
/// 2. Temporary Feedback - Opens list of drafts specific to surprise drills
class SurpriseDrillsEntryPage extends StatefulWidget {
  const SurpriseDrillsEntryPage({super.key});

  @override
  State<SurpriseDrillsEntryPage> createState() => _SurpriseDrillsEntryPageState();
}

class _SurpriseDrillsEntryPageState extends State<SurpriseDrillsEntryPage> {
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
      Query q = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'surprise_drill')
          .where('isTemporary', isEqualTo: true);
      if (!isAdmin) q = q.where('instructorId', isEqualTo: uid);
      final snap = await q.count().get().timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _draftCount = snap.count ?? 0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('תרגילי הפתעה'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Icon(Icons.bolt, size: 80, color: Colors.orangeAccent),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'תרגילי הפתעה',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Button 1: Add New Feedback
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RangeTrainingPage(
                            rangeType: 'הפתעה',
                            mode: 'surprise',
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: const Text('הוסף משוב חדש'),
                  ),
                ),
                const SizedBox(height: 24),

                // Button 2: Temporary Feedback
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const SurpriseDrillsTempFeedbacksPage(),
                        ),
                      );
                      _loadDraftCount();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_note, size: 28),
                        const SizedBox(width: 12),
                        const Text('משובים זמניים'),
                        if (_draftCount > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
