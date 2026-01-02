import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../instructor_course_feedback_page.dart';
import '../widgets/standard_back_button.dart';

class ScreeningsInProgressPage extends StatelessWidget {
  final String statusFilter;
  final String courseType;
  const ScreeningsInProgressPage({
    super.key,
    required this.courseType,
    this.statusFilter = 'draft',
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משובים בתהליך – קורס מדריכים'),
          leading: const StandardBackButton(),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: () {
            final uid =
                currentUser?.uid ?? FirebaseAuth.instance.currentUser?.uid;
            if (uid == null || uid.isEmpty) {
              return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
            }
            // Safe stream: single filter; filter client-side to avoid composite index
            return FirebaseFirestore.instance
                .collection('instructor_course_screenings')
                .where('createdBy', isEqualTo: uid)
                .snapshots();
          }(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'שגיאה בטעינה (ייתכן שחסר אינדקס). מציג נתוני משתמש בלבד.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data?.docs ?? [];
            // Client-side filter by courseType + status
            final filtered = docs.where((d) {
              final m = d.data();
              final matchesCourse = m['courseType'] == courseType;
              final matchesStatus = m['status'] == statusFilter;
              return matchesCourse && matchesStatus;
            }).toList();
            // Sort by updatedAt desc
            filtered.sort((a, b) {
              final ta = a.data()['updatedAt'] as Timestamp?;
              final tb = b.data()['updatedAt'] as Timestamp?;
              final da = ta?.toDate();
              final db = tb?.toDate();
              if (da == null && db == null) return 0;
              if (da == null) return 1;
              if (db == null) return -1;
              return db.compareTo(da);
            });
            if (filtered.isEmpty) {
              return Center(
                child: Text(
                  statusFilter == 'completed'
                      ? 'אין משובים סופיים'
                      : 'אין משובים בתהליך',
                ),
              );
            }
            return ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final doc = filtered[i];
                final data = doc.data();
                final title =
                    (data['title'] as String?) ?? data['candidateId'] ?? doc.id;
                final locked = (data['isFinalLocked'] as bool?) ?? false;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(title),
                    subtitle: Text(
                      locked
                          ? 'נעול'
                          : (statusFilter == 'completed' ? 'סופי' : 'טיוטה'),
                    ),
                    trailing: statusFilter == 'draft'
                        ? ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InstructorCourseFeedbackPage(
                                    screeningId: doc.id,
                                  ),
                                ),
                              );
                            },
                            child: const Text('המשך מילוי'),
                          )
                        : IconButton(
                            icon: const Icon(Icons.remove_red_eye),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InstructorCourseFeedbackPage(
                                    screeningId: doc.id,
                                  ),
                                ),
                              );
                            },
                            tooltip: 'צפה',
                          ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              InstructorCourseFeedbackPage(screeningId: doc.id),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
        floatingActionButton: null,
      ),
    );
  }
}
