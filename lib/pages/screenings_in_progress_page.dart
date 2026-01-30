import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../instructor_course_feedback_page.dart';
import '../widgets/standard_back_button.dart';

class ScreeningsInProgressPage extends StatefulWidget {
  final String statusFilter;
  final String courseType;
  const ScreeningsInProgressPage({
    super.key,
    required this.courseType,
    this.statusFilter = 'draft',
  });

  @override
  State<ScreeningsInProgressPage> createState() =>
      _ScreeningsInProgressPageState();
}

class _ScreeningsInProgressPageState extends State<ScreeningsInProgressPage> {
  int _refreshKey = 0;
  bool _isRefreshing = false;

  /// Fetch instructor Hebrew name from users collection (backward compatible)
  Future<String> _getInstructorName(
    String? createdByName,
    dynamic createdByUid,
  ) async {
    // If createdByName already exists and is valid, use it
    if (createdByName != null && createdByName.isNotEmpty) {
      return createdByName;
    }

    // Otherwise, fetch from users collection using UID
    if (createdByUid == null || createdByUid.toString().isEmpty) {
      return 'לא ידוע';
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(createdByUid.toString())
          .get()
          .timeout(const Duration(seconds: 3));

      if (userDoc.exists) {
        final userData = userDoc.data();
        // Priority: displayName > fullName > name (never show email/username)
        final displayName = userData?['displayName'] as String?;
        final fullName = userData?['fullName'] as String?;
        final name = userData?['name'] as String?;

        if (displayName != null &&
            displayName.isNotEmpty &&
            !displayName.contains('@')) {
          return displayName;
        } else if (fullName != null &&
            fullName.isNotEmpty &&
            !fullName.contains('@')) {
          return fullName;
        } else if (name != null && name.isNotEmpty && !name.contains('@')) {
          return name;
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ Failed to fetch instructor name for UID $createdByUid: $e',
      );
    }

    // Fallback: show truncated UID
    return 'מדריך ${createdByUid.toString().substring(0, min(8, createdByUid.toString().length))}...';
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      // Force StreamBuilder to rebuild by incrementing key
      setState(() => _refreshKey++);

      // Wait briefly to ensure Firestore query is re-executed
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הרשימה עודכנה'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('שגיאה ברענון. נסה שוב'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משובים בתהליך – קורס מדריכים'),
          leading: const StandardBackButton(),
          actions: [
            // Refresh button (positioned left in RTL layout)
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isRefreshing ? null : _refresh,
              tooltip: 'רענון',
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          key: ValueKey(_refreshKey), // Force rebuild on refresh
          stream: () {
            // ✅ SHARED COLLABORATION: All instructors/admins see ALL drafts
            return FirebaseFirestore.instance
                .collection('instructor_course_evaluations')
                .where('status', isEqualTo: 'draft')
                .where('courseType', isEqualTo: widget.courseType)
                .snapshots();
          }(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'שגיאה בטעינת הרשימה',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ייתכן שחסר אינדקס ב-Firestore או שאין הרשאות גישה.\n\n${snapshot.error}',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('נסה שוב'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data?.docs ?? [];

            // ✅ Already filtered by query (status=draft, courseType=courseType)
            // ✅ Sort by updatedAt descending in Dart (client-side)
            docs.sort((a, b) {
              final aUpdatedAt = a.data()['updatedAt'] as Timestamp?;
              final bUpdatedAt = b.data()['updatedAt'] as Timestamp?;
              if (aUpdatedAt == null && bUpdatedAt == null) return 0;
              if (aUpdatedAt == null) return 1;
              if (bUpdatedAt == null) return -1;
              return bUpdatedAt.compareTo(aUpdatedAt); // descending
            });

            if (docs.isEmpty) {
              return const Center(child: Text('אין משובים בתהליך'));
            }

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final doc = docs[i];
                final data = doc.data();
                // ✅ FIX: Include candidate number in title
                final candidateName =
                    (data['candidateName'] as String?) ??
                    (data['title'] as String?) ??
                    data['candidateId'] ??
                    '';
                final candidateNumber = data['candidateNumber'] as int?;
                // Build title: "שם מועמד (מס' X)" or just "שם מועמד"
                final title =
                    candidateNumber != null && candidateName.isNotEmpty
                    ? '$candidateName (מס\' $candidateNumber)'
                    : candidateName.isNotEmpty
                    ? candidateName
                    : doc.id;
                final locked = (data['isFinalLocked'] as bool?) ?? false;
                final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
                final dateStr = updatedAt != null
                    ? '${updatedAt.day}/${updatedAt.month}/${updatedAt.year} ${updatedAt.hour}:${updatedAt.minute.toString().padLeft(2, '0')}'
                    : '';

                // ✅ INSTRUCTOR NAME: Fetch from createdByName or lookup from users collection
                final createdByName = data['createdByName'] as String?;
                final createdByUid =
                    data['createdBy'] ??
                    data['createdByUid'] ??
                    data['ownerUid'];

                // Filter out emails from createdByName (backward compatibility fix)
                final safeCreatedByName =
                    createdByName != null &&
                        createdByName.isNotEmpty &&
                        !createdByName.contains('@')
                    ? createdByName
                    : null;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(title),
                    subtitle: FutureBuilder<String>(
                      future: _getInstructorName(
                        safeCreatedByName,
                        createdByUid,
                      ),
                      builder: (context, nameSnapshot) {
                        // NEVER show email - use fallback if data not loaded yet
                        final instructorName =
                            nameSnapshot.data ??
                            (nameSnapshot.connectionState ==
                                    ConnectionState.waiting
                                ? 'טוען...'
                                : 'מדריך לא ידוע');
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('נוצר ע״י: $instructorName'),
                            if (dateStr.isNotEmpty) Text('עודכן: $dateStr'),
                            if (locked) const Text('נעול'),
                          ],
                        );
                      },
                    ),
                    trailing: ElevatedButton(
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
