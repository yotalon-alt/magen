import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'main.dart'; // for currentUser and golanSettlements
import 'widgets/standard_back_button.dart';
import 'widgets/trainee_selection_dialog.dart';
import 'services/trainee_autocomplete_service.dart';

// ===== SINGLE SOURCE OF TRUTH: Long Range Detection =====
/// Determines if a feedback is Long Range based on available fields.
/// USE THIS EVERYWHERE: UI, LOAD, SAVE - ensures consistency.
///
/// Priority order:
/// 1. feedbackType (most reliable - set at save time)
/// 2. rangeSubType (UI label for display)
/// 3. rangeType (internal type, may be in Hebrew)
/// 4. folderKey (fallback for old data)
bool isLongRangeFeedback({
  String? feedbackType,
  String? rangeSubType,
  String? rangeType,
  String? folderKey,
}) {
  // Check feedbackType first (most reliable)
  if (feedbackType != null) {
    if (feedbackType == 'range_long' || feedbackType == 'דווח רחוק') {
      return true;
    }
    if (feedbackType == 'range_short' || feedbackType == 'דווח קצר') {
      return false;
    }
  }

  // Check rangeSubType (display label)
  if (rangeSubType != null) {
    if (rangeSubType == 'טווח רחוק') return true;
    if (rangeSubType == 'טווח קצר') return false;
  }

  // Check rangeType (internal, may be Hebrew)
  if (rangeType != null) {
    if (rangeType == 'ארוכים' || rangeType == 'long') return true;
    if (rangeType == 'קצרים' || rangeType == 'short') return false;
  }

  // Fallback: use folderKey (for old data)
  if (folderKey == 'ranges_474_long') return true;
  if (folderKey == 'ranges_474_short') return false;

  // Default: assume short range if inconclusive
  return false;
}

/// Model for Short Range stage in multi-stage list
class ShortRangeStageModel {
  final String? selectedStage; // Selected from dropdown
  final String manualName; // Manual stage name if "מקצה ידני" selected
  final bool isManual; // True if "מקצה ידני"
  final int bulletsCount; // Bullet count for this stage
  final int? timeLimit; // Time limit in seconds - for "בוחן רמה" only

  const ShortRangeStageModel({
    this.selectedStage,
    this.manualName = '',
    this.isManual = false,
    this.bulletsCount = 0,
    this.timeLimit,
  });

  /// Check if this stage is "בוחן רמה"
  bool get isLevelTester => selectedStage == 'בוחן רמה';

  /// Get display name - returns manual name or selected stage
  String get displayName {
    if (isManual && manualName.isNotEmpty) {
      return manualName;
    }
    return selectedStage ?? '';
  }
}

/// Model for Long Range stage with direct max score entry
class LongRangeStageModel {
  String name; // Stage name (predefined or custom)
  int
  maxPoints; // Maximum score for this stage (entered directly by instructor)
  int
  achievedPoints; // Total points achieved by trainees (calculated from trainee data)
  bool isManual; // True if custom stage

  // ✅ Bullet tracking field (TRACKING/DISPLAY ONLY - does NOT affect long-range scoring)
  // Long Range: Used only to track bullets fired per stage (for reference)
  // Short Range: Used for hit validation and percentage calculations
  int bulletsCount;

  LongRangeStageModel({
    required this.name,
    this.maxPoints = 0,
    this.achievedPoints = 0,
    this.isManual = false,
    this.bulletsCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'maxPoints': maxPoints, // Direct score value entered by instructor
    'achievedPoints': achievedPoints,
    'isManual': isManual,
    'bulletsCount': bulletsCount, // For tracking only (doesn't affect scoring)
  };

  factory LongRangeStageModel.fromJson(Map<String, dynamic> json) {
    return LongRangeStageModel(
      name: json['name'] as String? ?? '',
      maxPoints: (json['maxPoints'] as num?)?.toInt() ?? 0,
      achievedPoints: (json['achievedPoints'] as num?)?.toInt() ?? 0,
      isManual: json['isManual'] as bool? ?? false,
      bulletsCount: (json['bulletsCount'] as num?)?.toInt() ?? 0,
    );
  }
}

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
  // For Short Range: single-select dropdown with exact order
  static const List<String> shortRangeStages = [
    'הרמות',
    'שלשות',
    'UP עד UP',
    'מעצור גמר',
    'מעצור שני',
    'מעבר רחוקות',
    'מעבר קרובות',
    'מניפה',
    'בוחן רמה',
    'איפוס',
    'מקצה ידני',
  ];

  // For Long Range: predefined stage names (bullets entered by user per stage)
  static const List<String> longRangeStageNames = [
    'עמידה 50',
    'כריעה 50',
    'כריעה 100',
    'שכיבה 100',
    'כריעה 150',
    'שכיבה 150',
    'ילמ 50',
    'מקצה ידני',
  ];

  // רשימת עקרונות קבועה (surprise mode)
  static const List<String> availablePrinciples = [
    'קשר עין',
    'בחירת ציר התקדמות',
    'איום עיקרי ואיום משני',
    'קצב אש ומרחק',
    'קו ירי נקי',
    'וידוא ניטרול',
    'זיהוי והזדהות',
    'רמת ביצוע',
  ];

  String? selectedSettlement;
  String? rangeFolder; // "474 Ranges" or "Shooting Ranges"
  String? loadedFolderKey; // ✅ Folder ID loaded from draft (if any)
  String? loadedFolderLabel; // ✅ Folder label loaded from draft (if any)
  String settlementName = ''; // unified settlement field
  String instructorName = '';
  String? _originalCreatorName; // ✅ Track original creator's name
  String?
  _originalCreatorUid; // ✅ Track original creator's UID for permission checks
  bool isManualLocation =
      false; // Track if "Manual Location" is selected for Surprise Drills
  String manualLocationText =
      ''; // Store manual location text for Surprise Drills
  // ✅ NEW: Manual settlement for Range mode (מטווחים 474)
  bool isManualSettlement = false; // Track if "יישוב ידני" is selected
  String manualSettlementText = ''; // Store manual settlement text
  // ✅ NEW: Folder selection for Surprise Drills (474 or כללי)
  String? surpriseDrillsFolder; // No default - user must select
  int attendeesCount = 0;
  late TextEditingController _attendeesCountController;

  // מספר מדריכים ורשימת מדריכים
  int instructorsCount = 0;
  late TextEditingController _instructorsCountController;
  final Map<String, TextEditingController> _instructorNameControllers = {};

  late String _rangeType;
  String? rangeSubType; // "טווח קצר" or "טווח רחוק" for display label

  // Short Range specific: multi-stage dynamic list
  List<ShortRangeStageModel> shortRangeStagesList = [];

  // Legacy single-stage variables (kept for compatibility)
  String? selectedShortRangeStage;
  String manualStageName = '';
  late TextEditingController _manualStageController;

  // Long Range specific: multi-stage dynamic list
  List<LongRangeStageModel> longRangeStagesList = [];

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

  // ✅ LOADED DRAFT TRAINEES: Keep loaded trainee names for restoration when count changes
  List<TraineeRowModel> _loadedDraftTrainees = [];

  // editing document id stored in state so we can create/update temporary docs
  String? _editingFeedbackId;

  bool _isSaving = false;
  // הייצוא יתבצע מדף המשובים בלבד

  // ✅ SUMMARY FIELD: For instructor to write training summary
  String trainingSummary = '';
  late TextEditingController _trainingSummaryController;

  // ✅ DATE SELECTION: Allow admin (Yotam) to set custom feedback date
  DateTime _selectedDateTime = DateTime.now();
  bool _dateManuallySet = false;

  // ✅ AUTOSAVE TIMER: Debounced autosave (700ms delay)
  Timer? _autoSaveTimer;

  // ✅ REAL-TIME SYNC: Listen to concurrent edits by other admins
  StreamSubscription<DocumentSnapshot>? _draftListener;
  bool _isLoadingRemoteChanges = false;
  String? _lastRemoteUpdateBy;

  // ✅ STABLE CONTROLLERS: Prevent focus loss on rebuild
  // Key format: "trainee_{idx}" for name fields, "trainee_{idx}_station_{stationIdx}" for numeric fields
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  // ✅ AUTOCOMPLETE: List of trainees for 474 settlements
  List<String> _autocompleteTrainees = [];

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
    // Initialize instructor name - will be resolved properly on save
    instructorName = currentUser?.name ?? '';
    _settlementDisplayText = selectedSettlement ?? '';
    _attendeesCountController = TextEditingController(
      text: attendeesCount.toString(),
    );
    _instructorsCountController = TextEditingController(
      text: instructorsCount.toString(),
    );
    _manualStageController = TextEditingController();
    _trainingSummaryController = TextEditingController();
    // מקצה ברירת מחדל אחד
    stations.add(RangeStation(name: '', bulletsCount: 0));
    _rangeType = widget.rangeType;

    // ✅ Set rangeSubType for display label
    if (_rangeType == 'קצרים') {
      rangeSubType = 'טווח קצר';
    } else if (_rangeType == 'ארוכים') {
      rangeSubType = 'טווח רחוק';
    }

    // Initialize Long Range with empty stages list (user adds manually)
    if (_rangeType == 'ארוכים') {
      longRangeStagesList = [];
    }

    // ✅ FIX: FORCE RESET _editingFeedbackId to prevent ID carryover between sessions
    // CRITICAL: Always start clean, then load existing feedback only if explicitly provided
    _editingFeedbackId = null; // ✅ FORCE RESET - always start clean

