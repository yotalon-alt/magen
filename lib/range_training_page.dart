import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart'; // for currentUser and golanSettlements
import 'widgets/standard_back_button.dart';

/// מסך מטווח עם טבלה דינמית
class RangeTrainingPage extends StatefulWidget {
  final String rangeType; // 'קצרים' / 'ארוכים' / 'הפתעה'
  final String? feedbackId; // optional: edit an existing temporary feedback
  final String mode; // 'range' or 'surprise' - determines UI behavior

  const RangeTrainingPage({
    super.key,
    required this.rangeType,
    this.feedbackId,
    this.mode = 'range', // default to range mode
  });

  @override
  State<RangeTrainingPage> createState() => _RangeTrainingPageState();
}

class _RangeTrainingPageState extends State<RangeTrainingPage> {
  // רשימת מקצים קבועה (range mode)
  static const List<String> availableStations = [
    'הרמות',
    'שלשות',
    'UP עד UP',
    'מעצור גמר',
    'מעצור שני',
    'מעבר רחוקות',
    'מעבר קרובות',
    'מניפה',
    'ירי למטרה הישגית',
    'עמידה כריעה 50 מטר',
    'עמידה כריעה 100 מטר',
    'עמידה כריעה 150 מטר',
    'בוחן רמה',
    'מקצה ידני',
  ];

  // רשימת עקרונות קבועה (surprise mode)
  static const List<String> availablePrinciples = [
    'קשר עין',
    'בחירת ציר התקדמות',
    'איום עיקרי ואיום משני',
    'קצב אש ומרחק',
    'ירי בטוח בתוך קהל',
    'וידוא ניטרול',
    'זיהוי והדחה',
    'רמת ביצוע',
  ];

  String? selectedSettlement;
  String instructorName = '';
  int attendeesCount = 0;
  late TextEditingController _attendeesCountController;

  late String _rangeType;

  // Dynamic labels based on mode
  String get _itemLabel => widget.mode == 'surprise' ? 'עיקרון' : 'מקצה';
  String get _itemsLabel => widget.mode == 'surprise' ? 'עקרונות' : 'מקצים';
  String get _addItemLabel =>
      widget.mode == 'surprise' ? 'הוסף עיקרון' : 'הוסף מקצה';

  String _settlementDisplayText = '';

  // רשימת מקצים - כל מקצה מכיל שם + מספר כדורים
  List<RangeStation> stations = [];

  // רשימת חניכים - כל חניך מכיל שם + פגיעות למקצה
  List<Trainee> trainees = [];
  // sequential numbers for trainees (editable but reset on list changes)
  List<int> traineeNumbers = [];

  // editing document id stored in state so we can create/update temporary docs
  String? _editingFeedbackId;

  bool _isSaving = false;
  // הייצוא יתבצע מדף המשובים בלבד

  @override
  void initState() {
    super.initState();
    instructorName = currentUser?.name ?? '';
    _settlementDisplayText = selectedSettlement ?? '';
    _attendeesCountController = TextEditingController(
      text: attendeesCount.toString(),
    );
    // מקצה ברירת מחדל אחד
    stations.add(RangeStation(name: '', bulletsCount: 0));
    _rangeType = widget.rangeType;
    // track editing id and load existing temporary if provided
    _editingFeedbackId = widget.feedbackId;
    if (_editingFeedbackId != null) {
      _loadExistingTemporaryFeedback(_editingFeedbackId!);
    }
  }

  @override
  void dispose() {
    // NO AUTOSAVE - user must explicitly click Temporary Save button
    _attendeesCountController.dispose();
    super.dispose();
  }

