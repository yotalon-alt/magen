import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'main.dart';
import 'widgets/standard_back_button.dart';

/// 📝 Training Summary Temporary List Page
///
/// Shows ONLY temporary training summary drafts:
/// - module: "training_summary"
/// - isTemporary: true
class TrainingSummaryTempListPage extends StatefulWidget {
  const TrainingSummaryTempListPage({super.key});

  @override
  State<TrainingSummaryTempListPage> createState() =>
      _TrainingSummaryTempListPageState();
}

class _TrainingSummaryTempListPageState
    extends State<TrainingSummaryTempListPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tempSummaries = [];
  String? _errorMessage;
  bool _isMissingIndex = false;

  @override
  void initState() {
    super.initState();
    _loadTempSummaries();
  }

  Future<void> _loadTempSummaries() async {
    setState(() {
      _isLoading = true;
      _isMissingIndex = false;
      _errorMessage = null;
    });

    try {
      final uid = currentUser?.uid;
      if (uid == null) {
        throw Exception('משתמש לא מחובר');
      }

      final isAdmin = currentUser?.role == 'Admin';

      Query query = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'training_summary')
          .where('isTemporary', isEqualTo: true);

      if (!isAdmin) {
        query = query.where('instructorId', isEqualTo: uid);
      }

      query = query.orderBy('createdAt', descending: true);

      final snapshot = await query.get().timeout(const Duration(seconds: 15));

      final List<Map<String, dynamic>> summaries = [];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        summaries.add(data);
      }

      // ✨ Load shared summaries (where I'm an additional instructor)
      if (!isAdmin) {
        try {
          final currentUserName = currentUser?.name ?? '';

          // Query by UID
          final sharedQueryByUid = FirebaseFirestore.instance
              .collection('feedbacks')
              .where('module', isEqualTo: 'training_summary')
              .where('isTemporary', isEqualTo: true)
              .where('instructors', arrayContains: uid);

          final sharedSnapByUid = await sharedQueryByUid.get();

          for (final doc in sharedSnapByUid.docs) {
            final data = doc.data();
            if (summaries.any((s) => s['id'] == doc.id)) {
              continue;
            }
            data['id'] = doc.id;
            summaries.add(data);
          }

          // Query by name (fallback for old data)
          if (currentUserName.isNotEmpty) {
            final sharedQueryByName = FirebaseFirestore.instance
                .collection('feedbacks')
                .where('module', isEqualTo: 'training_summary')
                .where('isTemporary', isEqualTo: true)
                .where('instructors', arrayContains: currentUserName);

            final sharedSnapByName = await sharedQueryByName.get();

            for (final doc in sharedSnapByName.docs) {
              final data = doc.data();
              if (summaries.any((s) => s['id'] == doc.id)) {
                continue;
              }
              data['id'] = doc.id;
              summaries.add(data);
            }
          }
        } catch (e) {
          // Silently fail - user will just see their own summaries
          debugPrint('⚠️ Failed to load shared training summaries: $e');
        }
      }

      setState(() {
        _tempSummaries = summaries;
        _isLoading = false;
        _errorMessage = null;
        _isMissingIndex = false;
      });
    } on FirebaseException catch (e) {
      debugPrint(
        '❌ FirebaseException loading temp training summaries: ${e.code}',
      );
      debugPrint('   Message: ${e.message}');

      if (e.code == 'failed-precondition' ||
          e.message?.contains('index') == true) {
        debugPrint('❌ MISSING INDEX: ${e.message}');

        setState(() {
          _isLoading = false;
          _isMissingIndex = true;
          _errorMessage =
              'חסר אינדקס ב-Firestore. אנא צור אינדקס עבור:\n'
              'Collection: feedbacks\n'
              'Fields: module (Ascending), isTemporary (Ascending), createdAt (Descending)';
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'שגיאה בטעינת משובים: ${e.message}';
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading temp training summaries: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'שגיאה לא צפויה: $e';
      });
    }
  }

  Future<void> _deleteSummary(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת טיוטה'),
          content: const Text('האם אתה בטוח שברצונך למחוק טיוטה זו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('feedbacks').doc(id).delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הטיוטה נמחקה בהצלחה'),
          backgroundColor: Colors.green,
        ),
      );

      _loadTempSummaries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה במחיקה: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _editSummary(Map<String, dynamic> summaryData) {
    // Navigate to form page with the draft ID for editing
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                TrainingSummaryFormPage(draftId: summaryData['id'] as String?),
          ),
        )
        .then((_) {
          // Reload list when returning from form
          _loadTempSummaries();
        });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סיכומי אימון זמניים'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadTempSummaries,
              tooltip: 'רענן',
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
            Text('טוען סיכומי אימון זמניים...'),
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
              const Text(
                'חסר אינדקס ב-Firestore',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadTempSummaries,
                icon: const Icon(Icons.refresh),
                label: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadTempSummaries,
                icon: const Icon(Icons.refresh),
                label: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tempSummaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'אין סיכומי אימון זמניים',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'כל הסיכומים שתתחיל ישמרו אוטומטית כאן',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.add),
              label: const Text('צור סיכום חדש'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _tempSummaries.length,
      itemBuilder: (context, index) {
        final summary = _tempSummaries[index];
        return _buildSummaryCard(summary);
      },
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final settlement = summary['settlement'] as String? ?? 'לא צוין';
    final trainingType = summary['trainingType'] as String? ?? 'לא צוין';
    final attendeesCount = summary['attendeesCount'] as int? ?? 0;
    final instructorName = summary['instructorName'] as String? ?? 'לא ידוע';

    final createdAt = (summary['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt)
        : 'לא ידוע';

    // Calculate time since last update
    final timeSince = createdAt != null
        ? _formatTimeSince(DateTime.now().difference(createdAt))
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editSummary(summary),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Settlement and date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            settlement,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    dateStr,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Training type
              Row(
                children: [
                  const Icon(
                    Icons.fitness_center,
                    size: 18,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'סוג אימון: $trainingType',
                      style: const TextStyle(fontSize: 14),
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
              Row(
                children: [
                  const Icon(Icons.person, size: 18, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'מדריך: $instructorName',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),

              if (timeSince.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'שונה $timeSince',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _editSummary(summary),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('המשך עריכה'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _deleteSummary(summary['id'] as String),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('מחק'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
}
