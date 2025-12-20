import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../instructor_course_feedback_page.dart';
import 'screenings_in_progress_page.dart';

class ScreeningsMenuPage extends StatefulWidget {
  final String courseType; // expected: 'miunim'
  const ScreeningsMenuPage({super.key, required this.courseType});

  @override
  State<ScreeningsMenuPage> createState() => _ScreeningsMenuPageState();
}

class _ScreeningsMenuPageState extends State<ScreeningsMenuPage> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מיונים לקורס מדריכים'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Button: Open new screening
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('פתיחת משוב חדש'),
                  onPressed: () async {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null || uid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('נדרשת התחברות')),
                      );
                      return;
                    }
                    try {
                      final ref = FirebaseFirestore.instance
                          .collection('instructor_course_screenings')
                          .doc();
                      await ref.set({
                        'status': 'draft',
                        'isFinalLocked': false,
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                        'createdBy': uid,
                        'createdByName':
                            FirebaseAuth.instance.currentUser?.email ?? '',
                        'courseType': widget.courseType,
                        'title': 'מועמד חדש',
                      });
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              InstructorCourseFeedbackPage(screeningId: ref.id),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('שגיאה ביצירה: ${e.toString()}'),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Button: Temporary (in-progress) screenings
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.pending_actions),
                  label: const Text('מיונים זמניים (בתהליך)'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScreeningsInProgressPage(
                          courseType: widget.courseType,
                          statusFilter: 'draft',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
