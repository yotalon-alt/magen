import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import 'screening_details_page.dart';

class ScreeningsInProgressPage extends StatelessWidget {
  final String statusFilter;
  const ScreeningsInProgressPage({
    super.key,
    this.statusFilter = 'in_progress',
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('משובים בתהליך – קורס מדריכים')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: () {
            Query<Map<String, dynamic>> q = FirebaseFirestore.instance
                .collection('instructor_course_screenings')
                .where('status', isEqualTo: statusFilter);
            final uid =
                currentUser?.uid ?? FirebaseAuth.instance.currentUser?.uid;
            final isAdmin = currentUser?.role == 'Admin';
            if (!isAdmin && uid != null && uid.isNotEmpty) {
              q = q.where('createdBy', isEqualTo: uid);
            }
            q = q.orderBy('updatedAt', descending: true);
            return q.snapshots();
          }(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('שגיאה: ${snapshot.error}'));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  statusFilter == 'completed'
                      ? 'אין משובים סופיים'
                      : 'אין משובים בתהליך',
                ),
              );
            }
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final doc = docs[i];
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
                          : (statusFilter == 'completed' ? 'סופי' : 'בתהליך'),
                    ),
                    trailing: statusFilter == 'in_progress'
                        ? ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ScreeningDetailsPage(screeningId: doc.id),
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
                                  builder: (_) =>
                                      ScreeningDetailsPage(screeningId: doc.id),
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
                              ScreeningDetailsPage(screeningId: doc.id),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                onPressed: () async {
                  // Admin could create a new screening shell
                  final ref = FirebaseFirestore.instance
                      .collection('instructor_course_screenings')
                      .doc();
                  await ref.set({
                    'status': 'in_progress',
                    'isFinalLocked': false,
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                    'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
                    'createdByName': currentUser?.name ?? '',
                    'title': 'מועמד חדש',
                    'fields': {
                      'ירי': {'value': null},
                      'קבלת החלטות': {'value': null},
                      'עמידה בלחץ': {'value': null},
                    },
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('צור משוב'),
              )
            : null,
      ),
    );
  }
}
