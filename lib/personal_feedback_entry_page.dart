import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // For FeedbackFormPage, currentUser
import 'personal_feedback_temp_list_page.dart';
import 'widgets/standard_back_button.dart';

/// מסך כניסה למשובים אישיים (מעגל פתוח / מעגל פרוץ / סריקות רחוב)
///
/// מציג שני כפתורים:
/// 1. משוב חדש - פותח את הטופס
/// 2. משובים זמניים - פותח רשימת טיוטות
class PersonalFeedbackEntryPage extends StatefulWidget {
  final String exercise;

  const PersonalFeedbackEntryPage({super.key, required this.exercise});

  @override
  State<PersonalFeedbackEntryPage> createState() =>
      _PersonalFeedbackEntryPageState();
}

class _PersonalFeedbackEntryPageState extends State<PersonalFeedbackEntryPage> {
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
          .where('module', isEqualTo: 'personal_feedback')
          .where('isTemporary', isEqualTo: true)
          .where('exercise', isEqualTo: widget.exercise);
      if (!isAdmin) q = q.where('instructorId', isEqualTo: uid);
      final snap = await q.limit(500).get().timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _draftCount = snap.docs.length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.exercise),
          leading: const StandardBackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                const Icon(Icons.person, size: 80, color: Colors.green),
                const SizedBox(height: 32),

                // Title
                Text(
                  widget.exercise,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // כפתור 1: משוב חדש
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              FeedbackFormPage(exercise: widget.exercise),
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
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle, size: 28),
                        SizedBox(width: 12),
                        Text('משוב חדש'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // כפתור 2: משובים זמניים
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PersonalFeedbackTempListPage(
                            exercise: widget.exercise,
                          ),
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