  void _openSettlementSelectorSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.blueGrey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: const [
                    Icon(Icons.location_city, color: Colors.white70),
                    SizedBox(width: 8),
                    Text(
                      'בחר יישוב',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: ListView.separated(
                    itemCount: golanSettlements.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = golanSettlements[i];
                      return ListTile(
                        title: Text(
                          s,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          setState(() {
                            selectedSettlement = s;
                            _settlementDisplayText = s;
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateAttendeesCount(int count) {
    setState(() {
      attendeesCount = count;

      // יצירת רשימת חניכים לפי הכמות
      if (count > trainees.length) {
        // הוספת חניכים
        for (int i = trainees.length; i < count; i++) {
          trainees.add(Trainee(name: '', hits: {}));
          traineeNumbers.add(i + 1);
        }
        // NO AUTOSAVE - user must explicitly save
      } else if (count < trainees.length) {
        // הסרת חניכים
        trainees = trainees.sublist(0, count);
        traineeNumbers = List<int>.generate(trainees.length, (i) => i + 1);
        // NO AUTOSAVE - user must explicitly save
      }
    });
  }

  void _addStation() {
    setState(() {
      stations.add(
        RangeStation(
          name: '',
          bulletsCount: 0,
          timeSeconds: null,
          hits: null,
          isManual: false,
          isLevelTester: false,
          selectedRubrics: ['זמן', 'פגיעות'],
        ),
      );
    });
  }

  void _removeStation(int index) {
    if (stations.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('חייב להיות לפחות $_itemLabel אחד')),
      );
      return;
    }

    setState(() {
      // מחיקת המקצה מכל החניכים
      for (var trainee in trainees) {
        trainee.hits.remove(index);
        // עדכון אינדקסים של מקצים שאחריו
        final updatedHits = <int, int>{};
        trainee.hits.forEach((key, value) {
          if (key > index) {
            updatedHits[key - 1] = value;
          } else {
            updatedHits[key] = value;
          }
        });
        trainee.hits = updatedHits;
      }

      stations.removeAt(index);
    });
  }

  int _getTraineeTotalHits(int traineeIndex) {
    if (traineeIndex >= trainees.length) return 0;

    int total = 0;
    trainees[traineeIndex].hits.forEach((stationIndex, hits) {
      total += hits;
    });
    return total;
  }

  int _getTotalBullets() {
    int total = 0;
    for (var station in stations) {
      total += station.bulletsCount;
    }
    return total;
  }

  // Calculate total points for a trainee (surprise mode only)
  // Sum of all filled principle scores
  int _getTraineeTotalPoints(int traineeIndex) {
    if (traineeIndex >= trainees.length) return 0;
    if (widget.mode != 'surprise') return 0;

    int total = 0;
    trainees[traineeIndex].hits.forEach((stationIndex, score) {
      if (score > 0) {
        total += score;
      }
    });
    return total;
  }

  // Calculate average points for a trainee (surprise mode only)
  // Average of filled principle scores (ignores empty/0 scores)
  double _getTraineeAveragePoints(int traineeIndex) {
    if (traineeIndex >= trainees.length) return 0.0;
    if (widget.mode != 'surprise') return 0.0;

    int total = 0;
    int count = 0;
    trainees[traineeIndex].hits.forEach((stationIndex, score) {
      if (score > 0) {
        total += score;
        count++;
      }
    });
    return count > 0 ? total / count : 0.0;
  }

  // ⚠️ פונקציות הייצוא הוסרו - הייצוא יבוצע רק מדף המשובים (Admin בלבד)
  // ייצוא לקובץ XLSX מקומי יתבוצע על משובים שכבר נשמרו בלבד

  Future<void> _saveToFirestore() async {
    // בדיקות תקינות
    if (selectedSettlement == null || selectedSettlement!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא בחר יישוב/מחלקה')));
      return;
    }

    if (attendeesCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן כמות נוכחים')));
      return;
    }

    // וידוא שכל המקצים/עקרונות מוגדרים
    for (int i = 0; i < stations.length; i++) {
      if (stations[i].name.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('אנא הזן שם ל$_itemLabel ${i + 1}')),
        );
        return;
      }

      // בדיקת תקינות לפי סוג המקצה (range mode only)
      if (widget.mode == 'range' && stations[i].isLevelTester) {
        // בוחן רמה - חייב זמן ופגיעות
        if (stations[i].timeSeconds == null || stations[i].timeSeconds! <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('אנא הזן זמן תקין למקצה ${i + 1} (בוחן רמה)'),
            ),
          );
          return;
        }
        if (stations[i].hits == null || stations[i].hits! < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('אנא הזן פגיעות תקינות למקצה ${i + 1} (בוחן רמה)'),
            ),
          );
          return;
        }
      } else if (widget.mode == 'range') {
        // מקצים רגילים - חייב כדורים (range mode only)
        if (stations[i].bulletsCount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('אנא הזן מספר כדורים ל$_itemLabel ${i + 1}'),
            ),
          );
          return;
        }
      }
      // Surprise mode: no bullets validation needed
    }

    // וידוא שכל החניכים מוגדרים
    for (int i = 0; i < trainees.length; i++) {
      if (trainees[i].name.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('אנא הזן שם לחניך ${i + 1}')));
        return;
      }
    }

    // ========== SAVE_CLICK DIAGNOSTICS ==========
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final email = FirebaseAuth.instance.currentUser?.email;
    final saveType = widget.mode == 'surprise'
        ? 'surprise'
        : (_rangeType == 'קצרים' ? 'range_short' : 'range_long');

    debugPrint('\n========== SAVE_CLICK ==========');
    debugPrint('SAVE_CLICK type=$saveType mode=${widget.mode}');
    debugPrint('SAVE_CLICK uid=$uid email=$email');
    debugPrint('SAVE_CLICK platform=${kIsWeb ? "web" : "mobile"}');
    debugPrint(
      'SAVE_CLICK trainees=${trainees.length} stations=${stations.length}',
    );
    debugPrint('================================\n');

    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('שגיאה: משתמש לא מחובר'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // הכנת הנתונים לשמירה
      final String subFolder = widget.mode == 'surprise'
          ? 'תרגילי הפתעה'
          : (_rangeType == 'קצרים' ? 'דיווח קצר' : 'דיווח רחוק');

      // Build trainees data - only include non-empty fields
      final List<Map<String, dynamic>> traineesData = [];
      for (int i = 0; i < trainees.length; i++) {
        final trainee = trainees[i];
        if (trainee.name.trim().isEmpty) continue; // Skip empty names

        // Build hits map, only include non-zero values
        final Map<String, int> hitsMap = {};
        trainee.hits.forEach((stationIdx, hits) {
          if (hits > 0) {
            hitsMap['station_$stationIdx'] = hits;
          }
        });

        traineesData.add({
          'name': trainee.name.trim(),
          'hits': hitsMap,
          'totalHits': _getTraineeTotalHits(i),
          'number': traineeNumbers.length > i ? traineeNumbers[i] : i + 1,
        });
      }

      final Map<String, dynamic> baseData = {
        'instructorName': instructorName,
        'instructorId': uid,
        'instructorEmail': email,
        'instructorRole': currentUser?.role ?? 'Instructor',
        'instructorUsername': currentUser?.username ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'rangeType': _rangeType,
        'settlement': selectedSettlement,
        'attendeesCount': attendeesCount,
        'stations': stations.map((s) => s.toJson()).toList(),
        'trainees': traineesData,
        'status': 'final',
      };

      // ========== SEPARATE COLLECTIONS FOR SURPRISE VS RANGE ==========
      DocumentReference? docRef;
      String collectionPath;
      String successMessage;

      if (widget.mode == 'surprise') {
        // SURPRISE DRILLS: Save to dedicated collection
        collectionPath = 'feedbacks';
        final Map<String, dynamic> surpriseData = {
          ...baseData,
          // Required fields for Surprise Drills
          'module': 'surprise_drill',
          'type': 'surprise_exercise',
          'isTemporary': false,
          'exercise': 'תרגילי הפתעה',
          'folder': 'משוב תרגילי הפתעה',
          'name': selectedSettlement ?? '',
          'role': 'תרגיל הפתעה',
          'scores': {},
          'notes': {'general': subFolder},
          'criteriaList': [],
        };

        debugPrint('\n========== FINAL SAVE: SURPRISE DRILL ==========');
        debugPrint('SAVE: collection=$collectionPath');
        debugPrint('SAVE: module=surprise_drill');
        debugPrint('SAVE: type=surprise_exercise');
        debugPrint('SAVE: isTemporary=false');
        debugPrint('SAVE: folder=משוב תרגילי הפתעה');

        if (widget.feedbackId != null && widget.feedbackId!.isNotEmpty) {
          docRef = FirebaseFirestore.instance
              .collection(collectionPath)
              .doc(widget.feedbackId);
          debugPrint('SAVE: Updating existing doc=${docRef.path}');
          await docRef.update(surpriseData);
        } else {
          debugPrint('SAVE: Creating NEW document in $collectionPath');
          docRef = await FirebaseFirestore.instance
              .collection(collectionPath)
              .add(surpriseData);
          debugPrint('SAVE: New doc created=${docRef.path}');
        }

        // Delete temporary draft if it exists
        if (_editingFeedbackId != null && _editingFeedbackId!.isNotEmpty) {
          try {
            debugPrint('SAVE: Deleting temporary draft: $_editingFeedbackId');
            await FirebaseFirestore.instance
                .collection('feedbacks')
                .doc(_editingFeedbackId)
                .delete();
            debugPrint('✅ SAVE: Temporary draft deleted successfully');
          } catch (e) {
            debugPrint('⚠️ SAVE: Failed to delete draft: $e');
          }
        }

        debugPrint('===============================================\n');
        successMessage = '✅ המשוב נשמר בהצלחה - תרגילי הפתעה';
      } else {
        // SHOOTING RANGES: Save to dedicated collection
        collectionPath = 'feedbacks';
        final Map<String, dynamic> rangeData = {
          ...baseData,
          // Required fields for Shooting Ranges
          'module': 'shooting_ranges',
          'type': 'range_feedback',
          'isTemporary': false,
          'exercise': 'מטווחים',
          'folder': 'מטווחי ירי',
          'rangeSubFolder': subFolder,
          'name': selectedSettlement ?? '',
          'role': 'מטווח',
          'scores': {},
          'notes': {'general': subFolder},
          'criteriaList': [],
        };

        debugPrint('\n========== FINAL SAVE: SHOOTING RANGE ==========');
        debugPrint('SAVE: collection=$collectionPath');
        debugPrint('SAVE: module=shooting_ranges');
        debugPrint('SAVE: type=range_feedback');
        debugPrint('SAVE: rangeType=$_rangeType');
        debugPrint('SAVE: isTemporary=false');
        debugPrint('SAVE: folder=מטווחי ירי');

        if (widget.feedbackId != null && widget.feedbackId!.isNotEmpty) {
          docRef = FirebaseFirestore.instance
              .collection(collectionPath)
              .doc(widget.feedbackId);
          debugPrint('SAVE: Updating existing doc=${docRef.path}');
          await docRef.update(rangeData);
        } else {
          debugPrint('SAVE: Creating NEW document in $collectionPath');
          docRef = await FirebaseFirestore.instance
              .collection(collectionPath)
              .add(rangeData);
          debugPrint('SAVE: New doc created=${docRef.path}');
        }

        // Delete temporary draft if it exists
        if (_editingFeedbackId != null && _editingFeedbackId!.isNotEmpty) {
          try {
            debugPrint('SAVE: Deleting temporary draft: $_editingFeedbackId');
            await FirebaseFirestore.instance
                .collection('feedbacks')
                .doc(_editingFeedbackId)
                .delete();
            debugPrint('✅ SAVE: Temporary draft deleted successfully');
          } catch (e) {
            debugPrint('⚠️ SAVE: Failed to delete draft: $e');
          }
        }

        debugPrint('===============================================\n');
        successMessage = '✅ המשוב נשמר בהצלחה - מטווחים';
      }

      debugPrint('SAVE: Write completed, path=${docRef.path}');

      // ========== IMMEDIATE READBACK VERIFICATION ==========
      try {
        final snap = await docRef.get();
        debugPrint('SAVE_READBACK: exists=${snap.exists}');
        if (snap.exists) {
          final savedData = snap.data() as Map<String, dynamic>?;
          final savedTrainees = savedData?['trainees'] as List?;
          debugPrint(
            'SAVE_READBACK: traineesCount=${savedTrainees?.length ?? 0}',
          );
          debugPrint('✅ SAVE VERIFIED: Document persisted successfully');
        } else {
          debugPrint('❌ SAVE WARNING: Document not found on readback!');
        }
      } catch (readbackError) {
        debugPrint('⚠️ SAVE: Readback verification failed: $readbackError');
      }

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate back to appropriate feedbacks list
      // Since we're using nested navigation, just pop back
      Navigator.pop(context);

      debugPrint('SAVE: Navigation complete');
      debugPrint('========== SAVE END ==========\n');
    } catch (e, stackTrace) {
      debugPrint('❌ ========== SAVE ERROR ==========');
      debugPrint('SAVE_ERROR: $e');
      debugPrint('SAVE_ERROR_STACK: $stackTrace');
      debugPrint('===================================\n');

      if (!mounted) return;

      // Show error with actual error message (don't swallow it)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בשמירה: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );

      // Rethrow to ensure error is not swallowed
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveTemporarily() async {
    // ========== ATOMIC TEMPORARY SAVE ==========
    // ONLY write path for temp saves - NO autosave, NO dispose save
    // HARD VALIDATION + READ-BACK VERIFICATION + LOUD FAILURE

    // Set loading state
    if (mounted) {
      setState(() => _isSaving = true);
    }

    try {
      debugPrint('\n========== TEMP_SAVE_ATOMIC START ==========');

      // Step 1: Force UI commit by unfocusing ALL fields
      FocusManager.instance.primaryFocus?.unfocus();
      await Future.delayed(const Duration(milliseconds: 80));
      debugPrint('TEMP_SAVE: UI committed (unfocused)');

      debugPrint('TEMP_SAVE: attendeesCount=$attendeesCount');
      debugPrint('TEMP_SAVE: trainees.length=${trainees.length}');
      debugPrint('TEMP_SAVE: stations.length=${stations.length}');

      // Step 2: Get user ID
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        debugPrint('❌ TEMP_SAVE: No user ID');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('שגיאה קריטית'),
              content: const Text('משתמש לא מחובר - לא ניתן לשמור'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('הבנתי'),
                ),
              ],
            ),
          );
        }
        throw Exception('TEMP_SAVE_FAIL: No user ID');
      }

      // Step 3: Build payload by serializing UI state directly
      final String moduleType = widget.mode == 'surprise'
          ? 'surprise_drill'
          : 'shooting_ranges';
      final String docId =
          '${uid}_${moduleType}_${_rangeType.replaceAll(' ', '_')}';
      _editingFeedbackId = docId;

      debugPrint('TEMP_SAVE: module=$moduleType docId=$docId');
      debugPrint(
        'TEMP_SAVE: rangeType=$_rangeType settlement=$selectedSettlement',
      );

      // Serialize trainees from current UI state
      final List<Map<String, dynamic>> traineesPayload = [];
      for (int i = 0; i < trainees.length; i++) {
        final t = trainees[i];
        final hitsMap = <String, int>{};

        // Serialize hits (station_index -> value)
        for (final entry in t.hits.entries) {
          final stationIdx = entry.key;
          final value = entry.value;
          if (value != 0) {
            hitsMap['station_$stationIdx'] = value;
          }
        }

        final payload = {'index': i, 'name': t.name.trim(), 'values': hitsMap};

        traineesPayload.add(payload);
        debugPrint(
          'TEMP_SAVE: trainee[$i] name="${payload['name']}" values=${payload['values']}',
        );
      }

      // Step 4: HARD VALIDATION - fail loudly if data is invalid
      debugPrint('TEMP_SAVE: VALIDATION START');

      // Assert: trainees list not empty
      if (traineesPayload.isEmpty) {
        debugPrint('❌ VALIDATION FAILED: No trainees');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('שגיאת ולידציה'),
              content: const Text('אין חניכים לשמירה'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('הבנתי'),
                ),
              ],
            ),
          );
        }
        throw Exception('TEMP_SAVE_VALIDATION_FAIL: trainees.length == 0');
      }

      // Assert: at least one trainee has name AND values
      final hasValidData = traineesPayload.any((t) {
        final name = (t['name'] as String?) ?? '';
        final values = (t['values'] as Map?) ?? {};
        return name.isNotEmpty && values.isNotEmpty;
      });

      if (!hasValidData) {
        debugPrint('❌ VALIDATION FAILED: No trainee with name AND values');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('שגיאת ולידציה'),
              content: const Text('חייב להיות לפחות חניך אחד עם שם וציונים'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('הבנתי'),
                ),
              ],
            ),
          );
        }
        throw Exception('TEMP_SAVE_VALIDATION_FAIL: No valid trainee data');
      }

      debugPrint(
        '✅ VALIDATION PASSED: trainees=${traineesPayload.length} hasValidData=true',
      );

      // Step 5: Build Firestore payload (MANDATORY schema)
      // CRITICAL: folder must match what RangeTempFeedbacksPage queries
      final String folderName = widget.mode == 'surprise'
          ? 'תרגילי הפתעה - משוב זמני'
          : 'מטווחים - משוב זמני';

      final Map<String, dynamic> payload = {
        'status': 'temporary',
        'module': moduleType,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(), // Required for orderBy query
        'trainees': traineesPayload,
        'instructorId': uid,
        'instructorName': instructorName,
        'rangeType': _rangeType,
        'settlement': selectedSettlement ?? '',
        'stations': stations.map((s) => s.toJson()).toList(),
        'attendeesCount': attendeesCount,
        'isTemporary': true,
        'folder': folderName,
      };

      debugPrint('TEMP_SAVE: payload keys=${payload.keys.toList()}');

      // Step 6: Write to Firestore (ONCE)
      final docRef = FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(docId);
      debugPrint('TEMP_SAVE: Writing to ${docRef.path}');

      try {
        await docRef.set(
          payload,
          SetOptions(merge: false),
        ); // Overwrite completely
        debugPrint('✅ TEMP_SAVE: Write complete');
      } catch (e, st) {
        debugPrint('❌ TEMP_SAVE_WRITE_FAIL: $e');
        debugPrint('Stack: $st');
        if (mounted) {
          // Show both dialog AND SnackBar for visibility
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ שגיאה בשמירה: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('שגיאת כתיבה'),
              content: Text('נכשל בכתיבה לFirestore: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('הבנתי'),
                ),
              ],
            ),
          );
        }
        throw Exception('TEMP_SAVE_WRITE_FAIL: $e');
      }

      // Step 7: READ-BACK VERIFICATION (MANDATORY)
      debugPrint('TEMP_SAVE: Read-back verification...');
      final DocumentSnapshot verifySnap;
      try {
        verifySnap = await docRef.get();
      } catch (e) {
        debugPrint('❌ TEMP_SAVE_READBACK_FAIL: $e');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('שגיאת אימות'),
              content: Text('נכשל בקריאה חוזרת: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('הבנתי'),
                ),
              ],
            ),
          );
        }
        throw Exception('TEMP_SAVE_READBACK_FAIL: $e');
      }

      if (!verifySnap.exists) {
        debugPrint('❌ VERIFY_FAIL: Document does not exist after write');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const AlertDialog(
              title: Text('שגיאת אימות'),
              content: Text('המסמך לא נמצא אחרי השמירה'),
              actions: [TextButton(onPressed: null, child: Text('הבנתי'))],
            ),
          );
        }
        throw Exception('TEMP_SAVE_VERIFY_FAIL: Document not found');
      }

      final verifyData = verifySnap.data() as Map<String, dynamic>?;
      if (verifyData == null) {
        debugPrint('❌ VERIFY_FAIL: Document data is null');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const AlertDialog(
              title: Text('שגיאת אימות'),
              content: Text('נתוני המסמך ריקים'),
              actions: [TextButton(onPressed: null, child: Text('הבנתי'))],
            ),
          );
        }
        throw Exception('TEMP_SAVE_VERIFY_FAIL: Data is null');
      }

      // Verify trainees array exists and has data
      final verifyTrainees = verifyData['trainees'] as List?;
      if (verifyTrainees == null || verifyTrainees.isEmpty) {
        debugPrint('❌ VERIFY_FAIL: trainees missing or empty');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const AlertDialog(
              title: Text('שגיאת אימות'),
              content: Text('נתוני חניכים חסרים'),
              actions: [TextButton(onPressed: null, child: Text('הבנתי'))],
            ),
          );
        }
        throw Exception('TEMP_SAVE_VERIFY_FAIL: trainees missing');
      }

      // Verify count matches
      if (verifyTrainees.length != traineesPayload.length) {
        debugPrint(
          '❌ VERIFY_FAIL: Count mismatch: ${verifyTrainees.length} != ${traineesPayload.length}',
        );
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('שגיאת אימות'),
              content: Text(
                'מספר חניכים לא תואם: ${verifyTrainees.length} != ${traineesPayload.length}',
              ),
              actions: const [
                TextButton(onPressed: null, child: Text('הבנתי')),
              ],
            ),
          );
        }
        throw Exception('TEMP_SAVE_VERIFY_FAIL: Count mismatch');
      }

      // Verify at least one trainee has values map with numeric data
      final hasNumericData = verifyTrainees.any((t) {
        final values = (t as Map?)?['values'] as Map?;
        return values != null && values.isNotEmpty;
      });

      if (!hasNumericData) {
        debugPrint('❌ VERIFY_FAIL: No numeric data in trainees');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const AlertDialog(
              title: Text('שגיאת אימות'),
              content: Text('חסרים נתונים נומריים'),
              actions: [TextButton(onPressed: null, child: Text('הבנתי'))],
            ),
          );
        }
        throw Exception('TEMP_SAVE_VERIFY_FAIL: No numeric data');
      }

      debugPrint(
        '✅ VERIFY_OK: trainees=${verifyTrainees.length} valuesPresent=true',
      );

      // Step 8: Rehydrate UI from verified Firestore data
      debugPrint('TEMP_SAVE: Rehydrating UI from Firestore data');

      // Clear and rebuild trainees from verified data
      trainees.clear();
      traineeNumbers.clear();

      for (final traineeData in verifyTrainees) {
        final tMap = traineeData as Map<String, dynamic>;
        final name = (tMap['name'] as String?) ?? '';
        final idx = (tMap['index'] as num?)?.toInt() ?? 0;
        final values = (tMap['values'] as Map<String, dynamic>?) ?? {};

        // Rebuild hits map from values
        final hits = <int, int>{};
        for (final entry in values.entries) {
          if (entry.key.startsWith('station_')) {
            final stationIdx = int.tryParse(
              entry.key.replaceFirst('station_', ''),
            );
            final value = (entry.value as num?)?.toInt() ?? 0;
            if (stationIdx != null) {
              hits[stationIdx] = value;
            }
          }
        }

        trainees.add(Trainee(name: name, hits: hits));
        traineeNumbers.add(idx + 1);
        debugPrint(
          'TEMP_SAVE_REHYDRATE: trainee[$idx] name="$name" hits=$hits',
        );
      }

      if (mounted) {
        setState(() {});
      }

      debugPrint('TEMP_SAVE_OK trainees=${trainees.length} valuesPresent=true');
      debugPrint(
        'RANGE_DRAFT_OK path=${docRef.path} trainees=${trainees.length}',
      );
      debugPrint('   folder=${payload['folder']}');
      debugPrint('   module=${payload['module']}');
      debugPrint('   rangeType=${payload['rangeType']}');
      debugPrint('   settlement=${payload['settlement']}');
      debugPrint('   isTemporary=${payload['isTemporary']}');
      debugPrint('   status=${payload['status']}');
      debugPrint('========== TEMP_SAVE_ATOMIC END ==========\n');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ שמירה זמנית הושלמה\nנתיב: ${docRef.path}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Catch any uncaught errors
      debugPrint('❌ TEMP_SAVE: Uncaught error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      rethrow;
    } finally {
      // Always reset loading state
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _loadExistingTemporaryFeedback(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final email = FirebaseAuth.instance.currentUser?.email;
    debugPrint('\n========== TEMP_LOAD START ==========');
    debugPrint('TEMP_LOAD: user=$uid email=$email');
    debugPrint('TEMP_LOAD: path=feedbacks/$id');
    debugPrint('TEMP_LOAD: module=${widget.mode} rangeType=$_rangeType');
    debugPrint('TEMP_LOAD: using direct docRef.get() (no query)');

    try {
      final docRef = FirebaseFirestore.instance.collection('feedbacks').doc(id);
      debugPrint('TEMP_LOAD: fullPath=${docRef.path}');

      final doc = await docRef.get();

      debugPrint('TEMP_LOAD: got document, exists=${doc.exists}');

      if (!doc.exists) {
        debugPrint('⚠️ TEMP_LOAD: Document does not exist: $id');
        debugPrint('========== TEMP_LOAD END (NOT FOUND) ==========\n');
        return;
      }

      final data = doc.data();
      if (data == null) {
        debugPrint('⚠️ TEMP_LOAD: Document data is null: $id');
        debugPrint('========== TEMP_LOAD END (NULL DATA) ==========\n');
        return;
      }

      final rawTrainees = data['trainees'] as List?;
      final rawStations = data['stations'] as List?;
      final rawSettlement = data['settlement'] as String?;
      final rawAttendeesCount = data['attendeesCount'] as num?;
      debugPrint('TEMP_LOAD: doc.id=$id');
      debugPrint('TEMP_LOAD: dataKeys=${data.keys.toList()}');
      debugPrint('TEMP_LOAD: rawTrainees.length=${rawTrainees?.length ?? -1}');
      debugPrint('TEMP_LOAD: rawStations.length=${rawStations?.length ?? -1}');
      debugPrint('TEMP_LOAD: settlement=$rawSettlement');
      debugPrint('TEMP_LOAD: attendeesCount=$rawAttendeesCount');
      if (rawTrainees != null && rawTrainees.isNotEmpty) {
        debugPrint('TEMP_LOAD: firstTraineeRaw=${rawTrainees[0]}');
      }

      debugPrint('TEMP_LOAD: Parsing data...');
      setState(() {
        selectedSettlement =
            data['settlement'] as String? ?? selectedSettlement;
        _settlementDisplayText = selectedSettlement ?? '';
        attendeesCount =
            (data['attendeesCount'] as num?)?.toInt() ?? attendeesCount;
        // ✅ Update controller to reflect loaded value
        _attendeesCountController.text = attendeesCount.toString();
        debugPrint('   Loaded attendeesCount: $attendeesCount');
        instructorName = data['instructorName'] as String? ?? instructorName;

        stations =
            (data['stations'] as List?)?.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              return RangeStation(
                name: m['name']?.toString() ?? '',
                bulletsCount: (m['bulletsCount'] as num?)?.toInt() ?? 0,
                timeSeconds: (m['timeSeconds'] as num?)?.toInt(),
                hits: (m['hits'] as num?)?.toInt(),
                isManual: m['isManual'] as bool? ?? false,
                isLevelTester: m['isLevelTester'] as bool? ?? false,
                selectedRubrics:
                    (m['selectedRubrics'] as List?)
                        ?.map((x) => x.toString())
                        .toList() ??
                    ['זמן', 'פגיעות'],
              );
            }).toList() ??
            stations;

        trainees =
            (data['trainees'] as List?)?.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              final name = m['name']?.toString() ?? '';
              final hitsRaw = m['hits'] as Map? ?? {};
              final hits = <int, int>{};
              hitsRaw.forEach((k, v) {
                // keys may be 'station_0' or int
                if (k is String && k.startsWith('station_')) {
                  final idx = int.tryParse(k.replaceFirst('station_', '')) ?? 0;
                  hits[idx] = (v as num?)?.toInt() ?? 0;
                } else if (k is int) {
                  hits[k] = (v as num?)?.toInt() ?? 0;
                }
              });
              return Trainee(name: name, hits: hits);
            }).toList() ??
            trainees;

        debugPrint('TEMP_LOAD: Parsed ${trainees.length} trainees into model');
        for (int i = 0; i < trainees.length && i < 3; i++) {
          debugPrint(
            'TEMP_LOAD:   Trainee $i: name="${trainees[i].name}", hits=${trainees[i].hits}',
          );
        }

        // rebuild sequential numbers according to loaded trainees
        traineeNumbers = List<int>.generate(trainees.length, (i) => i + 1);

        debugPrint('TEMP_LOAD: ✅ Load complete');
        debugPrint('TEMP_LOAD:   attendeesCount=$attendeesCount');
        debugPrint('TEMP_LOAD:   trainees.length=${trainees.length}');
        debugPrint('TEMP_LOAD:   stations.length=${stations.length}');
        debugPrint('========== TEMP_LOAD END (SUCCESS) ==========\n');
      });
    } catch (e, stackTrace) {
      debugPrint('❌ ========== TEMP_LOAD ERROR ==========');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      debugPrint('========================================\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    // קביעת שם המטווח/תרגיל להצגה
    final String rangeTitle = widget.mode == 'surprise'
        ? 'תרגילי הפתעה'
        : (_rangeType == 'קצרים' ? 'טווח קצר' : 'טווח רחוק');

    return Scaffold(
      appBar: AppBar(
        title: Text(rangeTitle),
        leading: const StandardBackButton(),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // כותרת
              Text(
                rangeTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // יישוב/מחלקה
              TextField(
                controller: TextEditingController(text: _settlementDisplayText),
                decoration: InputDecoration(
                  labelText: 'יישוב / מחלקה',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                readOnly: true,
                onTap: _openSettlementSelectorSheet,
              ),
              const SizedBox(height: 16),

              // מדריך
              TextField(
                controller: TextEditingController(text: instructorName)
                  ..selection = TextSelection.collapsed(
                    offset: instructorName.length,
                  ),
                decoration: const InputDecoration(
                  labelText: 'מדריך',
                  border: OutlineInputBorder(),
                ),
                enabled: false,
              ),
              const SizedBox(height: 16),

              // כמות נוכחים
              TextField(
                controller: _attendeesCountController,
                decoration: const InputDecoration(
                  labelText: 'כמות נוכחים',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final count = int.tryParse(v) ?? 0;
                  _updateAttendeesCount(count);
                },
              ),
              const SizedBox(height: 32),

              // כותרת מקצים/עקרונות
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _itemsLabel,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addStation,
                    icon: const Icon(Icons.add),
                    label: Text(_addItemLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // רשימת מקצים
              ...stations.asMap().entries.map((entry) {
                final index = entry.key;
                final station = entry.value;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '$_itemLabel ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeStation(index),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // שדה שם המקצה - דרופדאון או טקסט לפי סוג
                        if (station.isManual) ...[
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'שם המקצה (ידני)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              setState(() {
                                station.name = v;
                              });
                            },
                          ),
                        ] else ...[
                          DropdownButtonFormField<String>(
                            initialValue: station.name.isEmpty
                                ? null
                                : station.name,
                            hint: Text(
                              widget.mode == 'surprise'
                                  ? 'בחר עיקרון'
                                  : 'בחר מקצה',
                            ),
                            decoration: InputDecoration(
                              labelText: widget.mode == 'surprise'
                                  ? 'שם העיקרון'
                                  : 'שם המקצה',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items:
                                (widget.mode == 'surprise'
                                        ? availablePrinciples
                                        : availableStations)
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) {
                              setState(() {
                                station.name = v ?? '';
                                // עדכון סוג המקצה לפי השם (range mode only)
                                if (widget.mode == 'range') {
                                  if (v == 'בוחן רמה') {
                                    station.isLevelTester = true;
                                    station.isManual = false;
                                  } else if (v == 'מקצה ידני') {
                                    station.isManual = true;
                                    station.isLevelTester = false;
                                  } else {
                                    station.isLevelTester = false;
                                    station.isManual = false;
                                  }
                                }
                              });
                              // NO AUTOSAVE - user must manually save
                            },
                          ),
                        ],
                        const SizedBox(height: 8),
                        // שדות לפי סוג המקצה
                        if (station.isLevelTester) ...[
                          // בוחן רמה - זמן ושניות
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(
                                    labelText: 'זמן (שניות)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (v) {
                                    setState(() {
                                      station.timeSeconds =
                                          int.tryParse(v) ?? 0;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(
                                    labelText: 'פגיעות',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (v) {
                                    setState(() {
                                      station.hits = int.tryParse(v) ?? 0;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ] else if (widget.mode == 'range') ...[
                          // מקצים רגילים - כדורים (range mode only)
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'מספר כדורים',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (v) {
                              setState(() {
                                station.bulletsCount = int.tryParse(v) ?? 0;
                              });
                            },
                          ),
                        ],
                        // Surprise mode: no bullets field needed
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 32),

              // טבלת חניכים מלאה לעריכה - מוצגת רק אם יש נוכחים
              if (attendeesCount > 0) ...[
                const Text(
                  'טבלת חניכים',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // טבלה דינמית
                _buildTraineesTable(),

                const SizedBox(height: 24),

                // TWO BUTTONS: Temporary Save and Finalize Save
                // Temporary Save button (validates and saves to temp)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveTemporarily,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blueGrey,
                    ),
                    child: _isSaving
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'שומר זמנית...',
                                style: TextStyle(fontSize: 18),
                              ),
                            ],
                          )
                        : Text(
                            widget.mode == 'surprise'
                                ? 'שמירה זמנית - תרגיל הפתעה'
                                : 'שמירה זמנית - מטווח',
                            style: const TextStyle(fontSize: 18),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // Finalize Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveToFirestore,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: _isSaving
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('שומר...', style: TextStyle(fontSize: 18)),
                            ],
                          )
                        : Text(
                            widget.mode == 'surprise'
                                ? 'שמירה סופית - תרגיל הפתעה'
                                : 'שמירה סופית - מטווח',
                            style: const TextStyle(fontSize: 18),
                          ),
                  ),
                ),

                // הערות למשתמש
                const SizedBox(height: 12),
                const Text(
                  'שמירה זמנית: שומר את הנתונים לטיוטה (עם אימות מלא). שמירה סופית: משלים את המשוב ושולח לארכיון.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'לייצוא לקובץ מקומי, עבור לדף המשובים ולחץ על המטווח השמור',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTraineesTable() {
    if (trainees.isEmpty) {
      return const Center(child: Text('אין חניכים להצגה'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          // Mobile layout: Horizontal scroll with sticky trainee names
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    widget.mode == 'surprise'
                        ? 'הזנת ציונים - החלק ימינה לגלילה'
                        : 'הזנת פגיעות - החלק ימינה לגלילה',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      // Frozen columns on the left: Number FIRST (appears RIGHT in RTL), then Name
                      SizedBox(
                        width: 80,
                        child: Column(
                          children: [
                            Container(
                              height: 60,
                              padding: const EdgeInsets.all(8.0),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                border: Border(
                                  right: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'מספר',
                                style: TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            // Compact square Number input fields (editable, sequential by default)
                            ...trainees.asMap().entries.map((entry) {
                              final idx = entry.key;
                              return Container(
                                height: 60,
                                padding: const EdgeInsets.all(4.0),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 44,
                                    height: 40,
                                    child: TextField(
                                      controller: TextEditingController(
                                        text: traineeNumbers.length > idx
                                            ? traineeNumbers[idx].toString()
                                            : '${idx + 1}',
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        hintText: '1',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: (v) {
                                        setState(() {
                                          final val =
                                              int.tryParse(v) ?? (idx + 1);
                                          if (traineeNumbers.length > idx) {
                                            traineeNumbers[idx] = val;
                                          } else {
                                            traineeNumbers = List<int>.generate(
                                              trainees.length,
                                              (i) => i + 1,
                                            );
                                            traineeNumbers[idx] = val;
                                          }
                                        });
                                        // NO AUTOSAVE - user must manually save
                                      },
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      // Second frozen column: Name (160px width)
                      SizedBox(
                        width: 160,
                        child: Column(
                          children: [
                            Container(
                              height: 60,
                              padding: const EdgeInsets.all(8.0),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                border: Border(
                                  right: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'Name',
                                style: TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            // Name input fields
                            ...trainees.asMap().entries.map((entry) {
                              final trainee = entry.value;
                              return Container(
                                height: 60,
                                padding: const EdgeInsets.all(4.0),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                ),
                                child: TextField(
                                  controller:
                                      TextEditingController(text: trainee.name)
                                        ..selection = TextSelection.collapsed(
                                          offset: trainee.name.length,
                                        ),
                                  decoration: const InputDecoration(
                                    hintText: 'שם חניך',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (v) {
                                    setState(() {
                                      trainee.name = v;
                                    });
                                    // NO AUTOSAVE - user must manually save
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      // Scrollable stations columns
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ...stations.asMap().entries.map((entry) {
                                final stationIndex = entry.key;
                                final station = entry.value;
                                return Container(
                                  width: 120,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      // Station header
                                      Container(
                                        height: 60,
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.blueGrey.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              station.name.isEmpty
                                                  ? '$_itemLabel ${stationIndex + 1}'
                                                  : station.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (widget.mode == 'range')
                                              Text(
                                                '(${station.bulletsCount})',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade600,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Trainee input fields for this station
                                      ...trainees.map((trainee) {
                                        return Container(
                                          height: 60,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: TextField(
                                            controller:
                                                TextEditingController(
                                                    text:
                                                        (trainee.hits[stationIndex] ??
                                                                0) ==
                                                            0
                                                        ? ''
                                                        : trainee
                                                              .hits[stationIndex]
                                                              .toString(),
                                                  )
                                                  ..selection =
                                                      TextSelection.collapsed(
                                                        offset:
                                                            (trainee.hits[stationIndex] ??
                                                                    0)
                                                                .toString()
                                                                .length,
                                                      ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                              hintText: '0',
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 8,
                                                  ),
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                            onChanged: (v) {
                                              final score =
                                                  int.tryParse(v) ?? 0;

                                              // Validation based on mode
                                              if (widget.mode == 'surprise') {
                                                // Surprise mode: 1-10 scale
                                                if (score < 0 || score > 10) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'ציון חייב להיות בין 1 ל-10',
                                                      ),
                                                      duration: Duration(
                                                        seconds: 1,
                                                      ),
                                                    ),
                                                  );
                                                  return;
                                                }
                                              } else {
                                                // Range mode: hits limited by bullets
                                                if (score >
                                                    station.bulletsCount) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'פגיעות לא יכולות לעלות על ${station.bulletsCount} כדורים',
                                                      ),
                                                      duration: const Duration(
                                                        seconds: 1,
                                                      ),
                                                    ),
                                                  );
                                                  return;
                                                }
                                              }
                                              setState(() {
                                                trainee.hits[stationIndex] =
                                                    score;
                                              });
                                              // NO AUTOSAVE - user must manually save
                                            },
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              }),
                              // Summary columns (conditional based on mode)
                              if (widget.mode == 'surprise') ...[
                                // Total Points column (Surprise mode)
                                Container(
                                  width: 100,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      // Header
                                      Container(
                                        height: 60,
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'סך הכל\nנקודות',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            color: Colors.blue,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      // Values
                                      ...trainees.asMap().entries.map((entry) {
                                        final traineeIndex = entry.key;
                                        final totalPoints =
                                            _getTraineeTotalPoints(
                                              traineeIndex,
                                            );
                                        return Container(
                                          height: 60,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            totalPoints.toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                              fontSize: 11,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                // Average Points column (Surprise mode)
                                Container(
                                  width: 80,
                                  color: Colors.transparent,
                                  child: Column(
                                    children: [
                                      // Header
                                      Container(
                                        height: 60,
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'ממוצע\nנקודות',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            color: Colors.green,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      // Values
                                      ...trainees.asMap().entries.map((entry) {
                                        final traineeIndex = entry.key;
                                        final avgPoints =
                                            _getTraineeAveragePoints(
                                              traineeIndex,
                                            );
                                        return Container(
                                          height: 60,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            avgPoints > 0
                                                ? avgPoints.toStringAsFixed(1)
                                                : '—',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: avgPoints >= 7
                                                  ? Colors.green
                                                  : avgPoints >= 5
                                                  ? Colors.orange
                                                  : Colors.red,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                // Bullets/Hits column (Range mode)
                                Container(
                                  width: 100,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      // Header
                                      Container(
                                        height: 60,
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'פגיעות/\nכדורים',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            color: Colors.blue,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      // Values
                                      ...trainees.asMap().entries.map((entry) {
                                        final traineeIndex = entry.key;
                                        return Container(
                                          height: 60,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            '${_getTraineeTotalHits(traineeIndex)}/${_getTotalBullets()}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                              fontSize: 11,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                // Percentage column (Range mode)
                                Container(
                                  width: 80,
                                  color: Colors.transparent,
                                  child: Column(
                                    children: [
                                      // Header
                                      Container(
                                        height: 60,
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'אחוז\nפגיעות',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            color: Colors.green,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      // Values
                                      ...trainees.asMap().entries.map((entry) {
                                        final traineeIndex = entry.key;
                                        final totalHits = _getTraineeTotalHits(
                                          traineeIndex,
                                        );
                                        final totalBullets = _getTotalBullets();
                                        final percentage = totalBullets > 0
                                            ? (totalHits / totalBullets * 100)
                                            : 0.0;
                                        return Container(
                                          height: 60,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            '${percentage.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: percentage >= 70
                                                  ? Colors.green
                                                  : percentage >= 50
                                                  ? Colors.orange
                                                  : Colors.red,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // Desktop layout: Original table layout
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // Header row
                  Row(
                    children: [
                      // First frozen column: Number (appears RIGHT in RTL)
                      const SizedBox(
                        width: 80,
                        child: Text(
                          'מספר',
                          style: TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Second frozen column: Name
                      const SizedBox(
                        width: 120,
                        child: Text(
                          'חניך',
                          style: TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ...stations.asMap().entries.map((entry) {
                                final index = entry.key;
                                final station = entry.value;
                                return SizedBox(
                                  width: 80,
                                  child: Column(
                                    children: [
                                      Text(
                                        station.name.isEmpty
                                            ? 'מקצה ${index + 1}'
                                            : station.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        '(${station.bulletsCount})',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              // Summary column headers (conditional based on mode)
                              if (widget.mode == 'surprise') ...[
                                const SizedBox(
                                  width: 100,
                                  child: Text(
                                    'סך הכל נקודות',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(
                                  width: 100,
                                  child: Text(
                                    'ממוצע נקודות',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(
                                  width: 100,
                                  child: Text(
                                    'פגיעות/כדורים',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(
                                  width: 100,
                                  child: Text(
                                    'אחוז פגיעות',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  // Trainee rows
                  ...trainees.asMap().entries.map((entry) {
                    final traineeIndex = entry.key;
                    final trainee = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          // First column: Number (appears RIGHT in RTL)
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: TextEditingController(
                                text: traineeNumbers.length > traineeIndex
                                    ? traineeNumbers[traineeIndex].toString()
                                    : '${traineeIndex + 1}',
                              ),
                              decoration: const InputDecoration(
                                hintText: 'מספר',
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.center,
                              onChanged: (v) {
                                final n = int.tryParse(v) ?? (traineeIndex + 1);
                                setState(() {
                                  // ensure list length
                                  while (traineeNumbers.length <=
                                      traineeIndex) {
                                    traineeNumbers.add(
                                      traineeNumbers.length + 1,
                                    );
                                  }
                                  traineeNumbers[traineeIndex] = n;
                                });
                                // NO AUTOSAVE - user must manually save
                              },
                            ),
                          ),
                          // Second column: Name
                          SizedBox(
                            width: 120,
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: 'שם חניך',
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                              ),
                              textAlign: TextAlign.center,
                              onChanged: (v) {
                                setState(() {
                                  trainee.name = v;
                                });
                                // NO AUTOSAVE - user must manually save
                              },
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ...stations.asMap().entries.map((
                                    stationEntry,
                                  ) {
                                    final stationIndex = stationEntry.key;
                                    final station = stationEntry.value;
                                    return SizedBox(
                                      width: 80,
                                      child: TextField(
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          hintText: '0',
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 12,
                                          ),
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        textAlign: TextAlign.center,
                                        onChanged: (v) {
                                          final score = int.tryParse(v) ?? 0;

                                          // Validation based on mode
                                          if (widget.mode == 'surprise') {
                                            // Surprise mode: 1-10 scale
                                            if (score < 0 || score > 10) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'ציון חייב להיות בין 1 ל-10',
                                                  ),
                                                  duration: Duration(
                                                    seconds: 1,
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                          } else {
                                            // Range mode: hits limited by bullets
                                            if (score > station.bulletsCount) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'פגיעות לא יכולות לעלות על ${station.bulletsCount} כדורים',
                                                  ),
                                                  duration: const Duration(
                                                    seconds: 1,
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                          }
                                          setState(() {
                                            trainee.hits[stationIndex] = score;
                                          });
                                          // NO AUTOSAVE - user must manually save
                                        },
                                      ),
                                    );
                                  }),
                                  // Summary columns (conditional based on mode)
                                  if (widget.mode == 'surprise') ...[
                                    // Total Points column (Surprise mode)
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        _getTraineeTotalPoints(
                                          traineeIndex,
                                        ).toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    // Average Points column (Surprise mode)
                                    SizedBox(
                                      width: 100,
                                      child: Builder(
                                        builder: (_) {
                                          final avgPoints =
                                              _getTraineeAveragePoints(
                                                traineeIndex,
                                              );
                                          return Text(
                                            avgPoints > 0
                                                ? avgPoints.toStringAsFixed(1)
                                                : '—',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: avgPoints >= 7
                                                  ? Colors.green
                                                  : avgPoints >= 5
                                                  ? Colors.orange
                                                  : Colors.red,
                                            ),
                                            textAlign: TextAlign.center,
                                          );
                                        },
                                      ),
                                    ),
                                  ] else ...[
                                    // Bullets/Hits column (Range mode)
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        '${_getTraineeTotalHits(traineeIndex)}/${_getTotalBullets()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    // Percentage column (Range mode)
                                    SizedBox(
                                      width: 100,
                                      child: Builder(
                                        builder: (_) {
                                          final totalHits =
                                              _getTraineeTotalHits(
                                                traineeIndex,
                                              );
                                          final totalBullets =
                                              _getTotalBullets();
                                          final percentage = totalBullets > 0
                                              ? (totalHits / totalBullets * 100)
                                              : 0.0;
                                          return Text(
                                            '${percentage.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: percentage >= 70
                                                  ? Colors.green
                                                  : percentage >= 50
                                                  ? Colors.orange
                                                  : Colors.red,
                                            ),
                                            textAlign: TextAlign.center,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

/// מודל מקצה
class RangeStation {
  String name;
  int bulletsCount;
  int? timeSeconds; // זמן בשניות - עבור "בוחן רמה"
  int? hits; // פגיעות - עבור "בוחן רמה"
  bool isManual; // האם מקצה ידני
  bool isLevelTester; // האם מקצה "בוחן רמה"
  List<String> selectedRubrics; // רובליקות נבחרות למקצה ידני

  RangeStation({
    required this.name,
    required this.bulletsCount,
    this.timeSeconds,
    this.hits,
    this.isManual = false,
    this.isLevelTester = false,
    List<String>? selectedRubrics,
  }) : selectedRubrics = selectedRubrics ?? ['זמן', 'פגיעות'];

  // בדיקה אם המקצה הוא "בוחן רמה"
  bool get isLevelTest => name == 'בוחן רמה';

  // בדיקה אם המקצה ידני
  bool get isManualStation => name == 'מקצה ידני' || isManual;
}

/// מודל חניך
class Trainee {
  String name;
  Map<int, int> hits; // מפה: אינדקס מקצה -> מספר פגיעות

  Trainee({required this.name, required this.hits});

  Map<String, dynamic> toJson() {
    return {'name': name, 'hits': hits};
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'hits': hits.map((k, v) => MapEntry('station_$k', v)),
    };
  }

  bool hasAnyNonZeroField() {
    return hits.values.any((v) => v != 0);
  }
}

extension RangeStationJson on RangeStation {
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bulletsCount': bulletsCount,
      'timeSeconds': timeSeconds,
      'hits': hits,
      'isManual': isManual,
      'isLevelTester': isLevelTester,
      'selectedRubrics': selectedRubrics,
    };
  }
}
