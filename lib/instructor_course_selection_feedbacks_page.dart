import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // for currentUser
import 'feedback_export_service.dart'; // for export functionality
import 'widgets/standard_back_button.dart';

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
    // Show selection dialog with 3 options
    final selection = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'בחר קטגוריה לייצוא',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'איזו קטגוריה תרצה לייצא?',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'suitable'),
                icon: const Icon(Icons.check_circle),
                label: const Text('מתאימים לקורס מדריכים'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'not_suitable'),
                icon: const Icon(Icons.cancel),
                label: const Text('לא מתאימים לקורס מדריכים'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'both'),
                icon: const Icon(Icons.list_alt),
                label: const Text('שניהם (שני גיליונות)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
          ],
        ),
      ),
    );

    if (selection == null) return; // User canceled

    debugPrint('🔵 User selected: $selection');

    setState(() => _isLoading = true);

    try {
      await FeedbackExportService.exportInstructorCourseSelection(selection);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקובץ נוצר בהצלחה!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('❌ Export error: $e');
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
    if (_selectedFeedbackIds.isEmpty) {
      debugPrint('⚠️ EXPORT_CLICKED: No feedbacks selected');
      return;
    }

    final selectedFeedbacks = _feedbacks
        .where((f) => _selectedFeedbackIds.contains(f['id']))
        .toList();

    final categoryLabel = _selectedCategory == 'suitable'
        ? 'מתאימים'
        : 'לא מתאימים';

    debugPrint(
      '🔵 EXPORT_CLICKED: screen=$_selectedCategory, count=${selectedFeedbacks.length}',
    );

    setState(() => _isLoading = true);

    try {
      await FeedbackExportService.exportSelectedInstructorCourseFeedbacksToXlsx(
        selectedFeedbacks,
        categoryLabel,
      );

      debugPrint('✅ EXPORT_SUCCESS: $categoryLabel exported successfully');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקובץ נוצר בהצלחה!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ EXPORT_FAILED: error=$e');
      debugPrint('Stack trace: $stackTrace');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: ${e.toString()}'),
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
      debugPrint(
        '\n🔍 ===== MIUNIM_LIST_LOAD: INSTRUCTOR COURSE FEEDBACKS =====',
      );

      // Map category to isSuitable boolean
      final isSuitable = category == 'suitable';
      debugPrint(
        '🔵 MIUNIM_LIST_READ: collection=instructor_course_evaluations isSuitable=$isSuitable (ALL instructors)',
      );
      debugPrint(
        '🔵 MIUNIM_LIST_READ: where("status", "==", "final") + where("isSuitable", "==", $isSuitable)',
      );

      // ✅ SHARED QUERY: All instructors see all final submissions
      // Requires composite index: status + isSuitable + createdAt
      final snapshot = await FirebaseFirestore.instance
          .collection('instructor_course_evaluations')
          .where('status', isEqualTo: 'final')
          .where('isSuitable', isEqualTo: isSuitable)
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 15));

      debugPrint(
        '🔵 MIUNIM_LIST_READ_RAW: Got ${snapshot.docs.length} documents (status=final, isSuitable=$isSuitable)',
      );

      final filtered = snapshot.docs;

      debugPrint(
        '🔵 MIUNIM_LIST_READ_FILTERED: ${filtered.length} documents (sorted by Firestore orderBy)',
      );

      final feedbacks = <Map<String, dynamic>>[];
      for (final doc in filtered) {
        final data = doc.data();
        data['id'] = doc.id;

        // ✅ MAP SCORES: Extract from fields structure and flatten to scores map
        final fields = data['fields'] as Map<String, dynamic>? ?? {};
        final Map<String, dynamic> scores = {};
        double totalScore = 0.0;
        int scoreCount = 0;

        // Map Hebrew category names to English keys for backward compatibility
        final categoryMapping = {
          'בוחן רמה': 'levelTest',
          'הדרכה טובה': 'goodInstruction',
          'הדרכת מבנה': 'structureInstruction',
          'יבשים': 'dryPractice',
          'תרגיל הפתעה': 'surpriseExercise',
        };

        fields.forEach((hebrewName, fieldData) {
          if (fieldData is Map && fieldData.containsKey('value')) {
            final value = fieldData['value'];
            final numValue = (value is num) ? value.toDouble() : 0.0;

            // Store with English key for UI compatibility
            final englishKey = categoryMapping[hebrewName];
            if (englishKey != null) {
              scores[englishKey] = numValue;
              if (numValue > 0) {
                totalScore += numValue;
                scoreCount++;
              }
            }

            debugPrint(
              '  SCORE_MAP: "$hebrewName" → "$englishKey" = $numValue',
            );
          } else {
            debugPrint(
              '  ⚠️ SCORE_PARSE_ERROR: Field "$hebrewName" has unexpected structure: $fieldData',
            );
          }
        });

        // Calculate average score
        final averageScore = scoreCount > 0 ? totalScore / scoreCount : 0.0;
        data['scores'] = scores;
        data['averageScore'] = averageScore;

        feedbacks.add(data);
        debugPrint(
          'DOC: ${doc.id} - ${data["candidateName"]} (suitable=${data["isSuitable"]}) avg=$averageScore scores=${scores.length}',
        );
      }
      debugPrint('===================================================\n');

      if (mounted) {
        setState(() {
          _feedbacks = feedbacks;
          _isLoading = false;
        });
      }

      debugPrint('✅ Loaded ${feedbacks.length} feedbacks');
    } on FirebaseException catch (e) {
      debugPrint('❌ FirebaseException: ${e.code}');
      debugPrint('   Message: ${e.message}');

      if (e.code == 'failed-precondition' ||
          e.message?.contains('index') == true) {
        debugPrint('\n❌❌❌ UNEXPECTED INDEX ERROR! ❌❌❌');
        debugPrint('Query should NOT require composite index!');
        debugPrint('Using single where filter: ownerUid == <currentUser.uid>');
        debugPrint('Error: ${e.code} - ${e.message}');
        debugPrint('❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌\n');

        if (mounted) {
          setState(() {
            _feedbacks = [];
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאת Firestore: ${e.code}\n${e.message ?? ""}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 10),
              margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
              action: SnackBarAction(
                label: 'סגור',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      } else {
        debugPrint('❌ Other Firebase error: ${e.code}');
        if (mounted) {
          setState(() {
            _feedbacks = [];
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאת Firebase: ${e.message}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            ),
          );
        }
      }
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
    // Local state for this dialog (not shared with outer widget)
    Set<String> localSelectedIds = {};
    bool isExporting = false;

    debugPrint('🔵 EXPORT_DIALOG_OPEN: selectedCount=0, isExporting=false');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // Log button state before rendering
            final disabled = localSelectedIds.isEmpty || isExporting;
            debugPrint(
              '📊 EXPORT_DISABLED_REASON: selectedCount=${localSelectedIds.length}, isExporting=$isExporting, disabled=$disabled',
            );

            return AlertDialog(
              title: const Text('בחר משובים לייצוא'),
              content: SizedBox(
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
                            setDialogState(() {
                              localSelectedIds = _feedbacks
                                  .map((f) => f['id'] as String)
                                  .toSet();
                            });
                          },
                          child: const Text('בחר הכל'),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              localSelectedIds.clear();
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
                          final isSelected = localSelectedIds.contains(id);

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
                              setDialogState(() {
                                if (value == true) {
                                  localSelectedIds.add(id);
                                } else {
                                  localSelectedIds.remove(id);
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ביטול'),
                ),
                ElevatedButton(
                  onPressed: (localSelectedIds.isEmpty || isExporting)
                      ? null
                      : () async {
                          debugPrint(
                            '🔵 EXPORT_CLICK: selectedCount=${localSelectedIds.length}',
                          );

                          setDialogState(() {
                            isExporting = true;
                          });

                          try {
                            // Copy selected IDs to parent widget state for export
                            _selectedFeedbackIds = localSelectedIds;
                            Navigator.pop(ctx);
                            await _exportSelectedFeedbacks();
                          } finally {
                            // Reset exporting flag (dialog is closed so state won't update, but for consistency)
                            isExporting = false;
                          }
                        },
                  child: isExporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('ייצא לאקסל'),
                ),
              ],
            );
          },
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
                StandardBackButton(
                  onPressed: () => setState(() {
                    _selectedCategory = null;
                    _feedbacks = [];
                  }),
                  color: Colors.white,
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

    debugPrint('\n📋 FEEDBACK_DETAILS_OPEN: ${feedback['id']}');
    debugPrint('   candidateName=$candidateName');
    debugPrint('   averageScore=$averageScore');
    debugPrint('   scores=$scores');

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
                _buildScoreRow('בוחן רמה', scores['levelTest'], 'levelTest'),
                _buildScoreRow(
                  'הדרכה טובה',
                  scores['goodInstruction'],
                  'goodInstruction',
                ),
                _buildScoreRow(
                  'הדרכת מבנה',
                  scores['structureInstruction'],
                  'structureInstruction',
                ),
                _buildScoreRow('יבשים', scores['dryPractice'], 'dryPractice'),
                _buildScoreRow(
                  'תרגיל הפתעה',
                  scores['surpriseExercise'],
                  'surpriseExercise',
                ),
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

  Widget _buildScoreRow(String label, dynamic score, [String? scoreKey]) {
    // Parse score value with proper type handling
    String displayValue;
    if (score == null) {
      debugPrint('  ⚠️ SCORE_DISPLAY: $label ($scoreKey) = null → showing "—"');
      displayValue = '—';
    } else if (score is num) {
      final numScore = score.toDouble();
      displayValue = numScore == numScore.toInt()
          ? numScore.toInt().toString()
          : numScore.toStringAsFixed(1);
      debugPrint('  ✅ SCORE_DISPLAY: $label ($scoreKey) = $displayValue');
    } else {
      debugPrint(
        '  ⚠️ SCORE_DISPLAY: $label ($scoreKey) has unexpected type ${score.runtimeType} → showing "—"',
      );
      displayValue = '—';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            displayValue,
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
        leading: const StandardBackButton(),
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
