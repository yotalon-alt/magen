import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'range_training_page.dart';
import 'widgets/standard_back_button.dart';
import 'widgets/feedback_list_tile_card.dart';

/// מסך משובים זמניים למטווחים - Temporary Range Feedbacks List
class RangeTempFeedbacksPage extends StatefulWidget {
  const RangeTempFeedbacksPage({super.key});

  @override
  State<RangeTempFeedbacksPage> createState() => _RangeTempFeedbacksPageState();
}

class _RangeTempFeedbacksPageState extends State<RangeTempFeedbacksPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tempFeedbacks = [];
  String? _errorMessage;
  bool _isMissingIndex = false;

  @override
  void initState() {
    super.initState();
    _loadTempFeedbacks();
  }

  Future<void> _loadTempFeedbacks() async {
    setState(() => _isLoading = true);

    try {
      final uid = currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final isAdmin = currentUser?.role == 'Admin';

      // ========== QUERY SHAPE FOR FIRESTORE INDEX ==========
      // ADMIN QUERY:
      //   - where('module', '==', 'shooting_ranges')
      //   - where('isTemporary', '==', true)
      //   - orderBy('createdAt', 'DESCENDING')
      //
      // INSTRUCTOR QUERY:
      //   - where('module', '==', 'shooting_ranges')
      //   - where('isTemporary', '==', true)
      //   - where('instructorId', '==', uid)
      //   - orderBy('createdAt', 'DESCENDING')
      //
      // Required indexes in firestore.indexes.json:
      //   1. module ASC + isTemporary ASC + createdAt DESC (for admin)
      //   2. module ASC + isTemporary ASC + instructorId ASC + createdAt DESC (for instructors)
      // =====================================================

      Query query = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'shooting_ranges')
          .where('isTemporary', isEqualTo: true);

      // Non-admins only see their own temp feedbacks
      if (!isAdmin) {
        query = query.where('instructorId', isEqualTo: uid);
      }

      query = query.orderBy('createdAt', descending: true);

      final snapshot = await query.get();

      final List<Map<String, dynamic>> feedbacks = [];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        feedbacks.add(data);
      }

      // ✨ Load temp feedbacks where I'm an additional instructor (non-admins only)
      if (!isAdmin) {
        try {
          final sharedQuery = FirebaseFirestore.instance
              .collection('feedbacks')
              .where('module', isEqualTo: 'shooting_ranges')
              .where('isTemporary', isEqualTo: true)
              .where('instructors', arrayContains: currentUser?.name ?? '');

          final sharedSnap = await sharedQuery.get();

          for (final doc in sharedSnap.docs) {
            final data = doc.data();
            if (feedbacks.any((f) => f['id'] == doc.id)) {
              continue;
            }
            data['id'] = doc.id;
            feedbacks.add(data);
          }
        } catch (e) {
          // Silently fail - user will just see their own feedbacks
        }
      }

      setState(() {
        _tempFeedbacks = feedbacks;
        _isLoading = false;
        _errorMessage = null;
        _isMissingIndex = false;
      });
    } on FirebaseException catch (e) {
      debugPrint('❌ FirebaseException loading temp range feedbacks: ${e.code}');
      debugPrint('   Message: ${e.message}');

      if (e.code == 'failed-precondition' ||
          e.message?.contains('index') == true) {
        debugPrint('❌ MISSING INDEX: ${e.message}');

        setState(() {
          _isLoading = false;
          _isMissingIndex = true;
          _errorMessage =
              'חסר אינדקס ב-Firestore למסך זה.\n\n'
              'יש להריץ deploy לאינדקסים (firestore:indexes) כדי להפעיל את המסך.\n\n'
              'הפעל: firebase deploy --only firestore:indexes\n\n'
              'לאחר ה-deploy, המתן 1-5 דקות עד שהאינדקסים ייבנו ב-Firebase Console.';
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'שגיאה בטעינת נתונים: ${e.message}';
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading temp range feedbacks: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'שגיאה לא צפויה: $e';
      });
    }
  }

  Future<void> _deleteTempFeedback(String id) async {
    try {
      await FirebaseFirestore.instance.collection('feedbacks').doc(id).delete();

      // Remove from local list
      setState(() {
        _tempFeedbacks.removeWhere((f) => f['id'] == id);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('משוב זמני נמחק')));
    } catch (e) {
      debugPrint('❌ Error deleting temp feedback: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה במחיקה: $e')));
    }
  }

  void _confirmDelete(String id, String settlement) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משוב זמני'),
          content: Text('האם למחוק את המשוב הזמני עבור $settlement?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteTempFeedback(id);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משוב זמני - מטווחים'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadTempFeedbacks,
              tooltip: 'רענן רשימה',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isMissingIndex
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'חסר אינדקס ב-Firestore',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage ?? '',
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadTempFeedbacks,
                        icon: const Icon(Icons.refresh),
                        label: const Text('נסה שוב'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'שגיאה בטעינת נתונים',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
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
              )
            : _tempFeedbacks.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'אין משובים זמניים',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'שמירות זמניות ממטווחים יופיעו כאן',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12.0),
                itemCount: _tempFeedbacks.length,
                itemBuilder: (ctx, i) {
                  final feedback = _tempFeedbacks[i];
                  final id = feedback['id'] as String;
                  final rangeType = feedback['rangeType'] as String? ?? 'קצרים';
                  // ✅ FIX: Try both settlement and settlementName fields
                  final settlementField =
                      feedback['settlement'] as String? ?? '';
                  final settlementNameField =
                      feedback['settlementName'] as String? ?? '';
                  final settlement = settlementField.isNotEmpty
                      ? settlementField
                      : (settlementNameField.isNotEmpty
                            ? settlementNameField
                            : 'לא צוין');
                  final createdByName =
                      feedback['createdByName'] as String? ?? '';
                  final updatedByName =
                      feedback['updatedByName'] as String? ?? '';
                  final attendeesCount =
                      feedback['attendeesCount'] as int? ?? 0;

                  // Parse createdAt
                  String dateStr = '';
                  final createdAt = feedback['createdAt'];
                  if (createdAt is Timestamp) {
                    final date = createdAt.toDate().toLocal();
                    dateStr =
                        '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                  }

                  // Get blue tag label from document data
                  final blueTagLabel = getBlueTagLabelFromDoc(feedback);

                  // Build metadata lines
                  final metadataLines = <String>[];
                  if (createdByName.isNotEmpty) {
                    metadataLines.add('מדריך ממשב: $createdByName');
                  }
                  // Show last editor only if different from creator
                  if (updatedByName.isNotEmpty &&
                      updatedByName != createdByName) {
                    metadataLines.add('מדריך אחרון שערך: $updatedByName');
                  }
                  if (attendeesCount > 0) {
                    metadataLines.add('משתתפים: $attendeesCount');
                  }
                  if (dateStr.isNotEmpty) {
                    metadataLines.add('נשמר: $dateStr');
                  }

                  // Check permissions - only owner (instructorId) or admin can delete temp feedbacks
                  final canDelete =
                      currentUser?.role == 'Admin' ||
                      feedback['instructorId'] == currentUser?.uid;

                  return FeedbackListTileCard(
                    title: settlement,
                    metadataLines: metadataLines,
                    blueTagLabel: blueTagLabel,
                    canDelete: canDelete,
                    leadingIcon: Icons.edit_note,
                    iconColor: rangeType == 'קצרים'
                        ? Colors.blue
                        : Colors.orange,
                    iconBackgroundColor: rangeType == 'קצרים'
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                    onOpen: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RangeTrainingPage(
                            rangeType: rangeType,
                            feedbackId: id,
                          ),
                        ),
                      ).then((_) {
                        _loadTempFeedbacks();
                      });
                    },
                    onDelete: () => _confirmDelete(id, settlement),
                  );
                },
              ),
      ),
    );
  }
}
