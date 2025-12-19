import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screening_details_page.dart';
import 'screenings_in_progress_page.dart';

class ScreeningsMenuPage extends StatefulWidget {
  final String courseType; // e.g. 'miunim' | 'instructor_course'
  const ScreeningsMenuPage({super.key, required this.courseType});

  @override
  State<ScreeningsMenuPage> createState() => _ScreeningsMenuPageState();
}

class _ScreeningsMenuPageState extends State<ScreeningsMenuPage> {
  bool _hasOpen = false;
  bool _checkedOnEnter = false;

  @override
  void initState() {
    super.initState();
    // On enter: only check if there are open feedbacks for this course.
    // Do NOT auto-create. Show a single "משובים פתוחים" tile if exists.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (!mounted) return;
      if (uid == null || uid.isEmpty) {
        setState(() => _checkedOnEnter = true);
        return;
      }
      try {
        Query q = FirebaseFirestore.instance
            .collection('instructor_course_screenings')
            .where('courseType', isEqualTo: widget.courseType)
            .where('status', isEqualTo: 'in_progress');
        // Non-admins: only their own
        q = q.where('createdBy', isEqualTo: uid);
        final snap = await q.limit(1).get();
        if (!mounted) return;
        setState(() {
          _hasOpen = snap.docs.isNotEmpty;
          _checkedOnEnter = true;
        });
      } catch (_) {
        if (mounted) setState(() => _checkedOnEnter = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('תרגילי קורס מיונים'),
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
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('הוסף משוב'),
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
                        'status': 'in_progress',
                        'isFinalLocked': false,
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                        'createdBy': uid,
                        'createdByName':
                            FirebaseAuth.instance.currentUser?.email ?? '',
                        'courseType': widget.courseType,
                        'title': 'מועמד חדש',
                        'fields': {
                          'ירי': {'value': null},
                          'קבלת החלטות': {'value': null},
                          'עמידה בלחץ': {'value': null},
                        },
                      });
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ScreeningDetailsPage(screeningId: ref.id),
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
              const SizedBox(height: 12),
              const Text(
                'יצירת משוב מתבצעת רק כשאין משוב פתוח. רשימות משובים מוצגות רק לאחר חזרה למסך.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_checkedOnEnter && _hasOpen)
                Card(
                  color: Colors.blueGrey.shade700,
                  child: ListTile(
                    leading: const Icon(
                      Icons.folder,
                      color: Colors.orangeAccent,
                    ),
                    title: const Text('משובים פתוחים'),
                    subtitle: const Text('המשך מילוי משובים בתהליך'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScreeningsInProgressPage(
                            courseType: widget.courseType,
                            statusFilter: 'in_progress',
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
