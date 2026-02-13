import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'main.dart';
import 'range_training_page.dart';

/// Surprise Drills Temporary Feedbacks List Page
///
/// Shows ONLY temporary feedback drafts for surprise drills:
/// - type: "surprise_exercise"
/// - folder: "תרגילי הפתעה - משוב זמני"
/// - status: "temporary"
class SurpriseDrillsTempFeedbacksPage extends StatefulWidget {
  const SurpriseDrillsTempFeedbacksPage({super.key});

  @override
  State<SurpriseDrillsTempFeedbacksPage> createState() =>
      _SurpriseDrillsTempFeedbacksPageState();
}

class _SurpriseDrillsTempFeedbacksPageState
    extends State<SurpriseDrillsTempFeedbacksPage> {
  bool _isLoading = true;
  bool _isMissingIndex = false;
  String _errorMessage = '';
  List<Map<String, dynamic>> _tempFeedbacks = [];

  @override
  void initState() {
    super.initState();
    _loadTempFeedbacks();
  }

  Future<void> _loadTempFeedbacks() async {
    setState(() {
      _isLoading = true;
      _isMissingIndex = false;
      _errorMessage = '';
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('משתמש לא מחובר');
      }

      final isAdmin = currentUser?.role == 'Admin';

      Query query = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'surprise_drill')
          .where('isTemporary', isEqualTo: true);

      if (!isAdmin) {
        query = query.where('instructorId', isEqualTo: uid);
      }

      query = query.orderBy('createdAt', descending: true);

      final snapshot = await query.get().timeout(const Duration(seconds: 15));

      debugPrint('✅ Query succeeded: ${snapshot.docs.length} documents');

      final List<Map<String, dynamic>> feedbacks = [];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        feedbacks.add(data);
        debugPrint('   📄 Doc ${doc.id}: ${data['settlement'] ?? 'N/A'}');
      }

      // ✨ NEW: Load temp surprise drills where I'm an additional instructor (non-admins only)
      // ✅ HYBRID: Check BOTH UID and name for backward compatibility
      if (!isAdmin) {
        debugPrint('\n🔍 Loading shared temp surprise drills (UID + name)...');
        final Set<String> processedIds = {};

        // Query: Search by instructor name in instructors array
        try {
          debugPrint('   Query: By instructor name=${currentUser?.name}');
          final sharedQueryByUid = FirebaseFirestore.instance
              .collection('feedbacks')
              .where('module', isEqualTo: 'surprise_drill')
              .where('isTemporary', isEqualTo: true)
              .where('instructors', arrayContains: currentUser?.name ?? '');

          final sharedSnapByUid = await sharedQueryByUid.get();
          debugPrint(
            '   Found ${sharedSnapByUid.docs.length} shared feedbacks',
          );

          for (final doc in sharedSnapByUid.docs) {
            final data = doc.data();
            if (feedbacks.any((f) => f['id'] == doc.id) ||
                processedIds.contains(doc.id)) {
              continue;
            }
            data['id'] = doc.id;
            feedbacks.add(data);
            processedIds.add(doc.id);
            debugPrint('  ✅ Added shared (UID): ${data['settlement']}');
          }
        } catch (e) {
          debugPrint('⚠️ Failed to load by UID: $e');
        }

        // Query 2: Search by name
        try {
          final currentUserName = currentUser?.name ?? '';
          if (currentUserName.isNotEmpty) {
            debugPrint('   Query 2: By name="$currentUserName"');
            final sharedQueryByName = FirebaseFirestore.instance
                .collection('feedbacks')
                .where('module', isEqualTo: 'surprise_drill')
                .where('isTemporary', isEqualTo: true)
                .where('instructors', arrayContains: currentUserName);

            final sharedSnapByName = await sharedQueryByName.get();
            debugPrint('   Found ${sharedSnapByName.docs.length} by name');

            for (final doc in sharedSnapByName.docs) {
              final data = doc.data();
              if (feedbacks.any((f) => f['id'] == doc.id) ||
                  processedIds.contains(doc.id)) {
                continue;
              }
              data['id'] = doc.id;
              feedbacks.add(data);
              processedIds.add(doc.id);
              debugPrint('  ✅ Added shared (name): ${data['settlement']}');
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to load by name: $e');
        }
      }

      if (mounted) {
        setState(() {
          _tempFeedbacks = feedbacks;
          _isLoading = false;
        });
      }
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition' ||
          e.message?.contains('index') == true) {
        debugPrint('❌ MISSING INDEX: ${e.message}');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isMissingIndex = true;
            _errorMessage =
                'חסר אינדקס ב-Firestore למסך זה.\n\nיש להריץ deploy לאינדקסים (firestore:indexes) כדי להפעיל את המסך.\n\nהפעל: firebase deploy --only firestore:indexes\n\nלאחר ה-deploy, המתן 1-5 דקות עד שהאינדקסים ייבנו ב-Firebase Console.';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'שגיאה בטעינת משובים זמניים: ${e.message}';
          });
        }
      }
    } on TimeoutException {
      debugPrint('❌ Query timeout');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'פג הזמן - נסה שוב';
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading temp feedbacks: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'שגיאה: $e';
        });
      }
    }
  }

  Future<void> _deleteTempFeedback(String id) async {
    try {
      await FirebaseFirestore.instance.collection('feedbacks').doc(id).delete();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('המשוב הזמני נמחק')));

      _loadTempFeedbacks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה במחיקה: $e')));
    }
  }

  void _editFeedback(Map<String, dynamic> feedbackData) {
    final id = feedbackData['id'] as String;

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => RangeTrainingPage(
              rangeType: 'הפתעה',
              mode: 'surprise',
              feedbackId: id,
            ),
          ),
        )
        .then((_) => _loadTempFeedbacks());
  }

  String _formatTimeSince(Duration duration) {
    if (duration.inMinutes < 60) {
      return 'לפני ${duration.inMinutes} דקות';
    } else if (duration.inHours < 24) {
      return 'לפני ${duration.inHours} שעות';
    } else {
      return 'לפני ${duration.inDays} ימים';
    }
  }

  Widget _buildFeedbackCard(Map<String, dynamic> feedback) {
    final settlement = (feedback['settlement'] ?? '').toString();
    final attendeesCount = (feedback['attendeesCount'] as num?)?.toInt() ?? 0;
    final createdByName = (feedback['createdByName'] ?? '').toString();
    final updatedByName = (feedback['updatedByName'] ?? '').toString();

    final createdAt = (feedback['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt)
        : 'לא ידוע';

    final timeSince = createdAt != null
        ? _formatTimeSince(DateTime.now().difference(createdAt))
        : '';

    // Check permissions
    final canDelete =
        currentUser?.role == 'Admin' ||
        feedback['instructorId'] == currentUser?.uid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editFeedback(feedback),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Settlement and date with delete button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 20,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            settlement.isNotEmpty ? settlement : 'ללא יישוב',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (canDelete) ...[
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 28,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => Directionality(
                                  textDirection: ui.TextDirection.rtl,
                                  child: AlertDialog(
                                    title: const Text('מחיקת משוב זמני'),
                                    content: const Text(
                                      'האם למחוק משוב זמני זה?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('ביטול'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteTempFeedback(
                                            feedback['id'] as String,
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                        child: const Text('מחק'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.delete, size: 14),
                            label: const Text(
                              'מחק',
                              style: TextStyle(fontSize: 11),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Type
              Row(
                children: [
                  const Icon(Icons.whatshot, size: 18, color: Colors.purple),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'סוג: תרגילי הפתעה',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Attendees count
              Row(
                children: [
                  const Icon(Icons.people, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    '$attendeesCount נוכחים',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Instructor
              if (createdByName.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.purple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'מדריך: $createdByName',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Last editor (if different)
              if (updatedByName.isNotEmpty &&
                  updatedByName != createdByName) ...[
                Row(
                  children: [
                    const Icon(Icons.edit, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'עדכון אחרון: $updatedByName',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              if (timeSince.isNotEmpty) ...[
                Text(
                  'שונה $timeSince',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משובים זמניים - תרגילי הפתעה'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
          actions: [
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadTempFeedbacks,
              tooltip: 'רענן רשימה',
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('טוען משובים זמניים...'),
          ],
        ),
      );
    }

    if (_isMissingIndex) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadTempFeedbacks,
                icon: const Icon(Icons.refresh),
                label: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadTempFeedbacks,
                icon: const Icon(Icons.refresh),
                label: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tempFeedbacks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('אין משובים זמניים'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('חזרה'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _tempFeedbacks.length,
      itemBuilder: (context, index) {
        final feedback = _tempFeedbacks[index];
        return _buildFeedbackCard(feedback);
      },
    );
  }
}
