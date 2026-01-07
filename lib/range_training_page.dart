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

  // ✅ SINGLE SOURCE OF TRUTH: List of trainee row models
  // Contains ALL data for table: index, name, and all numeric values
  List<TraineeRowModel> traineeRows = [];

  // editing document id stored in state so we can create/update temporary docs
  String? _editingFeedbackId;

  bool _isSaving = false;
  // הייצוא יתבצע מדף המשובים בלבד

  // ✅ AUTOSAVE TIMER: Debounced autosave (700ms delay)
  Timer? _autoSaveTimer;

  // ✅ STABLE CONTROLLERS: Prevent focus loss on rebuild
  // Key format: "trainee_{idx}" for name fields, "trainee_{idx}_station_{stationIdx}" for numeric fields
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  // ✅ PERSISTENT SCROLL CONTROLLERS: For synchronized scrolling in range tables
  // OLD APPROACH (will be replaced): Single controllers shared by multiple scrollables
  // late final ScrollController _verticalCtrl;
  // late final ScrollController _horizontalCtrl;

  // ✅ NEW APPROACH: Separate controllers with manual sync via listeners
  late final ScrollController _namesVertical;
  late final ScrollController _resultsVertical;
  late final ScrollController _headerHorizontal;
  late final ScrollController _resultsHorizontal;

  // ✅ SYNC GUARD FLAGS: Prevent infinite loops during listener sync
  bool _syncingVertical = false;
  bool _syncingHorizontal = false;

  // ✅ SCROLL SYNC CONSTANTS
  static const double nameColumnWidth = 160.0;
  static const double stationColumnWidth = 90.0;
  static const double rowHeight = 44.0;

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
    // ✅ Initialize autosave timer (will be scheduled on data changes)
    // ✅ Initialize persistent scroll controllers for table sync
    // NEW APPROACH: 4 separate controllers with manual sync
    _namesVertical = ScrollController();
    _resultsVertical = ScrollController();
    _headerHorizontal = ScrollController();
    _resultsHorizontal = ScrollController();

    // ✅ SYNC LISTENERS: Vertical scroll sync (names ↔ results)
    _namesVertical.addListener(() {
      if (_syncingVertical) return;
      _syncingVertical = true;
      if (_resultsVertical.hasClients) {
        final targetOffset = _namesVertical.offset.clamp(
          0.0,
          _resultsVertical.position.maxScrollExtent,
        );
        _resultsVertical.jumpTo(targetOffset);
      }
      _syncingVertical = false;
    });

    _resultsVertical.addListener(() {
      if (_syncingVertical) return;
      _syncingVertical = true;
      if (_namesVertical.hasClients) {
        final targetOffset = _resultsVertical.offset.clamp(
          0.0,
          _namesVertical.position.maxScrollExtent,
        );
        _namesVertical.jumpTo(targetOffset);
      }
      _syncingVertical = false;
    });

    // ✅ SYNC LISTENERS: Horizontal scroll sync (header ↔ results)
    _headerHorizontal.addListener(() {
      if (_syncingHorizontal) return;
      _syncingHorizontal = true;
      if (_resultsHorizontal.hasClients) {
        final targetOffset = _headerHorizontal.offset.clamp(
          0.0,
          _resultsHorizontal.position.maxScrollExtent,
        );
        _resultsHorizontal.jumpTo(targetOffset);
      }
      _syncingHorizontal = false;
    });

    _resultsHorizontal.addListener(() {
      if (_syncingHorizontal) return;
      _syncingHorizontal = true;
      if (_headerHorizontal.hasClients) {
        final targetOffset = _resultsHorizontal.offset.clamp(
          0.0,
          _headerHorizontal.position.maxScrollExtent,
        );
        _headerHorizontal.jumpTo(targetOffset);
      }
      _syncingHorizontal = false;
    });
  }

  /// ✅ GET OR CREATE STABLE CONTROLLER: Returns existing or creates new controller
  TextEditingController _getController(String key, String initialValue) {
    if (!_textControllers.containsKey(key)) {
      _textControllers[key] = TextEditingController(text: initialValue);
    } else {
      // Update text if it changed (e.g., loaded from Firestore)
      if (_textControllers[key]!.text != initialValue) {
        _textControllers[key]!.text = initialValue;
      }
    }
    return _textControllers[key]!;
  }

  /// ✅ GET OR CREATE STABLE FOCUS NODE: Returns existing or creates new focus node with blur listener
  FocusNode _getFocusNode(String key) {
    if (!_focusNodes.containsKey(key)) {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) {
          // ✅ IMMEDIATE SAVE ON FOCUS LOSS: User finished editing this field
          debugPrint('🔵 FOCUS LOST: $key → triggering immediate save');
          _saveImmediately();
        }
      });
      _focusNodes[key] = node;
    }
    return _focusNodes[key]!;
  }

  /// ✅ DEBOUNCED AUTOSAVE: Schedule autosave after 700ms of inactivity
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 700), () {
      debugPrint('🔄 AUTOSAVE: Timer triggered (700ms debounce)');
      _saveTemporarily();
    });
  }

  /// ✅ IMMEDIATE SAVE: Triggered when user leaves a field (focus loss)
  void _saveImmediately() {
    _autoSaveTimer?.cancel(); // Cancel pending debounced save
    debugPrint('⚡ IMMEDIATE SAVE: Saving now');
    _saveTemporarily();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _attendeesCountController.dispose();
    // ✅ Dispose all controllers and focus nodes
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _textControllers.clear();
    _focusNodes.clear();
    // ✅ Dispose persistent scroll controllers
    _namesVertical.dispose();
    _resultsVertical.dispose();
    _headerHorizontal.dispose();
    _resultsHorizontal.dispose();
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
    debugPrint('\n🔍 DEBUG: _updateAttendeesCount called with count=$count');
    debugPrint(
      '   Before update: traineeRows.length=${traineeRows.length}, stations.length=${stations.length}',
    );

    setState(() {
      attendeesCount = count;

      // ✅ Update traineeRows to match count
      if (count > traineeRows.length) {
        // Add new rows
        for (int i = traineeRows.length; i < count; i++) {
          traineeRows.add(TraineeRowModel(index: i, name: ''));
        }
      } else if (count < traineeRows.length) {
        // Remove excess rows
        traineeRows = traineeRows.sublist(0, count);
      }
    });

    debugPrint(
      '   After update: traineeRows.length=${traineeRows.length}, attendeesCount=$attendeesCount',
    );
    debugPrint('   traineeRows isEmpty: ${traineeRows.isEmpty}');

    // ✅ Schedule autosave
    _scheduleAutoSave();
  }

  void _addStation() {
    debugPrint('\n🔍 DEBUG: _addStation called');
    debugPrint('   Before add: stations.length=${stations.length}');

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

    debugPrint('   After add: stations.length=${stations.length}');
  }

  void _removeStation(int index) {
    if (stations.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('חייב להיות לפחות $_itemLabel אחד')),
      );
      return;
    }

    setState(() {
      // ✅ Remove station data from all trainee rows and shift indices
      for (var row in traineeRows) {
        row.values.remove(index);
        // Shift indices down for stations after removed one
        final updatedValues = <int, int>{};
        row.values.forEach((stationIdx, value) {
          if (stationIdx > index) {
            updatedValues[stationIdx - 1] = value;
          } else {
            updatedValues[stationIdx] = value;
          }
        });
        row.values.clear();
        row.values.addAll(updatedValues);
      }

      stations.removeAt(index);
    });
    // ✅ Schedule autosave
    _scheduleAutoSave();
  }

  int _getTraineeTotalHits(int traineeIndex) {
    if (traineeIndex >= traineeRows.length) return 0;

    int total = 0;
    traineeRows[traineeIndex].values.forEach((stationIndex, hits) {
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
    if (traineeIndex >= traineeRows.length) return 0;
    if (widget.mode != 'surprise') return 0;

    int total = 0;
    traineeRows[traineeIndex].values.forEach((stationIndex, score) {
      if (score > 0) {
        total += score;
      }
    });
    return total;
  }

  // Calculate average points for a trainee (surprise mode only)
  // Average of filled principle scores (ignores empty/0 scores)
  double _getTraineeAveragePoints(int traineeIndex) {
    if (traineeIndex >= traineeRows.length) return 0.0;
    if (widget.mode != 'surprise') return 0.0;

    int total = 0;
    int count = 0;
    traineeRows[traineeIndex].values.forEach((stationIndex, score) {
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
    for (int i = 0; i < traineeRows.length; i++) {
      if (traineeRows[i].name.trim().isEmpty) {
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
      'SAVE_CLICK trainees=${traineeRows.length} stations=${stations.length}',
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

      // ✅ Build trainees data from traineeRows model
      final List<Map<String, dynamic>> traineesData = [];
      for (int i = 0; i < traineeRows.length; i++) {
        final row = traineeRows[i];
        if (row.name.trim().isEmpty) continue; // Skip empty names

        // Build hits map from values, only include non-zero
        final Map<String, int> hitsMap = {};
        row.values.forEach((stationIdx, value) {
          if (value > 0) {
            hitsMap['station_$stationIdx'] = value;
          }
        });

        traineesData.add({
          'name': row.name.trim(),
          'hits': hitsMap,
          'totalHits': _getTraineeTotalHits(i),
          'number': i + 1,
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

        // ✅ FINALIZE LOG
        debugPrint(
          'FINALIZE_SAVE path=${docRef.path} module=surprise_drill type=surprise_exercise isTemporary=false',
        );

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

        // ✅ FINALIZE LOG
        debugPrint(
          'FINALIZE_SAVE path=${docRef.path} module=shooting_ranges type=range_feedback isTemporary=false rangeType=$_rangeType',
        );

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
    // ✅ ATOMIC DRAFT SAVE: Single document with full traineeRows data
    // Updates same draftId, never creates duplicates
    // Comprehensive debug logging for verification
    // ✅ NO REBUILD: Doesn't call setState during background auto-save

    if (_isSaving) {
      debugPrint('⚠️ DRAFT_SAVE: Already saving, skipping...');
      return; // Prevent concurrent saves
    }

    // ✅ Track saving state WITHOUT rebuilding (prevents focus loss)
    _isSaving = true;

    try {
      debugPrint('\n========== ✅ DRAFT_SAVE START ==========');
      debugPrint('DRAFT_SAVE: mode=${widget.mode} rangeType=$_rangeType');
      debugPrint('DRAFT_SAVE: platform=${kIsWeb ? "web" : "mobile"}');

      // Get user ID
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        debugPrint('❌ DRAFT_SAVE: No user ID, aborting');
        _isSaving = false;
        return;
      }

      // Build deterministic draft ID
      final String moduleType = widget.mode == 'surprise'
          ? 'surprise_drill'
          : 'shooting_ranges';
      final String draftId =
          '${uid}_${moduleType}_${_rangeType.replaceAll(' ', '_')}';
      _editingFeedbackId = draftId;

      debugPrint('DRAFT_SAVE: uid=$uid');
      debugPrint('DRAFT_SAVE: draftId=$draftId');

      // ✅ Serialize traineeRows to Firestore format
      final List<Map<String, dynamic>> traineesPayload = [];
      debugPrint(
        'DRAFT_SAVE: Serializing ${traineeRows.length} trainee rows...',
      );
      for (int i = 0; i < traineeRows.length; i++) {
        final row = traineeRows[i];
        final rowData = row.toFirestore();
        traineesPayload.add(rowData);
        debugPrint(
          'DRAFT_SAVE:   row[$i]: name="${row.name}" values=${row.values}',
        );
      }

      // Build complete payload
      final String folderName = widget.mode == 'surprise'
          ? 'תרגילי הפתעה - משוב זמני'
          : 'מטווחים - משוב זמני';

      final Map<String, dynamic> payload = {
        'status': 'temporary',
        'module': moduleType,
        'isTemporary': true,
        'folder': folderName,
        'instructorId': uid,
        'instructorName': instructorName,
        'rangeType': _rangeType,
        'settlement': selectedSettlement ?? '',
        'attendeesCount': attendeesCount,
        'stations': stations.map((s) => s.toJson()).toList(),
        'trainees': traineesPayload,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      debugPrint('DRAFT_SAVE: payload.attendeesCount=$attendeesCount');
      debugPrint(
        'DRAFT_SAVE: payload.trainees.length=${traineesPayload.length}',
      );
      debugPrint('DRAFT_SAVE: payload.stations.length=${stations.length}');
      debugPrint('DRAFT_SAVE: payload.folder=$folderName');

      // Write to Firestore (overwrite completely)
      final docRef = FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(draftId);
      debugPrint('DRAFT_SAVE: Writing to ${docRef.path}');

      await docRef.set(payload, SetOptions(merge: false));
      debugPrint('✅ DRAFT_SAVE: Write complete');

      // ✅ READ-BACK VERIFICATION
      debugPrint('DRAFT_SAVE: Read-back verification...');
      final verifySnap = await docRef.get();

      if (!verifySnap.exists) {
        debugPrint('❌ DRAFT_SAVE: Document NOT FOUND after write!');
        throw Exception('Draft document not persisted');
      }

      final verifyData = verifySnap.data();
      if (verifyData == null) {
        debugPrint('❌ DRAFT_SAVE: Document data is NULL!');
        throw Exception('Draft data is null');
      }

      final verifyTrainees = verifyData['trainees'] as List?;
      debugPrint(
        'DRAFT_SAVE: Verified trainees.length=${verifyTrainees?.length ?? 0}',
      );
      if (verifyTrainees == null || verifyTrainees.isEmpty) {
        debugPrint('❌ DRAFT_SAVE: Trainees array is empty!');
        throw Exception('Trainees not saved');
      }

      // Check first trainee has data
      if (verifyTrainees.isNotEmpty) {
        final firstTrainee = verifyTrainees[0] as Map?;
        final firstName = firstTrainee?['name'];
        final firstValues = firstTrainee?['values'];
        debugPrint(
          'DRAFT_SAVE: First trainee: name="$firstName" values=$firstValues',
        );
      }

      debugPrint('✅ DRAFT_SAVE: Verification PASSED');
      debugPrint('DRAFT_SAVE: Draft saved at ${docRef.path}');
      debugPrint('DRAFT_SAVE: traineeRows.length=${traineeRows.length}');
      debugPrint('========== ✅ DRAFT_SAVE END ==========\n');

      if (!mounted) return;

      // Show subtle success indicator (don't spam user)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ שמירה אוטומטית'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('\n========== ❌ DRAFT_SAVE ERROR ==========');
      debugPrint('DRAFT_SAVE_ERROR: $e');
      debugPrint('DRAFT_SAVE_ERROR_STACK: $stackTrace');
      debugPrint('==========================================\n');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ שגיאה בשמירה: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      // ✅ NO REBUILD: Reset flag WITHOUT setState to prevent focus loss
      _isSaving = false;
    }
  }

  Future<void> _loadExistingTemporaryFeedback(String id) async {
    // ✅ ATOMIC DRAFT LOAD: Load doc, rebuild traineeRows from Firestore
    // NO default empty rows after load - only what's in the document
    // Comprehensive debug logging for verification

    debugPrint('\n========== ✅ DRAFT_LOAD START ==========');
    debugPrint('DRAFT_LOAD: id=$id');
    debugPrint('DRAFT_LOAD: mode=${widget.mode} rangeType=$_rangeType');
    debugPrint('DRAFT_LOAD: platform=${kIsWeb ? "web" : "mobile"}');

    try {
      final docRef = FirebaseFirestore.instance.collection('feedbacks').doc(id);
      debugPrint('DRAFT_LOAD: path=${docRef.path}');

      final doc = await docRef.get();
      debugPrint('DRAFT_LOAD: doc.exists=${doc.exists}');

      if (!doc.exists) {
        debugPrint('⚠️ DRAFT_LOAD: Document does not exist');
        debugPrint('========== ✅ DRAFT_LOAD END (NOT FOUND) ==========\n');
        return;
      }

      final data = doc.data();
      if (data == null) {
        debugPrint('⚠️ DRAFT_LOAD: Document data is null');
        debugPrint('========== ✅ DRAFT_LOAD END (NULL DATA) ==========\n');
        return;
      }

      debugPrint('DRAFT_LOAD: dataKeys=${data.keys.toList()}');

      final rawTrainees = data['trainees'] as List?;
      final rawStations = data['stations'] as List?;
      final rawSettlement = data['settlement'] as String?;
      final rawAttendeesCount = data['attendeesCount'] as num?;

      debugPrint('DRAFT_LOAD: rawTrainees.length=${rawTrainees?.length ?? -1}');
      debugPrint('DRAFT_LOAD: rawStations.length=${rawStations?.length ?? -1}');
      debugPrint('DRAFT_LOAD: settlement=$rawSettlement');
      debugPrint('DRAFT_LOAD: attendeesCount=$rawAttendeesCount');

      if (rawTrainees != null && rawTrainees.isNotEmpty) {
        debugPrint('DRAFT_LOAD: firstTraineeRaw=${rawTrainees[0]}');
      }

      // ✅ Parse and rebuild traineeRows from Firestore data
      final List<TraineeRowModel> loadedRows = [];
      if (rawTrainees != null) {
        for (int i = 0; i < rawTrainees.length; i++) {
          final rawRow = rawTrainees[i];
          if (rawRow is Map<String, dynamic>) {
            final row = TraineeRowModel.fromFirestore(rawRow);
            loadedRows.add(row);
            debugPrint(
              'DRAFT_LOAD:   row[$i]: name="${row.name}" values=${row.values}',
            );
          }
        }
      }

      debugPrint('DRAFT_LOAD: Loaded ${loadedRows.length} trainee rows');

      // ✅ Parse stations
      final List<RangeStation> loadedStations = [];
      if (rawStations != null) {
        for (final stationData in rawStations) {
          final m = Map<String, dynamic>.from(stationData as Map);
          loadedStations.add(
            RangeStation(
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
            ),
          );
        }
      }

      // ✅ UPDATE STATE: Replace all data with loaded data
      setState(() {
        // Update metadata
        selectedSettlement = rawSettlement ?? selectedSettlement;
        _settlementDisplayText = selectedSettlement ?? '';
        attendeesCount = rawAttendeesCount?.toInt() ?? attendeesCount;
        _attendeesCountController.text = attendeesCount.toString();
        instructorName = data['instructorName'] as String? ?? instructorName;

        // ✅ Replace traineeRows with loaded data (NO default empty rows)
        traineeRows = loadedRows;

        // Replace stations with loaded data
        stations = loadedStations.isNotEmpty ? loadedStations : stations;

        debugPrint('DRAFT_LOAD: State updated');
        debugPrint('DRAFT_LOAD:   attendeesCount=$attendeesCount');
        debugPrint('DRAFT_LOAD:   traineeRows.length=${traineeRows.length}');
        debugPrint('DRAFT_LOAD:   stations.length=${stations.length}');
      });

      // ✅ FORCE REBUILD: Ensure UI updates with loaded data
      debugPrint('DRAFT_LOAD: Forcing rebuild...');
      if (mounted) {
        setState(() {}); // Explicit rebuild trigger
      }

      debugPrint('✅ DRAFT_LOAD: Load complete');
      debugPrint('DRAFT_LOAD: traineeRows.length=${traineeRows.length}');
      for (int i = 0; i < traineeRows.length && i < 3; i++) {
        debugPrint(
          'DRAFT_LOAD:   traineeRows[$i]: name="${traineeRows[i].name}" values=${traineeRows[i].values}',
        );
      }
      debugPrint('========== ✅ DRAFT_LOAD END (SUCCESS) ==========\n');
    } catch (e, stackTrace) {
      debugPrint('\n========== ❌ DRAFT_LOAD ERROR ==========');
      debugPrint('DRAFT_LOAD_ERROR: $e');
      debugPrint('DRAFT_LOAD_ERROR_STACK: $stackTrace');
      debugPrint('==========================================\n');
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
                  'שמירה אוטומטית: הנתונים נשמרים אוטומטית לטיוטה. שמירה סופית: משלים את המשוב ושולח לארכיון.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'לייצוא לקובץ מקומי, עבור לדף המשובים ולחץ על המשוב השמור',
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    debugPrint('\n🔍 DEBUG: _buildTraineesTable called');
    debugPrint('   screenWidth=$screenWidth');
    debugPrint('   traineeRows.length=${traineeRows.length}');
    debugPrint('   traineeRows.isEmpty=${traineeRows.isEmpty}');
    debugPrint('   attendeesCount=$attendeesCount');
    debugPrint('   stations.length=${stations.length}');

    if (traineeRows.isEmpty) {
      return Center(
        child: Card(
          color: Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'אין חניכים במקצה זה',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'כמות נוכחים: $attendeesCount',
                  style: const TextStyle(color: Colors.black54),
                ),
                if (attendeesCount > 0) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Force reinitialize traineeRows
                      _updateAttendeesCount(attendeesCount);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('רענן רשימת חניכים'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          // ✅ FINAL PRODUCTION-SAFE SYNCHRONIZED SCROLLING
          // Calculate total width for stations + summary columns
          final double totalStationsWidth =
              (stations.length * stationColumnWidth) +
              (widget.mode == 'surprise' ? 170 : 160);

          return SizedBox(
            height: 320,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // A) TOP STICKY HEADER ROW (does not scroll vertically)
                  Row(
                    children: [
                      // Fixed "שם חניך" header
                      Container(
                        width: nameColumnWidth,
                        height: 56,
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          border: Border(
                            right: BorderSide(color: Colors.grey.shade300),
                            bottom: BorderSide(color: Colors.grey.shade300),
                          ),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'שם חניך',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      // Horizontally scrollable station headers (synced with body)
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _headerHorizontal,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: totalStationsWidth,
                            child: Row(
                              children: [
                                ...stations.asMap().entries.map((entry) {
                                  final stationIndex = entry.key;
                                  final station = entry.value;
                                  return Container(
                                    width: stationColumnWidth,
                                    height: 56,
                                    padding: const EdgeInsets.all(4.0),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
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
                                  );
                                }),
                                // Summary column headers
                                if (widget.mode == 'surprise') ...[
                                  Container(
                                    width: 90,
                                    height: 56,
                                    padding: const EdgeInsets.all(4.0),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                        bottom: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'סך נקודות',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          color: Colors.blue,
                                        ),
                                        textAlign: TextAlign.center,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 80,
                                    height: 56,
                                    padding: const EdgeInsets.all(4.0),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'ממוצע',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          color: Colors.green,
                                        ),
                                        textAlign: TextAlign.center,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    width: 90,
                                    height: 56,
                                    padding: const EdgeInsets.all(4.0),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                        bottom: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'פגיעות/כדורים',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          color: Colors.blue,
                                        ),
                                        textAlign: TextAlign.center,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 70,
                                    height: 56,
                                    padding: const EdgeInsets.all(4.0),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'אחוז',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          color: Colors.green,
                                        ),
                                        textAlign: TextAlign.center,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // B) SCROLLABLE BODY with synchronized vertical & horizontal scrolling
                  Expanded(
                    child: Row(
                      children: [
                        // Fixed trainee names column (scrolls vertically only)
                        SizedBox(
                          width: nameColumnWidth,
                          child: ListView.builder(
                            controller: _namesVertical,
                            primary: false,
                            physics: const ClampingScrollPhysics(),
                            itemCount: traineeRows.length,
                            itemExtent: rowHeight,
                            itemBuilder: (context, idx) {
                              final row = traineeRows[idx];
                              final controllerKey = 'trainee_$idx';
                              final focusKey = 'trainee_$idx';
                              return SizedBox(
                                height: rowHeight,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                      vertical: 2.0,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _getController(
                                        controllerKey,
                                        row.name,
                                      ),
                                      focusNode: _getFocusNode(focusKey),
                                      decoration: const InputDecoration(
                                        hintText: 'שם',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      onChanged: (v) {
                                        // ✅ ONLY UPDATE DATA: No setState, no save
                                        row.name = v;
                                        _scheduleAutoSave();
                                      },
                                      onSubmitted: (v) {
                                        // ✅ IMMEDIATE SAVE: User pressed Enter
                                        row.name = v;
                                        _saveImmediately();
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Scrollable results (scrolls both horizontally and vertically, synced)
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _resultsHorizontal,
                            primary: false,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: totalStationsWidth,
                              child: ListView.builder(
                                controller: _resultsVertical,
                                primary: false,
                                physics: const ClampingScrollPhysics(),
                                itemCount: traineeRows.length,
                                itemExtent: rowHeight,
                                itemBuilder: (context, traineeIdx) {
                                  final row = traineeRows[traineeIdx];
                                  return SizedBox(
                                    height: rowHeight,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // Station input fields
                                          ...stations.asMap().entries.map((
                                            entry,
                                          ) {
                                            final stationIndex = entry.key;
                                            final station = entry.value;
                                            final currentValue = row.getValue(
                                              stationIndex,
                                            );
                                            final controllerKey =
                                                'trainee_${traineeIdx}_station_$stationIndex';
                                            final focusKey =
                                                'trainee_${traineeIdx}_station_$stationIndex';
                                            return SizedBox(
                                              width: stationColumnWidth,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 64,
                                                        maxWidth: 90,
                                                      ),
                                                  child: SizedBox(
                                                    height: rowHeight - 4,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 2.0,
                                                          ),
                                                      child: TextField(
                                                        controller: _getController(
                                                          controllerKey,
                                                          currentValue == 0
                                                              ? ''
                                                              : currentValue
                                                                    .toString(),
                                                        ),
                                                        focusNode:
                                                            _getFocusNode(
                                                              focusKey,
                                                            ),
                                                        decoration: const InputDecoration(
                                                          isDense: true,
                                                          border:
                                                              OutlineInputBorder(),
                                                          hintText: '0',
                                                          contentPadding:
                                                              EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 10,
                                                              ),
                                                        ),
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                        inputFormatters: [
                                                          FilteringTextInputFormatter
                                                              .digitsOnly,
                                                        ],
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                        maxLines: 1,
                                                        onChanged: (v) {
                                                          final score =
                                                              int.tryParse(v) ??
                                                              0;

                                                          // Validation based on mode
                                                          if (widget.mode ==
                                                              'surprise') {
                                                            if (score < 0 ||
                                                                score > 10) {
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              ).showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                    'ציון חייב להיות בין 1 ל-10',
                                                                  ),
                                                                  duration:
                                                                      Duration(
                                                                        seconds:
                                                                            1,
                                                                      ),
                                                                ),
                                                              );
                                                              return;
                                                            }
                                                          } else {
                                                            if (score >
                                                                station
                                                                    .bulletsCount) {
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              ).showSnackBar(
                                                                SnackBar(
                                                                  content: Text(
                                                                    'פגיעות לא יכולות לעלות על ${station.bulletsCount} כדורים',
                                                                  ),
                                                                  duration:
                                                                      const Duration(
                                                                        seconds:
                                                                            1,
                                                                      ),
                                                                ),
                                                              );
                                                              return;
                                                            }
                                                          }
                                                          // ✅ ONLY UPDATE DATA: No setState, no save
                                                          row.setValue(
                                                            stationIndex,
                                                            score,
                                                          );
                                                          _scheduleAutoSave();
                                                        },
                                                        onSubmitted: (v) {
                                                          // ✅ IMMEDIATE SAVE: User pressed Enter
                                                          final score =
                                                              int.tryParse(v) ??
                                                              0;
                                                          row.setValue(
                                                            stationIndex,
                                                            score,
                                                          );
                                                          _saveImmediately();
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                          // Summary columns
                                          if (widget.mode == 'surprise') ...[
                                            SizedBox(
                                              width: 90,
                                              height: rowHeight,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: Text(
                                                  _getTraineeTotalPoints(
                                                    traineeIdx,
                                                  ).toString(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue,
                                                    fontSize: 11,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 80,
                                              height: rowHeight,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: Builder(
                                                  builder: (_) {
                                                    final avgPoints =
                                                        _getTraineeAveragePoints(
                                                          traineeIdx,
                                                        );
                                                    return Text(
                                                      avgPoints > 0
                                                          ? avgPoints
                                                                .toStringAsFixed(
                                                                  1,
                                                                )
                                                          : '—',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 11,
                                                        color: avgPoints >= 7
                                                            ? Colors.green
                                                            : avgPoints >= 5
                                                            ? Colors.orange
                                                            : Colors.red,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 1,
                                                      softWrap: false,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ] else ...[
                                            SizedBox(
                                              width: 90,
                                              height: rowHeight,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '${_getTraineeTotalHits(traineeIdx)}/${_getTotalBullets()}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue,
                                                    fontSize: 10,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 70,
                                              height: rowHeight,
                                              child: Align(
                                                alignment: Alignment.center,
                                                child: Builder(
                                                  builder: (_) {
                                                    final totalHits =
                                                        _getTraineeTotalHits(
                                                          traineeIdx,
                                                        );
                                                    final totalBullets =
                                                        _getTotalBullets();
                                                    final percentage =
                                                        totalBullets > 0
                                                        ? (totalHits /
                                                              totalBullets *
                                                              100)
                                                        : 0.0;
                                                    return Text(
                                                      '${percentage.toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 10,
                                                        color: percentage >= 70
                                                            ? Colors.green
                                                            : percentage >= 50
                                                            ? Colors.orange
                                                            : Colors.red,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 1,
                                                      softWrap: false,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
                  ...traineeRows.asMap().entries.map((entry) {
                    final traineeIndex = entry.key;
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          // First column: Number (appears RIGHT in RTL)
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: TextEditingController(
                                text: '${traineeIndex + 1}',
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
                                // Numbers are for display only
                              },
                            ),
                          ),
                          // Second column: Name
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _getController(
                                'desktop_trainee_$traineeIndex',
                                row.name,
                              ),
                              focusNode: _getFocusNode(
                                'desktop_trainee_$traineeIndex',
                              ),
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
                                // ✅ ONLY UPDATE DATA: No setState, no save
                                row.name = v;
                                _scheduleAutoSave();
                              },
                              onSubmitted: (v) {
                                // ✅ IMMEDIATE SAVE: User pressed Enter
                                row.name = v;
                                _saveImmediately();
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
                                    final currentValue = row.getValue(
                                      stationIndex,
                                    );
                                    final controllerKey =
                                        'desktop_trainee_${traineeIndex}_station_$stationIndex';
                                    final focusKey =
                                        'desktop_trainee_${traineeIndex}_station_$stationIndex';
                                    return SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller: _getController(
                                          controllerKey,
                                          currentValue > 0
                                              ? currentValue.toString()
                                              : '',
                                        ),
                                        focusNode: _getFocusNode(focusKey),
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
                                          // ✅ ONLY UPDATE DATA: No setState, no save
                                          row.setValue(stationIndex, score);
                                          _scheduleAutoSave();
                                        },
                                        onSubmitted: (v) {
                                          // ✅ IMMEDIATE SAVE: User pressed Enter
                                          final score = int.tryParse(v) ?? 0;
                                          row.setValue(stationIndex, score);
                                          _saveImmediately();
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

/// TraineeRowModel - Single Source of Truth for trainee table row
/// Contains ALL data needed for one trainee row: index, name, and all numeric values
class TraineeRowModel {
  final int index;
  String name;
  final Map<int, int> values; // stationIndex -> value (hits or score)

  TraineeRowModel({
    required this.index,
    required this.name,
    Map<int, int>? values,
  }) : values = values ?? {};

  // Get value for a specific station/principle
  int getValue(int stationIndex) => values[stationIndex] ?? 0;

  // Set value for a specific station/principle
  void setValue(int stationIndex, int value) {
    if (value == 0) {
      values.remove(stationIndex);
    } else {
      values[stationIndex] = value;
    }
  }

  // Check if has any non-zero data
  bool hasData() => name.trim().isNotEmpty || values.values.any((v) => v != 0);

  // Serialize to Firestore format
  Map<String, dynamic> toFirestore() {
    final valuesMap = <String, int>{};
    values.forEach((stationIdx, val) {
      if (val != 0) {
        valuesMap['station_$stationIdx'] = val;
      }
    });
    return {'index': index, 'name': name.trim(), 'values': valuesMap};
  }

  // Deserialize from Firestore format
  static TraineeRowModel fromFirestore(Map<String, dynamic> data) {
    final index = (data['index'] as num?)?.toInt() ?? 0;
    final name = (data['name'] as String?) ?? '';
    final valuesRaw = (data['values'] as Map<String, dynamic>?) ?? {};

    final values = <int, int>{};
    valuesRaw.forEach((key, val) {
      if (key.startsWith('station_')) {
        final stationIdx = int.tryParse(key.replaceFirst('station_', ''));
        final value = (val as num?)?.toInt() ?? 0;
        if (stationIdx != null && value != 0) {
          values[stationIdx] = value;
        }
      }
    });

    return TraineeRowModel(index: index, name: name, values: values);
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
