import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // For TrainingSummaryFormPage, currentUser
import 'training_summary_temp_list_page.dart';
import 'widgets/standard_back_button.dart';

/// 📊 סיכום אימון 474 - Entry Screen
///
/// This screen provides TWO options:
/// 1. Add New Training Summary - Opens the form
/// 2. Temporary Summaries - Opens list of drafts
class TrainingSummaryEntryPage extends StatefulWidget {
  const TrainingSummaryEntryPage({super.key});

  @override
  State<TrainingSummaryEntryPage> createState() => _TrainingSummaryEntryPageState();
}

class _TrainingSummaryEntryPageState extends State<TrainingSummaryEntryPage> {
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
          .where('module', isEqualTo: 'training_summary')
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
          title: const Text('סיכום אימון'),
          leading: const StandardBackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                const Icon(Icons.assessment, size: 80, color: Colors.green),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'סיכום אימון',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Button 1: Add New Training Summary
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TrainingSummaryFormPage(),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_circle, size: 28),
                        const SizedBox(width: 12),
                        const Text('הוסף משוב חדש'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Button 2: Temporary Summaries
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TrainingSummaryTempListPage(),
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
