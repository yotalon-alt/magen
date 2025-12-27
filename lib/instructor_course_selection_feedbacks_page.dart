import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // for currentUser
import 'feedback_export_service.dart'; // for export functionality

/// דף תצוגת משובים למיונים לקורס מדריכים
class InstructorCourseSelectionFeedbacksPage extends StatefulWidget {
  const InstructorCourseSelectionFeedbacksPage({super.key});

  @override
  State<InstructorCourseSelectionFeedbacksPage> createState() =>
      _InstructorCourseSelectionFeedbacksPageState();
}

class _InstructorCourseSelectionFeedbacksPageState
    extends State<InstructorCourseSelectionFeedbacksPage> {
  String?
  _selectedCategory; // null = show buttons, 'suitable' or 'not_suitable' = show list
  bool _isLoading = false;
  List<Map<String, dynamic>> _feedbacks = [];
  Set<String> _selectedFeedbackIds = {}; // For export selection

  Future<void> _exportInstructorCourseFeedbacks() async {
    setState(() => _isLoading = true);

    try {
      await FeedbackExportService.exportInstructorCourseFeedbacksToXlsx();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקובץ נוצר בהצלחה!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportSelectedFeedbacks() async {
    if (_selectedFeedbackIds.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final selectedFeedbacks = _feedbacks
          .where((f) => _selectedFeedbackIds.contains(f['id']))
          .toList();
      await FeedbackExportService.exportSelectedInstructorCourseFeedbacksToXlsx(
        selectedFeedbacks,
        _selectedCategory == 'suitable' ? 'מתאימים' : 'לא מתאימים',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקובץ נוצר בהצלחה!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadFeedbacks(String category) async {
    setState(() {
      _isLoading = true;
      _selectedCategory = category;
    });

    try {
      // Fixed collection path - use top-level collections
      final collectionPath = category == 'suitable'
          ? 'instructor_course_selection_suitable'
          : 'instructor_course_selection_not_suitable';
      debugPrint('🔍 Loading feedbacks from: $collectionPath');

      final snapshot = await FirebaseFirestore.instance
          .collection(collectionPath)
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 15));

      final feedbacks = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        feedbacks.add(data);
      }

      if (mounted) {
        setState(() {
          _feedbacks = feedbacks;
          _isLoading = false;
        });
      }

      debugPrint('✅ Loaded ${feedbacks.length} feedbacks');
    } catch (e) {
      debugPrint('❌ Error loading feedbacks: $e');
      if (mounted) {
        setState(() {
          _feedbacks = [];
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בטעינת משובים: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
          ),
        );
      }
    }
  }

  void _showExportSelectionDialog() {
    _selectedFeedbackIds.clear(); // Reset selection

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('בחר משובים לייצוא'),
          content: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Select All / None buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedFeedbackIds = _feedbacks
                                .map((f) => f['id'] as String)
                                .toSet();
                          });
                        },
                        child: const Text('בחר הכל'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedFeedbackIds.clear();
                          });
                        },
                        child: const Text('בטל בחירה'),
                      ),
                    ],
                  ),
                  const Divider(),
                  // Feedback list with checkboxes
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _feedbacks.length,
                      itemBuilder: (context, i) {
                        final feedback = _feedbacks[i];
                        final id = feedback['id'] as String;
                        final candidateName =
                            feedback['candidateName'] ?? 'לא ידוע';
                        final candidateNumber =
                            feedback['candidateNumber'] as int?;
                        final isSelected = _selectedFeedbackIds.contains(id);

                        return CheckboxListTile(
                          title: Text(
                            candidateNumber != null
                                ? '$candidateName – $candidateNumber'
                                : candidateName,
                          ),
                          subtitle: Text(
                            'מדריך: ${feedback['instructorName'] ?? 'לא ידוע'}',
                          ),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedFeedbackIds.add(id);
                              } else {
                                _selectedFeedbackIds.remove(id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: _selectedFeedbackIds.isNotEmpty
                  ? () async {
                      Navigator.pop(ctx);
                      await _exportSelectedFeedbacks();
                    }
                  : null,
              child: const Text('ייצא לאקסל'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryButtons() {
    final isAdmin = currentUser?.role == 'Admin';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text(
              'מיונים לקורס מדריכים',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // כפתור ייצוא - רק לאדמין
            if (isAdmin) ...[
              SizedBox(
                height: 60,
                child: ElevatedButton(
                  onPressed: _exportInstructorCourseFeedbacks,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download, size: 28),
                      SizedBox(width: 16),
                      Text(
                        'הורדת משובים – קורס מדריכים',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // כפתור ירוק - מתאימים
            SizedBox(
              height: 80,
              child: ElevatedButton(
                onPressed: () => _loadFeedbacks('suitable'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 32),
                    SizedBox(width: 16),
                    Text(
                      'מתאימים לקורס מדריכים',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // כפתור אדום - לא מתאימים
            SizedBox(
              height: 80,
              child: ElevatedButton(
                onPressed: () => _loadFeedbacks('not_suitable'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel, size: 32),
                    SizedBox(width: 16),
                    Text(
                      'לא מתאימים לקורס מדריכים',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbacksList() {
    final categoryTitle = _selectedCategory == 'suitable'
        ? 'מתאימים לקורס מדריכים'
        : 'לא מתאימים לקורס מדריכים';

    final categoryColor = _selectedCategory == 'suitable'
        ? Colors.green.shade700
        : Colors.red.shade700;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // Header with back button
          Container(
            color: categoryColor,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_forward, color: Colors.white),
                  onPressed: () => setState(() {
                    _selectedCategory = null;
                    _feedbacks = [];
                  }),
                ),
                Expanded(
                  child: Text(
                    categoryTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // Export button
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  onPressed: () => _showExportSelectionDialog(),
                  tooltip: 'ייצוא משובים לאקסל',
                ),
              ],
            ),
          ),

          // List of feedbacks
          Expanded(
            child: _feedbacks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'אין משובים בקטגוריה זו',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _feedbacks.length,
                    itemBuilder: (ctx, i) {
                      final feedback = _feedbacks[i];
                      final candidateName =
                          feedback['candidateName'] ?? 'לא ידוע';
                      final candidateNumber =
                          feedback['candidateNumber'] as int?;
                      final instructorName =
                          feedback['instructorName'] ?? 'לא ידוע';
                      final averageScore = feedback['averageScore'] ?? 0.0;
                      final command = feedback['command'] ?? '';
                      final brigade = feedback['brigade'] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(
                            candidateNumber != null
                                ? '$candidateName – $candidateNumber'
                                : candidateName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('מדריך: $instructorName'),
                              if (command.isNotEmpty) Text('פיקוד: $command'),
                              if (brigade.isNotEmpty) Text('חטיבה: $brigade'),
                            ],
                          ),
                          trailing: SizedBox(
                            width: 50,
                            height: 50,
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: categoryColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'ממוצע',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    averageScore.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          onTap: () => _showFeedbackDetails(feedback),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDetails(Map<String, dynamic> feedback) {
    final candidateName = feedback['candidateName'] ?? 'לא ידוע';
    final candidateNumber = feedback['candidateNumber'] as int?;
    final instructorName = feedback['instructorName'] ?? 'לא ידוע';
    final command = feedback['command'] ?? '';
    final brigade = feedback['brigade'] ?? '';
    final averageScore = feedback['averageScore'] ?? 0.0;
    final scores = feedback['scores'] as Map<String, dynamic>? ?? {};

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  candidateName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (candidateNumber != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$candidateNumber',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('מדריך', instructorName),
                if (command.isNotEmpty) _buildDetailRow('פיקוד', command),
                if (brigade.isNotEmpty) _buildDetailRow('חטיבה', brigade),
                const Divider(),
                const Text(
                  'ציונים:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _buildScoreRow('בוחן רמה', scores['levelTest']),
                _buildScoreRow('הדרכה טובה', scores['goodInstruction']),
                _buildScoreRow('הדרכת מבנה', scores['structureInstruction']),
                _buildScoreRow('יבשים', scores['dryPractice']),
                _buildScoreRow('תרגיל הפתעה', scores['surpriseExercise']),
                const Divider(),
                _buildDetailRow(
                  'ממוצע',
                  averageScore.toStringAsFixed(2),
                  isHighlight: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isHighlight = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              fontSize: isHighlight ? 18 : 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              fontSize: isHighlight ? 18 : 14,
              color: color ?? (isHighlight ? Colors.orangeAccent : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreRow(String label, dynamic score) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            score?.toString() ?? '0',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('מיונים לקורס מדריכים'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.pop(context),
          tooltip: 'חזרה',
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('טוען משובים...'),
                ],
              ),
            )
          : _selectedCategory == null
          ? _buildCategoryButtons()
          : _buildFeedbacksList(),
    );
  }
}
