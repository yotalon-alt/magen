import 'dart:async';
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

      debugPrint('\n🔍 ===== LOADING SURPRISE DRILLS TEMP FEEDBACKS =====');
      debugPrint('   User UID: $uid');
      debugPrint('   Is Admin: $isAdmin');
      debugPrint('   Query:');
      debugPrint('     collection: feedbacks');
      debugPrint('     where: folder == "תרגילי הפתעה - משוב זמני"');
      debugPrint('     where: status == "temporary"');
      if (!isAdmin) {
        debugPrint('     where: instructorId == "$uid"');
      }
      debugPrint('     orderBy: createdAt DESC');
      debugPrint('🔍 ================================================\n');

      Query query = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('folder', isEqualTo: 'תרגילי הפתעה - משוב זמני')
          .where('status', isEqualTo: 'temporary');

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

      if (mounted) {
        setState(() {
          _tempFeedbacks = feedbacks;
          _isLoading = false;
        });
      }
    } on FirebaseException catch (e) {
      debugPrint('❌ FirebaseException: ${e.code}');
      debugPrint('   Message: ${e.message}');

      if (e.code == 'failed-precondition' ||
          e.message?.contains('index') == true) {
        debugPrint('\n🔥 COMPOSITE INDEX ERROR DETECTED!');
        debugPrint('   Required index:');
        debugPrint('     Collection: feedbacks');
        debugPrint('     Fields:');
        debugPrint('       1. folder (Ascending)');
        debugPrint('       2. status (Ascending)');
        if (currentUser?.role != 'Admin') {
          debugPrint('       3. instructorId (Ascending)');
        }
        debugPrint('       N. createdAt (Descending)');
        debugPrint('');
        debugPrint(
          '   Deploy indexes: firebase deploy --only firestore:indexes',
        );
        debugPrint('🔥 ==========================================\n');

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
      debugPrint('❌ Unexpected error: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        final id = feedback['id'] as String;
        final settlement = (feedback['settlement'] ?? '').toString();
        final attendeesCount =
            (feedback['attendeesCount'] as num?)?.toInt() ?? 0;
        final instructorName = (feedback['instructorName'] ?? '').toString();

        final createdAt = feedback['createdAt'];
        String dateStr = '';
        if (createdAt is Timestamp) {
          dateStr = DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate());
        } else if (createdAt is String) {
          final dt = DateTime.tryParse(createdAt);
          if (dt != null) {
            dateStr = DateFormat('dd/MM/yyyy HH:mm').format(dt);
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            title: Text(
              settlement.isNotEmpty ? settlement : 'ללא יישוב',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (instructorName.isNotEmpty) Text('מדריך: $instructorName'),
                Text('נוכחים: $attendeesCount'),
                if (dateStr.isNotEmpty) Text('תאריך: $dateStr'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('מחיקת משוב זמני'),
                        content: const Text('האם למחוק משוב זמני זה?'),
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
                            child: const Text('מחק'),
                          ),
                        ],
                      ),
                    );
                  },
                  tooltip: 'מחק',
                ),
              ],
            ),
            onTap: () {
              // Open editor to continue editing
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
            },
          ),
        );
      },
    );
  }
}
