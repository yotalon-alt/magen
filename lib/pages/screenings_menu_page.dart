import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screening_details_page.dart';

class ScreeningsMenuPage extends StatelessWidget {
  const ScreeningsMenuPage({super.key});

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
                    // Create screening doc as draft, then navigate to fill
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
                'יצירת משוב היא השלב הראשון. רשימות משובים נטענות רק במסך הייעודי.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
