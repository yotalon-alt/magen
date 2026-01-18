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

  // Filter state variables
  String _filterCommand = 'הכל'; // Dropdown: הכל, צפון, מרכז, דרום
  final TextEditingController _filterNameController = TextEditingController();
  final TextEditingController _filterNumberController = TextEditingController();
  String _filterName = '';
  String _filterNumber = '';
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;

  @override
  void dispose() {
    _filterNameController.dispose();
    _filterNumberController.dispose();
    super.dispose();
  }

  /// Get filtered feedbacks based on search filters (AND logic, case-insensitive contains)
  List<Map<String, dynamic>> get _filteredFeedbacks {
    if (_filterCommand == 'הכל' &&
        _filterName.isEmpty &&
        _filterNumber.isEmpty &&
        _filterDateFrom == null &&
        _filterDateTo == null) {
      return _feedbacks;
    }

    return _feedbacks.where((feedback) {
      // Command filter (פיקוד) - exact match
      if (_filterCommand != 'הכל') {
        final command = (feedback['command'] ?? '').toString();
        if (command != _filterCommand) {
          return false;
        }
      }

      // Name filter (שם)
      if (_filterName.isNotEmpty) {
        final candidateName = (feedback['candidateName'] ?? '')
            .toString()
            .toLowerCase();
        if (!candidateName.contains(_filterName.toLowerCase())) {
          return false;
        }
      }

      // Number filter (מס׳ חניך)
      if (_filterNumber.isNotEmpty) {
        final candidateNumber = (feedback['candidateNumber'] ?? '').toString();
        if (!candidateNumber.contains(_filterNumber)) {
          return false;
        }
      }

      // Date filter
      if (_filterDateFrom != null || _filterDateTo != null) {
        final createdAt = feedback['createdAt'];
        DateTime? feedbackDate;
        if (createdAt is Timestamp) {
          feedbackDate = createdAt.toDate();
        } else if (createdAt is String) {
          feedbackDate = DateTime.tryParse(createdAt);
        }
        if (feedbackDate != null) {
          if (_filterDateFrom != null &&
              feedbackDate.isBefore(_filterDateFrom!)) {
            return false;
          }
          if (_filterDateTo != null &&
              feedbackDate.isAfter(
                _filterDateTo!.add(const Duration(days: 1)),
              )) {
            return false;
          }
        }
      }

      return true;
    }).toList();
  }

  /// Clear all filters
  void _clearFilters() {
    setState(() {
      _filterCommand = 'הכל';
      _filterName = '';
      _filterNumber = '';
      _filterDateFrom = null;
      _filterDateTo = null;
      _filterNameController.clear();
      _filterNumberController.clear();
    });
  }

  /// Check if any filter is active
  bool get _hasActiveFilters =>
      _filterCommand != 'הכל' ||
      _filterName.isNotEmpty ||
      _filterNumber.isNotEmpty ||
      _filterDateFrom != null ||
      _filterDateTo != null;

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

        // ✅ EXTRACT CREATOR INFO: Get instructor who created this feedback
        final createdByUid = data['createdBy'] ?? data['createdByUid'];
        final createdByName = data['createdByName'] as String?;

        // ✅ FETCH INSTRUCTOR NAME: Look up user document for creator's Hebrew full name
        String instructorName = 'לא ידוע';

        // Try to fetch from Firestore users collection if we have a UID
        if (createdByUid != null && createdByUid.toString().isNotEmpty) {
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

              if (displayName != null && displayName.isNotEmpty) {
                instructorName = displayName;
              } else if (fullName != null && fullName.isNotEmpty) {
                instructorName = fullName;
              } else if (name != null && name.isNotEmpty) {
                instructorName = name;
              }
              // If valid UID exists but name fetch failed, show UID instead of "לא ידוע"
              else {
                instructorName =
                    'מדריך ${createdByUid.toString().substring(0, 8)}...';
              }
            } else {
              // User document doesn't exist, show truncated UID
              instructorName =
                  'מדריך ${createdByUid.toString().substring(0, 8)}...';
            }
          } catch (e) {
            debugPrint(
              '⚠️ Failed to fetch instructor name for UID $createdByUid: $e',
            );
            // On error, show truncated UID instead of "לא ידוע"
            instructorName =
                'מדריך ${createdByUid.toString().substring(0, 8)}...';
          }
        } else if (createdByName != null && createdByName.isNotEmpty) {
          // Fallback: use createdByName if no UID available
          instructorName = createdByName;
        }
        data['instructorName'] = instructorName;

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

              // ✅ LEVEL TEST: Extract hits and time for detail display
              if (hebrewName == 'בוחן רמה') {
                data['levelTestHits'] = fieldData['hits'] as int?;
                data['levelTestTimeSeconds'] = (fieldData['timeSeconds'] is num)
                    ? (fieldData['timeSeconds'] as num).toDouble()
                    : null;
                debugPrint(
                  '  📊 LEVEL_TEST_DETAILS: hits=${data["levelTestHits"]}, time=${data["levelTestTimeSeconds"]}s',
                );
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
                  onPressed: () {
                    _clearFilters(); // Clear filters when going back
                    setState(() {
                      _selectedCategory = null;
                      _feedbacks = [];
                    });
                  },
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
                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _isLoading
                      ? null
                      : () => _loadFeedbacks(_selectedCategory!),
                  tooltip: 'רענן רשימה',
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

          // Filter bar
          Card(
            color: Colors.blueGrey.shade800,
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filter row
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.start,
                    children: [
                      // Command filter (פיקוד) - Dropdown
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterCommand,
                          decoration: const InputDecoration(
                            labelText: 'פיקוד',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            prefixIcon: Icon(Icons.military_tech, size: 20),
                          ),
                          items: ['הכל', 'צפון', 'מרכז', 'דרום']
                              .map(
                                (cmd) => DropdownMenuItem(
                                  value: cmd,
                                  child: Text(cmd),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _filterCommand = v ?? 'הכל'),
                        ),
                      ),
                      // Name filter (שם)
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _filterNameController,
                          decoration: InputDecoration(
                            labelText: 'שם',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            prefixIcon: const Icon(Icons.person, size: 20),
                            suffixIcon: _filterName.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _filterNameController.clear();
                                      setState(() => _filterName = '');
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _filterName = v),
                        ),
                      ),
                      // Number filter (מס׳ חניך)
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _filterNumberController,
                          decoration: InputDecoration(
                            labelText: 'מס׳ חניך',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            prefixIcon: const Icon(Icons.tag, size: 20),
                            suffixIcon: _filterNumber.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _filterNumberController.clear();
                                      setState(() => _filterNumber = '');
                                    },
                                  )
                                : null,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => setState(() => _filterNumber = v),
                        ),
                      ),
                      // Date from filter
                      SizedBox(
                        width: 140,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _filterDateFrom ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => _filterDateFrom = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            _filterDateFrom == null
                                ? 'מתאריך'
                                : '${_filterDateFrom!.day}/${_filterDateFrom!.month}/${_filterDateFrom!.year}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      // Date to filter
                      SizedBox(
                        width: 140,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _filterDateTo ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => _filterDateTo = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            _filterDateTo == null
                                ? 'עד תאריך'
                                : '${_filterDateTo!.day}/${_filterDateTo!.month}/${_filterDateTo!.year}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      // Clear all filters button
                      if (_hasActiveFilters)
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('נקה הכל'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                          ),
                        ),
                    ],
                  ),
                  // Show filter status
                  if (_hasActiveFilters) ...[
                    const SizedBox(height: 8),
                    Text(
                      'מציג ${_filteredFeedbacks.length} מתוך ${_feedbacks.length} משובים',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // List of feedbacks
          Expanded(
            child: _filteredFeedbacks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _hasActiveFilters ? Icons.search_off : Icons.inbox,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _hasActiveFilters
                              ? 'לא נמצאו משובים התואמים לחיפוש'
                              : 'אין משובים בקטגוריה זו',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        if (_hasActiveFilters) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear),
                            label: const Text('נקה חיפוש'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _filteredFeedbacks.length,
                    itemBuilder: (ctx, i) {
                      final feedback = _filteredFeedbacks[i];
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
                              // תאריך יצירת המשוב
                              Builder(
                                builder: (context) {
                                  final createdAt = feedback['createdAt'];
                                  DateTime? date;
                                  if (createdAt is Timestamp) {
                                    date = createdAt.toDate();
                                  } else if (createdAt is String) {
                                    date = DateTime.tryParse(createdAt);
                                  }
                                  if (date != null) {
                                    final formatted =
                                        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                    return Text('תאריך: $formatted');
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Percentage (left side)
                              Text(
                                '${((averageScore / 5.0) * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: averageScore > 3.6
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Score box (right side)
                              SizedBox(
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
                            ],
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

  Future<void> _confirmDeleteFeedback(
    Map<String, dynamic> feedback,
    BuildContext dialogContext,
  ) async {
    final feedbackId = feedback['id'] as String?;
    final candidateName = feedback['candidateName'] ?? 'לא ידוע';

    if (feedbackId == null || feedbackId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('שגיאה: לא ניתן למחוק משוב ללא מזהה'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משוב'),
          content: Text(
            'האם למחוק את המשוב של "$candidateName" לצמיתות?\n\nפעולה זו אינה ניתנת לשחזור.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete the document from Firestore
      await FirebaseFirestore.instance
          .collection('instructor_course_evaluations')
          .doc(feedbackId)
          .delete();

      // Remove from local list
      setState(() {
        _feedbacks.removeWhere((f) => f['id'] == feedbackId);
      });

      // Close details dialog if open
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('המשוב נמחק'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error deleting feedback: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה במחיקת משוב: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showFeedbackDetails(Map<String, dynamic> feedback) {
    final candidateName = feedback['candidateName'] ?? 'לא ידוע';
    final candidateNumber = feedback['candidateNumber'] as int?;
    final instructorName = feedback['instructorName'] ?? 'לא ידוע';
    final command = feedback['command'] ?? '';
    final brigade = feedback['brigade'] ?? '';
    final averageScore = feedback['averageScore'] ?? 0.0;
    final scores = feedback['scores'] as Map<String, dynamic>? ?? {};
    final isAdmin = currentUser?.role == 'Admin';

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
                _buildScoreRow(
                  'בוחן רמה',
                  scores['levelTest'],
                  'levelTest',
                  feedback,
                ),
                _buildScoreRow(
                  'הדרכה טובה',
                  scores['goodInstruction'],
                  'goodInstruction',
                  feedback,
                ),
                _buildScoreRow(
                  'הדרכת מבנה',
                  scores['structureInstruction'],
                  'structureInstruction',
                  feedback,
                ),
                _buildScoreRow(
                  'יבשים',
                  scores['dryPractice'],
                  'dryPractice',
                  feedback,
                ),
                _buildScoreRow(
                  'תרגיל הפתעה',
                  scores['surpriseExercise'],
                  'surpriseExercise',
                  feedback,
                ),
                const Divider(),
                _buildDetailRow(
                  'ממוצע',
                  averageScore.toStringAsFixed(2),
                  isHighlight: true,
                ),
                const SizedBox(height: 8),
                // Percentage row
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'אחוז הצלחה:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${((averageScore / 5.0) * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: averageScore > 3.6 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Admin-only delete button
            if (isAdmin)
              TextButton.icon(
                onPressed: () => _confirmDeleteFeedback(feedback, ctx),
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('מחק'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
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

  Widget _buildScoreRow(
    String label,
    dynamic score, [
    String? scoreKey,
    Map<String, dynamic>? feedback,
  ]) {
    // Extract level test details if this is the level test row
    int? levelTestHits;
    double? levelTestTimeSeconds;
    if (scoreKey == 'levelTest' && feedback != null) {
      levelTestHits = feedback['levelTestHits'] as int?;
      levelTestTimeSeconds = feedback['levelTestTimeSeconds'] as double?;
    }
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

    // Build additional details for level test (hits and time)
    String prefix = '';
    if (levelTestHits != null || levelTestTimeSeconds != null) {
      final List<String> parts = [];

      // תחילה הזמן (תמיד עם נקודה עשרונית)
      if (levelTestTimeSeconds != null) {
        parts.add('${levelTestTimeSeconds.toStringAsFixed(1)} שנ\'');
      }

      // אחר כך הפגיעות
      if (levelTestHits != null) {
        parts.add('$levelTestHits פג\'');
      }

      // בניית הקידומת: זמן | פגיעות •
      if (parts.isNotEmpty) {
        prefix = '${parts.join(' | ')} • ';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '$prefix$displayValue',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
      ),
    );
  }
}