    // Only set editing ID if we're explicitly editing an existing feedback
    if (widget.feedbackId != null && widget.feedbackId!.isNotEmpty) {
      _editingFeedbackId = widget.feedbackId;
      debugPrint('INIT: Loading existing temp feedback: $_editingFeedbackId');
      _loadExistingTemporaryFeedback(_editingFeedbackId!);
    } else {
      debugPrint('INIT: Starting new feedback (clean slate)');
      // ✅ New feedback: set creator name and UID to current user
      _originalCreatorName = currentUser?.name;
      _originalCreatorUid = FirebaseAuth.instance.currentUser?.uid;
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
  /// CRITICAL: Does NOT update existing controller during build to prevent value transformation
  TextEditingController _getController(String key, String initialValue) {
    if (!_textControllers.containsKey(key)) {
      // ✅ CREATE NEW: Only happens once per key
      _textControllers[key] = TextEditingController(text: initialValue);
      debugPrint(
        '🆕 CONTROLLER CREATED: key=$key, initialValue="$initialValue"',
      );
      // 🔥 WEB LONG RANGE DEBUG: Verify raw points preservation
      if (kIsWeb && _rangeType == 'ארוכים' && initialValue.isNotEmpty) {
        debugPrint(
          '   🌐 LR_WEB_CONTROLLER_CREATE: RAW value="$initialValue" (must be points, not normalized)',
        );
      }
    } else {
      // ✅ EXISTING CONTROLLER: DO NOT UPDATE during build
      // This prevents feedback loop where build -> update controller -> rebuild -> update again
      // Controller text should ONLY change from:
      // 1. User typing (onChanged)
      // 2. Explicit programmatic updates (like loading from Firestore)
      debugPrint(
        '♻️ CONTROLLER REUSED: key=$key, currentText="${_textControllers[key]!.text}", wouldBeInitialValue="$initialValue"',
      );
      // 🔥 WEB LONG RANGE DEBUG: Detect potential normalization issue
      if (kIsWeb && _rangeType == 'ארוכים') {
        final currentText = _textControllers[key]!.text;
        if (currentText != initialValue &&
            currentText.isNotEmpty &&
            initialValue.isNotEmpty) {
          debugPrint(
            '   ⚠️ LR_WEB_CONTROLLER_REUSE: MISMATCH detected! current="$currentText" vs initial="$initialValue"',
          );
          debugPrint(
            '   This may indicate stale controller values after load.',
          );
        }
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

  /// ✅ LOAD TRAINEES FOR AUTOCOMPLETE (474 only)
  Future<void> _loadTraineesForAutocomplete(String settlement) async {
    debugPrint(
      '🔄 _loadTraineesForAutocomplete called with settlement: $settlement',
    );

    if (settlement.isEmpty) {
      debugPrint('⚠️ Settlement is empty, clearing autocomplete list');
      setState(() => _autocompleteTrainees = []);
      return;
    }

    debugPrint(
      '📥 Calling TraineeAutocompleteService.getTraineesForSettlement...',
    );
    final trainees = await TraineeAutocompleteService.getTraineesForSettlement(
      settlement,
    );
    debugPrint('📋 Received ${trainees.length} trainees from service');

    if (mounted) {
      setState(() => _autocompleteTrainees = trainees);
      debugPrint(
        '✅ _autocompleteTrainees updated with ${trainees.length} items',
      );
    }
  }

  /// ✨ NEW: Open trainee selection dialog and auto-fill table
  Future<void> _openTraineeSelectionDialog() async {
    if (_autocompleteTrainees.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('טוען רשימת חניכים...')));
      return;
    }

    // ✅ שלח את החניכים הנוכחיים כ-preSelected כדי לאפשר עריכה
    final currentTrainees = traineeRows.map((row) => row.name).toList();

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => TraineeSelectionDialog(
        settlementName: settlementName,
        availableTrainees: _autocompleteTrainees,
        preSelectedTrainees:
            currentTrainees, // ✅ החניכים הנוכחיים יופיעו מסומנים
      ),
    );

    // ✅ אפשר לקבל גם רשימה ריקה אם המשתמש ניקה את כולם
    if (result != null) {
      setState(() {
        // Update attendees count
        attendeesCount = result.length;
        _attendeesCountController.text = attendeesCount.toString();

        // ✅ שמירת נתונים קיימים - יוצרים Map של שם → TraineeRowModel
        final existingDataMap = <String, TraineeRowModel>{};
        for (final row in traineeRows) {
          if (row.name.trim().isNotEmpty) {
            existingDataMap[row.name] = row;
          }
        }

        // Clear existing trainees
        traineeRows.clear();

        // Fill in selected trainees - שמירת נתונים של חניכים קיימים
        for (int i = 0; i < result.length; i++) {
          final selectedName = result[i];

          // אם החניך כבר היה ברשימה - שמור את הנתונים שלו
          if (existingDataMap.containsKey(selectedName)) {
            final existingRow = existingDataMap[selectedName]!;
            traineeRows.add(
              TraineeRowModel(
                index: i,
                name: selectedName,
                values: Map<int, int>.from(existingRow.values),
                timeValues: Map<int, double>.from(existingRow.timeValues),
                valuesTouched: Map<int, bool>.from(existingRow.valuesTouched),
                timeValuesTouched: Map<int, bool>.from(
                  existingRow.timeValuesTouched,
                ),
              ),
            );
          } else {
            // חניך חדש - צור שורה ריקה
            traineeRows.add(TraineeRowModel(index: i, name: selectedName));
          }
        }

        // ✅ נקה controllers כדי לאלץ יצירה מחדש עם אינדקסים מעודכנים
        // כשמסירים/מוסיפים חניכים, האינדקסים משתנים ו-controllers ישנים
        // עם keys כמו "trainee_1_station_0" לא תואמים יותר
        debugPrint(
          '🧹 Clearing ${_textControllers.length} controllers after trainee selection change',
        );
        for (final controller in _textControllers.values) {
          controller.dispose();
        }
        _textControllers.clear();
      });

      // ✅ FIX: Save trainee names immediately after selection
      _scheduleAutoSave();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isEmpty ? 'הרשימה נוקתה' : 'נבחרו ${result.length} חניכים',
          ),
        ),
      );
    }
  }

  /// ✅ BUILD TRAINEE NAME FIELD - SMART AUTOCOMPLETE
  /// Automatically shows autocomplete for 474 folders, regular TextField otherwise
  Widget _buildTraineeAutocomplete({
    required int idx,
    required TraineeRowModel row,
    required String controllerKey,
    required String focusKey,
  }) {
    // ✅ Determine if should show autocomplete
    final bool shouldShowAutocomplete =
        (widget.mode == 'range' && rangeFolder == 'מטווחים 474') ||
        (widget.mode == 'surprise' &&
            surpriseDrillsFolder == 'משוב תרגילי הפתעה');

    final bool hasAutocompleteData = _autocompleteTrainees.isNotEmpty;

    // 🔍 DEBUG: Log on first trainee only
    if (idx == 0) {
      debugPrint('🎯 _buildTraineeAutocomplete called:');
      debugPrint('   widget.mode: ${widget.mode}');
      debugPrint('   rangeFolder: $rangeFolder');
      debugPrint('   surpriseDrillsFolder: $surpriseDrillsFolder');
      debugPrint('   shouldShowAutocomplete: $shouldShowAutocomplete');
      debugPrint(
        '   hasAutocompleteData: $hasAutocompleteData (${_autocompleteTrainees.length} items)',
      );
    }

    // If autocomplete should be shown AND we have data - use RawAutocomplete
    if (shouldShowAutocomplete && hasAutocompleteData) {
      return RawAutocomplete<String>(
        textEditingController: _getController(controllerKey, row.name),
        focusNode: _getFocusNode(focusKey),
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return _autocompleteTrainees.take(8);
          }
          return TraineeAutocompleteService.filterTrainees(
            _autocompleteTrainees,
            textEditingValue.text,
            maxResults: 8,
          );
        },
        onSelected: (String selection) {
          row.name = selection;
          _getController(controllerKey, row.name).text = selection;
          _scheduleAutoSave();
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: const InputDecoration(
              hintText: 'שם',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            onChanged: (_) {
              row.name = controller.text;
              _scheduleAutoSave();
            },
            onSubmitted: (_) {
              row.name = controller.text;
              onFieldSubmitted();
              _saveImmediately();
            },
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topRight,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 200,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(
                        option,
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right,
                      ),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    }

    // Otherwise - return regular TextField
    return TextField(
      controller: _getController(controllerKey, row.name),
      focusNode: _getFocusNode(focusKey),
      decoration: const InputDecoration(
        hintText: 'שם',
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12),
      maxLines: 1,
      onChanged: (_) {
        final currentController = _getController(controllerKey, row.name);
        row.name = currentController.text;
        _scheduleAutoSave();
      },
      onSubmitted: (_) {
        final currentController = _getController(controllerKey, row.name);
        row.name = currentController.text;
        _saveImmediately();
      },
    );
  }

  /// אוסף את רשימת שמות המדריכים מהבקרים (מסנן ריקים)
  List<String> _collectInstructorNames() {
    final List<String> validInstructors = [];
    for (int i = 0; i < instructorsCount; i++) {
      final controller = _instructorNameControllers['instructor_$i'];
      final name = controller?.text.trim() ?? '';
      if (name.isNotEmpty) {
        validInstructors.add(name);
      }
    }
    return validInstructors;
  }

  /// ✅ DEBOUNCED AUTOSAVE: Schedule autosave after 700ms of inactivity
  void _scheduleAutoSave() {
    // 🆕 Don't autosave until settlement is entered
    // Check: selectedSettlement (dropdown), settlementName (free text), or manualSettlementText (ידני)
    final hasSettlement =
        (selectedSettlement != null &&
            selectedSettlement!.isNotEmpty &&
            selectedSettlement != 'יישוב ידני') ||
        settlementName.trim().isNotEmpty ||
        manualSettlementText.trim().isNotEmpty;
    if (!hasSettlement) {
      debugPrint('⏸️ AUTOSAVE: Skipping - no settlement entered yet');
      return;
    }

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 700), () {
      debugPrint('🔄 AUTOSAVE: Timer triggered (700ms debounce)');
      _saveTemporarily();
    });
  }

  /// ✅ IMMEDIATE SAVE: Triggered when user leaves a field (focus loss)
  void _saveImmediately() {
    // 🆕 Don't save until settlement is entered
    // Check: selectedSettlement (dropdown), settlementName (free text), or manualSettlementText (ידני)
    final hasSettlement =
        (selectedSettlement != null &&
            selectedSettlement!.isNotEmpty &&
            selectedSettlement != 'יישוב ידני') ||
        settlementName.trim().isNotEmpty ||
        manualSettlementText.trim().isNotEmpty;
    if (!hasSettlement) {
      debugPrint('⏸️ IMMEDIATE SAVE: Skipping - no settlement entered yet');
      return;
    }

    _autoSaveTimer?.cancel(); // Cancel pending debounced save
    debugPrint('⚡ IMMEDIATE SAVE: Saving now');
    _saveTemporarily();
  }

  /// ✅ תאריך מותאם אישית - רק עבור אדמין יותם
  Future<void> _selectDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );

    if (pickedTime == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _dateManuallySet = true;
    });

    _scheduleAutoSave();
  }

  @override
  void dispose() {
    _draftListener?.cancel(); // ✅ Cancel real-time listener
    _autoSaveTimer?.cancel();
    _attendeesCountController.dispose();
    _instructorsCountController.dispose();
    _manualStageController.dispose();
    _trainingSummaryController.dispose();
    // Dispose instructor name controllers
    for (final controller in _instructorNameControllers.values) {
      controller.dispose();
    }
    _instructorNameControllers.clear();
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
    // For Surprise Drills: show dropdown with settlements + Manual Location
    // For Range mode: show dropdown with settlements + יישוב ידני
    final isSurpriseMode = widget.mode == 'surprise';
    final items = isSurpriseMode
        ? [...golanSettlements, 'Manual Location']
        : [...golanSettlements, 'יישוב ידני'];

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
                  children: [
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
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = items[i];
                      final isManualOption =
                          s == 'Manual Location' || s == 'יישוב ידני';
                      return ListTile(
                        leading: isManualOption
                            ? const Icon(
                                Icons.edit_location_alt,
                                color: Colors.orangeAccent,
                              )
                            : null,
                        title: Text(
                          s,
                          style: TextStyle(
                            color: isManualOption
                                ? Colors.orangeAccent
                                : Colors.white,
                            fontWeight: isManualOption
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            if (s == 'Manual Location') {
                              // Surprise Drills manual location
                              isManualLocation = true;
                              isManualSettlement = false;
                              selectedSettlement = 'Manual Location';
                              _settlementDisplayText = 'Manual Location';
                              // Clear autocomplete for manual locations
                              _autocompleteTrainees = [];
                            } else if (s == 'יישוב ידני') {
                              // Range mode manual settlement
                              isManualSettlement = true;
                              isManualLocation = false;
                              selectedSettlement = 'יישוב ידני';
                              _settlementDisplayText = 'יישוב ידני';
                              // Clear autocomplete for manual settlements
                              _autocompleteTrainees = [];
                            } else {
                              isManualLocation = false;
                              isManualSettlement = false;
                              selectedSettlement = s;
                              settlementName = s;
                              _settlementDisplayText = s;
                              manualLocationText = '';
                              manualSettlementText = '';

                              // 🔍 DEBUG: Check conditions for autocomplete
                              debugPrint('🔍 Settlement selected: $s');
                              debugPrint('   widget.mode: ${widget.mode}');
                              debugPrint('   rangeFolder: $rangeFolder');
                              debugPrint(
                                '   surpriseDrillsFolder: $surpriseDrillsFolder',
                              );

                              // ✅ Load trainees for autocomplete (474 only)
                              if (widget.mode == 'range' &&
                                  rangeFolder == 'מטווחים 474') {
                                debugPrint('   ✅ Condition MET for range 474!');
                                _loadTraineesForAutocomplete(s);
                              } else if (widget.mode == 'range') {
                                // ⚠️ ALWAYS load for ALL range folders (not just 474)
                                debugPrint(
                                  '   🔄 Loading for rangeFolder: $rangeFolder',
                                );
                                _loadTraineesForAutocomplete(s);
                              }
                              // ✅ Load trainees for Surprise Drills 474
                              if (widget.mode == 'surprise' &&
                                  surpriseDrillsFolder == 'משוב תרגילי הפתעה') {
                                debugPrint(
                                  '   ✅ Condition MET for surprise 474!',
                                );
                                _loadTraineesForAutocomplete(s);
                              }
                            }
                          });
                          Navigator.pop(ctx);
                          _scheduleAutoSave();
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
        // Add new rows - try to restore from loaded draft
        for (int i = traineeRows.length; i < count; i++) {
          if (i < _loadedDraftTrainees.length &&
              _loadedDraftTrainees[i].name.trim().isNotEmpty) {
            // Restore from loaded draft with saved name and values
            traineeRows.add(
              TraineeRowModel(
                index: i,
                name: _loadedDraftTrainees[i].name,
                values: Map<int, int>.from(_loadedDraftTrainees[i].values),
              ),
            );
            debugPrint(
              '   Restored trainee $i: "${_loadedDraftTrainees[i].name}"',
            );
          } else {
            // Create new empty row
            traineeRows.add(TraineeRowModel(index: i, name: ''));
          }
        }
      } else if (count < traineeRows.length) {
        // Remove excess rows
        traineeRows = traineeRows.sublist(0, count);

        // ✅ נקה controllers כי האינדקסים השתנו במקרה של הסרה
        debugPrint(
          '🧹 Clearing ${_textControllers.length} controllers after attendees count change',
        );
        for (final controller in _textControllers.values) {
          controller.dispose();
        }
        _textControllers.clear();
      }
    });

    debugPrint(
      '   After update: traineeRows.length=${traineeRows.length}, attendeesCount=$attendeesCount',
    );
    debugPrint('   traineeRows isEmpty: ${traineeRows.isEmpty}');

    // ✅ Schedule autosave
    _scheduleAutoSave();
  }

  // Short Range: Add a new stage to the list
  void _addShortRangeStage() {
    debugPrint('\n🔍 DEBUG: _addShortRangeStage called');
    debugPrint(
      '   Before add: shortRangeStagesList.length=${shortRangeStagesList.length}',
    );

    setState(() {
      shortRangeStagesList.add(
        const ShortRangeStageModel(
          selectedStage: null,
          manualName: '',
          isManual: false,
          bulletsCount: 0,
        ),
      );
    });

    debugPrint(
      '   After add: shortRangeStagesList.length=${shortRangeStagesList.length}',
    );
    _scheduleAutoSave();
  }

  // Short Range: Remove a stage from the list
  void _removeShortRangeStage(int index) {
    if (shortRangeStagesList.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('חייב להיות לפחות מקצה אחד')),
      );
      return;
    }

    setState(() {
      shortRangeStagesList.removeAt(index);

      // Update stations list to match
      if (index < stations.length) {
        // Remove station data from all trainee rows and shift indices
        for (var row in traineeRows) {
          row.values.remove(index);
          row.timeValues.remove(index); // Also remove time values for בוחן רמה
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

          // Also shift timeValues indices
          final updatedTimeValues = <int, double>{};
          row.timeValues.forEach((stationIdx, value) {
            if (stationIdx > index) {
              updatedTimeValues[stationIdx - 1] = value;
            } else {
              updatedTimeValues[stationIdx] = value;
            }
          });
          row.timeValues.clear();
          row.timeValues.addAll(updatedTimeValues);
        }

        stations.removeAt(index);
      }
    });

    debugPrint(
      '   After remove: shortRangeStagesList.length=${shortRangeStagesList.length}',
    );
    _scheduleAutoSave();
  }

  // Long Range: Add a new stage to the list (like Short Range - no pre-selection needed)
  void _addLongRangeStage() {
    debugPrint('\n🔍 DEBUG: _addLongRangeStage called');
    debugPrint(
      '   Before add: longRangeStagesList.length=${longRangeStagesList.length}',
    );

    setState(() {
      longRangeStagesList.add(
        LongRangeStageModel(
          name: '', // Empty name - user will select from dropdown
          bulletsCount: 0,
          isManual: false,
        ),
      );
    });

    debugPrint(
      '   After add: longRangeStagesList.length=${longRangeStagesList.length}',
    );
    _scheduleAutoSave();
  }

  // Long Range: Remove a stage from the list
  void _removeLongRangeStage(int index) {
    // Allow removing all stages (no minimum requirement)
    setState(() {
      longRangeStagesList.removeAt(index);

      // Update trainee data: shift stage indices
      for (var row in traineeRows) {
        row.values.remove(index);
        // Shift indices down for stages after removed one
        final updatedValues = <int, int>{};
        row.values.forEach((stageIdx, value) {
          if (stageIdx > index) {
            updatedValues[stageIdx - 1] = value;
          } else {
            updatedValues[stageIdx] = value;
          }
        });
        row.values.clear();
        row.values.addAll(updatedValues);
      }
    });

    debugPrint(
      '   After remove: longRangeStagesList.length=${longRangeStagesList.length}',
    );
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

  /// Get total bullets for ALL stages - SHORT RANGE AND SURPRISE ONLY (FOR FORM DISPLAY)
  /// Used during form editing to show total possible bullets
  /// Long range has its own tracking function: _getTotalBulletsLongRangeTracking()
  int _getTotalBulletsAllStages() {
    // For Short Range, use shortRangeStagesList
    if (_rangeType == 'קצרים' && shortRangeStagesList.isNotEmpty) {
      int total = 0;
      for (var stage in shortRangeStagesList) {
        total += stage.bulletsCount;
      }
      return total;
    }
    // ⚠️ LONG RANGE: Should NOT call this function - use points instead
    if (_rangeType == 'ארוכים') {
      return 0;
    }
    // For Surprise, use stations list
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

  // ===== SURPRISE DRILLS FIXED MAXPOINTS =====
  // For Surprise Drills, maxPoints is ALWAYS 10 for each principle
  static const int _surpriseMaxPointsPerPrinciple = 10;

  // Get maxPoints for a specific principle (Surprise Drills)
  // Always returns 10 for surprise mode
  int _getMaxPointsForPrinciple(int principleIndex) {
    if (widget.mode != 'surprise') return 0;
    return _surpriseMaxPointsPerPrinciple;
  }

  // ✅ SURPRISE DRILLS: Calculate average score (0-10) from filled principle scores
  // Average = sum(filled scores) / count(filled scores)
  // Ignores empty/zero scores
  double _getTraineeAveragePoints(int traineeIndex) {
    if (traineeIndex >= traineeRows.length) return 0.0;
    if (widget.mode != 'surprise') return 0.0;

    final trainee = traineeRows[traineeIndex];
    final filledScores = trainee.values.values
        .where((score) => score > 0)
        .toList();

    if (filledScores.isEmpty) return 0.0;

    final sum = filledScores.reduce((a, b) => a + b);
    return sum / filledScores.length;
  }

  // ===== LONG RANGE POINTS CALCULATION (NEW) =====
  // For Long Range, values represent POINTS ACHIEVED (not hits)
  // Totals are: sum(points) / sum(maxPoints)

  /// Get total points achieved by trainee (Long Range only)
  int _getTraineeTotalPointsLongRange(int traineeIndex) {
    if (traineeIndex >= traineeRows.length) return 0;
    if (_rangeType != 'ארוכים') return 0;

    int total = 0;
    traineeRows[traineeIndex].values.forEach((stationIndex, points) {
      if (points > 0) {
        total += points;
      }
    });
    return total;
  }

  /// ===== V2 DATA MODEL FOR LONG-RANGE FEEDBACKS =====
  /// Build canonical V2 data structure from current UI state
  /// V2 ensures points/points calculations (bullets never affect scoring)
  Map<String, dynamic> _buildLrV2() {
    if (_rangeType != 'ארוכים') return {};

    final N = traineeRows.length;
    if (N == 0 || longRangeStagesList.isEmpty) return {};

    // Build stages array with maxScorePoints (NOT bullets!)
    final List<Map<String, dynamic>> stages = [];
    for (int i = 0; i < longRangeStagesList.length; i++) {
      final stage = longRangeStagesList[i];
      stages.add({
        'id': 'stage_$i',
        'name': stage.name,
        'maxScorePoints': stage.maxPoints, // Instructor-entered max score
        'bulletsTracking':
            stage.bulletsCount, // Tracking only, never used for scoring
      });
    }

    // Build trainee values map: { traineeKey: { stageId: pointsRaw } }
    final Map<String, Map<String, int>> traineeValues = {};
    for (int tIdx = 0; tIdx < traineeRows.length; tIdx++) {
      final row = traineeRows[tIdx];
      final traineeKey = 'trainee_$tIdx';
      final Map<String, int> stagePoints = {};

      row.values.forEach((stationIdx, points) {
        if (stationIdx < stages.length) {
          final stageId = 'stage_$stationIdx';
          stagePoints[stageId] = points; // Store RAW points as entered
        }
      });

      traineeValues[traineeKey] = stagePoints;
    }

    return {
      'version': 2,
      'traineesCount': N,
      'stages': stages,
      'traineeValues': traineeValues,
    };
  }

  /// Migrate legacy long-range feedback to V2 model
  /// Returns V2 structure ready to persist to Firestore
  Map<String, dynamic> _migrateLongRangeToV2(
    Map<String, dynamic> feedbackData,
  ) {
    debugPrint('\n🔄 ===== LR_V2_MIGRATION START =====');

    final rawStations = feedbackData['stations'] as List?;
    final rawTrainees = feedbackData['trainees'] as List?;

    if (rawStations == null || rawTrainees == null) {
      debugPrint(
        '⚠️ LR_V2_MIGRATION: Missing stations or trainees, cannot migrate',
      );
      debugPrint('🔄 ===== LR_V2_MIGRATION END (FAILED) =====\n');
      return {};
    }

    final N = rawTrainees.length;
    debugPrint('🔄 LR_V2_MIGRATION: N=$N trainees');

    // Build stages array
    final List<Map<String, dynamic>> stages = [];
    for (int i = 0; i < rawStations.length; i++) {
      final stationData = rawStations[i] as Map<String, dynamic>?;
      if (stationData == null) continue;

      final name = stationData['name'] as String? ?? 'Stage ${i + 1}';

      // Determine maxScorePoints from legacy data
      int maxScorePoints = 0;
      if (stationData.containsKey('maxPoints')) {
        maxScorePoints = (stationData['maxPoints'] as num?)?.toInt() ?? 0;
      } else if (stationData.containsKey('maxScorePoints')) {
        maxScorePoints = (stationData['maxScorePoints'] as num?)?.toInt() ?? 0;
      }
      // If neither exists, leave as 0 (mark as missing max)

      final bulletsTracking =
          (stationData['bulletsCount'] as num?)?.toInt() ?? 0;

      stages.add({
        'id': 'stage_$i',
        'name': name,
        'maxScorePoints': maxScorePoints,
        'bulletsTracking': bulletsTracking,
      });

      debugPrint(
        '🔄   Stage[$i]: "$name" maxScorePoints=$maxScorePoints (bullets=$bulletsTracking tracking-only)',
      );
    }

    // Build trainee values
    final Map<String, Map<String, int>> traineeValues = {};
    for (int tIdx = 0; tIdx < rawTrainees.length; tIdx++) {
      final traineeData = rawTrainees[tIdx] as Map<String, dynamic>?;
      if (traineeData == null) continue;

      final traineeName =
          traineeData['name'] as String? ?? 'Trainee ${tIdx + 1}';
      final traineeKey = 'trainee_$tIdx';
      final hitsMap = traineeData['hits'] as Map<String, dynamic>? ?? {};

      final Map<String, int> stagePoints = {};
      hitsMap.forEach((key, value) {
        // Key format: station_0, station_1, etc.
        final match = RegExp(r'station_(\d+)').firstMatch(key);
        if (match != null) {
          final stationIdx = int.parse(match.group(1)!);
          if (stationIdx < stages.length) {
            final stageId = 'stage_$stationIdx';
            final pointsRaw = (value as num?)?.toInt() ?? 0;
            stagePoints[stageId] =
                pointsRaw; // Use stored value AS-IS (no normalization)
          }
        }
      });

      traineeValues[traineeKey] = stagePoints;
      debugPrint('🔄   Trainee[$tIdx]: "$traineeName" points=$stagePoints');
    }

    final v2Data = {
      'version': 2,
      'traineesCount': N,
      'stages': stages,
      'traineeValues': traineeValues,
    };

    debugPrint('🔄 LR_V2_MIGRATION: Created V2 model');
    debugPrint('🔄   totalStages=${stages.length}');
    debugPrint('🔄   totalTrainees=$N');
    debugPrint('🔄 ===== LR_V2_MIGRATION END (SUCCESS) =====\n');

    return v2Data;
  }

  /// Calculate summary using V2 data model
  /// Returns { totalAchieved, totalMax, stageResults: [{stageId, achieved, max}] }
  Map<String, dynamic> _calculateSummaryFromV2(Map<String, dynamic> lrV2) {
    final stages = lrV2['stages'] as List? ?? [];
    final traineeValues = lrV2['traineeValues'] as Map<String, dynamic>? ?? {};
    final N = lrV2['traineesCount'] as int? ?? 0;

    int totalAchieved = 0;
    int totalMax = 0;
    final List<Map<String, dynamic>> stageResults = [];

    for (int i = 0; i < stages.length; i++) {
      final stageData = stages[i] as Map<String, dynamic>;
      final stageId = stageData['id'] as String;
      final maxScorePoints =
          (stageData['maxScorePoints'] as num?)?.toInt() ?? 0;

      // Calculate achieved points for this stage across all trainees
      int stageAchieved = 0;
      traineeValues.forEach((traineeKey, stagePoints) {
        if (stagePoints is Map<String, dynamic>) {
          final points = (stagePoints[stageId] as num?)?.toInt() ?? 0;
          stageAchieved += points;
        }
      });

      // Per-stage max = N * maxScorePoints
      final stageMax = N * maxScorePoints;

      stageResults.add({
        'stageId': stageId,
        'stageName': stageData['name'] as String? ?? '',
        'achieved': stageAchieved,
        'max': stageMax,
      });

      totalAchieved += stageAchieved;
      totalMax += stageMax;
    }

    return {
      'totalAchieved': totalAchieved,
      'totalMax': totalMax,
      'stageResults': stageResults,
    };
  }

  /// Get total max points across all Long Range stages
  /// ✅ FIX: Formula: SUM(stage.maxPoints * trainees_who_performed_this_stage)
  /// Only count max points for stages that trainees actually performed
  /// Example: 3 trainees, 3 stages (100,100,100), only 2 performed stage 1 → 2*100 + 3*100 + 3*100 = 800
  int _getTotalMaxPointsLongRange() {
    if (_rangeType != 'ארוכים') return 0;
    if (longRangeStagesList.isEmpty) return 0;

    // N = number of trainees in this feedback
    final N = traineeRows.length;
    if (N == 0) return 0;

    // ✅ FIX: Count max points only for stages performed
    int totalMaxPoints = 0;
    final List<String> debugLog = [];

    for (int stageIdx = 0; stageIdx < longRangeStagesList.length; stageIdx++) {
      final stage = longRangeStagesList[stageIdx];
      // Count how many trainees performed this stage
      int traineesPerformed = 0;
      for (final trainee in traineeRows) {
        if (trainee.valuesTouched[stageIdx] == true) {
          traineesPerformed++;
        }
      }

      final stageMaxPoints = stage.maxPoints * traineesPerformed;
      totalMaxPoints += stageMaxPoints;
      debugLog.add(
        'Stage $stageIdx: ${stage.maxPoints} × $traineesPerformed = $stageMaxPoints',
      );
    }

    // 🔍 DEBUG: Log calculation breakdown
    debugPrint('\n🎯 LONG-RANGE SUMMARY DENOMINATOR CALCULATION (FIXED):');
    debugPrint('   Total trainees = $N');
    for (final log in debugLog) {
      debugPrint('   $log');
    }
    debugPrint('   totalMaxPoints = $totalMaxPoints (only performed stages)');
    debugPrint('   Expected format: achieved/$totalMaxPoints\n');

    return totalMaxPoints;
  }

  /// Get total max points for Long Range edit table (UI-only)
  /// Formula: SUM(stage.maxPoints) - NOT multiplied by trainees
  /// Example: 3 stages (100,100,150) → 100 + 100 + 150 = 350
  /// This is for edit table display only, NOT for final summary calculations
  int _getTotalMaxPointsLongRangeEditTable() {
    if (_rangeType != 'ארוכים') return 0;
    if (longRangeStagesList.isEmpty) return 0;

    // Sum all stage maxPoints (no trainee multiplication)
    int sumOfStageMaxPoints = 0;
    for (var stage in longRangeStagesList) {
      sumOfStageMaxPoints += stage.maxPoints;
    }

    return sumOfStageMaxPoints;
  }

  /// Edit-table-only: Calculate percent for a stage row (Long Range)
  /// percent = (rowEarnedPoints / stage.maxPoints) * 100
  /// rowEarnedPoints = sum of all trainee points for this stage
  double calcEditStagePercent(int stageIdx) {
    if (_rangeType != 'ארוכים' ||
        stageIdx < 0 ||
        stageIdx >= longRangeStagesList.length) {
      return 0.0;
    }
    final maxPoints = longRangeStagesList[stageIdx].maxPoints;
    if (maxPoints == 0) return 0.0;
    int earned = 0;
    for (final row in traineeRows) {
      final v = row.values[stageIdx] ?? 0;
      if (v > 0) earned += v;
    }
    return (earned / maxPoints) * 100.0;
  }

  /// REMOVED: _getTraineeTotalBulletsLongRange
  /// Long range uses POINTS ONLY - bullets are for tracking/display only, not calculations

  /// Get total bullets for long range (TRACKING/DISPLAY ONLY - does NOT affect scoring)
  /// This is purely for displaying how many bullets were fired, not for calculations
  int _getTotalBulletsLongRangeTracking() {
    int total = 0;
    for (var stage in longRangeStagesList) {
      total += stage.bulletsCount;
    }
    return total;
  }

  /// Get average percentage for trainee (Long Range points-based)
  double _getTraineeAveragePercentLongRange(int traineeIndex) {
    final totalPoints = _getTraineeTotalPointsLongRange(traineeIndex);
    final totalMaxPoints = _getTotalMaxPointsLongRange();
    if (totalMaxPoints == 0) return 0.0;
    return (totalPoints / totalMaxPoints) * 100;
  }

  // ⚠️ פונקציות הייצוא הוסרו - הייצוא יבוצע רק מדף המשובים (Admin בלבד)
  // ייצוא לקובץ XLSX מקומי יתבוצע על משובים שכבר נשמרו בלבד

  Future<void> _saveToFirestore() async {
    // בדיקות תקינות - REQUIRED folder selection for Long Range (NOT for Surprise)
    // Surprise Drill has a fixed folder, no selection needed
    // ✅ IMPROVED: Check BOTH rangeFolder (UI) and loadedFolderKey (from draft)
    if (widget.mode != 'surprise') {
      final hasUIFolder = rangeFolder != null && rangeFolder!.isNotEmpty;
      final hasDraftFolder =
          loadedFolderKey != null && loadedFolderKey!.isNotEmpty;

      if (!hasUIFolder && !hasDraftFolder) {
        debugPrint(
          '❌ SAVE VALIDATION: No folder selected (UI: $rangeFolder, Draft: $loadedFolderKey)',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('אנא בחר תיקייה')));
        return;
      }
    }

    // Long Range: Validate folder is exactly one of the allowed options
    // ✅ IMPROVED: Accept valid loadedFolderKey even if rangeFolder UI is not set
    if (_rangeType == 'ארוכים' && widget.mode == 'range') {
      final hasValidUIFolder =
          rangeFolder == 'מטווחים 474' || rangeFolder == 'מטווחי ירי';
      final hasValidDraftFolder =
          loadedFolderKey == 'ranges_474' ||
          loadedFolderKey == 'shooting_ranges';

      if (!hasValidUIFolder && !hasValidDraftFolder) {
        debugPrint(
          '❌ SAVE VALIDATION: Invalid folder (UI: $rangeFolder, Draft: $loadedFolderKey)',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('אנא בחר תיקייה תקינה: מטווחים 474 או מטווחי ירי'),
          ),
        );
        return;
      }
    }

    if (settlementName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן יישוב')));
      return;
    }

    if (attendeesCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן כמות נוכחים')));
      return;
    }

    // Short Range: Validate at least one stage exists
    if (_rangeType == 'קצרים') {
      if (shortRangeStagesList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('אנא הוסף לפחות מקצה אחד')),
        );
        return;
      }

      // Validate all stages have names
      for (final stage in shortRangeStagesList) {
        if (stage.isManual && stage.manualName.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('אנא הזן שם למקצה ידני')),
          );
          return;
        }
      }
    }

    // Long Range: Validate multi-stage list
    if (_rangeType == 'ארוכים') {
      if (longRangeStagesList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('אנא הוסף לפחות מקצה אחד')),
        );
        return;
      }

      for (int i = 0; i < longRangeStagesList.length; i++) {
        final stage = longRangeStagesList[i];
        if (stage.name.trim().isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('אנא הזן שם למקצה ${i + 1}')));
          return;
        }
        if (stage.bulletsCount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('אנא הזן מספר כדורים תקין למקצה ${i + 1}')),
          );
          return;
        }
      }
    }

    // Surprise: וידוא שכל העקרונות מוגדרים
    if (widget.mode == 'surprise' && _rangeType != 'קצרים') {
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
          if (stations[i].timeSeconds == null ||
              stations[i].timeSeconds! <= 0) {
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
                content: Text(
                  'אנא הזן פגיעות תקינות למקצה ${i + 1} (בוחן רמה)',
                ),
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
    } // End of Long Range/Surprise validation

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

    // ✅ PERMISSION CHECK: Only creator or admin can finalize feedback
    // This check uses cached _originalCreatorUid (loaded during initState) - NO extra Firestore read
    if (_editingFeedbackId != null && _editingFeedbackId!.isNotEmpty) {
      final isAdmin = currentUser?.role == 'Admin';
      final isCreator = _originalCreatorUid == uid;

      if (!isAdmin && !isCreator) {
        debugPrint(
          '❌ PERMISSION DENIED: User $uid cannot finalize feedback created by $_originalCreatorUid',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('רק היוצר של המשוב או אדמין יכולים לסיים משוב'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return; // ❌ Block finalize for collaborators
      }
      debugPrint(
        '✅ PERMISSION GRANTED: User $uid (${isAdmin ? "Admin" : "Creator"}) can finalize feedback',
      );
    }

    setState(() => _isSaving = true);

    try {
      // הכנת הנתונים לשמירה
      final String subFolder = widget.mode == 'surprise'
          ? 'תרגילי הפתעה'
          : (_rangeType == 'קצרים' ? 'דיווח קצר' : 'דיווח רחוק');

      // ====== UNIFIED FOLDER KEYS ======
      // ✅ PRIORITY: Use loaded folder fields from draft if available (prevents recomputation bugs)
      // If not loaded from draft, map UI selection to canonical folderKey and folderLabel
      String folderKey;
      String folderLabel;
      String folderId = '';
      final String uiFolderValue = (rangeFolder ?? '')
          .toString(); // ✅ Declare outside for logging

      debugPrint('\n========== FOLDER RESOLUTION START ==========');
      debugPrint('FOLDER_RESOLVE: uiFolderValue="$uiFolderValue"');
      debugPrint('FOLDER_RESOLVE: loadedFolderKey="$loadedFolderKey"');
      debugPrint('FOLDER_RESOLVE: loadedFolderLabel="$loadedFolderLabel"');
      debugPrint('FOLDER_RESOLVE: rangeFolder="$rangeFolder"');
      debugPrint(
        'FOLDER_RESOLVE: Is loading from draft? ${loadedFolderKey != null && loadedFolderKey!.isNotEmpty}',
      );

      // ✅ FIX: ALWAYS prioritize loaded folder values from draft to prevent folder switching bug
      // When user loads a draft and returns to it, the folder should remain exactly as saved
      if (loadedFolderKey != null && loadedFolderKey!.isNotEmpty) {
        // ✅ CRITICAL: Use draft folder values - DO NOT recompute from UI
        folderKey = loadedFolderKey!;
        folderLabel =
            loadedFolderLabel ?? folderKey; // Fallback to key if label missing
        folderId = folderKey; // Use folderKey as folderId
        debugPrint(
          'FOLDER_RESOLVE: ✅ Using LOADED folder fields from draft: folderKey=$folderKey folderLabel=$folderLabel',
        );
        debugPrint(
          'FOLDER_RESOLVE: ✅ DRAFT FOLDER PRESERVED - no UI recomputation',
        );
      } else {
        // ✅ COMPUTE FROM UI SELECTION (new feedback, not from draft)

        // SURPRISE DRILL: Use surpriseDrillsFolder selection
        if (widget.mode == 'surprise') {
          if (surpriseDrillsFolder == 'תרגילי הפתעה כללי') {
            folderKey = 'surprise_drills_general';
            folderLabel = 'תרגילי הפתעה כללי';
            folderId = 'surprise_drills_general';
          } else {
            folderKey = 'surprise_drills';
            folderLabel = 'משוב תרגילי הפתעה';
            folderId = 'surprise_drills';
          }
        }
        // Exact matching only - no fallbacks to ensure user selection is respected
        else if (uiFolderValue == 'מטווחים 474') {
          folderKey = 'ranges_474';
          folderLabel = 'מטווחים 474';
          folderId = 'ranges_474';
        } else if (uiFolderValue == 'מטווחי ירי') {
          folderKey = 'shooting_ranges';
          folderLabel = 'מטווחי ירי';
          folderId = 'shooting_ranges';
        } else {
          // Should never reach here due to validation above
          debugPrint(
            '❌ FOLDER_RESOLVE: Invalid UI folder value: $uiFolderValue',
          );
          throw Exception('Invalid folder selection: $uiFolderValue');
        }
        debugPrint(
          'FOLDER_RESOLVE: ✅ COMPUTED folder fields from UI: folderKey=$folderKey folderLabel=$folderLabel',
        );
      }

      debugPrint(
        'FOLDER_RESOLVE: Final values: folderKey=$folderKey folderLabel=$folderLabel folderId=$folderId',
      );
      debugPrint('========== FOLDER RESOLUTION END ==========\n');

      // ✅ CRITICAL VALIDATION: Ensure folder fields are never empty (defensive check)
      if (folderKey.isEmpty || folderLabel.isEmpty) {
        debugPrint(
          '❌ SAVE ERROR: Empty folder fields! folderKey="$folderKey" folderLabel="$folderLabel"',
        );
        debugPrint(
          '❌ SAVE ERROR: Draft had: loadedFolderKey="$loadedFolderKey" loadedFolderLabel="$loadedFolderLabel"',
        );
        debugPrint('❌ SAVE ERROR: UI had: rangeFolder="$rangeFolder"');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'שגיאה פנימית: נתוני תיקייה חסרים. אנא בחר תיקייה מחדש.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // ✅ Build trainees data from traineeRows model
      final List<Map<String, dynamic>> traineesData = [];

      // ⚠️ DEBUG: Log before normalization for Long Range
      if (_rangeType == 'ארוכים') {
        debugPrint('\n╔═══ LONG RANGE SAVE: BEFORE SERIALIZATION ═══╗');
        debugPrint('║ RangeType: $_rangeType');
        debugPrint('║ Total trainees: ${traineeRows.length}');
        for (int i = 0; i < traineeRows.length && i < 3; i++) {
          final row = traineeRows[i];
          debugPrint('║ Trainee[$i]: "${row.name}"');
          debugPrint('║   RAW values from model: ${row.values}');
        }
        debugPrint('╚════════════════════════════════════════════╝\n');
      }

      for (int i = 0; i < traineeRows.length; i++) {
        final row = traineeRows[i];
        if (row.name.trim().isEmpty) continue; // Skip empty names

        // ⚠️ DEBUG: Log BEFORE serialization (long-range only)
        if (_rangeType == 'ארוכים' && row.values.isNotEmpty) {
          debugPrint('\n🔍 PRE-SAVE DEBUG: Trainee "${row.name}"');
          debugPrint('   RAW row.values (from model): ${row.values}');
        }

        // Build hits map from values - include ALL stages
        // ✅ FIX: Save ALL stage data without filtering (including 0 values)
        // Filtering should ONLY apply to stats/export, NOT to saved data
        final Map<String, int> hitsMap = {};
        row.values.forEach((stationIdx, value) {
          // Include ALL stages in saved data (no filtering)
          // This ensures Details screen sees complete stage breakdown
          hitsMap['station_$stationIdx'] = value;
        });

        // Build time values map from timeValues (for בוחן רמה) - include ALL stages
        final Map<String, double> timeValuesMap = {};
        row.timeValues.forEach((stationIdx, value) {
          timeValuesMap['station_${stationIdx}_time'] = value;
        });

        // ✅ FIX: Use correct function based on range type for טווח רחוק bug fix
        // For long range (ארוכים), use _getTraineeTotalPointsLongRange() which correctly sums points
        // For short range (קצרים), use _getTraineeTotalHits() which sums hits
        final int totalValue = _rangeType == 'ארוכים'
            ? _getTraineeTotalPointsLongRange(i)
            : _getTraineeTotalHits(i);

        traineesData.add({
          'name': row.name.trim(),
          'hits': hitsMap,
          'timeValues': timeValuesMap,
          'totalHits': totalValue, // Now contains correct points for long range
          'number': i + 1,
        });
      }

      // ⚠️ DEBUG: Log after serialization for Long Range
      if (_rangeType == 'ארוכים' && traineesData.isNotEmpty) {
        debugPrint('\n╔═══ LONG RANGE SAVE: AFTER SERIALIZATION ═══╗');
        debugPrint('║ Platform: ${kIsWeb ? "WEB" : "MOBILE"}');
        debugPrint('║ Total serialized: ${traineesData.length}');
        debugPrint('║');
        debugPrint('║ ✅ VERIFICATION: RAW POINTS PRESERVATION');
        debugPrint(
          '║    Expected: Points entered by instructor (e.g., 58 stays 58)',
        );
        debugPrint(
          '║    Bug check: If 58 became 5, normalization bug detected!',
        );
        debugPrint('║');

        // ✅ STRICT VERIFICATION: Check for division bug
        bool bugDetected = false;
        for (int i = 0; i < traineesData.length && i < 3; i++) {
          final t = traineesData[i];
          final hits = t['hits'] as Map<String, dynamic>? ?? {};
          debugPrint('║ Trainee[$i]: "${t['name']}"');
          debugPrint('║   SERIALIZED hits: $hits');
          debugPrint('║   Total hits: ${t['totalHits']}');

          // 🔥 WEB VERIFICATION: Log each value explicitly
          if (kIsWeb) {
            hits.forEach((key, val) {
              debugPrint('║   🌐 WEB LR_RAW_BEFORE_SAVE: $key=$val');
            });
          }

          // Check each value for suspicious division
          hits.forEach((key, val) {
            if (val is int && val > 0 && val <= 10) {
              final possibleOriginal = val * 10;
              if (possibleOriginal <= 100) {
                debugPrint(
                  '║   ⚠️ SUSPICIOUS: $key=$val (could be $possibleOriginal÷10)',
                );
                bugDetected = true;
              }
            }
          });
        }

        if (bugDetected) {
          debugPrint('║');
          debugPrint('║ ❌❌❌ BUG DETECTED: Values look normalized by /10 ❌❌❌');
          debugPrint('║ Expected: 0-100 points, Got: suspicious 0-10 values');
        }

        debugPrint('╚════════════════════════════════════════════╝\n');
      }

      // Prepare stations data
      List<Map<String, dynamic>> stationsData;
      if (_rangeType == 'קצרים') {
        // Short Range: Create stations from dynamic list
        stationsData = shortRangeStagesList.map((stage) {
          final stageName = stage.isManual
              ? stage.manualName.trim()
              : stage.selectedStage ?? '';

          return {
            'name': stageName,
            'bulletsCount': stage.bulletsCount,
            'timeSeconds': null,
            'hits': null,
            'isManual': stage.isManual,
            'isLevelTester': stage.selectedStage == 'בוחן רמה',
            'selectedRubrics': ['זמן', 'פגיעות'],
          };
        }).toList();
      } else if (_rangeType == 'ארוכים') {
        // Long Range: Create stations from multi-stage list with user-entered bullets
        stationsData = longRangeStagesList.asMap().entries.map((entry) {
          final index = entry.key;
          final stage = entry.value;

          // Calculate achieved points from trainee data for this stage
          int achievedPoints = 0;
          for (final row in traineeRows) {
            achievedPoints += row.values[index] ?? 0;
          }

          return {
            'name': stage.name,
            'bulletsCount': stage.bulletsCount,
            'maxPoints': stage.maxPoints,
            'achievedPoints': achievedPoints,
            'isManual': stage.isManual,
            'timeSeconds': null,
            'hits': null,
            'isLevelTester': false,
            'selectedRubrics': ['זמן', 'פגיעות'],
          };
        }).toList();
      } else {
        // Surprise: Build stations from principles list with FIXED maxPoints = 10
        // ✅ FIX: maxPoints for surprise drills is ALWAYS 10 per principle (not from trainee data)
        stationsData = stations.map((s) {
          final json = s.toJson();
          // Force maxPoints to 10 for all surprise drill principles
          json['maxPoints'] = _surpriseMaxPointsPerPrinciple; // Always 10
          return json;
        }).toList();
      }

      final Map<String, dynamic> baseData = {
        'instructorName':
            currentUser?.name ?? '', // ✅ Use local name (no Firestore fetch)
        'instructorId': uid,
        'instructorEmail': email,
        'instructorRole': currentUser?.role ?? 'Instructor',
        'instructorUsername': currentUser?.username ?? '',
        'createdAt': _dateManuallySet
            ? Timestamp.fromDate(_selectedDateTime)
            : FieldValue.serverTimestamp(),
        'createdByName':
            currentUser?.name ?? '', // ✅ Use local name (no Firestore fetch)
        'createdByUid': uid,
        'rangeType': _rangeType,
        'rangeSubType':
            rangeSubType, // ✅ Display label for list UI (טווח קצר/טווח רחוק)
        'settlement': isManualLocation
            ? manualLocationText
            : (isManualSettlement && manualSettlementText.isNotEmpty)
            ? manualSettlementText
            : (settlementName.isNotEmpty ? settlementName : selectedSettlement),
        'settlementName': settlementName,
        'rangeFolder': rangeFolder,
        // Unified classification
        'folderKey': folderKey,
        'folderLabel': folderLabel,
        'folderId': folderId,
        'attendeesCount': attendeesCount,
        'instructorsCount': instructorsCount, // מספר מדריכים
        'instructors': _collectInstructorNames(), // רשימת מדריכים
        'stations': stationsData,
        'trainees': traineesData,
        'summary': trainingSummary, // ✅ סיכום האימון מהמדריך
        'status': 'final',
      };

      // ========== SEPARATE COLLECTIONS FOR SURPRISE VS RANGE ==========
      DocumentReference? docRef;
      String collectionPath;

      if (widget.mode == 'surprise') {
        // SURPRISE DRILLS: Save to dedicated collection
        collectionPath = 'feedbacks';
        // Determine final settlement value: manual location text or selected settlement
        final String finalSettlement = isManualLocation
            ? manualLocationText
            : (settlementName.isNotEmpty
                  ? settlementName
                  : selectedSettlement ?? '');
        // 🔍 DEBUG: Log final save flags before write (Surprise Drill)
        debugPrint(
          'FINAL_SAVE_FLAGS_SURPRISE: isTemporary=false finalizedAt=serverTimestamp() status=final',
        );

        final Map<String, dynamic> surpriseData = {
          ...baseData,
          // Required fields for Surprise Drills
          'module': 'surprise_drill',
          'type': 'surprise_exercise',
          'isTemporary': false, // ✅ FINAL SAVE: Mark as final (not temp)
          'isDraft': false, // ✅ FINAL SAVE: Mark as final (not draft)
          'status': 'final', // ✅ FINAL SAVE: Override baseData status
          'finalizedAt':
              FieldValue.serverTimestamp(), // ✅ FINAL SAVE: Track when finalized
          'exercise': 'תרגילי הפתעה',
          'folder': surpriseDrillsFolder, // ✅ Use selected folder (474 or כללי)
          // ✅ CRITICAL: Override folderKey/folderLabel to prevent range filter matching
          'folderKey': surpriseDrillsFolder == 'תרגילי הפתעה כללי'
              ? 'surprise_drills_general'
              : 'surprise_drills', // NOT ranges_474 or shooting_ranges
          'folderLabel': surpriseDrillsFolder,
          'folderId': surpriseDrillsFolder == 'תרגילי הפתעה כללי'
              ? 'surprise_drills_general'
              : 'surprise_drills',
          'feedbackType': saveType,
          'rangeMode': widget.mode,
          'name': finalSettlement,
          'settlement':
              finalSettlement, // Also store in settlement field for filtering
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
        debugPrint('SAVE: folder=$surpriseDrillsFolder');

        // Diagnostic: log canonical folder info & payload keys
        debugPrint('SAVE_DEBUG: uiFolderValue=$uiFolderValue');
        debugPrint(
          'SAVE_DEBUG: folderKey=$folderKey folderLabel=$folderLabel folderId=$folderId',
        );
        debugPrint(
          'SAVE_DEBUG: feedbackType=$saveType rangeMode=${widget.mode}',
        );
        debugPrint('SAVE_DEBUG: payload keys=${surpriseData.keys.toList()}');

        debugPrint('\n========== FIRESTORE WRITE START ==========');

        final collRef = FirebaseFirestore.instance.collection(collectionPath);

        try {
          // ✅ FIX: Use EXISTING draft document if available from autosave
          // This prevents duplicate feedbacks (one temp, one final)
          DocumentReference finalDocRef;

          // Check if we're editing an existing FINAL (non-draft) feedback
          final String? existingFinalId =
              (widget.feedbackId != null && widget.feedbackId!.isNotEmpty)
              ? widget.feedbackId
              : null;

          // ✅ NEW LOGIC: Check if we have a draft ID from autosave
          final String? autosavedDraftId = _editingFeedbackId;

          if (existingFinalId != null) {
            // EDIT mode: update existing final feedback
            finalDocRef = collRef.doc(existingFinalId);
            debugPrint(
              'WRITE: EDIT MODE - Updating existing final feedback id=$existingFinalId',
            );
            debugPrint('WRITE: ✅ No duplicate - updating same document');
            await finalDocRef.set(surpriseData);
          } else if (autosavedDraftId != null && autosavedDraftId.isNotEmpty) {
            // ✅ AUTOSAVE DRAFT EXISTS: Convert draft to final by updating same document
            finalDocRef = collRef.doc(autosavedDraftId);
            debugPrint(
              'WRITE: DRAFT→FINAL - Converting autosaved draft id=$autosavedDraftId to final',
            );
            debugPrint(
              'WRITE: ✅ No duplicate - updating autosaved draft to final status',
            );
            await finalDocRef.set(
              surpriseData,
            ); // Overwrites temp fields with final fields
            debugPrint('🆔 DRAFT CONVERTED TO FINAL: docId=$autosavedDraftId');
          } else {
            // CREATE mode: generate new auto-ID (only if NO draft and NOT editing)
            finalDocRef = collRef.doc(); // Firestore auto-ID
            final docId = finalDocRef.id;
            debugPrint('WRITE: CREATE MODE - New auto-ID: $docId');
            debugPrint(
              'WRITE: ⚠️ No autosaved draft found - creating new document',
            );
            await finalDocRef.set(surpriseData);
            debugPrint('🆔 NEW FEEDBACK CREATED: docId=$docId');
          }

          docRef = finalDocRef; // Store for readback
          debugPrint(
            'WRITE: ✅ Final document saved at path=${finalDocRef.path}',
          );
          debugPrint('🆔 SAVED DOCUMENT ID: ${finalDocRef.id}');

          // 🔍 DEBUG: Verify final save flags after write (Surprise Drill)
          debugPrint(
            'FINAL_SAVE_VERIFY_SURPRISE: docId=${finalDocRef.id} written with isTemporary=false finalizedAt=serverTimestamp() status=final',
          );

          debugPrint('========== FIRESTORE WRITE END ==========\n');

          // ✅ SUCCESS SNACKBAR
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('FINAL SAVE OK -> folderKey=$folderKey'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } catch (writeError) {
          debugPrint('❌❌❌ FIRESTORE WRITE FAILED ❌❌❌');
          debugPrint('WRITE_ERROR: $writeError');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('FINAL SAVE ERROR: $writeError'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() => _isSaving = false);
          rethrow;
        }

        // ✅ FINALIZE LOG
        debugPrint(
          'FINALIZE_SAVE path=${docRef.path} module=surprise_drill type=surprise_exercise isTemporary=false finalId=${docRef.id}',
        );
        debugPrint('FINALIZE_SAVE: Temp document updated to final (same ID)');
        debugPrint(
          'FINALIZE_SAVE: No cleanup needed - same document updated in place',
        );
        debugPrint('FINALIZE_SAVE: ✅ SURPRISE DRILL SAVE COMPLETE - RETURNING');
        debugPrint('===============================================\n');

        // ========== IMMEDIATE READBACK VERIFICATION (SURPRISE) ==========
        debugPrint(
          '\n========== READBACK VERIFICATION START (SURPRISE) ==========',
        );
        debugPrint('READBACK: Verifying finalDocRef at ${docRef.path}');
        debugPrint('READBACK: finalId=${docRef.id}');
        try {
          final snap = await docRef.get();
          debugPrint('READBACK: exists=${snap.exists} (MUST be true)');
          if (snap.exists) {
            final savedData = snap.data() as Map<String, dynamic>?;
            final savedModule = savedData?['module'] as String?;
            final savedFolder = savedData?['folder'] as String?;
            final savedType = savedData?['type'] as String?;
            debugPrint(
              'READBACK: module=$savedModule (MUST be surprise_drill)',
            );
            debugPrint(
              'READBACK: folder=$savedFolder (MUST be משוב תרגילי הפתעה)',
            );
            debugPrint('READBACK: type=$savedType (MUST be surprise_exercise)');
            debugPrint(
              'READBACK: ✅ VERIFIED - Surprise drill saved to correct destination',
            );
          } else {
            debugPrint('READBACK: ❌❌❌ CRITICAL ERROR - Document not found!');
          }
        } catch (readbackError) {
          debugPrint(
            'READBACK: ⚠️ ERROR - Verification failed: $readbackError',
          );
        }
        debugPrint(
          '========== READBACK VERIFICATION END (SURPRISE) ==========\n',
        );

        if (!mounted) return;

        // Navigate back
        Navigator.pop(context);

        debugPrint('SAVE: Navigation complete (SURPRISE)');
        debugPrint('========== SURPRISE DRILL SAVE END ==========\n');

        // ✅ CRITICAL: RETURN HERE to prevent fallthrough to shooting ranges logic
        setState(() => _isSaving = false);
        return;
      } else {
        // SHOOTING RANGES: Save to dedicated collection
        collectionPath = 'feedbacks';

        // Determine target folder - Use resolved folder values from above
        // ✅ FIX: ALWAYS use the already resolved folderLabel (consistent with folder resolution logic)
        String targetFolder = folderLabel;
        debugPrint(
          'FINAL_SAVE: ✅ Using resolved folderLabel as targetFolder: $targetFolder',
        );

        // 🔍 DEBUG: Log final save flags before write (Range)
        final rangeTypeDebug = _rangeType == 'קצרים'
            ? 'range_short'
            : 'range_long';
        debugPrint(
          'FINAL_SAVE_FLAGS_RANGE: type=$rangeTypeDebug isTemporary=false finalizedAt=serverTimestamp() status=final',
        );

        final Map<String, dynamic> rangeData = {
          ...baseData,
          // Required fields for Shooting Ranges
          'module': 'shooting_ranges',
          'type': 'range_feedback',
          'isTemporary': false, // ✅ FINAL SAVE: Mark as final (not temp)
          'isDraft': false, // ✅ FINAL SAVE: Mark as final (not draft)
          'status': 'final', // ✅ FINAL SAVE: Override baseData status
          'finalizedAt':
              FieldValue.serverTimestamp(), // ✅ FINAL SAVE: Track when finalized
          'exercise': 'מטווחים',
          'folder': targetFolder, // ✅ Final folder (not temp)
          'folderCategory':
              folderLabel, // ✅ FIX: Always use resolved folderLabel
          'folderKey': folderKey,
          'folderLabel': folderLabel,
          'folderId': folderId,
          'feedbackType': saveType,
          'rangeMode': widget.mode,
          'rangeSubFolder': subFolder,
          // rangeSubType inherited from baseData
          'name': settlementName,
          'role': 'מטווח',
          'scores': {},
          'notes': {'general': subFolder},
          'criteriaList': [],
        };

        debugPrint('\n========== FINAL SAVE: LONG RANGE ==========');
        debugPrint('SAVE: collection=$collectionPath');
        debugPrint('SAVE: module=shooting_ranges');
        debugPrint('SAVE: type=range_feedback');
        debugPrint('SAVE: rangeType=$_rangeType (should be ארוכים)');
        debugPrint('SAVE: feedbackType=$saveType (should be range_long)');
        debugPrint('SAVE: isTemporary=false');
        debugPrint('SAVE: targetFolder=$targetFolder (FINAL DESTINATION)');
        debugPrint('SAVE: folderKey=$folderKey');
        debugPrint('SAVE: folderLabel=$folderLabel');
        debugPrint('SAVE_DEBUG: userSelectedFolder=$rangeFolder');
        debugPrint('SAVE_DEBUG: Will appear in משובים → $targetFolder');
        debugPrint('SAVE_DEBUG: payload keys=${rangeData.keys.toList()}');

        // ✅ BUILD AND PERSIST V2 DATA MODEL FOR LONG RANGE
        final lrV2 = _buildLrV2();
        if (lrV2.isNotEmpty) {
          rangeData['lrV2'] = lrV2;
          debugPrint('\n✅ LR_V2_SAVE: Built V2 data model');
          debugPrint('   V2 traineesCount=${lrV2['traineesCount']}');
          debugPrint('   V2 stages count=${(lrV2['stages'] as List).length}');

          final stages = lrV2['stages'] as List;
          for (int i = 0; i < stages.length; i++) {
            final stage = stages[i] as Map<String, dynamic>;
            debugPrint(
              '   V2 Stage[$i]: maxScorePoints=${stage['maxScorePoints']}, bullets=${stage['bulletsTracking']} (tracking)',
            );
          }
        }

        // ====== ACCEPTANCE TEST: LONG RANGE FINAL SAVE PROOF ======
        debugPrint('\n╔══════════════════════════════════════════════════╗');
        debugPrint('║  LONG RANGE ACCEPTANCE TEST: PRE-SAVE PROOF      ║');
        debugPrint('╠══════════════════════════════════════════════════╣');
        debugPrint('║ 📁 folderKey: $folderKey');
        debugPrint('║ 📁 folderLabel: $folderLabel');
        debugPrint('║ 📊 stagesCount: ${stationsData.length}');
        debugPrint('║ 👥 traineesCount: ${traineesData.length}');
        // Log each stage with maxPoints (no bullets conversion)
        for (
          int i = 0;
          i < stationsData.length && i < longRangeStagesList.length;
          i++
        ) {
          final stage = longRangeStagesList[i];
          debugPrint(
            '║ 📌 Stage[$i]: "${stage.name}" → bulletsCount=${stage.bulletsCount}, maxPoints=${stage.maxPoints}',
          );
        }
        // Log trainee points (no conversion)
        debugPrint(
          '║ ⚠️  POINTS VERIFICATION: Values stored AS-IS, NO division/multiplication',
        );
        for (int i = 0; i < traineeRows.length && i < 3; i++) {
          final row = traineeRows[i];
          final totalPoints = _getTraineeTotalPointsLongRange(i);
          debugPrint(
            '║ 👤 Trainee[$i]: "${row.name}" → totalPoints=$totalPoints (RAW values=${row.values})',
          );
          // Verify: Print first station value as example
          if (row.values.isNotEmpty) {
            final firstStationIdx = row.values.keys.first;
            final firstValue = row.values[firstStationIdx];
            debugPrint(
              '║    ↳ Station[$firstStationIdx]: value=$firstValue (stored/displayed AS-IS)',
            );
          }
        }
        debugPrint('╚══════════════════════════════════════════════════╝\n');

        // 🔥🔥🔥 WEB SAVE GUARD: Detect long range and verify payload 🔥🔥🔥
        final isLongRange = isLongRangeFeedback(
          feedbackType: saveType,
          rangeSubType: _rangeType == 'ארוכים' ? 'טווח רחוק' : 'טווח קצר',
          rangeType: _rangeType,
          folderKey: folderKey,
        );

        if (kIsWeb) {
          debugPrint('\n🌐🌐🌐 WEB_SAVE GUARD START 🌐🌐🌐');
          debugPrint('🌐 WEB_SAVE isLongRange=$isLongRange');
          debugPrint('🌐 WEB_SAVE feedbackType=$saveType');
          debugPrint('🌐 WEB_SAVE rangeType=$_rangeType');
          debugPrint('🌐 WEB_SAVE folderKey=$folderKey');
          debugPrint(
            '🌐 WEB_SAVE payload keys BEFORE write: ${rangeData.keys.toList()}',
          );

          // ✅ STRICT VERIFICATION: Check trainees data for LONG RANGE
          if (isLongRange) {
            debugPrint(
              '🌐 WEB_SAVE LONG RANGE: Verifying points-only payload...',
            );
            final trainees = rangeData['trainees'] as List?;
            if (trainees != null && trainees.isNotEmpty) {
              for (int i = 0; i < trainees.length && i < 3; i++) {
                final t = trainees[i] as Map<String, dynamic>;
                final hits = t['hits'] as Map<String, dynamic>? ?? {};
                debugPrint('🌐 WEB_SAVE LR Trainee[$i]: name="${t['name']}"');
                debugPrint('🌐 WEB_SAVE LR   hits keys: ${hits.keys.toList()}');
                debugPrint(
                  '🌐 WEB_SAVE LR   hits values: ${hits.values.toList()}',
                );

                // ❌ DETECT NORMALIZATION BUG
                hits.forEach((key, val) {
                  if (val is int && val > 0 && val <= 10) {
                    debugPrint(
                      '🌐 ⚠️⚠️ WEB_SAVE LR WARNING: $key=$val looks normalized! Expected 0-100 points.',
                    );
                  }
                });
              }
            }

            // ✅ VERIFY: No percentage, bullets, normalizedScore fields
            final forbiddenKeys = [
              'percentage',
              'bullets',
              'normalizedScore',
              'accuracy',
            ];
            final hasForbiddenKeys = rangeData.keys.any(
              (k) => forbiddenKeys.contains(k),
            );
            if (hasForbiddenKeys) {
              debugPrint(
                '🌐 ❌❌ WEB_SAVE LR ERROR: Payload contains forbidden fields!',
              );
              debugPrint(
                '🌐 Forbidden fields found: ${rangeData.keys.where((k) => forbiddenKeys.contains(k)).toList()}',
              );
            } else {
              debugPrint(
                '🌐 ✅ WEB_SAVE LR VERIFIED: No forbidden percentage/bullets fields',
              );
            }
          }
          debugPrint('🌐🌐🌐 WEB_SAVE GUARD END 🌐🌐🌐\n');
        }

        debugPrint('\n========== FIRESTORE WRITE START ==========');
        debugPrint('📄 DOCUMENT DATA TO SAVE:');
        debugPrint('   folder: ${rangeData['folder']}');
        debugPrint('   folderCategory: ${rangeData['folderCategory']}');
        debugPrint('   folderKey: ${rangeData['folderKey']}');
        debugPrint('   folderLabel: ${rangeData['folderLabel']}');
        debugPrint('   folderId: ${rangeData['folderId']}');
        debugPrint('   module: ${rangeData['module']}');
        debugPrint('   type: ${rangeData['type']}');
        debugPrint('   feedbackType: ${rangeData['feedbackType']}');
        debugPrint('   isTemporary: ${rangeData['isTemporary']}');
        debugPrint('   isDraft: ${rangeData['isDraft']}');
        debugPrint('   status: ${rangeData['status']}');

        final collRef = FirebaseFirestore.instance.collection(collectionPath);

        try {
          // ✅ FIX: Use EXISTING draft document if available from autosave
          // This prevents duplicate feedbacks (one temp, one final)
          DocumentReference finalDocRef;

          // Check if we're editing an existing FINAL (non-draft) feedback
          final String? existingFinalId =
              (widget.feedbackId != null && widget.feedbackId!.isNotEmpty)
              ? widget.feedbackId
              : null;

          // ✅ NEW LOGIC: Check if we have a draft ID from autosave
          final String? autosavedDraftId = _editingFeedbackId;

          if (existingFinalId != null) {
            // EDIT mode: update existing final feedback
            finalDocRef = collRef.doc(existingFinalId);
            debugPrint(
              'WRITE: EDIT MODE - Updating existing final feedback id=$existingFinalId',
            );
            debugPrint('WRITE: ✅ No duplicate - updating same document');
            await finalDocRef.set(rangeData);
          } else if (autosavedDraftId != null && autosavedDraftId.isNotEmpty) {
            // ✅ AUTOSAVE DRAFT EXISTS: Convert draft to final by updating same document
            finalDocRef = collRef.doc(autosavedDraftId);
            debugPrint(
              'WRITE: DRAFT→FINAL - Converting autosaved draft id=$autosavedDraftId to final',
            );
            debugPrint(
              'WRITE: ✅ No duplicate - updating autosaved draft to final status',
            );
            await finalDocRef.set(
              rangeData,
            ); // Overwrites temp fields with final fields
            debugPrint('🆔 DRAFT CONVERTED TO FINAL: docId=$autosavedDraftId');
          } else {
            // CREATE mode: generate new auto-ID (only if NO draft and NOT editing)
            finalDocRef = collRef.doc(); // Firestore auto-ID
            final docId = finalDocRef.id;
            debugPrint('WRITE: CREATE MODE - New auto-ID: $docId');
            debugPrint(
              'WRITE: ⚠️ No autosaved draft found - creating new document',
            );
            await finalDocRef.set(rangeData);
            debugPrint('🆔 NEW FEEDBACK CREATED: docId=$docId');
          }

          docRef = finalDocRef; // Store for readback
          debugPrint(
            'WRITE: ✅ Final document saved at path=${finalDocRef.path}',
          );
          debugPrint('🆔 SAVED DOCUMENT ID: ${finalDocRef.id}');
          debugPrint('📂 SAVED TO COLLECTION: $collectionPath');
          debugPrint('📁 SAVED FOLDER DATA:');
          debugPrint('   -> folder: ${rangeData['folder']}');
          debugPrint('   -> folderKey: ${rangeData['folderKey']}');
          debugPrint('   -> folderLabel: ${rangeData['folderLabel']}');
          debugPrint('   -> module: ${rangeData['module']}');
          debugPrint('   -> type: ${rangeData['type']}');
          debugPrint('   -> status: ${rangeData['status']}');

          // 🔍 DEBUG: Verify final save flags after write (Range)
          debugPrint(
            'FINAL_SAVE_VERIFY_RANGE: type=$rangeTypeDebug docId=${finalDocRef.id} written with isTemporary=false finalizedAt=serverTimestamp() status=final',
          );

          // ✅ DEBUG: Log saved document path for טווח רחוק bug verification
          if (_rangeType == 'ארוכים') {
            debugPrint(
              '🔍 טווח רחוק SAVED: collection=feedbacks, docId=${finalDocRef.id}',
            );
            debugPrint('   Path: ${finalDocRef.path}');
            debugPrint('   TraineesCount: ${traineesData.length}');
            debugPrint('   StationsCount: ${stationsData.length}');
            for (int i = 0; i < traineesData.length && i < 3; i++) {
              final trainee = traineesData[i];
              debugPrint(
                '   Trainee[$i]: ${trainee['name']} -> totalHits=${trainee['totalHits']}',
              );
            }
          }

          debugPrint('========== FIRESTORE WRITE END ==========\n');

          // ✅ SUCCESS SNACKBAR
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('FINAL SAVE OK -> folderKey=$folderKey'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } catch (writeError) {
          debugPrint('❌❌❌ FIRESTORE WRITE FAILED ❌❌❌');
          debugPrint('WRITE_ERROR: $writeError');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('FINAL SAVE ERROR: $writeError'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() => _isSaving = false);
          rethrow;
        }

        // ✅ FINALIZE LOG
        debugPrint(
          'FINALIZE_SAVE path=${docRef.path} module=shooting_ranges type=range_feedback isTemporary=false rangeType=$_rangeType',
        );

        // ====== ACCEPTANCE TEST: LONG RANGE POST-SAVE PROOF ======
        debugPrint('\n╔══════════════════════════════════════════════════╗');
        debugPrint('║  LONG RANGE ACCEPTANCE TEST: POST-SAVE PROOF     ║');
        debugPrint('╠══════════════════════════════════════════════════╣');
        debugPrint('║ ✅ finalId: ${docRef.id} (SAME as temp draft)');
        debugPrint('║ ✅ finalPath: ${docRef.path}');
        debugPrint('║ ✅ folderKey: $folderKey');
        debugPrint('║ ✅ folderLabel: $folderLabel');
        debugPrint('║ ✅ targetFolder: $targetFolder');
        debugPrint('║ ✅ UPDATE IN PLACE - temp converted to final');
        debugPrint('║ ✅ Status changed: temporary → final');
        debugPrint('║ ✅ Folder changed: משוב זמני → $targetFolder');
        debugPrint('╚══════════════════════════════════════════════════╝\n');

        debugPrint('===============================================\n');
      }

      debugPrint('SAVE: Write completed, path=${docRef.path}');

      // ========== IMMEDIATE READBACK VERIFICATION ==========
      debugPrint('\n========== READBACK VERIFICATION START ==========');
      debugPrint('READBACK: Verifying finalDocRef at ${docRef.path}');
      debugPrint('READBACK: finalId=${docRef.id}');
      try {
        final snap = await docRef.get();
        debugPrint('READBACK: exists=${snap.exists} (MUST be true)');
        if (snap.exists) {
          final savedData = snap.data() as Map<String, dynamic>?;
          final savedTrainees = savedData?['trainees'] as List?;
          final savedDraftId = savedData?['draftId'] as String?;
          debugPrint('READBACK: traineesCount=${savedTrainees?.length ?? 0}');
          if (savedDraftId != null) {
            debugPrint('READBACK: sourceDraftId=$savedDraftId (tracked)');
          }

          // 🔥🔥🔥 WEB READBACK VERIFICATION: Check for normalization bug 🔥🔥🔥
          if (kIsWeb && widget.mode == 'range') {
            final readbackFeedbackType = savedData?['feedbackType'] as String?;
            final readbackRangeSubType = savedData?['rangeSubType'] as String?;
            final readbackRangeType = _rangeType; // Use current UI state
            final readbackFolderKey = savedData?['folderKey'] as String?;

            final isLongRangeReadback = isLongRangeFeedback(
              feedbackType: readbackFeedbackType,
              rangeSubType: readbackRangeSubType,
              rangeType: readbackRangeType,
              folderKey: readbackFolderKey,
            );

            debugPrint('\n🌐🌐🌐 WEB_READBACK VERIFICATION START 🌐🌐🌐');
            debugPrint('🌐 WEB_READBACK isLongRange=$isLongRangeReadback');
            debugPrint('🌐 WEB_READBACK feedbackType=$readbackFeedbackType');
            debugPrint('🌐 WEB_READBACK rangeSubType=$readbackRangeSubType');

            if (isLongRangeReadback && savedTrainees != null) {
              debugPrint(
                '🌐 WEB_READBACK LONG RANGE: Verifying saved points...',
              );
              for (int i = 0; i < savedTrainees.length && i < 3; i++) {
                final t = savedTrainees[i] as Map<String, dynamic>;
                final hits = t['hits'] as Map<String, dynamic>? ?? {};
                debugPrint(
                  '🌐 WEB_READBACK LR Trainee[$i]: name="${t['name']}"',
                );
                debugPrint('🌐 WEB_READBACK LR   SAVED hits: $hits');

                // ✅ CRITICAL: Detect if values were normalized AFTER save
                bool normalizedDetected = false;
                hits.forEach((key, val) {
                  if (val is int && val > 0 && val <= 10) {
                    debugPrint(
                      '🌐 ❌❌ WEB_READBACK LR BUG DETECTED: $key=$val (expected 0-100 points!)',
                    );
                    normalizedDetected = true;
                  }
                });

                if (!normalizedDetected && hits.isNotEmpty) {
                  debugPrint(
                    '🌐 ✅ WEB_READBACK LR PASS: Values in valid 0-100 range',
                  );
                }
              }
            }
            debugPrint('🌐🌐🌐 WEB_READBACK VERIFICATION END 🌐🌐🌐\n');
          }

          debugPrint(
            'READBACK: ✅ VERIFIED - Final document persisted successfully',
          );
          debugPrint('READBACK: Collection: feedbacks');
          debugPrint('READBACK: Document ID: ${docRef.id}');
        } else {
          debugPrint('READBACK: ❌❌❌ CRITICAL ERROR - Document not found!');
          debugPrint(
            'READBACK: This should NEVER happen after successful write',
          );
        }
      } catch (readbackError) {
        debugPrint('READBACK: ⚠️ ERROR - Verification failed: $readbackError');
      }
      debugPrint('========== READBACK VERIFICATION END ==========\n');

      if (!mounted) return;

      // ✅ NO CLEANUP NEEDED: Document updated in-place from draft to final
      // Both Range and Surprise modes now work consistently - same document updated
      debugPrint(
        '🔄 CONSISTENCY: Document updated in-place, no deletion needed',
      );

      // Navigate back to appropriate feedbacks list
      // Since we're using nested navigation, just pop back
      if (!mounted) return;
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
    // ✅ ATOMIC DRAFT SAVE: PATCH ONLY CHANGED FIELDS (merge) for Short/Long Range
    // Updates same draftId, never creates duplicates
    // NO REBUILD: Doesn't call setState during background auto-save

    if (_isSaving) {
      debugPrint('⚠️ DRAFT_SAVE: Already saving, skipping...');
      return; // Prevent concurrent saves
    }

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

      // ✅ ADMIN EDIT FIX: If already editing an existing feedback, keep the same ID
      // Don't create a new draft based on current user's UID - this allows admin
      // to edit any instructor's feedback without creating duplicates
      final String draftId;
      if (_editingFeedbackId != null && _editingFeedbackId!.isNotEmpty) {
        // Already editing - keep same document ID
        draftId = _editingFeedbackId!;
        debugPrint(
          'DRAFT_SAVE: Using existing draftId=$draftId (editing mode)',
        );
      } else {
        // New draft - create UNIQUE ID with timestamp to prevent overwrites
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        draftId =
            '${uid}_${moduleType}_${_rangeType.replaceAll(' ', '_')}_$timestamp';
        _editingFeedbackId = draftId;
        debugPrint(
          'DRAFT_SAVE: Created new unique draftId=$draftId (new mode)',
        );
      }

      debugPrint('DRAFT_SAVE: uid=$uid');
      debugPrint('DRAFT_SAVE: draftId=$draftId');

      // Track range type for logging
      final bool isLongRange = _rangeType == 'ארוכים';

      // Serialize traineeRows to Firestore format
      final List<Map<String, dynamic>> traineesPayload = [];
      debugPrint(
        'DRAFT_SAVE: Serializing ${traineeRows.length} trainee rows...',
      );
      for (int i = 0; i < traineeRows.length; i++) {
        final row = traineeRows[i];
        final rowData = row.toFirestore();

        // Backward-compatibility: details/stage screens expect 'hits' and
        // 'totalHits' fields (legacy format). Ensure temp save writes them
        // so details/stage screens see the same data as the editor.
        final Map<String, dynamic> valuesMap = Map<String, dynamic>.from(
          rowData['values'] as Map? ?? {},
        );

        final Map<String, int> hitsMap = {};
        int total = 0;
        valuesMap.forEach((k, v) {
          try {
            final intVal = (v as num).toInt();
            hitsMap[k.toString()] = intVal;
            total += intVal;
          } catch (_) {
            // ignore parse errors and treat as 0
          }
        });

        // legacy field names used by details/stage screens
        rowData['hits'] = hitsMap;
        rowData['totalHits'] = total;

        traineesPayload.add(rowData);
        debugPrint(
          'DRAFT_SAVE:   row[$i]: name="${row.name}" values=${row.values} totalHits=$total',
        );
      }

      // Build complete payload (for new fields)
      final String folderName = widget.mode == 'surprise'
          ? 'תרגילי הפתעה - משוב זמני'
          : 'מטווחים - משוב זמני';

      String draftFolderKey;
      String draftFolderLabel;

      // ✅ DRAFT SAVE FIX: Use loaded folder values if available (from existing draft)
      // This prevents folder switching when user returns to edit an existing draft
      if (loadedFolderKey != null && loadedFolderKey!.isNotEmpty) {
        draftFolderKey = loadedFolderKey!;
        draftFolderLabel = loadedFolderLabel ?? loadedFolderKey!;
        debugPrint(
          'DRAFT_SAVE: ✅ Using LOADED folder: key=$draftFolderKey label=$draftFolderLabel',
        );
      } else if (widget.mode == 'surprise') {
        // ✅ SURPRISE DRILLS: Use surpriseDrillsFolder selection
        if (surpriseDrillsFolder == 'תרגילי הפתעה כללי') {
          draftFolderKey = 'surprise_drills_general';
          draftFolderLabel = 'תרגילי הפתעה כללי';
        } else {
          draftFolderKey = 'surprise_drills';
          draftFolderLabel = 'משוב תרגילי הפתעה';
        }
        debugPrint(
          'DRAFT_SAVE: ✅ Using SURPRISE folder: key=$draftFolderKey label=$draftFolderLabel',
        );
      } else {
        // ✅ NEW DRAFT: Use UI selection to determine folder
        if (rangeFolder == 'מטווחים 474' || rangeFolder == '474 Ranges') {
          draftFolderKey = 'ranges_474';
          draftFolderLabel = 'מטווחים 474';
        } else if (rangeFolder == 'מטווחי ירי' ||
            rangeFolder == 'Shooting Ranges') {
          draftFolderKey = 'shooting_ranges';
          draftFolderLabel = 'מטווחי ירי';
        } else {
          draftFolderKey = 'shooting_ranges';
          draftFolderLabel = 'מטווחי ירי';
        }
        debugPrint(
          'DRAFT_SAVE: ✅ Using UI folder: key=$draftFolderKey label=$draftFolderLabel',
        );
      }

      // Prepare stations data for temporary save
      List<Map<String, dynamic>> stationsData;
      if (_rangeType == 'קצרים') {
        stationsData = shortRangeStagesList.map((stage) {
          final stageName = stage.isManual
              ? stage.manualName.trim()
              : stage.selectedStage ?? '';
          return {
            'name': stageName,
            'bulletsCount': stage.bulletsCount,
            'timeSeconds': null,
            'hits': null,
            'isManual': stage.isManual,
            'isLevelTester': stage.selectedStage == 'בוחן רמה',
            'selectedRubrics': ['זמן', 'פגיעות'],
          };
        }).toList();
        if (stationsData.isEmpty && stations.isNotEmpty) {
          stationsData = stations.map((s) => s.toJson()).toList();
        }
      } else if (_rangeType == 'ארוכים') {
        stationsData = longRangeStagesList.asMap().entries.map((entry) {
          final index = entry.key;
          final stage = entry.value;
          int achievedPoints = 0;
          for (final row in traineeRows) {
            achievedPoints += row.values[index] ?? 0;
          }
          return {
            'name': stage.name,
            'bulletsCount': stage.bulletsCount,
            'maxPoints': stage.maxPoints,
            'achievedPoints': achievedPoints,
            'isManual': stage.isManual,
            'timeSeconds': null,
            'hits': null,
            'isLevelTester': false,
            'selectedRubrics': ['זמן', 'פגיעות'],
          };
        }).toList();
        if (stationsData.isEmpty && stations.isNotEmpty) {
          stationsData = stations.map((s) => s.toJson()).toList();
        }
      } else {
        // Surprise mode: Build stations with FIXED maxPoints = 10 for each principle
        stationsData = stations.map((s) {
          final json = s.toJson();
          json['maxPoints'] = _surpriseMaxPointsPerPrinciple; // Always 10
          return json;
        }).toList();
      }

      // PATCH LOGIC: Only update changed fields for Short/Long Range
      final docRef = FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(draftId);

      // ✅ Check if document exists to preserve original creator
      final existingDoc = await docRef.get();
      final isNewDocument = !existingDoc.exists;

      Map<String, dynamic> patch = {
        'status': 'temporary',
        'isDraft': true,
        'module': moduleType,
        'isTemporary': true, // ✅ TEMP SAVE: Mark as temporary
        'finalizedAt': null, // ✅ TEMP SAVE: Not finalized yet
        'folder': folderName,
        'folderKey': draftFolderKey,
        'folderLabel': draftFolderLabel,
        'feedbackType': (_rangeType == 'קצרים'
            ? 'range_short'
            : (_rangeType == 'ארוכים' ? 'range_long' : moduleType)),
        'rangeMode': widget.mode,
        'instructorId': uid,
        'instructorName':
            currentUser?.name ?? '', // ✅ Use local name (no Firestore fetch)
        'updatedByUid': uid, // ✅ Track last editor
        'updatedByName': currentUser?.name ?? '', // ✅ Track last editor name
        'rangeType': _rangeType,
        'rangeSubType': rangeSubType,
        // ✅ FIX: Settlement value based on mode
        // For surprise drills: use settlementName (user input)
        // For 474 ranges: use selectedSettlement (dropdown) OR manualSettlementText (manual)
        // For general ranges: use settlementName (free text)
        'settlement': widget.mode == 'surprise'
            ? settlementName
            : (isManualSettlement && manualSettlementText.isNotEmpty)
            ? manualSettlementText
            : ((rangeFolder == 'מטווחי ירי' && settlementName.isNotEmpty)
                  ? settlementName
                  : (selectedSettlement ?? '')),
        'settlementName': settlementName,
        'rangeFolder': rangeFolder ?? '',
        'attendeesCount': attendeesCount,
        'instructorsCount': instructorsCount, // מספר מדריכים
        'instructors': _collectInstructorNames(), // רשימת מדריכים
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': _dateManuallySet
            ? Timestamp.fromDate(_selectedDateTime)
            : FieldValue.serverTimestamp(),
        'selectedShortRangeStage': selectedShortRangeStage,
        'manualStageName': manualStageName,
        'summary': trainingSummary, // ✅ סיכום האימון מהמדריך
      };

      // ✅ Add creator fields ONLY for new documents (preserve original creator)
      if (isNewDocument) {
        patch['createdByName'] = currentUser?.name ?? '';
        patch['createdByUid'] = uid;
        patch['createdAt'] = FieldValue.serverTimestamp();
      }

      // 🔍 DEBUG: Log temp save flags before write
      debugPrint(
        'TEMP_SAVE_FLAGS: docId=$draftId isTemporary=true finalizedAt=null status=temporary isNewDocument=$isNewDocument',
      );

      // ✅ FIX: ALWAYS save trainees (even if no stations yet)
      // This allows users to fill trainee names first, then add stations/principles later
      // Only skip writing stations if they're empty (to preserve existing stage data)
      patch['trainees'] = traineesPayload;

      if (stationsData.isNotEmpty) {
        patch['stations'] = stationsData;
      }

      debugPrint('DRAFT_SAVE: PATCH keys=${patch.keys.toList()}');
      debugPrint('DRAFT_SAVE: PATCH.attendeesCount=$attendeesCount');
      debugPrint('DRAFT_SAVE: PATCH.trainees.length=${traineesPayload.length}');
      debugPrint('DRAFT_SAVE: PATCH.stations.length=${stationsData.length}');
      debugPrint('DRAFT_SAVE: PATCH.folder=$folderName');

      // 🔥 WEB LONG RANGE: Verify raw points BEFORE Firestore write
      if (kIsWeb && _rangeType == 'ארוכים') {
        debugPrint('\n🌐 ===== LR_WEB_BEFORE_SAVE VERIFICATION =====');
        for (int i = 0; i < traineesPayload.length && i < 3; i++) {
          final traineeData = traineesPayload[i];
          final traineeName = traineeData['name'] ?? 'Unknown';
          final values = traineeData['values'] ?? {};
          debugPrint('   Trainee[$i]: "$traineeName"');
          debugPrint('     RAW values map: $values');
          values.forEach((stageIdx, points) {
            debugPrint(
              '       Stage[$stageIdx]: $points (MUST be raw points 0-100, NOT normalized)',
            );
          });
        }
        debugPrint('🌐 =========================================\n');
      }

      // Use Firestore merge to patch only changed fields
      await docRef.set(patch, SetOptions(merge: true));
      debugPrint('✅ DRAFT_SAVE: Patch (merge) complete');

      // ✅ Update loaded draft trainees after successful save
      _loadedDraftTrainees = List<TraineeRowModel>.from(traineeRows);

      // ✅ LONG RANGE: Verify we NEVER use add(), ALWAYS use doc(id).set(merge:true)
      if (isLongRange) {
        debugPrint(
          '✅ LR_TEMP_VERIFY: Used doc($draftId).set(merge:true) - NO add() call',
        );
        debugPrint('   This ensures same document is updated, not duplicated');
      }

      // 🔍 DEBUG: Verify temp save flags after write
      debugPrint(
        'TEMP_SAVE_VERIFY: docId=${docRef.id} written with isTemporary=true finalizedAt=null',
      );

      // ✅ READ-BACK VERIFICATION
      debugPrint('DRAFT_SAVE: Read-back verification...');
      final verifySnap = await docRef.get();
      if (!verifySnap.exists) {
        debugPrint('❌ DRAFT_SAVE: Document NOT FOUND after patch!');
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

      // ✅ CRITICAL: Store draftId in _editingFeedbackId after FIRST save
      // This ensures subsequent _saveFinalFeedback() UPDATES same doc instead of creating new one
      final bool isFirstSave =
          _editingFeedbackId == null || _editingFeedbackId != draftId;
      if (isFirstSave) {
        _editingFeedbackId = draftId;
        debugPrint('DRAFT_SAVE: ✅ _editingFeedbackId set to "$draftId"');
        debugPrint(
          'DRAFT_SAVE: Next final save will UPDATE this doc, not create new',
        );

        // ✅ START REAL-TIME LISTENER: Monitor concurrent edits by other admins
        _startListeningToDraft(draftId);
      }

      debugPrint('========== ✅ DRAFT_SAVE END ==========');

      // Auto-save notification removed - saves silently in background
      // if (!mounted) return;
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text('✅ שמירה אוטומטית'),
      //     duration: Duration(seconds: 1),
      //     backgroundColor: Colors.green,
      //   ),
      // );
    } catch (e, stackTrace) {
      debugPrint('\n========== ❌ DRAFT_SAVE ERROR ==========');
      debugPrint('DRAFT_SAVE_ERROR: $e');
      debugPrint('DRAFT_SAVE_ERROR_STACK: $stackTrace');
      debugPrint('==========================================\n');

      // Auto-save error notification removed - errors logged to console only
      // if (!mounted) return;
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(
      //     content: Text('❌ שגיאה בשמירה: $e'),
      //     backgroundColor: Colors.red,
      //     duration: const Duration(seconds: 3),
      //   ),
      // );
    } finally {
      _isSaving = false;
    }
  }

  /// ✅ REAL-TIME SYNC: Start listening to draft changes by other admins
  void _startListeningToDraft(String draftId) {
    // Cancel previous listener if exists
    _draftListener?.cancel();

    debugPrint('🔄 REALTIME: Starting listener for draft=$draftId');

    final docRef = FirebaseFirestore.instance
        .collection('feedbacks')
        .doc(draftId);

    _draftListener = docRef.snapshots().listen(
      (snapshot) {
        if (!snapshot.exists || !mounted) {
          debugPrint(
            '⚠️ REALTIME: Snapshot does not exist or widget unmounted',
          );
          return;
        }

        final data = snapshot.data();
        if (data == null) {
          debugPrint('⚠️ REALTIME: Snapshot data is null');
          return;
        }

        // Check who updated
        final updatedByUid = data['updatedByUid'] as String?;
        final updatedByName = data['updatedByName'] as String?;
        final currentUid = FirebaseAuth.instance.currentUser?.uid;

        // Ignore our own updates
        if (updatedByUid == currentUid) {
          debugPrint('⏭️ REALTIME: Ignoring own update');
          return;
        }

        debugPrint('📥 REALTIME: Remote update detected!');
        debugPrint('   Updated by: $updatedByName (uid=$updatedByUid)');

        // Show notification when another admin edits
        if (updatedByName != null && updatedByName != _lastRemoteUpdateBy) {
          _lastRemoteUpdateBy = updatedByName;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$updatedByName עדכן/ה את המשוב בזמן אמת'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }

        // Merge remote changes into local state
        _mergeRemoteChanges(data);
      },
      onError: (error) {
        debugPrint('❌ REALTIME: Listener error: $error');
      },
    );
  }

  /// ✅ REAL-TIME SYNC: Merge remote changes with local state
  /// SMART MERGE: Keeps non-empty values from both local and remote
  void _mergeRemoteChanges(Map<String, dynamic> remoteData) {
    // Prevent recursion (merging while saving)
    if (_isLoadingRemoteChanges || _isSaving) {
      debugPrint('⏸️ REALTIME: Skipping merge (already saving or loading)');
      return;
    }

    _isLoadingRemoteChanges = true;

    try {
      debugPrint('🔄 REALTIME: Merging remote changes...');

      final remoteTrainees = remoteData['trainees'] as List?;
      if (remoteTrainees == null || remoteTrainees.isEmpty) {
        debugPrint('⚠️ REALTIME: No remote trainees to merge');
        _isLoadingRemoteChanges = false;
        return;
      }

      debugPrint('   Remote trainees count: ${remoteTrainees.length}');
      debugPrint('   Local trainees count: ${traineeRows.length}');

      setState(() {
        // Merge each trainee - KEEP NON-EMPTY VALUES from both sides
        for (int i = 0; i < remoteTrainees.length; i++) {
          // Ensure we have enough local rows
          while (i >= traineeRows.length) {
            traineeRows.add(
              TraineeRowModel(index: traineeRows.length, name: ''),
            );
          }

          final remoteTrainee = remoteTrainees[i] as Map<String, dynamic>;
          final remoteName = (remoteTrainee['name'] as String?) ?? '';
          final remoteValues =
              remoteTrainee['values'] as Map<String, dynamic>? ?? {};

          debugPrint('   Merging trainee[$i]:');
          debugPrint('     Local name: "${traineeRows[i].name}"');
          debugPrint('     Remote name: "$remoteName"');

          // MERGE NAME: Use remote name if local is empty
          if (traineeRows[i].name.trim().isEmpty && remoteName.isNotEmpty) {
            debugPrint('     ✅ Taking remote name');
            traineeRows[i].name = remoteName;

            // ✅ FIX: Update name TextField controller explicitly to prevent display mismatch
            // This ensures the UI shows the merged name immediately
            final nameControllerKey = 'trainee_$i';
            if (_textControllers.containsKey(nameControllerKey)) {
              _textControllers[nameControllerKey]!.text = remoteName;
              debugPrint('     🔄 Updated name controller to: "$remoteName"');
            }
          } else if (traineeRows[i].name.trim().isNotEmpty &&
              remoteName.isEmpty) {
            debugPrint('     ✅ Keeping local name');
            // Keep local name - controller already correct
          } else if (traineeRows[i].name.trim().isNotEmpty &&
              remoteName.isNotEmpty &&
              traineeRows[i].name != remoteName) {
            debugPrint(
              '     ⚠️ Both have names - keeping local (user is editing)',
            );
            // Keep local (current user is typing) - don't update controller
          }

          // MERGE VALUES: Take non-zero values from either side
          final Map<int, int> mergedValues = Map<int, int>.from(
            traineeRows[i].values,
          );
          int mergedCount = 0;

          remoteValues.forEach((key, value) {
            final stageIdx = int.tryParse(
              key.toString().replaceAll('station_', ''),
            );
            if (stageIdx != null) {
              final localValue = traineeRows[i].values[stageIdx] ?? 0;
              final remoteValue = (value as num?)?.toInt() ?? 0;

              debugPrint(
                '     Station[$stageIdx]: local=$localValue remote=$remoteValue',
              );

              // SMART MERGE: Take non-zero value
              if (localValue == 0 && remoteValue > 0) {
                mergedValues[stageIdx] = remoteValue;
                mergedCount++;
                debugPrint('       → Taking remote value');
              } else if (localValue > 0 && remoteValue == 0) {
                // Keep local
                debugPrint('       → Keeping local value');
              } else if (localValue > 0 &&
                  remoteValue > 0 &&
                  localValue != remoteValue) {
                // Both have values - keep local (user is actively editing)
                debugPrint('       → Both non-zero, keeping local');
              }
            }
          });

          // Apply merged values
          traineeRows[i].values.addAll(mergedValues);

          debugPrint('     Merged $mergedCount cells from remote');
        }
      });

      debugPrint('✅ REALTIME: Merge complete');
    } catch (e) {
      debugPrint('❌ REALTIME: Merge failed: $e');
    } finally {
      _isLoadingRemoteChanges = false;
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
      final rawSettlementName = data['settlementName'] as String?;
      final rawRangeFolder = data['rangeFolder'] as String?;
      final rawFolderKey = data['folderKey'] as String?; // ✅ Load folder ID
      final rawFolderLabel =
          data['folderLabel'] as String?; // ✅ Load folder label
      final rawAttendeesCount = data['attendeesCount'] as num?;
      final rawInstructorsCount =
          data['instructorsCount'] as num?; // מספר מדריכים
      final rawInstructors = data['instructors'] as List?; // רשימת מדריכים
      final rawSelectedShortRangeStage =
          data['selectedShortRangeStage'] as String?;
      final rawManualStageName = data['manualStageName'] as String?;
      final rawSelectedLongRangeStage =
          data['selectedLongRangeStage'] as String?;
      final rawLongRangeManualStageName =
          data['longRangeManualStageName'] as String?;
      final rawLongRangeManualBulletsCount =
          data['longRangeManualBulletsCount'] as num?;

      // ✅ Load original creator's name (use stored name)
      final createdByName = data['createdByName'] as String?;
      final createdByUid =
          data['instructorId'] as String? ??
          data['createdByUid'] as String?; // ✅ Load creator UID for permissions

      debugPrint('DRAFT_LOAD: rawTrainees.length=${rawTrainees?.length ?? -1}');
      debugPrint('DRAFT_LOAD: rawStations.length=${rawStations?.length ?? -1}');
      debugPrint('DRAFT_LOAD: settlement=$rawSettlement');
      debugPrint('DRAFT_LOAD: settlementName=$rawSettlementName');
      debugPrint('DRAFT_LOAD: rangeFolder=$rawRangeFolder');
      debugPrint('DRAFT_LOAD: folderKey=$rawFolderKey'); // ✅ Debug log
      debugPrint('DRAFT_LOAD: folderLabel=$rawFolderLabel'); // ✅ Debug log
      debugPrint('DRAFT_LOAD: attendeesCount=$rawAttendeesCount');
      debugPrint(
        'DRAFT_LOAD: selectedShortRangeStage=$rawSelectedShortRangeStage',
      );
      debugPrint('DRAFT_LOAD: manualStageName=$rawManualStageName');
      debugPrint(
        'DRAFT_LOAD: selectedLongRangeStage=$rawSelectedLongRangeStage',
      );
      debugPrint(
        'DRAFT_LOAD: longRangeManualStageName=$rawLongRangeManualStageName',
      );
      debugPrint(
        'DRAFT_LOAD: longRangeManualBulletsCount=$rawLongRangeManualBulletsCount',
      );

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

            // 🔥 WEB VERIFICATION: Log loaded values for Long Range
            if (kIsWeb && _rangeType == 'ארוכים') {
              debugPrint(
                '🌐 WEB LR_RAW_AFTER_LOAD: trainee="${row.name}", values=${row.values}',
              );
            }

            loadedRows.add(row);
            debugPrint(
              'DRAFT_LOAD:   row[$i]: name="${row.name}" values=${row.values}',
            );
          }
        }
      }

      debugPrint('DRAFT_LOAD: Loaded ${loadedRows.length} trainee rows');
      // ⚠️ POINTS VERIFICATION: Log loaded points for Long Range (no conversion)
      if (_rangeType == 'ארוכים' && loadedRows.isNotEmpty) {
        debugPrint('╔═══ LONG RANGE POINTS LOAD VERIFICATION ═══╗');
        for (int i = 0; i < loadedRows.length && i < 3; i++) {
          final row = loadedRows[i];
          debugPrint('║ Trainee[$i]: "${row.name}" RAW values=${row.values}');
          if (row.values.isNotEmpty) {
            final firstIdx = row.values.keys.first;
            debugPrint(
              '║   Station[$firstIdx]: value=${row.values[firstIdx]} (NO conversion applied)',
            );
          }
        }
        debugPrint('╚═══════════════════════════════════════════════╝');
      }

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
              maxPoints: (m['maxPoints'] as num?)
                  ?.toInt(), // Long Range: max score
              achievedPoints: (m['achievedPoints'] as num?)
                  ?.toInt(), // Long Range: achieved score
            ),
          );
        }
      }

      // ✅ Restore Short Range stage selection from draft
      String? restoredShortRangeStage = rawSelectedShortRangeStage;
      String restoredManualStageName = rawManualStageName ?? '';

      // ✅ BACKWARD COMPATIBILITY: If no stage data saved, try to restore from first station
      if (_rangeType == 'קצרים' && restoredShortRangeStage == null) {
        if (loadedStations.isNotEmpty) {
          final firstStation = loadedStations.first;
          // Check if it's a manual stage
          if (firstStation.isManual) {
            restoredShortRangeStage = 'מקצה ידני';
            restoredManualStageName = firstStation.name;
          } else {
            // Find matching stage name from predefined list
            final matchingStage = shortRangeStages.firstWhere(
              (stage) => stage == firstStation.name,
              orElse: () => '',
            );
            if (matchingStage.isNotEmpty) {
              restoredShortRangeStage = matchingStage;
            }
          }
          debugPrint(
            'DRAFT_LOAD: Restored Short Range stage from station: $restoredShortRangeStage',
          );
        }
      }

      // 🔥 WEB LONG RANGE DEBUG: CRITICAL checkpoint - verify values BEFORE setState
      if (kIsWeb && _rangeType == 'ארוכים' && loadedRows.isNotEmpty) {
        debugPrint('\n╔═══ WEB LR: VALUES ENTERING setState ═══╗');
        for (int i = 0; i < loadedRows.length && i < 3; i++) {
          final row = loadedRows[i];
          debugPrint('║ Row[$i]: "${row.name}"');
          debugPrint('║   values map: ${row.values}');
          row.values.forEach((stationIdx, value) {
            debugPrint(
              '║   ⚠️ station[$stationIdx] = $value ← THIS WILL ENTER STATE',
            );
            if (value > 0 && value <= 10 && (value * 10) <= 100) {
              debugPrint(
                '║   ❌ SUSPICIOUS: Looks like $value was divided by 10 (original might be ${value * 10})',
              );
            }
          });
        }
        debugPrint('╚═══════════════════════════════════════╝\n');
      }

      // ✅ CHECK FOR V2 DATA MODEL AND MIGRATE IF NEEDED (before setState)
      Map<String, dynamic>? lrV2 = data['lrV2'] as Map<String, dynamic>?;
      if (_rangeType == 'ארוכים') {
        if (lrV2 == null || lrV2.isEmpty) {
          debugPrint('🔄 LR_V2_LOAD: V2 data missing, running migration...');
          lrV2 = _migrateLongRangeToV2(data);

          if (lrV2.isNotEmpty) {
            // ✅ PERSIST V2 BACK TO FIRESTORE (one-time migration)
            try {
              await docRef.update({'lrV2': lrV2});
              debugPrint('✅ LR_V2_MIGRATED: Persisted V2 to Firestore');
            } catch (e) {
              debugPrint('⚠️ LR_V2_MIGRATION: Failed to persist: $e');
            }
          }
        } else {
          debugPrint(
            '✅ LR_V2_LOAD: V2 data found (version=${lrV2['version']})',
          );
        }

        // ✅ CALCULATE SUMMARY FROM V2
        if (lrV2.isNotEmpty) {
          final summary = _calculateSummaryFromV2(lrV2);
          debugPrint('\n📊 LR_V2_SUMMARY CALCULATION:');
          debugPrint(
            '   Total: ${summary['totalAchieved']}/${summary['totalMax']}',
          );
          final stageResults = summary['stageResults'] as List;
          for (final stageResult in stageResults) {
            debugPrint(
              '   ${stageResult['stageName']}: ${stageResult['achieved']}/${stageResult['max']}',
            );
          }
        }
      }

      // ✅ UPDATE STATE: Replace all data with loaded data
      setState(() {
        // ✅ Save original creator name and UID
        _originalCreatorName = createdByName;
        _originalCreatorUid =
            createdByUid; // ✅ Save creator UID for finalize permission check

        // Update metadata
        selectedSettlement = rawSettlement ?? selectedSettlement;
        settlementName = rawSettlementName ?? settlementName;

        // ✅ FIX: Restore rangeFolder/surpriseDrillsFolder UI value from folderKey/folderLabel
        if (widget.mode == 'surprise') {
          // ✅ SURPRISE DRILLS: Restore surpriseDrillsFolder from folderKey
          if (rawFolderKey == 'surprise_drills_general') {
            surpriseDrillsFolder = 'תרגילי הפתעה כללי';
          } else if (rawFolderKey == 'surprise_drills') {
            surpriseDrillsFolder = 'משוב תרגילי הפתעה';
          } else if (rawFolderLabel != null && rawFolderLabel.isNotEmpty) {
            // Fallback to folderLabel for backwards compatibility
            surpriseDrillsFolder = rawFolderLabel;
          }
          debugPrint(
            'DRAFT_LOAD: ✅ Restored surpriseDrillsFolder=$surpriseDrillsFolder from folderKey=$rawFolderKey',
          );
        } else {
          // ✅ RANGE MODES: Restore rangeFolder from folderKey/folderLabel
          // Priority: Use folderKey to determine correct UI value, fallback to rawRangeFolder
          if (rawFolderKey != null && rawFolderKey.isNotEmpty) {
            if (rawFolderKey == 'ranges_474') {
              rangeFolder = 'מטווחים 474';
            } else if (rawFolderKey == 'shooting_ranges') {
              rangeFolder = 'מטווחי ירי';
            } else {
              // Unknown folderKey, use folderLabel or rawRangeFolder as fallback
              rangeFolder = rawFolderLabel ?? rawRangeFolder;
            }
          } else if (rawFolderLabel != null && rawFolderLabel.isNotEmpty) {
            // Fallback to folderLabel if folderKey is missing
            rangeFolder = rawFolderLabel;
          } else {
            // Last resort: use rawRangeFolder (may be null)
            rangeFolder = rawRangeFolder ?? rangeFolder;
          }
        }

        loadedFolderKey =
            rawFolderKey; // ✅ Store loaded folder ID (can be null)
        loadedFolderLabel =
            rawFolderLabel; // ✅ Store loaded folder label (can be null)
        rangeSubType = data['rangeSubType'] as String?; // ✅ Load display label
        isManualLocation = data['isManualLocation'] as bool? ?? false;
        manualLocationText = data['manualLocationText'] as String? ?? '';
        _settlementDisplayText = isManualLocation
            ? 'Manual Location'
            : (settlementName.isNotEmpty
                  ? settlementName
                  : (selectedSettlement ?? ''));
        attendeesCount = rawAttendeesCount?.toInt() ?? attendeesCount;
        _attendeesCountController.text = attendeesCount.toString();

        // טען נתוני מדריכים
        instructorsCount = rawInstructorsCount?.toInt() ?? instructorsCount;
        _instructorsCountController.text = instructorsCount.toString();

        // טען שמות מדריכים לבקרים
        if (rawInstructors != null) {
          // נקה בקרים קיימים
          for (final controller in _instructorNameControllers.values) {
            controller.dispose();
          }
          _instructorNameControllers.clear();

          // צור בקרים חדשים עם השמות הטעונים
          for (
            int i = 0;
            i < rawInstructors.length && i < instructorsCount;
            i++
          ) {
            final instructorName = rawInstructors[i]?.toString() ?? '';
            final controllerKey = 'instructor_$i';
            _instructorNameControllers[controllerKey] = TextEditingController(
              text: instructorName,
            );
          }
        }

        instructorName = data['instructorName'] as String? ?? instructorName;

        // ✅ Restore Short Range multi-stage list
        if (_rangeType == 'קצרים') {
          shortRangeStagesList.clear();
          for (final station in loadedStations) {
            final isManual = station.isManual;
            final bullets = station.bulletsCount;
            if (isManual) {
              shortRangeStagesList.add(
                ShortRangeStageModel(
                  selectedStage: 'מקצה ידני',
                  manualName: station.name,
                  isManual: true,
                  bulletsCount: bullets,
                ),
              );
            } else {
              // Try to match with predefined stages
              final matchingStage = shortRangeStages.firstWhere(
                (s) => s == station.name,
                orElse: () => 'מקצה ידני',
              );
              if (matchingStage == 'מקצה ידני') {
                // Treat as manual if no match
                shortRangeStagesList.add(
                  ShortRangeStageModel(
                    selectedStage: 'מקצה ידני',
                    manualName: station.name,
                    isManual: true,
                    bulletsCount: bullets,
                  ),
                );
              } else {
                shortRangeStagesList.add(
                  ShortRangeStageModel(
                    selectedStage: matchingStage,
                    manualName: '',
                    isManual: false,
                    bulletsCount: bullets,
                  ),
                );
              }
            }
          }
          debugPrint(
            'DRAFT_LOAD: Restored ${shortRangeStagesList.length} Short Range stages',
          );
        }

        // ✅ Legacy compatibility: Also restore single-stage variables
        selectedShortRangeStage = restoredShortRangeStage;
        manualStageName = restoredManualStageName;
        _manualStageController.text = manualStageName;

        // ✅ Restore Long Range multi-stage list
        if (_rangeType == 'ארוכים') {
          longRangeStagesList.clear();

          // Try to restore from stations data
          if (loadedStations.isNotEmpty) {
            for (final station in loadedStations) {
              final isManual = station.isManual;
              final stageName = station.name;

              // ✅ Read maxPoints from station (NOT from bulletsCount!)
              final int maxPoints = station.maxPoints ?? 0;
              final int bulletsCount = station.bulletsCount;
              final int achievedPoints = station.achievedPoints ?? 0;

              longRangeStagesList.add(
                LongRangeStageModel(
                  name: stageName,
                  maxPoints: maxPoints, // ✅ Restore user-entered max score
                  bulletsCount: bulletsCount, // ✅ Tracking only
                  achievedPoints: achievedPoints, // ✅ Restore achieved points
                  isManual: isManual,
                ),
              );
            }
            debugPrint(
              'DRAFT_LOAD: Restored ${longRangeStagesList.length} Long Range stages from stations',
            );
          } else {
            // No stations data - initialize with default stages
            for (final stageName in longRangeStageNames) {
              longRangeStagesList.add(
                LongRangeStageModel(
                  name: stageName,
                  bulletsCount: stageName == 'מקצה ידני'
                      ? 0
                      : 8, // default bullets
                  achievedPoints: 0,
                  isManual: stageName == 'מקצה ידני',
                ),
              );
            }
            debugPrint(
              'DRAFT_LOAD: Initialized ${longRangeStagesList.length} default Long Range stages',
            );
          }
        }

        // ✅ Replace traineeRows with loaded data (NO default empty rows)
        traineeRows = loadedRows;

        // ✅ Save loaded trainees for restoration when count changes
        _loadedDraftTrainees = List<TraineeRowModel>.from(loadedRows);

        // ✅ Load summary text from draft
        final loadedSummary = data['summary'] as String? ?? '';
        trainingSummary = loadedSummary;
        _trainingSummaryController.text = loadedSummary;

        // Replace stations with loaded data
        stations = loadedStations.isNotEmpty ? loadedStations : stations;

        // 🔥 WEB FIX: Clear text controllers for long range to force recreation with fresh values
        // Root cause: _getController reuses existing controllers without updating text
        // After load, old controller.text still has pre-save values (e.g., "75")
        // but if they were normalized during save/load cycle, we need fresh controllers
        // This ensures controllers are recreated on next build with current traineeRows values
        if (kIsWeb && _rangeType == 'ארוכים') {
          debugPrint(
            '🌐 WEB LONG RANGE: Clearing ${_textControllers.length} text controllers to prevent stale values',
          );
          // Dispose old controllers
          for (final controller in _textControllers.values) {
            controller.dispose();
          }
          _textControllers.clear();
          debugPrint(
            '🌐 WEB LONG RANGE: Controllers cleared, will be recreated on rebuild',
          );
        }

        debugPrint('DRAFT_LOAD: State updated');
        debugPrint('DRAFT_LOAD:   attendeesCount=$attendeesCount');
        debugPrint('DRAFT_LOAD:   traineeRows.length=${traineeRows.length}');
        debugPrint('DRAFT_LOAD:   stations.length=${stations.length}');
        debugPrint(
          'DRAFT_LOAD:   selectedShortRangeStage=$selectedShortRangeStage',
        );
        debugPrint('DRAFT_LOAD:   manualStageName=$manualStageName');
        debugPrint(
          'DRAFT_LOAD:   shortRangeStagesList.length=${shortRangeStagesList.length}',
        );
        debugPrint(
          'DRAFT_LOAD:   longRangeStagesList.length=${longRangeStagesList.length}',
        );
      });

      // ✅ FORCE REBUILD: Ensure UI updates with loaded data
      debugPrint('DRAFT_LOAD: Forcing rebuild...');
      if (mounted) {
        setState(() {}); // Explicit rebuild trigger
        debugPrint('DRAFT_LOAD: UI setState completed');
      }

      debugPrint('✅ DRAFT_LOAD: Load complete');
      debugPrint('DRAFT_LOAD: traineeRows.length=${traineeRows.length}');
      for (int i = 0; i < traineeRows.length && i < 3; i++) {
        debugPrint(
          'DRAFT_LOAD:   traineeRows[$i]: name="${traineeRows[i].name}" values=${traineeRows[i].values}',
        );
      }

      // ✅ FIX: Load autocomplete trainees after draft is loaded
      // This ensures the green button appears when opening a draft
      if ((widget.mode == 'range' && rangeFolder == 'מטווחים 474') ||
          (widget.mode == 'surprise' &&
              surpriseDrillsFolder == 'משוב תרגילי הפתעה')) {
        final settlementToLoad = settlementName.isNotEmpty
            ? settlementName
            : (selectedSettlement ?? '');
        if (settlementToLoad.isNotEmpty) {
          debugPrint(
            '🔄 DRAFT_LOAD: Loading autocomplete trainees for settlement: $settlementToLoad',
          );
          await _loadTraineesForAutocomplete(settlementToLoad);
        }
      }

      debugPrint('========== ✅ DRAFT_LOAD END (SUCCESS) ==========\n');

      // ✅ START REAL-TIME LISTENER: Monitor concurrent edits by other admins
      _startListeningToDraft(id);
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(rangeTitle),
          leading: const StandardBackButton(),
        ),
        body: SingleChildScrollView(
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

              // Folder selection for Surprise Drills (required field)
              if (widget.mode == 'surprise') ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('surprise_folder_$surpriseDrillsFolder'),
                  initialValue: surpriseDrillsFolder,
                  hint: const Text('בחר תיקייה'),
                  decoration: const InputDecoration(
                    labelText: 'תיקייה',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'משוב תרגילי הפתעה',
                      child: Text('תרגילי הפתעה 474'),
                    ),
                    DropdownMenuItem(
                      value: 'תרגילי הפתעה כללי',
                      child: Text('תרגילי הפתעה כללי'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      surpriseDrillsFolder = value;
                      // Reset settlement when folder changes
                      settlementName = '';
                      selectedSettlement = null;
                      _settlementDisplayText = '';
                      isManualLocation = false;
                      manualLocationText = '';
                    });
                    _scheduleAutoSave();
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Folder selection for Range modes
              if (widget.mode != 'surprise') ...[
                // Select Folder (474 Ranges or Shooting Ranges)
                DropdownButtonFormField<String>(
                  initialValue: rangeFolder,
                  decoration: const InputDecoration(
                    labelText: 'בחר תיקייה',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'מטווחים 474',
                      child: Text('מטווחים 474'),
                    ),
                    DropdownMenuItem(
                      value: 'מטווחי ירי',
                      child: Text('מטווחי ירי'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      rangeFolder = value;
                      // Clear settlement when folder changes
                      settlementName = '';
                      selectedSettlement = null;
                      _settlementDisplayText = '';
                      // Clear autocomplete when folder changes
                      _autocompleteTrainees = [];
                    });
                    _scheduleAutoSave();
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Settlement/Location Field - Different behavior for Surprise vs Range modes
              if (widget.mode == 'surprise') ...[
                // SURPRISE DRILLS: Different behavior based on folder selection
                if (surpriseDrillsFolder == 'תרגילי הפתעה כללי') ...[
                  // תרגילי הפתעה כללי: Free text input for settlement
                  TextField(
                    controller: TextEditingController(text: settlementName)
                      ..selection = TextSelection.collapsed(
                        offset: settlementName.length,
                      ),
                    decoration: const InputDecoration(
                      labelText: 'יישוב',
                      border: OutlineInputBorder(),
                      hintText: 'הזן שם יישוב',
                    ),
                    onChanged: (value) {
                      setState(() {
                        settlementName = value;
                        _settlementDisplayText = value;
                      });
                      _scheduleAutoSave();
                    },
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  // תרגילי הפתעה 474: Dropdown with settlements + Manual Location option
                  TextField(
                    controller: TextEditingController(
                      text: _settlementDisplayText,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'יישוב',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    readOnly: true,
                    onTap: _openSettlementSelectorSheet,
                  ),
                  const SizedBox(height: 16),

                  // Manual Location text field (shown when Manual Location is selected)
                  if (isManualLocation) ...[
                    TextField(
                      controller:
                          TextEditingController(text: manualLocationText)
                            ..selection = TextSelection.collapsed(
                              offset: manualLocationText.length,
                            ),
                      decoration: const InputDecoration(
                        labelText: 'יישוב ידני',
                        border: OutlineInputBorder(),
                        hintText: 'הזן שם יישוב',
                        prefixIcon: Icon(
                          Icons.edit_location_alt,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          manualLocationText = value;
                          settlementName =
                              value; // Store in settlementName for save
                        });
                        _scheduleAutoSave();
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ] else ...[
                // RANGE MODE: Conditional based on folder
                if (rangeFolder == 'מטווחים 474') ...[
                  // Dropdown for 474 Ranges (Golan settlements + יישוב ידני)
                  TextField(
                    controller: TextEditingController(
                      text: _settlementDisplayText,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'יישוב',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    readOnly: true,
                    onTap: _openSettlementSelectorSheet,
                  ),
                  const SizedBox(height: 16),

                  // ✅ Manual Settlement text field (shown when יישוב ידני is selected)
                  if (isManualSettlement) ...[
                    TextField(
                      controller:
                          TextEditingController(text: manualSettlementText)
                            ..selection = TextSelection.collapsed(
                              offset: manualSettlementText.length,
                            ),
                      decoration: const InputDecoration(
                        labelText: 'שם יישוב',
                        border: OutlineInputBorder(),
                        hintText: 'הזן שם יישוב',
                        prefixIcon: Icon(
                          Icons.edit_location_alt,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          manualSettlementText = value;
                          settlementName = value; // Store for save
                        });
                        _scheduleAutoSave();
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ] else if (rangeFolder == 'מטווחי ירי') ...[
                  // Free text for Shooting Ranges
                  TextField(
                    controller: TextEditingController(text: settlementName)
                      ..selection = TextSelection.collapsed(
                        offset: settlementName.length,
                      ),
                    decoration: const InputDecoration(
                      labelText: 'יישוב',
                      border: OutlineInputBorder(),
                      hintText: 'הזן שם יישוב',
                    ),
                    onChanged: (value) {
                      setState(() {
                        settlementName = value;
                      });
                      _scheduleAutoSave();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ],

              // מדריך
              TextField(
                controller:
                    TextEditingController(
                        text: _originalCreatorName ?? instructorName,
                      )
                      ..selection = TextSelection.collapsed(
                        offset: (_originalCreatorName ?? instructorName).length,
                      ),
                decoration: const InputDecoration(
                  labelText: 'מדריך',
                  border: OutlineInputBorder(),
                ),
                enabled: false,
              ),
              const SizedBox(height: 16),

              // ✅ תאריך - עריכה רק עבור אדמין יותם
              if (currentUser?.name == 'יותם אלון' &&
                  currentUser?.role == 'Admin') ...[
                InkWell(
                  onTap: _selectDateTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'תאריך',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).format(_selectedDateTime),
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Icon(
                          Icons.edit_calendar,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // מספר מדריכים באימון
              TextField(
                controller: _instructorsCountController,
                decoration: const InputDecoration(
                  labelText: 'מספר מדריכים באימון',
                  border: OutlineInputBorder(),
                  hintText: 'הזן מספר מדריכים (אופציונלי)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final count = int.tryParse(v) ?? 0;
                  setState(() {
                    instructorsCount = count;
                  });
                  _scheduleAutoSave();
                },
              ),
              const SizedBox(height: 16),

              // טבלת מדריכים (displayed when count > 0)
              if (instructorsCount > 0) ...[
                const Text(
                  'מדריכים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.blueGrey.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Table header
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: const [
                              SizedBox(
                                width: 60,
                                child: Text(
                                  'מספר',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'שם',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Instructors rows
                        ...List.generate(instructorsCount, (index) {
                          final controllerKey = 'instructor_$index';
                          if (!_instructorNameControllers.containsKey(
                            controllerKey,
                          )) {
                            _instructorNameControllers[controllerKey] =
                                TextEditingController();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                // Number column
                                Container(
                                  width: 60,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Name column - Autocomplete with suggestions
                                Expanded(
                                  child: Autocomplete<String>(
                                    optionsBuilder:
                                        (TextEditingValue textEditingValue) {
                                          if (textEditingValue.text.isEmpty) {
                                            return brigade474Instructors;
                                          }
                                          return brigade474Instructors.where((
                                            name,
                                          ) {
                                            return name.contains(
                                              textEditingValue.text,
                                            );
                                          });
                                        },
                                    onSelected: (String selection) {
                                      setState(() {
                                        _instructorNameControllers[controllerKey]!
                                                .text =
                                            selection;
                                      });
                                      _scheduleAutoSave();
                                    },
                                    fieldViewBuilder:
                                        (
                                          context,
                                          controller,
                                          focusNode,
                                          onFieldSubmitted,
                                        ) {
                                          // Sync with instructor controller
                                          final instructorController =
                                              _instructorNameControllers[controllerKey]!;
                                          if (controller.text.isEmpty &&
                                              instructorController
                                                  .text
                                                  .isNotEmpty) {
                                            controller.text =
                                                instructorController.text;
                                          }
                                          // Update instructor controller when autocomplete changes
                                          controller.addListener(() {
                                            instructorController.text =
                                                controller.text;
                                            _scheduleAutoSave();
                                          });

                                          return TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            decoration: const InputDecoration(
                                              hintText: 'בחר או הקלד שם מדריך',
                                              labelText: 'שם מדריך',
                                              border: OutlineInputBorder(),
                                              filled: true,
                                              fillColor: Colors.white,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 14,
                                                  ),
                                              suffixIcon: Icon(
                                                Icons.arrow_drop_down,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 14,
                                            ),
                                          );
                                        },
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ✨ בחירת חניכים - כפתור מרכזי (רק למטווחים 474 ותרגילי הפתעה 474)
              // ✅ FIX: Use selectedSettlement OR settlementName to catch both new drafts and loaded ones
              if ((widget.mode == 'range' &&
                      rangeFolder == 'מטווחים 474' &&
                      (settlementName.isNotEmpty ||
                          (selectedSettlement?.isNotEmpty ?? false)) &&
                      _autocompleteTrainees.isNotEmpty) ||
                  (widget.mode == 'surprise' &&
                      surpriseDrillsFolder == 'משוב תרגילי הפתעה' &&
                      (settlementName.isNotEmpty ||
                          (selectedSettlement?.isNotEmpty ?? false)) &&
                      _autocompleteTrainees.isNotEmpty)) ...[
                const Text(
                  'בחירת נוכחים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openTraineeSelectionDialog,
                    icon: const Icon(Icons.how_to_reg, size: 24),
                    label: const Text(
                      'בחר חניכים מרשימה',
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
              ],

              // כמות נוכחים (ידני)
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
                onSubmitted: (v) {
                  final count = int.tryParse(v) ?? 0;
                  _updateAttendeesCount(count);
                  _saveImmediately(); // שמירה מיידית כשמסיימים לערוך
                },
              ),
              const SizedBox(height: 32),

              // Short Range: Multi-stage dynamic list with add/remove
              if (_rangeType == 'קצרים') ...[
                // כותרת מקצים
                const Text(
                  'מקצים',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Display each stage with delete button
                ...shortRangeStagesList.asMap().entries.map((entry) {
                  final index = entry.key;
                  final stage = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with stage number and delete button
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'מקצה ${index + 1}: ${stage.displayName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (stage.bulletsCount > 0)
                                      Text(
                                        '${stage.bulletsCount} כדורים',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeShortRangeStage(index),
                                tooltip: 'מחק מקצה',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Stage dropdown
                          DropdownButtonFormField<String>(
                            initialValue: stage.selectedStage,
                            decoration: const InputDecoration(
                              labelText: 'בחר מקצה',
                              border: OutlineInputBorder(),
                            ),
                            items: shortRangeStages.map((stageName) {
                              return DropdownMenuItem(
                                value: stageName,
                                child: Text(stageName),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                shortRangeStagesList[index] =
                                    ShortRangeStageModel(
                                      selectedStage: value,
                                      manualName: value == 'מקצה ידני'
                                          ? stage.manualName
                                          : '',
                                      isManual: value == 'מקצה ידני',
                                      bulletsCount: stage.bulletsCount,
                                      timeLimit:
                                          stage.timeLimit, // Preserve timeLimit
                                    );
                              });
                              _scheduleAutoSave();
                            },
                          ),

                          // Manual stage name input (shown only when "מקצה ידני" selected)
                          if (stage.isManual) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller:
                                  TextEditingController(text: stage.manualName)
                                    ..selection = TextSelection.collapsed(
                                      offset: stage.manualName.length,
                                    ),
                              decoration: const InputDecoration(
                                labelText: 'שם מקצה ידני',
                                border: OutlineInputBorder(),
                                hintText: 'הזן שם מקצה',
                              ),
                              onChanged: (value) {
                                setState(() {
                                  shortRangeStagesList[index] =
                                      ShortRangeStageModel(
                                        selectedStage: stage.selectedStage,
                                        manualName: value,
                                        isManual: true,
                                        bulletsCount: stage.bulletsCount,
                                        timeLimit: stage
                                            .timeLimit, // Preserve timeLimit
                                      );
                                });
                                _scheduleAutoSave();
                              },
                            ),
                          ],

                          // Bullets count input
                          const SizedBox(height: 12),
                          TextField(
                            controller:
                                TextEditingController(
                                    text: stage.bulletsCount > 0
                                        ? stage.bulletsCount.toString()
                                        : '',
                                  )
                                  ..selection = TextSelection.collapsed(
                                    offset:
                                        (stage.bulletsCount > 0
                                                ? stage.bulletsCount.toString()
                                                : '')
                                            .length,
                                  ),
                            decoration: const InputDecoration(
                              labelText: 'מס׳ כדורים',
                              border: OutlineInputBorder(),
                              hintText: 'הזן מספר כדורים',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (value) {
                              setState(() {
                                shortRangeStagesList[index] =
                                    ShortRangeStageModel(
                                      selectedStage: stage.selectedStage,
                                      manualName: stage.manualName,
                                      isManual: stage.isManual,
                                      bulletsCount: int.tryParse(value) ?? 0,
                                      timeLimit:
                                          stage.timeLimit, // Preserve timeLimit
                                    );
                              });
                              _scheduleAutoSave();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // כפתור הוסף מקצה/עיקרון - מתחת לרשימת המקצים
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _addShortRangeStage,
                    icon: const Icon(Icons.add),
                    label: Text(_addItemLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],

              // Long Range: Multi-stage with add/remove (like Short Range)
              if (_rangeType == 'ארוכים' && widget.mode == 'range') ...[
                // כותרת מקצים
                const Text(
                  'מקצים',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Show message when no stages added yet
                if (longRangeStagesList.isEmpty)
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'לא נוספו מקצים עדיין. לחץ "הוסף מקצה" להתחיל.',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Stage cards list
                ...longRangeStagesList.asMap().entries.map((entry) {
                  final index = entry.key;
                  final stage = entry.value;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with stage name and delete button
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'מקצה ${index + 1}: ${stage.name}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (stage.maxPoints > 0)
                                      Text(
                                        'מקסימום: ${stage.maxPoints} נק׳',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    if (stage.bulletsCount > 0)
                                      Text(
                                        'כדורים: ${stage.bulletsCount}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeLongRangeStage(index),
                                tooltip: 'מחק מקצה',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Stage name dropdown (like Short Range)
                          DropdownButtonFormField<String>(
                            initialValue:
                                longRangeStageNames.contains(stage.name)
                                ? stage.name
                                : (stage.isManual ? 'מקצה ידני' : null),
                            decoration: const InputDecoration(
                              labelText: 'בחר מקצה',
                              border: OutlineInputBorder(),
                            ),
                            hint: const Text('בחר מקצה'),
                            items: longRangeStageNames.map((stageName) {
                              return DropdownMenuItem(
                                value: stageName,
                                child: Text(stageName),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                final isManual = value == 'מקצה ידני';
                                stage.name = isManual
                                    ? stage.name
                                    : (value ?? '');
                                stage.isManual = isManual;
                              });
                              _scheduleAutoSave();
                            },
                          ),

                          // Manual stage name input (shown only when "מקצה ידני" selected)
                          if (stage.isManual) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller:
                                  TextEditingController(
                                      text: stage.name == 'מקצה ידני'
                                          ? ''
                                          : stage.name,
                                    )
                                    ..selection = TextSelection.collapsed(
                                      offset:
                                          (stage.name == 'מקצה ידני'
                                                  ? ''
                                                  : stage.name)
                                              .length,
                                    ),
                              decoration: const InputDecoration(
                                labelText: 'שם מקצה ידני',
                                border: OutlineInputBorder(),
                                hintText: 'הזן שם מקצה',
                              ),
                              onChanged: (value) {
                                setState(() {
                                  stage.name = value.isNotEmpty
                                      ? value
                                      : 'מקצה ידני';
                                });
                                _scheduleAutoSave();
                              },
                            ),
                          ],

                          // Max score input (direct entry, no multiplication)
                          const SizedBox(height: 12),
                          // Side-by-side layout for max score and bullets (RTL: right to left)
                          Row(
                            children: [
                              // Right side (50%): Max Score
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller:
                                      TextEditingController(
                                          text: stage.maxPoints > 0
                                              ? stage.maxPoints.toString()
                                              : '',
                                        )
                                        ..selection = TextSelection.collapsed(
                                          offset:
                                              (stage.maxPoints > 0
                                                      ? stage.maxPoints
                                                            .toString()
                                                      : '')
                                                  .length,
                                        ),
                                  decoration: const InputDecoration(
                                    labelText: 'ציון מקסימלי',
                                    border: OutlineInputBorder(),
                                    hintText: 'ציון מקס',
                                    helperText: 'ציון מקסימלי במקצה',
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      stage.maxPoints =
                                          int.tryParse(value) ?? 0;
                                    });
                                    _scheduleAutoSave();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Left side (50%): Bullet tracking
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller:
                                      TextEditingController(
                                          text: stage.bulletsCount > 0
                                              ? stage.bulletsCount.toString()
                                              : '',
                                        )
                                        ..selection = TextSelection.collapsed(
                                          offset:
                                              (stage.bulletsCount > 0
                                                      ? stage.bulletsCount
                                                            .toString()
                                                      : '')
                                                  .length,
                                        ),
                                  decoration: const InputDecoration(
                                    labelText: 'כדורים (מעקב)',
                                    border: OutlineInputBorder(),
                                    hintText: 'מספר כדורים',
                                    helperText: 'למעקב בלבד',
                                    suffixIcon: Icon(
                                      Icons.info_outline,
                                      size: 20,
                                    ),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      stage.bulletsCount =
                                          int.tryParse(value) ?? 0;
                                    });
                                    _scheduleAutoSave();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // כפתור הוסף מקצה - מתחת לרשימת המקצים
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _addLongRangeStage,
                    icon: const Icon(Icons.add),
                    label: const Text('הוסף מקצה'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],

              // Surprise: Multi-principle approach (existing)
              if (widget.mode == 'surprise') ...[
                // כותרת עקרונות
                Text(
                  _itemsLabel,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // רשימת עקרונות
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
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
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
                              hint: const Text('בחר עיקרון'),
                              decoration: const InputDecoration(
                                labelText: 'שם העיקרון',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: availablePrinciples
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
                                });
                                // NO AUTOSAVE - user must manually save
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Surprise mode: no bullets field needed
                        ],
                      ),
                    ),
                  );
                }),

                // כפתור הוספת עיקרון - מתחת לרשימת העקרונות
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _addStation,
                    icon: const Icon(Icons.add),
                    label: Text(_addItemLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ], // End of Surprise multi-principle section

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

                // ✅ סיכום האימון - שדה טקסט חופשי למדריך
                const Text(
                  'סיכום האימון',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _trainingSummaryController,
                  decoration: const InputDecoration(
                    labelText: 'סיכום',
                    hintText: 'תאר את האימון, נקודות חשובות, הערות...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  onChanged: (v) {
                    setState(() => trainingSummary = v);
                  },
                ),
                const SizedBox(height: 24),

                // Finalize Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('אישור סיום משוב'),
                                content: const Text(
                                  'האם אתה בטוח שברצונך לסיים ולסגור את המשוב?\nהפעולה סוגרת את המשוב לצמיתות.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('ביטול'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('סיים וסגור'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) _saveToFirestore();
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: _isSaving
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
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

  /// Build stations list from Short Range stages for table display
  List<RangeStation> _getDisplayStations() {
    if (_rangeType == 'קצרים' && shortRangeStagesList.isNotEmpty) {
      // Build from Short Range stages list
      return shortRangeStagesList.map((stage) {
        final stageName = stage.isManual
            ? stage.manualName.trim()
            : stage.selectedStage ?? '';

        return RangeStation(
          name: stageName,
          bulletsCount:
              stage.bulletsCount, // Use actual bullets count from stage
          timeSeconds: null,
          hits: null,
          isManual: stage.isManual,
          isLevelTester: stage.selectedStage == 'בוחן רמה',
          selectedRubrics: ['זמן', 'פגיעות'],
        );
      }).toList();
    }

    if (_rangeType == 'ארוכים' && longRangeStagesList.isNotEmpty) {
      // Build from Long Range stages list
      return longRangeStagesList.map((stage) {
        return RangeStation(
          name: stage.name,
          bulletsCount: stage.bulletsCount,
          timeSeconds: null,
          hits: stage.achievedPoints,
          isManual: stage.isManual,
          isLevelTester: false,
          selectedRubrics: ['זמן', 'פגיעות'],
        );
      }).toList();
    }

    // For Surprise mode, use existing stations list
    return stations;
  }

  // ✅ V2: Mobile Long Range Table - Isolated fix for render box size issue
  Widget _buildLongRangeMobileTableV2() {
    debugPrint('\n🎯🎯🎯 _buildLongRangeMobileTableV2 CALLED! 🎯🎯🎯');
    final displayStations = _getDisplayStations();
    debugPrint('   displayStations.length=${displayStations.length}');
    debugPrint('   traineeRows.length=${traineeRows.length}');
    debugPrint('   traineeRows.isEmpty=${traineeRows.isEmpty}');

    // ❌ CRITICAL CHECK: If traineeRows is empty, V2 will fail!
    if (traineeRows.isEmpty) {
      debugPrint(
        '   ❌❌❌ ERROR: traineeRows is EMPTY in V2! Returning error widget.',
      );
      return Center(
        child: Card(
          color: Colors.red.shade100,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'שגיאה: אין חניכים ב-V2',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'traineeRows.length = ${traineeRows.length}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ✅ NEW: Use same architecture as short range for stability
    // Calculate total width for stations + summary columns
    final double totalStationsWidth =
        (displayStations.length * stationColumnWidth) +
        285; // 3 summary columns × 95

    debugPrint('   totalStationsWidth=$totalStationsWidth');
    debugPrint('   ✅ Building with short-range-style architecture');

    // ✅ STABLE ARCHITECTURE: Copy short range structure exactly
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
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...displayStations.asMap().entries.map((entry) {
                          final stationIndex = entry.key;
                          final station = entry.value;
                          return SizedBox(
                            width: 95,
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.all(4.0),
                              decoration: BoxDecoration(
                                color: station.isLevelTester
                                    ? Colors.orange.shade50
                                    : Colors.blueGrey.shade50,
                                border: Border(
                                  left: BorderSide(color: Colors.grey.shade300),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    station.name.isEmpty
                                        ? 'שלב ${stationIndex + 1}'
                                        : station.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: station.isLevelTester
                                          ? Colors.orange.shade900
                                          : Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if ((station.maxPoints ?? 0) > 0) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'מקס: ${_rangeType == 'ארוכים' && stationIndex < longRangeStagesList.length ? longRangeStagesList[stationIndex].maxPoints : station.bulletsCount}',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: station.isLevelTester
                                            ? Colors.orange.shade700
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_rangeType == 'ארוכים' && stationIndex < longRangeStagesList.length ? longRangeStagesList[stationIndex].maxPoints : station.bulletsCount}',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        // Summary headers
                        SizedBox(
                          width: 95,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.all(4.0),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              border: Border(
                                left: BorderSide(color: Colors.grey.shade300),
                                bottom: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'סהכ נקודות',
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
                        ),
                        SizedBox(
                          width: 95,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.all(4.0),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              border: Border(
                                left: BorderSide(color: Colors.grey.shade300),
                                bottom: BorderSide(color: Colors.grey.shade300),
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
                        ),
                        SizedBox(
                          width: 95,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.all(4.0),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'סהכ כדורים',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  color: Colors.orange,
                                ),
                                textAlign: TextAlign.center,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // B) SCROLLABLE CONTENT AREA (can scroll vertically)
            Expanded(
              child: Row(
                children: [
                  // LEFT STICKY NAME COLUMN (scrolls only vertically)
                  SizedBox(
                    width: nameColumnWidth,
                    child: ListView.builder(
                      controller: _namesVertical,
                      physics: const ClampingScrollPhysics(),
                      itemCount: traineeRows.length,
                      itemExtent: rowHeight,
                      itemBuilder: (context, idx) {
                        final row = traineeRows[idx];
                        final controllerKey = 'trainee_$idx';
                        final focusKey = 'trainee_$idx';

                        return SizedBox(
                          height: rowHeight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(color: Colors.grey.shade300),
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: _buildTraineeAutocomplete(
                              idx: idx,
                              row: row,
                              controllerKey: controllerKey,
                              focusKey: focusKey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // RIGHT SCROLLABLE AREA (scrolls both ways, synced)
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _resultsHorizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalStationsWidth,
                        child: ListView.builder(
                          controller: _resultsVertical,
                          physics: const ClampingScrollPhysics(),
                          itemCount: traineeRows.length,
                          itemExtent: rowHeight,
                          itemBuilder: (context, rowIndex) {
                            final row = traineeRows[rowIndex];
                            return SizedBox(
                              height: rowHeight,
                              child: Row(
                                children: [
                                  ...displayStations.asMap().entries.map((
                                    entry,
                                  ) {
                                    final stationIndex = entry.key;
                                    final currentScore = row.getValue(
                                      stationIndex,
                                    );
                                    final controllerKey =
                                        'row_${rowIndex}_station_$stationIndex';
                                    final focusKey =
                                        'row_${rowIndex}_station_$stationIndex';
                                    return SizedBox(
                                      width: stationColumnWidth,
                                      child: Container(
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: Colors.grey.shade200,
                                            ),
                                            bottom: BorderSide(
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                        ),
                                        child: TextField(
                                          controller: _getController(
                                            controllerKey,
                                            currentScore.toString(),
                                          ),
                                          focusNode: _getFocusNode(focusKey),
                                          decoration: const InputDecoration(
                                            hintText: '0',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 6,
                                                ),
                                          ),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 12),
                                          maxLines: 1,
                                          keyboardType: TextInputType.number,
                                          onChanged: (v) {
                                            final parsed = int.tryParse(v) ?? 0;
                                            row.setValue(stationIndex, parsed);
                                            _scheduleAutoSave();
                                          },
                                          onSubmitted: (v) {
                                            final parsed = int.tryParse(v) ?? 0;
                                            row.setValue(stationIndex, parsed);
                                            _saveImmediately();
                                          },
                                        ),
                                      ),
                                    );
                                  }),
                                  // Summary columns
                                  SizedBox(
                                    width: 95,
                                    child: Container(
                                      padding: const EdgeInsets.all(4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        border: Border(
                                          left: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                          bottom: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${row.values.values.isEmpty ? 0 : row.values.values.reduce((a, b) => a + b)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 95,
                                    child: Container(
                                      padding: const EdgeInsets.all(4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        border: Border(
                                          left: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                          bottom: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          (() {
                                            final filledScores = row
                                                .values
                                                .values
                                                .where((v) => v > 0)
                                                .toList();
                                            if (filledScores.isEmpty) {
                                              return '0';
                                            }
                                            final avg =
                                                filledScores.reduce(
                                                  (a, b) => a + b,
                                                ) /
                                                filledScores.length;
                                            return avg.toStringAsFixed(1);
                                          })(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 95,
                                    child: Container(
                                      padding: const EdgeInsets.all(4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          (() {
                                            int total = 0;
                                            for (final station
                                                in displayStations) {
                                              total += station.bulletsCount;
                                            }
                                            return total.toString();
                                          })(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
  }

  Widget _buildTraineesTable() {
    // Get stations for display (builds from shortRangeStagesList for Short Range)
    final displayStations = _getDisplayStations();

    final screenWidth = MediaQuery.sizeOf(context).width;
    debugPrint('\n🔍 DEBUG: _buildTraineesTable called');
    debugPrint('   screenWidth=$screenWidth');
    debugPrint('   traineeRows.length=${traineeRows.length}');
    debugPrint('   traineeRows.isEmpty=${traineeRows.isEmpty}');
    debugPrint('   attendeesCount=$attendeesCount');
    debugPrint('   displayStations.length=${displayStations.length}');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        // ✅ Check isEmpty AFTER LayoutBuilder but BEFORE mobile/desktop split
        // This allows V2 and other branches to be reached if data exists
        if (traineeRows.isEmpty) {
          return Center(
            child: Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person_off,
                      size: 48,
                      color: Colors.orange,
                    ),
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

        if (isMobile) {
          debugPrint('   🔍 isMobile=true, _rangeType=$_rangeType');
          // ✅ V2: Use isolated method for mobile long-range to prevent render box size issues
          if (_rangeType == 'ארוכים') {
            debugPrint('   ✅ Calling _buildLongRangeMobileTableV2()');
            return _buildLongRangeMobileTableV2();
          }
          debugPrint('   ⚠️ NOT calling V2 - using short range mobile table');

          // ✅ FINAL PRODUCTION-SAFE SYNCHRONIZED SCROLLING
          // Calculate total width for stations + summary columns
          final double totalStationsWidth =
              (displayStations.length * stationColumnWidth) +
              (widget.mode == 'surprise' ? 170 : 160);

          // For short range: keep existing implementation
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
                        child: _rangeType == 'ארוכים'
                            ? SingleChildScrollView(
                                controller: _headerHorizontal,
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    ...displayStations.asMap().entries.map((
                                      entry,
                                    ) {
                                      final stationIndex = entry.key;
                                      final station = entry.value;
                                      return SizedBox(
                                        width: 95,
                                        child: Container(
                                          height:
                                              widget.mode == 'surprise' &&
                                                  kIsWeb
                                              ? 68
                                              : 56,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            color: station.isLevelTester
                                                ? Colors.orange.shade50
                                                : Colors.blueGrey.shade50,
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
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                  color: station.isLevelTester
                                                      ? Colors.orange.shade800
                                                      : Colors.black87,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                              ),
                                              if (stationIndex <
                                                      longRangeStagesList
                                                          .length &&
                                                  longRangeStagesList[stationIndex]
                                                          .maxPoints >
                                                      0) ...[
                                                Text(
                                                  '${longRangeStagesList[stationIndex].maxPoints}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                    // Summary columns for long range
                                    SizedBox(
                                      width: 95,
                                      child: Container(
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
                                            'סהכ נקודות',
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
                                    ),
                                    SizedBox(
                                      width: 95,
                                      child: Container(
                                        height: 56,
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
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
                                    ),
                                    SizedBox(
                                      width: 95,
                                      child: Container(
                                        height: 56,
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'סהכ כדורים',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                              color: Colors.orange,
                                            ),
                                            textAlign: TextAlign.center,
                                            softWrap: false,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                controller: _headerHorizontal,
                                primary: false,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: totalStationsWidth,
                                  child: Row(
                                    children: [
                                      ...displayStations.asMap().entries.map((
                                        entry,
                                      ) {
                                        final stationIndex = entry.key;
                                        final station = entry.value;
                                        return Container(
                                          width: stationColumnWidth,
                                          // ✅ WEB FIX: Increase height for surprise drills to show "מקס׳: 10" without clipping
                                          height:
                                              widget.mode == 'surprise' &&
                                                  kIsWeb
                                              ? 68
                                              : 56,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            color: station.isLevelTester
                                                ? Colors
                                                      .orange
                                                      .shade50 // Highlight בוחן רמה header
                                                : Colors.blueGrey.shade50,
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
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                  color: station.isLevelTester
                                                      ? Colors.orange.shade800
                                                      : Colors.black87,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                              ),
                                              // ✅ SURPRISE DRILLS: Show "מקס׳: 10" for each principle
                                              if (widget.mode ==
                                                  'surprise') ...[
                                                const SizedBox(
                                                  height: 2,
                                                ), // ✅ WEB FIX: Add spacing for better visibility
                                                const Text(
                                                  'מקס׳: 10',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black54,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ]
                                              // בוחן רמה: Show bullet count number
                                              else if (widget.mode == 'range' &&
                                                  station.isLevelTester) ...[
                                                Text(
                                                  '${station.bulletsCount}',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color:
                                                        Colors.orange.shade700,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ] else if (widget.mode ==
                                                      'range' &&
                                                  _rangeType == 'ארוכים' &&
                                                  stationIndex <
                                                      longRangeStagesList
                                                          .length &&
                                                  longRangeStagesList[stationIndex]
                                                          .maxPoints >
                                                      0) ...[
                                                Text(
                                                  '${longRangeStagesList[stationIndex].maxPoints}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ] else if (widget.mode ==
                                                      'range' &&
                                                  _rangeType == 'קצרים' &&
                                                  station.bulletsCount > 0) ...[
                                                // Short Range: Show just the number
                                                Text(
                                                  '${station.bulletsCount}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
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
                                      ] else if (_rangeType == 'ארוכים') ...[
                                        // Long Range: Use "נקודות" labels
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
                                              'סהכ נקודות',
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
                                        Container(
                                          width: 70,
                                          height: 56,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              'סהכ כדורים',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                                color: Colors.orange,
                                              ),
                                              textAlign: TextAlign.center,
                                              softWrap: false,
                                            ),
                                          ),
                                        ),
                                      ] else ...[
                                        // Short Range: Use "פגיעות" labels
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
                                    child: _buildTraineeAutocomplete(
                                      idx: idx,
                                      row: row,
                                      controllerKey: controllerKey,
                                      focusKey: focusKey,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Scrollable results (scrolls both horizontally and vertically, synced)
                        Expanded(
                          child: _rangeType == 'ארוכים'
                              ? ListView.builder(
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
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              // For long range, use fixed width for each station
                                              ...displayStations.asMap().entries.map((
                                                entry,
                                              ) {
                                                final stationIndex = entry.key;
                                                final currentValue = row
                                                    .getValue(stationIndex);
                                                final controllerKey =
                                                    'trainee_${traineeIdx}_station_$stationIndex';
                                                final focusKey =
                                                    'trainee_${traineeIdx}_station_$stationIndex';

                                                return SizedBox(
                                                  width: 95,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 2.0,
                                                          vertical: 1.0,
                                                        ),
                                                    child: TextField(
                                                      controller: _getController(
                                                        controllerKey,
                                                        row.values.containsKey(
                                                              stationIndex,
                                                            )
                                                            ? currentValue
                                                                  .toString()
                                                            : '',
                                                      ),
                                                      focusNode: _getFocusNode(
                                                        focusKey,
                                                      ),
                                                      decoration: const InputDecoration(
                                                        hintText: '0',
                                                        isDense: true,
                                                        border:
                                                            OutlineInputBorder(),
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 4,
                                                              vertical: 8,
                                                            ),
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                      keyboardType:
                                                          TextInputType.number,
                                                      inputFormatters: [
                                                        FilteringTextInputFormatter
                                                            .digitsOnly,
                                                      ],
                                                      onChanged: (v) {
                                                        if (v.isEmpty) {
                                                          row.setValue(
                                                            stationIndex,
                                                            0,
                                                          );
                                                        } else {
                                                          final score =
                                                              int.tryParse(v) ??
                                                              0;
                                                          row.setValue(
                                                            stationIndex,
                                                            score,
                                                          );
                                                        }
                                                        _scheduleAutoSave();
                                                      },
                                                      onSubmitted: (v) {
                                                        if (v.isEmpty) {
                                                          row.setValue(
                                                            stationIndex,
                                                            0,
                                                          );
                                                        } else {
                                                          final score =
                                                              int.tryParse(v) ??
                                                              0;
                                                          row.setValue(
                                                            stationIndex,
                                                            score,
                                                          );
                                                        }
                                                        _saveImmediately();
                                                      },
                                                    ),
                                                  ),
                                                );
                                              }),
                                              // Summary columns with fixed width
                                              SizedBox(
                                                width: 95,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2.0,
                                                        vertical: 1.0,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.shade50,
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      row.values.values.isEmpty
                                                          ? '0'
                                                          : row.values.values
                                                                .reduce(
                                                                  (a, b) =>
                                                                      a + b,
                                                                )
                                                                .toString(),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 11,
                                                        color: Colors.blue,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 95,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2.0,
                                                        vertical: 1.0,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.shade50,
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Builder(
                                                      builder: (context) {
                                                        if (row
                                                            .values
                                                            .isEmpty) {
                                                          return const Text(
                                                            '-',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 11,
                                                              color:
                                                                  Colors.green,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                          );
                                                        }
                                                        final total = row
                                                            .values
                                                            .values
                                                            .reduce(
                                                              (a, b) => a + b,
                                                            );
                                                        final count =
                                                            row.values.length;
                                                        final avg =
                                                            total / count;
                                                        return Text(
                                                          avg.toStringAsFixed(
                                                            1,
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .green,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 95,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2.0,
                                                        vertical: 1.0,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.orange.shade50,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      (longRangeStagesList
                                                              .map(
                                                                (s) => s
                                                                    .bulletsCount,
                                                              )
                                                              .reduce(
                                                                (a, b) => a + b,
                                                              ))
                                                          .toString(),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 11,
                                                        color: Colors.orange,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : SingleChildScrollView(
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
                                                // Station input fields - use displayStations for consistency
                                                ...displayStations.asMap().entries.map((
                                                  entry,
                                                ) {
                                                  final stationIndex =
                                                      entry.key;
                                                  final station = entry.value;
                                                  final currentValue = row
                                                      .getValue(stationIndex);

                                                  // 🔥 WEB DEBUG: BEFORE controller creation - verify source value
                                                  if (kIsWeb &&
                                                      _rangeType == 'ארוכים' &&
                                                      currentValue != 0) {
                                                    debugPrint(
                                                      '\n🌐 WEB_BUILD: trainee="${row.name}" station=$stationIndex currentValue=$currentValue',
                                                    );
                                                    debugPrint(
                                                      '   Source: row.values[$stationIndex]=${row.values[stationIndex]}',
                                                    );
                                                    debugPrint(
                                                      '   Will create controller with initialValue="${currentValue == 0 ? '' : currentValue.toString()}"',
                                                    );
                                                    if (currentValue <= 10 &&
                                                        (currentValue * 10) <=
                                                            100) {
                                                      debugPrint(
                                                        '   ❌ SUSPICIOUS currentValue=$currentValue (looks divided by 10)',
                                                      );
                                                    } else {
                                                      debugPrint(
                                                        '   ✅ currentValue=$currentValue looks correct (not divided)',
                                                      );
                                                    }
                                                  }

                                                  // 🔥 DEBUG: WEB LONG RANGE - trace exact value source
                                                  if (kIsWeb &&
                                                      _rangeType == 'ארוכים' &&
                                                      currentValue != 0) {
                                                    debugPrint(
                                                      '\n🔍 WEB_LR_BUILD: trainee="${row.name}" station=$stationIndex',
                                                    );
                                                    debugPrint(
                                                      '   row.getValue($stationIndex) = $currentValue',
                                                    );
                                                    debugPrint(
                                                      '   station.bulletsCount = ${station.bulletsCount}',
                                                    );
                                                    debugPrint(
                                                      '   station.name = "${station.name}"',
                                                    );
                                                    if (stationIndex <
                                                        longRangeStagesList
                                                            .length) {
                                                      final stage =
                                                          longRangeStagesList[stationIndex];
                                                      debugPrint(
                                                        '   stage.bulletsCount = ${stage.bulletsCount}',
                                                      );
                                                      debugPrint(
                                                        '   stage.maxPoints = ${stage.maxPoints}',
                                                      );
                                                    }
                                                    debugPrint(
                                                      '   Expected controller text: "$currentValue"',
                                                    );
                                                  }

                                                  final controllerKey =
                                                      'trainee_${traineeIdx}_station_$stationIndex';
                                                  final focusKey =
                                                      'trainee_${traineeIdx}_station_$stationIndex';

                                                  // בוחן רמה: Compact dual input (hits + time) in SAME cell
                                                  if (station.isLevelTester &&
                                                      widget.mode == 'range') {
                                                    final timeValue = row
                                                        .getTimeValue(
                                                          stationIndex,
                                                        );
                                                    final timeControllerKey =
                                                        'trainee_${traineeIdx}_station_${stationIndex}_time';
                                                    final timeFocusKey =
                                                        'trainee_${traineeIdx}_station_${stationIndex}_time';

                                                    // Compact vertical stack: hits on top, time below
                                                    return SizedBox(
                                                      width: stationColumnWidth,
                                                      height: rowHeight,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 2.0,
                                                              vertical: 1.0,
                                                            ),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            // Hits input (פגיעות) - top
                                                            SizedBox(
                                                              height:
                                                                  (rowHeight /
                                                                      2) -
                                                                  2,
                                                              child: TextField(
                                                                controller: _getController(
                                                                  controllerKey,
                                                                  row.values.containsKey(
                                                                        stationIndex,
                                                                      )
                                                                      ? currentValue
                                                                            .toString()
                                                                      : '',
                                                                ),
                                                                focusNode:
                                                                    _getFocusNode(
                                                                      focusKey,
                                                                    ),
                                                                decoration: const InputDecoration(
                                                                  isDense: true,
                                                                  border:
                                                                      OutlineInputBorder(),
                                                                  hintText:
                                                                      'פג׳',
                                                                  hintStyle:
                                                                      TextStyle(
                                                                        fontSize:
                                                                            8,
                                                                      ),
                                                                  contentPadding:
                                                                      EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            4,
                                                                        vertical:
                                                                            2,
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
                                                                    TextAlign
                                                                        .center,
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                    ),
                                                                maxLines: 1,
                                                                onChanged: (v) {
                                                                  final hits =
                                                                      int.tryParse(
                                                                        v,
                                                                      ) ??
                                                                      0;
                                                                  // Long Range validation against stage maxPoints
                                                                  if (_rangeType ==
                                                                          'ארוכים' &&
                                                                      stationIndex <
                                                                          longRangeStagesList
                                                                              .length) {
                                                                    final stage =
                                                                        longRangeStagesList[stationIndex];
                                                                    if (hits >
                                                                        stage
                                                                            .maxPoints) {
                                                                      ScaffoldMessenger.of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'נקודות לא יכולות לעלות על ${stage.maxPoints} נקודות',
                                                                          ),
                                                                          duration: const Duration(
                                                                            seconds:
                                                                                1,
                                                                          ),
                                                                        ),
                                                                      );
                                                                      return;
                                                                    }
                                                                  } else if (hits >
                                                                      station
                                                                          .bulletsCount) {
                                                                    // Short Range validation against station bulletsCount
                                                                    ScaffoldMessenger.of(
                                                                      context,
                                                                    ).showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text(
                                                                              'פגיעות לא יכולות לעלות על ${station.bulletsCount}',
                                                                            ),
                                                                        duration: const Duration(
                                                                          seconds:
                                                                              1,
                                                                        ),
                                                                      ),
                                                                    );
                                                                    return;
                                                                  }
                                                                  row.setValue(
                                                                    stationIndex,
                                                                    hits,
                                                                  );
                                                                  setState(
                                                                    () {},
                                                                  ); // מאלץ רענון מיידי של הטבלה
                                                                  _scheduleAutoSave();
                                                                },
                                                                onSubmitted: (v) {
                                                                  final hits =
                                                                      int.tryParse(
                                                                        v,
                                                                      ) ??
                                                                      0;
                                                                  row.setValue(
                                                                    stationIndex,
                                                                    hits,
                                                                  );
                                                                  setState(
                                                                    () {},
                                                                  ); // מאלץ רענון מיידי של הטבלה
                                                                  _saveImmediately();
                                                                },
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            // Time input (זמן) - bottom
                                                            SizedBox(
                                                              height:
                                                                  (rowHeight /
                                                                      2) -
                                                                  2,
                                                              child: TextField(
                                                                controller: _getController(
                                                                  timeControllerKey,
                                                                  timeValue == 0
                                                                      ? ''
                                                                      : timeValue
                                                                            .toString(),
                                                                ),
                                                                focusNode:
                                                                    _getFocusNode(
                                                                      timeFocusKey,
                                                                    ),
                                                                decoration: const InputDecoration(
                                                                  isDense: true,
                                                                  border:
                                                                      OutlineInputBorder(),
                                                                  hintText:
                                                                      'זמן',
                                                                  hintStyle:
                                                                      TextStyle(
                                                                        fontSize:
                                                                            8,
                                                                      ),
                                                                  contentPadding:
                                                                      EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            4,
                                                                        vertical:
                                                                            2,
                                                                      ),
                                                                ),
                                                                keyboardType:
                                                                    const TextInputType.numberWithOptions(
                                                                      decimal:
                                                                          true,
                                                                    ),
                                                                inputFormatters: [
                                                                  FilteringTextInputFormatter.allow(
                                                                    RegExp(
                                                                      r'^\d*\.?\d*$',
                                                                    ),
                                                                  ),
                                                                ],
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                    ),
                                                                maxLines: 1,
                                                                onChanged: (v) {
                                                                  final time =
                                                                      double.tryParse(
                                                                        v,
                                                                      ) ??
                                                                      0.0;
                                                                  row.setTimeValue(
                                                                    stationIndex,
                                                                    time,
                                                                  );
                                                                  setState(
                                                                    () {},
                                                                  ); // מאלץ רענון מיידי של הטבלה
                                                                  _scheduleAutoSave();
                                                                },
                                                                onSubmitted: (v) {
                                                                  final time =
                                                                      double.tryParse(
                                                                        v,
                                                                      ) ??
                                                                      0.0;
                                                                  row.setTimeValue(
                                                                    stationIndex,
                                                                    time,
                                                                  );
                                                                  setState(
                                                                    () {},
                                                                  ); // מאלץ רענון מיידי של הטבלה
                                                                  _saveImmediately();
                                                                },
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }

                                                  // Standard single input for non-level-tester stations
                                                  // ✅ LONG RANGE SCORE MODEL:
                                                  // - TextField shows/stores EXACT POINTS entered by instructor (0-100)
                                                  // - NO conversion, NO division, NO truncation
                                                  // - Persists value AS-IS to trainee.values[stationIndex]
                                                  // - Validation: clamps to stage.maxPoints (usually 100)

                                                  // 🐛 DEBUG LOGGING (LONG RANGE ONLY)
                                                  if (_rangeType == 'ארוכים') {
                                                    debugPrint(
                                                      '\n🔍 LONG RANGE DEBUG: Building TextField',
                                                    );
                                                    debugPrint(
                                                      '   traineeIdx=$traineeIdx, stationIndex=$stationIndex',
                                                    );
                                                    debugPrint(
                                                      '   currentValue from row.getValue($stationIndex)=$currentValue',
                                                    );
                                                    debugPrint(
                                                      '   row.values[$stationIndex]=${row.getValue(stationIndex)}',
                                                    );
                                                    debugPrint(
                                                      '   controllerKey=$controllerKey',
                                                    );
                                                    debugPrint(
                                                      '   Will pass to controller: initialValue="${currentValue == 0 ? '' : currentValue.toString()}"',
                                                    );
                                                  }

                                                  return SizedBox(
                                                    width: stationColumnWidth,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
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
                                                                  horizontal:
                                                                      2.0,
                                                                ),
                                                            child: Builder(
                                                              builder: (context) {
                                                                final controller = _getController(
                                                                  controllerKey,
                                                                  row.values.containsKey(
                                                                        stationIndex,
                                                                      )
                                                                      ? currentValue
                                                                            .toString()
                                                                      : '',
                                                                );

                                                                return TextField(
                                                                  controller:
                                                                      controller,
                                                                  focusNode:
                                                                      _getFocusNode(
                                                                        focusKey,
                                                                      ),
                                                                  decoration: const InputDecoration(
                                                                    isDense:
                                                                        true,
                                                                    border:
                                                                        OutlineInputBorder(),
                                                                    hintText:
                                                                        '0',
                                                                    contentPadding:
                                                                        EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              8,
                                                                          vertical:
                                                                              10,
                                                                        ),
                                                                  ),
                                                                  keyboardType:
                                                                      TextInputType
                                                                          .number,
                                                                  inputFormatters: [
                                                                    FilteringTextInputFormatter
                                                                        .digitsOnly,
                                                                    // ✅ LONG RANGE: Allow up to 3 digits (0-100)
                                                                    LengthLimitingTextInputFormatter(
                                                                      3,
                                                                    ),
                                                                  ],
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                  maxLines: 1,
                                                                  onChanged: (v) {
                                                                    // 🐛 DEBUG LOGGING (LONG RANGE ONLY)
                                                                    if (_rangeType ==
                                                                        'ארוכים') {
                                                                      if (kIsWeb) {
                                                                        debugPrint(
                                                                          '\n🌐 LR_WEB_INPUT="$v" trainee="${row.name}" station=$stationIndex',
                                                                        );
                                                                      } else {
                                                                        debugPrint(
                                                                          '\n📝 LONG RANGE onChanged: rawInput="$v" (MOBILE)',
                                                                        );
                                                                      }
                                                                    }

                                                                    // ✅ LONG RANGE SCORE INPUT:
                                                                    // Parse raw score - NO conversion
                                                                    final score =
                                                                        int.tryParse(
                                                                          v,
                                                                        ) ??
                                                                        0;

                                                                    // 🐛 DEBUG LOGGING (LONG RANGE ONLY)
                                                                    if (_rangeType ==
                                                                        'ארוכים') {
                                                                      if (kIsWeb) {
                                                                        debugPrint(
                                                                          '🌐 LR_WEB_PARSED=$score (RAW points, no conversion)',
                                                                        );
                                                                      } else {
                                                                        debugPrint(
                                                                          '   parsedScore=$score [MOBILE]',
                                                                        );
                                                                      }
                                                                    }

                                                                    // Validation based on mode
                                                                    if (widget
                                                                            .mode ==
                                                                        'surprise') {
                                                                      // ✅ Surprise drill: 0-10 scale (integers only)
                                                                      if (score <
                                                                              0 ||
                                                                          score >
                                                                              10) {
                                                                        ScaffoldMessenger.of(
                                                                          context,
                                                                        ).showSnackBar(
                                                                          const SnackBar(
                                                                            content: Text(
                                                                              'ציון חייב להיות בין 0 ל-10',
                                                                            ),
                                                                            duration: Duration(
                                                                              seconds: 1,
                                                                            ),
                                                                          ),
                                                                        );
                                                                        return;
                                                                      }
                                                                    } else if (_rangeType ==
                                                                        'ארוכים') {
                                                                      // ✅ LONG RANGE: Validate against stage maxPoints (POINTS-ONLY)
                                                                      // CRITICAL: NEVER validate against bullets for long-range
                                                                      if (stationIndex <
                                                                          longRangeStagesList
                                                                              .length) {
                                                                        final stage =
                                                                            longRangeStagesList[stationIndex];
                                                                        if (score >
                                                                            stage.maxPoints) {
                                                                          ScaffoldMessenger.of(
                                                                            context,
                                                                          ).showSnackBar(
                                                                            SnackBar(
                                                                              content: Text(
                                                                                'נקודות לא יכולות לעלות על ${stage.maxPoints} נקודות',
                                                                              ),
                                                                              duration: const Duration(
                                                                                seconds: 1,
                                                                              ),
                                                                            ),
                                                                          );
                                                                          return;
                                                                        }
                                                                      }
                                                                      // ✅ For long-range, accept ANY value if stage not found (defensive)
                                                                    } else if (score >
                                                                        station
                                                                            .bulletsCount) {
                                                                      // ✅ SHORT RANGE ONLY: Validate against bullets count
                                                                      ScaffoldMessenger.of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'פגיעות לא יכולות לעלות על ${station.bulletsCount} כדורים',
                                                                          ),
                                                                          duration: const Duration(
                                                                            seconds:
                                                                                1,
                                                                          ),
                                                                        ),
                                                                      );
                                                                      return;
                                                                    }
                                                                    // ✅ STORE RAW SCORE: No conversion, no division
                                                                    // Long Range: stores exact points (0-100)
                                                                    // Short Range: stores exact hits
                                                                    row.setValue(
                                                                      stationIndex,
                                                                      score,
                                                                    );

                                                                    // 🐛 DEBUG LOGGING (LONG RANGE ONLY)
                                                                    if (_rangeType ==
                                                                        'ארוכים') {
                                                                      if (kIsWeb) {
                                                                        debugPrint(
                                                                          '🌐 LR_WEB_MODEL_AFTER_SET=${row.getValue(stationIndex)} (verified RAW storage)',
                                                                        );
                                                                      } else {
                                                                        debugPrint(
                                                                          '   ✅ STORED: row.values[$stationIndex]=$score',
                                                                        );
                                                                        debugPrint(
                                                                          '   Verification: row.getValue($stationIndex)=${row.getValue(stationIndex)}',
                                                                        );
                                                                      }
                                                                    }

                                                                    _scheduleAutoSave();
                                                                  },
                                                                  onSubmitted: (v) {
                                                                    // ✅ IMMEDIATE SAVE: User pressed Enter
                                                                    // Store exact parsed value
                                                                    final score =
                                                                        int.tryParse(
                                                                          v,
                                                                        ) ??
                                                                        0;
                                                                    row.setValue(
                                                                      stationIndex,
                                                                      score,
                                                                    );
                                                                    _saveImmediately();
                                                                  },
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                // Summary columns
                                                if (widget.mode ==
                                                    'surprise') ...[
                                                  SizedBox(
                                                    width: 90,
                                                    height: rowHeight,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        _getTraineeTotalPoints(
                                                          traineeIdx,
                                                        ).toString(),
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.blue,
                                                          fontSize: 11,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 80,
                                                    height: rowHeight,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Builder(
                                                        builder: (_) {
                                                          // ✅ SURPRISE DRILLS: Show average score (0-10) with 1 decimal
                                                          final avgScore =
                                                              _getTraineeAveragePoints(
                                                                traineeIdx,
                                                              );
                                                          return Text(
                                                            avgScore > 0
                                                                ? avgScore
                                                                      .toStringAsFixed(
                                                                        1,
                                                                      )
                                                                : '—',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 11,
                                                              // Color thresholds for 0-10 scale: >=7=green, >=5=orange, <5=red
                                                              color:
                                                                  avgScore >=
                                                                      7.0
                                                                  ? Colors.green
                                                                  : avgScore >=
                                                                        5.0
                                                                  ? Colors
                                                                        .orange
                                                                  : Colors.red,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 1,
                                                            softWrap: false,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ] else if (_rangeType ==
                                                    'ארוכים') ...[
                                                  // Long Range: Points-based totals
                                                  SizedBox(
                                                    width: 90,
                                                    height: rowHeight,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        '${_getTraineeTotalPointsLongRange(traineeIdx)}/${_getTotalMaxPointsLongRangeEditTable()}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.blue,
                                                          fontSize: 10,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 70,
                                                    height: rowHeight,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Builder(
                                                        builder: (_) {
                                                          final percentage =
                                                              _getTraineeAveragePercentLongRange(
                                                                traineeIdx,
                                                              );
                                                          return Text(
                                                            '${percentage.toStringAsFixed(1)}%',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 10,
                                                              color:
                                                                  percentage >=
                                                                      70
                                                                  ? Colors.green
                                                                  : percentage >=
                                                                        50
                                                                  ? Colors
                                                                        .orange
                                                                  : Colors.red,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 1,
                                                            softWrap: false,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                  // Total bullets tracking column (Long Range)
                                                  SizedBox(
                                                    width: 70,
                                                    height: rowHeight,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        _getTotalBulletsLongRangeTracking()
                                                            .toString(),
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.orange,
                                                          fontSize: 10,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                ] else ...[
                                                  // Short Range: Hits-based totals
                                                  SizedBox(
                                                    width: 90,
                                                    height: rowHeight,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        '${_getTraineeTotalHits(traineeIdx)}/${_getTotalBulletsAllStages()}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.blue,
                                                          fontSize: 10,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 70,
                                                    height: rowHeight,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: Builder(
                                                        builder: (_) {
                                                          final totalHits =
                                                              _getTraineeTotalHits(
                                                                traineeIdx,
                                                              );
                                                          final totalBullets =
                                                              _getTotalBulletsAllStages();
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
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 10,
                                                              color:
                                                                  percentage >=
                                                                      70
                                                                  ? Colors.green
                                                                  : percentage >=
                                                                        50
                                                                  ? Colors
                                                                        .orange
                                                                  : Colors.red,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 1,
                                                            softWrap: false,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
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
                              ...displayStations.asMap().entries.map((entry) {
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
                                      // Surprise Drills: Show dynamic maxPoints
                                      if (widget.mode == 'surprise')
                                        Text(
                                          '${_getMaxPointsForPrinciple(index)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        )
                                      else if (_rangeType == 'ארוכים' &&
                                          index < longRangeStagesList.length &&
                                          longRangeStagesList[index].maxPoints >
                                              0)
                                        Text(
                                          '${longRangeStagesList[index].maxPoints}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                          textAlign: TextAlign.center,
                                        )
                                      else if (_rangeType == 'קצרים' &&
                                          station.bulletsCount > 0)
                                        // Short Range: Show just the number
                                        Text(
                                          '${station.bulletsCount}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                          textAlign: TextAlign.center,
                                        )
                                      else if (station.bulletsCount > 0)
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
                                    'אחוז',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ] else if (_rangeType == 'ארוכים') ...[
                                // Long Range: Use "נקודות" labels
                                const SizedBox(
                                  width: 100,
                                  child: Text(
                                    'סהכ נקודות',
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
                                const SizedBox(
                                  width: 100,
                                  child: Text(
                                    'סהכ כדורים',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ] else ...[
                                // Short Range: Use "פגיעות" labels
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
                                row.name = v;
                                _scheduleAutoSave();
                              },
                              onSubmitted: (v) {
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
                                  ...displayStations.asMap().entries.map((
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

                                    // בוחן רמה: Compact dual input (hits + time) stacked vertically
                                    if (station.isLevelTester &&
                                        widget.mode == 'range') {
                                      final timeValue = row.getTimeValue(
                                        stationIndex,
                                      );
                                      final timeControllerKey =
                                          'desktop_trainee_${traineeIndex}_station_${stationIndex}_time';
                                      final timeFocusKey =
                                          'desktop_trainee_${traineeIndex}_station_${stationIndex}_time';

                                      // Keep same width as other columns, stack inputs vertically
                                      return SizedBox(
                                        width: 90,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2.0,
                                            vertical: 2.0,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Hits input (פגיעות) - top
                                              SizedBox(
                                                height: 22,
                                                child: TextField(
                                                  controller: _getController(
                                                    controllerKey,
                                                    currentValue > 0
                                                        ? currentValue
                                                              .toString()
                                                        : '',
                                                  ),
                                                  focusNode: _getFocusNode(
                                                    focusKey,
                                                  ),
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                        border:
                                                            OutlineInputBorder(),
                                                        hintText: 'פג׳',
                                                        hintStyle: TextStyle(
                                                          fontSize: 9,
                                                        ),
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 4,
                                                              vertical: 2,
                                                            ),
                                                      ),
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                  ],
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                  onChanged: (v) {
                                                    final hits =
                                                        int.tryParse(v) ?? 0;
                                                    if (hits >
                                                        station.bulletsCount) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'פגיעות לא יכולות לעלות על ${station.bulletsCount}',
                                                          ),
                                                          duration:
                                                              const Duration(
                                                                seconds: 1,
                                                              ),
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    row.setValue(
                                                      stationIndex,
                                                      hits,
                                                    );
                                                    setState(() {});
                                                    _scheduleAutoSave();
                                                  },
                                                  onSubmitted: (v) {
                                                    final hits =
                                                        int.tryParse(v) ?? 0;
                                                    row.setValue(
                                                      stationIndex,
                                                      hits,
                                                    );
                                                    setState(
                                                      () {},
                                                    ); // מאלץ רענון מיידי של הטבלה
                                                    _saveImmediately();
                                                  },
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              // Time input (זמן) - bottom
                                              SizedBox(
                                                height: 22,
                                                child: TextField(
                                                  controller: _getController(
                                                    timeControllerKey,
                                                    timeValue > 0
                                                        ? timeValue.toString()
                                                        : '',
                                                  ),
                                                  focusNode: _getFocusNode(
                                                    timeFocusKey,
                                                  ),
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                        border:
                                                            OutlineInputBorder(),
                                                        hintText: 'זמן',
                                                        hintStyle: TextStyle(
                                                          fontSize: 9,
                                                        ),
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 4,
                                                              vertical: 2,
                                                            ),
                                                      ),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(r'^\d*\.?\d*$'),
                                                    ),
                                                  ],
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                  onChanged: (v) {
                                                    final time =
                                                        double.tryParse(v) ??
                                                        0.0;
                                                    row.setTimeValue(
                                                      stationIndex,
                                                      time,
                                                    );
                                                    setState(
                                                      () {},
                                                    ); // מאלץ רענון מיידי של הטבלה
                                                    _scheduleAutoSave();
                                                  },
                                                  onSubmitted: (v) {
                                                    final time =
                                                        double.tryParse(v) ??
                                                        0.0;
                                                    row.setTimeValue(
                                                      stationIndex,
                                                      time,
                                                    );
                                                    setState(
                                                      () {},
                                                    ); // מאלץ רענון מיידי של הטבלה
                                                    _saveImmediately();
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    // Standard single input for non-level-tester stations
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
                                          // ✅ LONG RANGE: Allow up to 3 digits (0-150)
                                          LengthLimitingTextInputFormatter(3),
                                        ],
                                        textAlign: TextAlign.center,
                                        onChanged: (v) {
                                          final score = int.tryParse(v) ?? 0;

                                          // Validation based on mode
                                          if (widget.mode == 'surprise') {
                                            // Surprise mode: 0-10 scale
                                            if (score < 0 || score > 10) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'ציון חייב להיות בין 0 ל-10',
                                                  ),
                                                  duration: Duration(
                                                    seconds: 1,
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                          } else if (_rangeType == 'ארוכים') {
                                            // ✅ LONG RANGE: Validate against stage maxPoints (POINTS-ONLY)
                                            // CRITICAL: NEVER validate against bullets for long-range
                                            if (stationIndex <
                                                longRangeStagesList.length) {
                                              final stage =
                                                  longRangeStagesList[stationIndex];
                                              if (score > stage.maxPoints) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'נקודות לא יכולות לעלות על ${stage.maxPoints} נקודות',
                                                    ),
                                                    duration: const Duration(
                                                      seconds: 1,
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                            }
                                            // ✅ Accept any value if stage not found (defensive)
                                          } else if (score >
                                              station.bulletsCount) {
                                            // ✅ SHORT RANGE ONLY: Validate against bullets count
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
                                  ] else if (_rangeType == 'ארוכים') ...[
                                    // Long Range: Points-based totals
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        '${_getTraineeTotalPointsLongRange(traineeIndex)}/${_getTotalMaxPointsLongRangeEditTable()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    // Percentage column (Long Range points-based)
                                    SizedBox(
                                      width: 100,
                                      child: Builder(
                                        builder: (_) {
                                          final percentage =
                                              _getTraineeAveragePercentLongRange(
                                                traineeIndex,
                                              );
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
                                    // Total bullets tracking column (Long Range)
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        _getTotalBulletsLongRangeTracking()
                                            .toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ] else ...[
                                    // Short Range: Hits/Bullets column
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        '${_getTraineeTotalHits(traineeIndex)}/${_getTotalBulletsAllStages()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    // Percentage column (Short Range hits-based)
                                    SizedBox(
                                      width: 100,
                                      child: Builder(
                                        builder: (_) {
                                          final totalHits =
                                              _getTraineeTotalHits(
                                                traineeIndex,
                                              );
                                          final totalBullets =
                                              _getTotalBulletsAllStages();
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
  final Map<int, double>
  timeValues; // stationIndex -> time in seconds (for בוחן רמה only) - supports decimals
  // Track which fields have been explicitly touched/entered (null/untouched vs 0/entered)
  final Map<int, bool>
  valuesTouched; // stationIndex -> true if explicitly entered
  final Map<int, bool>
  timeValuesTouched; // stationIndex -> true if explicitly entered

  TraineeRowModel({
    required this.index,
    required this.name,
    Map<int, int>? values,
    Map<int, double>? timeValues,
    Map<int, bool>? valuesTouched,
    Map<int, bool>? timeValuesTouched,
  }) : values = values ?? {},
       timeValues = timeValues ?? {},
       valuesTouched = valuesTouched ?? {},
       timeValuesTouched = timeValuesTouched ?? {};

  // Get value for a specific station/principle
  int getValue(int stationIndex) => values[stationIndex] ?? 0;

  // Set value for a specific station/principle
  void setValue(int stationIndex, int value) {
    // ✅ FIX: Only store values > 0
    // Existence of key in map = trainee performed this station
    // No key = not performed
    if (value > 0) {
      values[stationIndex] = value;
      debugPrint(
        '💾 setValue: stationIndex=$stationIndex, value=$value, stored=true',
      );
    } else {
      values.remove(stationIndex);
      debugPrint(
        '💾 setValue: stationIndex=$stationIndex, value=$value, removed from map',
      );
    }
  }

  // Get time value for a specific station (for בוחן רמה)
  double getTimeValue(int stationIndex) => timeValues[stationIndex] ?? 0.0;

  // Set time value for a specific station (for בוחן רמה)
  void setTimeValue(int stationIndex, double value) {
    // Mark as touched when user explicitly changes the field
    timeValuesTouched[stationIndex] = true;

    if (value == 0.0) {
      timeValues.remove(stationIndex);
    } else {
      timeValues[stationIndex] = value;
    }
  }

  // Check if has any data
  bool hasData() =>
      name.trim().isNotEmpty || values.isNotEmpty || timeValues.isNotEmpty;

  // Check if a specific stage should be included in FINAL statistics
  // Existence of key in values or timeValues map = stage was performed
  bool shouldIncludeStageInFinalStats(int stationIndex) {
    // Include if trainee has value OR time for this stage
    return values.containsKey(stationIndex) ||
        timeValues.containsKey(stationIndex);
  }

  // Serialize to Firestore format
  Map<String, dynamic> toFirestore() {
    final valuesMap = <String, int>{};
    // ✅ Only save stations that were actually performed (non-zero values)
    values.forEach((stationIdx, val) {
      if (val > 0) {
        valuesMap['station_$stationIdx'] = val;
      }
    });
    final timeValuesMap = <String, double>{};
    timeValues.forEach((stationIdx, val) {
      if (val != 0.0) {
        timeValuesMap['station_${stationIdx}_time'] = val;
      }
    });
    return {
      'index': index,
      'name': name.trim(),
      'values': valuesMap,
      'timeValues': timeValuesMap,
    };
  }

  // Deserialize from Firestore format
  static TraineeRowModel fromFirestore(Map<String, dynamic> data) {
    final index = (data['index'] as num?)?.toInt() ?? 0;
    final name = (data['name'] as String?) ?? '';
    // BACKWARD COMPATIBILITY: Read from 'values' (draft format) OR 'hits' (final save format)
    // Priority: 'values' first (draft format), fallback to 'hits' (final save format)
    final valuesRaw =
        (data['values'] as Map<String, dynamic>?) ??
        (data['hits'] as Map<String, dynamic>?) ??
        {};
    final timeValuesRaw = (data['timeValues'] as Map<String, dynamic>?) ?? {};

    // 🔥 WEB LONG RANGE DEBUG: Log RAW Firestore data BEFORE parsing
    if (kIsWeb) {
      debugPrint(
        '\n🌐 WEB_FROMFIRESTORE: trainee="$name" RAW valuesRaw=$valuesRaw',
      );
    }

    final values = <int, int>{};
    valuesRaw.forEach((key, val) {
      if (key.startsWith('station_') && !key.endsWith('_time')) {
        final stationIdx = int.tryParse(key.replaceFirst('station_', ''));
        final value = (val as num?)?.toInt() ?? 0;

        // 🔥 WEB LONG RANGE DEBUG: Log each value parsing step
        if (kIsWeb && value != 0) {
          debugPrint(
            '🌐 WEB_FROMFIRESTORE_PARSE: $key: raw=$val (type=${val.runtimeType}) → parsed=$value',
          );
        }

        // ✅ Only load non-zero values (if 0 was stored, it means not performed)
        if (stationIdx != null && value > 0) {
          values[stationIdx] = value;
        }
      }
    });

    final timeValues = <int, double>{};
    timeValuesRaw.forEach((key, val) {
      if (key.startsWith('station_') && key.endsWith('_time')) {
        final stationIdxStr = key
            .replaceFirst('station_', '')
            .replaceFirst('_time', '');
        final stationIdx = int.tryParse(stationIdxStr);
        final value = (val as num?)?.toDouble() ?? 0.0;
        if (stationIdx != null && value != 0.0) {
          timeValues[stationIdx] = value;
        }
      }
    });

    // 🔥 WEB LONG RANGE DEBUG: Log FINAL parsed values BEFORE return
    if (kIsWeb && values.isNotEmpty) {
      debugPrint(
        '🌐 WEB_FROMFIRESTORE_RESULT: trainee="$name" FINAL values=$values',
      );
    }

    return TraineeRowModel(
      index: index,
      name: name,
      values: values,
      timeValues: timeValues,
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

  // ✅ Long Range only: Max score points (e.g., 50, 100, 150) - NEVER derived from bulletsCount
  int? maxPoints;

  // ✅ Long Range only: Achieved points (0 to maxPoints)
  int? achievedPoints;

  RangeStation({
    required this.name,
    required this.bulletsCount,
    this.timeSeconds,
    this.hits,
    this.isManual = false,
    this.isLevelTester = false,
    List<String>? selectedRubrics,
    this.maxPoints,
    this.achievedPoints,
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
      'maxPoints': maxPoints, // Long Range: max score (e.g., 150)
      'achievedPoints': achievedPoints, // Long Range: achieved score
    };
  }
}
