import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'main.dart'; // For FeedbackFormPage, currentUser, canCurrentUserDeleteFeedbacks
import 'widgets/standard_back_button.dart';

/// רשימת משובים אישיים זמניים (טיוטות) לפי סוג תרגיל
///
/// שאילתה: module == 'personal_feedback' + isTemporary == true + exercise == feedbackType
class PersonalFeedbackTempListPage extends StatefulWidget {
  final String exercise;

  const PersonalFeedbackTempListPage({super.key, required this.exercise});

  @override
  State<PersonalFeedbackTempListPage> createState() =>
      _PersonalFeedbackTempListPageState();
}

class _PersonalFeedbackTempListPageState
    extends State<PersonalFeedbackTempListPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _drafts = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uid = currentUser?.uid;
      if (uid == null) throw Exception('משתמש לא מחובר');

      final isAdmin = currentUser?.role == 'Admin';

      Query query = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'personal_feedback')
          .where('isTemporary', isEqualTo: true)
          .where('exercise', isEqualTo: widget.exercise);

      if (!isAdmin) {
        query = query.where('instructorId', isEqualTo: uid);
      }

      query = query.orderBy('createdAt', descending: true);

      final snapshot = await query.get().timeout(const Duration(seconds: 15));

      final List<Map<String, dynamic>> drafts = [];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        drafts.add(data);
      }

      if (mounted) {
        setState(() {
          _drafts = drafts;
          _isLoading = false;
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'שגיאה בטעינת משובים: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'שגיאה לא צפויה: $e';
        });
      }
    }
  }

  Future<void> _deleteDraft(String id) async {
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

    if (!canCurrentUserDeleteFeedbacks) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אין הרשאה למחיקת משוב זה')));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('feedbacks').doc(id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הטיוטה נמחקה בהצלחה'),
          backgroundColor: Colors.green,
        ),
      );
      _loadDrafts();
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

  void _openDraft(Map<String, dynamic> draftData) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => FeedbackFormPage(
              exercise: widget.exercise,
              draftId: draftData['id'] as String?,
            ),
          ),
        )
        .then((_) => _loadDrafts());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('טיוטות - ${widget.exercise}'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDrafts,
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
            Text('טוען טיוטות...'),
          ],
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
                onPressed: _loadDrafts,
                icon: const Icon(Icons.refresh),
                label: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }

    if (_drafts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'אין טיוטות עבור ${widget.exercise}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'משובים שתשמור כזמניים יופיעו כאן',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('חזרה'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _drafts.length,
      itemBuilder: (context, index) => _buildDraftCard(_drafts[index]),
    );
  }

  Widget _buildDraftCard(Map<String, dynamic> draft) {
    final evaluatedName = draft['name'] as String? ?? 'לא צוין';
    final role = draft['role'] as String? ?? 'לא צוין';
    final settlement = draft['settlement'] as String? ?? 'לא צוין';
    final instructorName = draft['instructorName'] as String? ?? 'לא ידוע';
    final createdAt = (draft['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt)
        : 'לא ידוע';

    final canDelete = canCurrentUserDeleteFeedbacks;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDraft(draft),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 20, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            evaluatedName,
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
                            onPressed: () =>
                                _deleteDraft(draft['id'] as String),
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
              const SizedBox(height: 8),
              // Details
              Row(
                children: [
                  const Icon(Icons.work, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('תפקיד: $role'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('יישוב: $settlement'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text('מדריך: $instructorName'),
                ],
              ),
              const SizedBox(height: 12),
              // Chip + edit button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Chip(
                    label: const Text(
                      'טיוטה',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: Colors.orange,
                    padding: EdgeInsets.zero,
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openDraft(draft),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('המשך עריכה'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
}
