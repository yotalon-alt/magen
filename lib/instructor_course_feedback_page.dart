import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';
import 'widgets/standard_back_button.dart';

class InstructorCourseFeedbackPage extends StatefulWidget {
  final String? screeningId;
  const InstructorCourseFeedbackPage({super.key, this.screeningId});

  @override
  State<InstructorCourseFeedbackPage> createState() =>
      _InstructorCourseFeedbackPageState();
}

class _InstructorCourseFeedbackPageState
    extends State<InstructorCourseFeedbackPage> {
  String? _existingScreeningId;
  bool _loadingExisting = false;
  bool _hasUnsavedChanges = false;
  bool _isFormLocked = false;
  String? _selectedPikud;
  final List<String> _pikudOptions = ['פיקוד צפון', 'פיקוד מרכז', 'פיקוד דרום'];
  String? _selectedHativa; // ✅ NEW: Brigade selection for פיקוד צפון
  final List<String> _hativaOptions = ['חטיבה 474', 'חטיבה 769', 'חטיבה 300'];
  String? _originalCreatorName; // ✅ Track original creator's name
  String?
  _originalCreatorUid; // ✅ Track original creator's UID for permission checks

  final TextEditingController _hativaController = TextEditingController();
  final TextEditingController _candidateNameController =
      TextEditingController();
  int? _candidateNumber;

  final TextEditingController _hitsController = TextEditingController();
  final TextEditingController _timeSecondsController = TextEditingController();

  // ✅ NEW: Notes controllers for each category
  final Map<String, TextEditingController> _notesControllers = {};

  // ✅ בוחן רמה: Simple score 1-10 (changed from 1-5)
  int levelTestScore = 0;

  // ✅ Multi-field categories: Each has 5 fields (1-10 each)
  // Categories: הדרכה טובה, הדרכת מבנה, הדרכת יבשים, תרגיל הפתעה
  final Map<String, Map<String, int>> multiFieldCategories = {
    'הדרכה טובה': {
      'ידע': 0,
      'עמידה מול קהל': 0,
      'מתודיקה': 0,
      'איכות הדרכה': 0,
      'איכות הדגמה': 0,
    },
    'הדרכת מבנה': {
      'ידע': 0,
      'עמידה מול קהל': 0,
      'מתודיקה': 0,
      'איכות הדרכה': 0,
      'איכות הדגמה': 0,
    },
    'הדרכת יבשים': {
      'ידע': 0,
      'עמידה מול קהל': 0,
      'מתודיקה': 0,
      'איכות הדרכה': 0,
      'איכות הדגמה': 0,
    },
    'תרגיל הפתעה': {
      'תקשורת': 0,
      'ציר התקדמות': 0,
      'קשר עין': 0,
      'קצב אש מרחק': 0,
      'וידוא נטרול': 0,
      'איכות ביצוע': 0,
    },
  };

  // ✅ Legacy Map for backwards compatibility during migration
  final Map<String, int> categories = {
    'בוחן רמה': 0,
    'הדרכה טובה': 0,
    'הדרכת מבנה': 0,
    'הדרכת יבשים': 0,
    'תרגיל הפתעה': 0,
  };

  /// Calculate hitsScore for בוחן רמה
  /// NEW LOGIC for hits 4/5/6: 4→1, 5→2, 6→3
  /// EXISTING LOGIC for other values: scaled 1-5 based on hits (6-10 range)
  double _calculateHitsScore(int hits) {
    // ✅ NEW: Special scoring for hits 4, 5, 6 (1-10 scale)
    if (hits == 4) {
      debugPrint(
        '🎯 BOHEN_REMA: hits=4 → hitsScore=2 (NEW LOGIC - 1-10 scale)',
      );
      return 2.0;
    }
    if (hits == 5) {
      debugPrint(
        '🎯 BOHEN_REMA: hits=5 → hitsScore=4 (NEW LOGIC - 1-10 scale)',
      );
      return 4.0;
    }
    if (hits == 6) {
      debugPrint(
        '🎯 BOHEN_REMA: hits=6 → hitsScore=6 (NEW LOGIC - 1-10 scale)',
      );
      return 6.0;
    }

    // ✅ EXISTING LOGIC for other hits values (0-3, 7-10+) - scaled to 1-10
    if (hits <= 0) return 0.0;
    if (hits < 4) return 2.0; // hits 1-3 → score 2 (was 1)
    if (hits >= 10) return 10.0; // hits 10+ → score 10 (was 5)
    // hits 7-9: interpolate between 6 and 10
    // Linear scale: 7→7, 8→8, 9→9
    final hitsScore = 6.0 + ((hits - 6) / 4.0) * 4.0; // 7→7, 8→8, 9→9
    debugPrint(
      '🎯 BOHEN_REMA: hits=$hits → hitsScore=${hitsScore.toStringAsFixed(2)} (EXISTING LOGIC - 1-10 scale)',
    );
    return hitsScore.clamp(2.0, 10.0);
  }

  /// Calculate timeScore for בוחן רמה (MODIFIED - accepts decimal seconds)
  /// Scale: 7 seconds or less → 5, 15 seconds or more → 1
  double _calculateTimeScore(double timeSeconds) {
    if (timeSeconds <= 0) return 0.0;
    if (timeSeconds <= 7) {
      debugPrint(
        '⏱️ BOHEN_REMA: time=${timeSeconds}s → timeScore=10 (EXISTING LOGIC - 1-10 scale)',
      );
      return 10.0;
    }
    if (timeSeconds >= 15) {
      debugPrint(
        '⏱️ BOHEN_REMA: time=${timeSeconds}s → timeScore=2 (EXISTING LOGIC - 1-10 scale)',
      );
      return 2.0;
    }
    // Linear interpolation between 7s (score 10) and 15s (score 2)
    final timeFactor = (timeSeconds - 7) / (15 - 7); // 0 at 7s, 1 at 15s
    final timeScore = 10.0 - (timeFactor * 8.0); // 10 at 7s, 2 at 15s
    debugPrint(
      '⏱️ BOHEN_REMA: time=${timeSeconds}s → timeScore=${timeScore.toStringAsFixed(2)} (EXISTING LOGIC - 1-10 scale)',
    );
    return timeScore.clamp(2.0, 10.0);
  }

  int _calculateLevelTestRating() {
    final hits = int.tryParse(_hitsController.text) ?? 0;
    final timeSeconds = double.tryParse(_timeSecondsController.text) ?? 0.0;

    // If both are zero, return 0 (no rating yet)
    if (hits == 0 && timeSeconds == 0) return 0;

    // Calculate separate scores
    final hitsScore = _calculateHitsScore(hits);
    final timeScore = _calculateTimeScore(timeSeconds);

    // ✅ NEW FORMULA: finalScore = 50% hitsScore + 50% timeScore
    final finalScore = (0.5 * hitsScore) + (0.5 * timeScore);

    // Debug log for verification
    debugPrint('');
    debugPrint('🔵🔵🔵 BOHEN_REMA FINAL CALCULATION (1-10 scale new)🔵🔵🔵');
    debugPrint('   hits=$hits → hitsScore=${hitsScore.toStringAsFixed(2)}');
    debugPrint(
      '   time=${timeSeconds}s → timeScore=${timeScore.toStringAsFixed(2)}',
    );
    debugPrint(
      '   finalScore = (0.5 × ${hitsScore.toStringAsFixed(2)}) + (0.5 × ${timeScore.toStringAsFixed(2)}) = ${finalScore.toStringAsFixed(2)}',
    );
    debugPrint('   rounded = ${finalScore.round().clamp(1, 10)}');
    debugPrint('🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵');
    debugPrint('');

    return finalScore.round().clamp(1, 10);
  }

  void _updateLevelTestRating() {
    setState(() {
      levelTestScore =
          _calculateLevelTestRating(); // ✅ NEW: Use levelTestScore instead of categories
      if (!_isFormLocked) {
        _hasUnsavedChanges = true;
        _scheduleAutosave();
      }
    });
  }

  void _markFormDirty() {
    if (!_isFormLocked && !_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  /// ✅ DEBOUNCED AUTOSAVE: Schedule autosave after 700ms of inactivity
  void _scheduleAutosave() {
    if (_isFormLocked) return; // Don't autosave locked forms

    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      debugPrint('🔄 AUTOSAVE: Timer triggered');
      _autosaveDraft();
    });
  }

  /// ✅ AUTOSAVE TO DRAFT: Save current state to draft document
  Future<void> _autosaveDraft() async {
    if (_isAutosaving || _isSaving || _isFormLocked) {
      debugPrint('⚠️ AUTOSAVE: Skipping (already saving or locked)');
      return;
    }

    // Don't autosave if no required details filled
    if (!hasRequiredDetails) {
      debugPrint('⚠️ AUTOSAVE: Skipping (required details not filled)');
      return;
    }

    setState(() => _isAutosaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        debugPrint('❌ AUTOSAVE: No user ID');
        return;
      }

      debugPrint('\n========== ✅ AUTOSAVE START ==========');

      // ✅ Create stable draft ID once per form session
      if (_stableDraftId == null) {
        // Use existing ID if editing, otherwise create new
        _stableDraftId =
            _existingScreeningId ??
            'eval_${uid}_${DateTime.now().millisecondsSinceEpoch}';
        _existingScreeningId = _stableDraftId;
        debugPrint('AUTOSAVE: Using evalId=$_stableDraftId');
      }

      // Build fields map (NEW STRUCTURE: multi-field categories)
      final Map<String, dynamic> fields = {};

      // ✅ בוחן רמה - simple 1-10 score
      if (levelTestScore > 0) {
        final Map<String, dynamic> meta = {
          'value': levelTestScore,
          'filledBy': uid,
          'filledAt': FieldValue.serverTimestamp(),
        };
        final hits = int.tryParse(_hitsController.text);
        final time = double.tryParse(_timeSecondsController.text);
        if (hits != null) meta['hits'] = hits;
        if (time != null) meta['timeSeconds'] = time;
        fields['בוחן רמה'] = meta;
      }

      // ✅ Multi-field categories (5 fields each)
      multiFieldCategories.forEach((categoryName, categoryFields) {
        // Only save if at least one field is filled
        if (categoryFields.values.any((v) => v > 0)) {
          final Map<String, dynamic> meta = {
            'fields': categoryFields, // Save all 5 field scores
            'average': _getCategoryAverage(
              categoryName,
            ), // Save computed average
            'filledBy': uid,
            'filledAt': FieldValue.serverTimestamp(),
          };
          fields[categoryName] = meta;
        }
      });

      // ✅ Check if document exists to preserve original creator
      final docRef = FirebaseFirestore.instance
          .collection('instructor_course_evaluations')
          .doc(_stableDraftId);

      final existingDoc = await docRef.get();
      final isNewDocument = !existingDoc.exists;

      final draftData = {
        'status': 'draft',
        'courseType': 'miunim',
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': uid, // ✅ Track last editor
        'updatedByName':
            currentUser?.name ??
            '', // ✅ Track last editor name (no Firestore fetch)
        'command': _selectedPikud ?? '',
        'brigade':
            _selectedHativa ?? '', // ✅ NEW: Save brigade dropdown selection
        'candidateName': _candidateNameController.text.trim(),
        'candidateNumber': _candidateNumber ?? 0,
        'title': _candidateNameController.text.trim(),
        'fields': fields,
        'finalWeightedScore': finalWeightedScore,
        'isSuitable': isSuitableForInstructorCourse,
        'module': 'instructor_course_selection',
        'type': 'instructor_course_feedback',
        // ✅ NEW: Save category notes (multi-field categories)
        'categoryNotes': {
          for (var category in multiFieldCategories.keys)
            category: _notesControllers[category]?.text.trim() ?? '',
        },
      };

      // ✅ Add creator fields ONLY for new documents (preserve original creator)
      if (isNewDocument) {
        draftData['createdAt'] = FieldValue.serverTimestamp();
        draftData['createdBy'] = uid;
        draftData['createdByUid'] = uid;
        draftData['createdByName'] =
            currentUser?.name ?? ''; // Use local name (no Firestore fetch)
        draftData['ownerUid'] = uid; // Set owner only for new documents
      }

      // ✅ Save to single collection: instructor_course_evaluations

      final draftDocPath = docRef.path;
      debugPrint(
        '🔵 MIUNIM_AUTOSAVE_WRITE: collection=instructor_course_evaluations',
      );
      debugPrint('🔵 MIUNIM_AUTOSAVE_WRITE: docPath=$draftDocPath');
      debugPrint('🔵 MIUNIM_AUTOSAVE_WRITE: evalId=$_stableDraftId');
      debugPrint(
        '🔵 MIUNIM_AUTOSAVE_WRITE: status=draft, isNewDocument=$isNewDocument',
      );
      await docRef.set(draftData, SetOptions(merge: true));
      debugPrint('✅ AUTOSAVE: Save complete');

      // Verify save
      final verifySnap = await docRef.get();
      if (!verifySnap.exists) {
        debugPrint('❌ AUTOSAVE: Document not found after save!');
        throw Exception('Draft not persisted');
      }

      final verifyData = verifySnap.data();
      final verifyChecksum =
          'fields=${verifyData?['fields']?.length ?? 0}, candidate=${verifyData?['candidateName']}';
      debugPrint('✅ AUTOSAVE: Verification PASSED');
      debugPrint('AUTOSAVE: Checksum=$verifyChecksum');
      debugPrint('========== ✅ AUTOSAVE END ==========\n');

      // ✅ START REAL-TIME LISTENER: Monitor concurrent edits by other admins/instructors
      final bool isFirstSave = _draftListener == null;
      if (isFirstSave && _stableDraftId != null) {
        _startListeningToDraft(_stableDraftId!);
      }

      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('\n========== ❌ AUTOSAVE ERROR ==========');
      debugPrint('AUTOSAVE_ERROR: $e');
      debugPrint('AUTOSAVE_ERROR_STACK: $stackTrace');
      debugPrint('========================================\n');
    } finally {
      if (mounted) {
        setState(() => _isAutosaving = false);
      }
    }
  }

  /// ✅ REAL-TIME SYNC: Start listening to draft changes by other admins/instructors
  void _startListeningToDraft(String draftId) {
    // Cancel previous listener if exists
    _draftListener?.cancel();

    debugPrint('🔄 REALTIME_INSTRUCTOR: Starting listener for evalId=$draftId');

    final docRef = FirebaseFirestore.instance
        .collection('instructor_course_evaluations')
        .doc(draftId);

    _draftListener = docRef.snapshots().listen(
      (snapshot) {
        if (!snapshot.exists || !mounted) {
          debugPrint(
            '⚠️ REALTIME_INSTRUCTOR: Snapshot does not exist or widget unmounted',
          );
          return;
        }

        final data = snapshot.data();
        if (data == null) {
          debugPrint('⚠️ REALTIME_INSTRUCTOR: Snapshot data is null');
          return;
        }

        // Check who updated
        final updatedByUid = data['updatedByUid'] as String?;
        final updatedByName = data['updatedByName'] as String?;
        final currentUid = FirebaseAuth.instance.currentUser?.uid;

        // Ignore our own updates
        if (updatedByUid == currentUid) {
          debugPrint('⏭️ REALTIME_INSTRUCTOR: Ignoring own update');
          return;
        }

        debugPrint('📥 REALTIME_INSTRUCTOR: Remote update detected!');
        debugPrint('   Updated by: $updatedByName (uid=$updatedByUid)');

        // Show notification when another instructor/admin edits
        if (updatedByName != null && updatedByName != _lastRemoteUpdateBy) {
          _lastRemoteUpdateBy = updatedByName;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$updatedByName עדכן/ה את המיון בזמן אמת'),
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
        debugPrint('❌ REALTIME_INSTRUCTOR: Listener error: $error');
      },
    );
  }

  /// ✅ REAL-TIME SYNC: Merge remote changes with local state
  /// SMART MERGE: Keeps non-empty/non-zero values from both local and remote
  void _mergeRemoteChanges(Map<String, dynamic> remoteData) {
    // Prevent recursion (merging while saving)
    if (_isLoadingRemoteChanges || _isAutosaving || _isSaving) {
      debugPrint(
        '⏸️ REALTIME_INSTRUCTOR: Skipping merge (already saving or loading)',
      );
      return;
    }

    _isLoadingRemoteChanges = true;

    try {
      debugPrint('🔄 REALTIME_INSTRUCTOR: Merging remote changes...');

      final remoteFields = remoteData['fields'] as Map<String, dynamic>?;
      if (remoteFields == null) {
        debugPrint('⚠️ REALTIME_INSTRUCTOR: No remote fields to merge');
        _isLoadingRemoteChanges = false;
        return;
      }

      setState(() {
        // Merge category scores - SMART MERGE for NEW multi-field structure
        remoteFields.forEach((categoryName, fieldData) {
          if (fieldData is Map<String, dynamic>) {
            // ✅ בוחן רמה - simple score (1-10)
            if (categoryName == 'בוחן רמה') {
              final remoteValue = (fieldData['value'] as num?)?.toInt() ?? 0;
              final localValue = levelTestScore;

              debugPrint(
                '   Category "$categoryName": local=$localValue remote=$remoteValue',
              );

              // SMART MERGE: Take non-zero value
              if (localValue == 0 && remoteValue > 0) {
                levelTestScore = remoteValue;
                debugPrint('     → Taking remote value');
              } else if (localValue > 0 && remoteValue == 0) {
                // Keep local
                debugPrint('     → Keeping local value');
              } else if (localValue > 0 &&
                  remoteValue > 0 &&
                  localValue != remoteValue) {
                // Both have values - keep local (user is actively editing)
                debugPrint('     → Both non-zero, keeping local');
              }
            }
            // ✅ Multi-field categories (5 fields each)
            else if (multiFieldCategories.containsKey(categoryName)) {
              final remoteFields = fieldData['fields'] as Map<String, dynamic>?;
              if (remoteFields != null) {
                final localCategoryFields = multiFieldCategories[categoryName]!;

                debugPrint(
                  '   Category "$categoryName": merging multi-field data',
                );

                remoteFields.forEach((fieldName, remoteValue) {
                  final remoteInt = (remoteValue as num?)?.toInt() ?? 0;
                  final localInt = localCategoryFields[fieldName] ?? 0;

                  debugPrint(
                    '     Field "$fieldName": local=$localInt remote=$remoteInt',
                  );

                  // SMART MERGE: Take non-zero value
                  if (localInt == 0 && remoteInt > 0) {
                    localCategoryFields[fieldName] = remoteInt;
                    debugPrint('       → Taking remote value');
                  } else if (localInt > 0 && remoteInt == 0) {
                    // Keep local
                    debugPrint('       → Keeping local value');
                  } else if (localInt > 0 &&
                      remoteInt > 0 &&
                      localInt != remoteInt) {
                    // Both have values - keep local (user is actively editing)
                    debugPrint('       → Both non-zero, keeping local');
                  }
                });
              }
            }
          }
        });

        // Merge text fields (only if local is empty)
        final remotePikud = remoteData['command'] as String?;
        if ((_selectedPikud == null || _selectedPikud!.isEmpty) &&
            remotePikud != null &&
            remotePikud.isNotEmpty) {
          _selectedPikud = remotePikud;
          debugPrint('   ✅ Merged command: $remotePikud');
        }

        final remoteBrigade = remoteData['brigade'] as String?;
        if ((_selectedHativa == null || _selectedHativa!.isEmpty) &&
            remoteBrigade != null &&
            remoteBrigade.isNotEmpty) {
          _selectedHativa = remoteBrigade;
          debugPrint('   ✅ Merged brigade: $remoteBrigade');
        }

        final remoteName = remoteData['candidateName'] as String?;
        if (_candidateNameController.text.isEmpty &&
            remoteName != null &&
            remoteName.isNotEmpty) {
          _candidateNameController.text = remoteName;
          debugPrint('   ✅ Merged candidateName: $remoteName');
        }

        final remoteNumber = remoteData['candidateNumber'] as num?;
        if (_candidateNumber == null && remoteNumber != null) {
          _candidateNumber = remoteNumber.toInt();
          debugPrint('   ✅ Merged candidateNumber: $_candidateNumber');
        }
      });

      debugPrint('✅ REALTIME_INSTRUCTOR: Merge complete');
    } catch (e) {
      debugPrint('❌ REALTIME_INSTRUCTOR: Merge failed: $e');
    } finally {
      _isLoadingRemoteChanges = false;
    }
  }

  static const Map<String, double> _categoryWeights = {
    'בוחן רמה': 0.15,
    'תרגיל הפתעה': 0.25,
    'הדרכת יבשים': 0.20,
    'הדרכה טובה': 0.20,
    'הדרכת מבנה': 0.20,
  };

  bool _isSaving = false;
  Timer? _autosaveTimer;
  bool _isAutosaving = false;
  String? _stableDraftId; // Stable draft document ID for this session

  // ✅ REAL-TIME SYNC: Listen to concurrent edits by other admins/instructors
  StreamSubscription<DocumentSnapshot>? _draftListener;
  bool _isLoadingRemoteChanges = false;
  String? _lastRemoteUpdateBy;

  /// Calculate average for a multi-field category (average of 5 fields)
  double _getCategoryAverage(String categoryName) {
    final fields = multiFieldCategories[categoryName];
    if (fields == null || fields.isEmpty) return 0.0;

    final filledFields = fields.values.where((v) => v > 0).toList();
    if (filledFields.isEmpty) return 0.0;

    final sum = filledFields.reduce((a, b) => a + b);
    return sum / filledFields.length;
  }

  double get finalWeightedScore {
    // Check if all categories have scores
    // בוחן רמה: must have score
    if (levelTestScore == 0) return 0.0;

    // Multi-field categories: must have at least one field filled
    for (final category in multiFieldCategories.keys) {
      final avg = _getCategoryAverage(category);
      if (avg == 0.0) return 0.0;
    }

    // Calculate weighted sum
    double weightedSum = 0.0;

    // Add בוחן רמה (simple score 1-10)
    weightedSum += levelTestScore * (_categoryWeights['בוחן רמה'] ?? 0.15);

    // Add multi-field categories (average of 5 fields, each 1-10)
    multiFieldCategories.forEach((categoryName, fields) {
      final avg = _getCategoryAverage(categoryName);
      final weight = _categoryWeights[categoryName] ?? 0.0;
      weightedSum += avg * weight;
    });

    return weightedSum;
  }

  // Suitable threshold: 7.0/10 (70%)
  bool get isSuitableForInstructorCourse => finalWeightedScore >= 7.0;

  bool get isFormValid {
    // בוחן רמה must have score
    if (levelTestScore == 0) return false;

    // Each multi-field category must have at least one field filled
    for (final fields in multiFieldCategories.values) {
      if (fields.values.every((v) => v == 0)) return false;
    }
    return true;
  }

  bool get hasRequiredDetails {
    final pikud = (_selectedPikud ?? '').trim();
    final name = _candidateNameController.text.trim();
    final number = _candidateNumber;

    // ✅ Brigade is required only for פיקוד צפון
    final brigadeValid =
        pikud != 'פיקוד צפון' ||
        (_selectedHativa != null && _selectedHativa!.isNotEmpty);

    return pikud.isNotEmpty &&
        brigadeValid &&
        name.isNotEmpty &&
        number != null;
  }

  // Check if draft exists
  bool get hasDraft =>
      _existingScreeningId != null && _existingScreeningId!.isNotEmpty;

  @override
  void dispose() {
    _draftListener?.cancel(); // ✅ Cancel real-time listener
    _autosaveTimer?.cancel();
    _hativaController.dispose();
    _candidateNameController.dispose();
    _hitsController.dispose();
    _timeSecondsController.dispose();
    // ✅ Dispose all notes controllers
    _notesControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // ✅ Initialize notes controllers for each multi-field category
    multiFieldCategories.forEach((category, _) {
      _notesControllers[category] = TextEditingController();
    });
    _existingScreeningId = widget.screeningId;
    if (_existingScreeningId != null && _existingScreeningId!.isNotEmpty) {
      _loadExistingScreening(_existingScreeningId!);
    } else {
      // ✅ New feedback: set creator name and UID to current user
      _originalCreatorName = currentUser?.name;
      _originalCreatorUid = FirebaseAuth.instance.currentUser?.uid;
    }
  }

  Future<void> _loadExistingScreening(String id) async {
    setState(() => _loadingExisting = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('instructor_course_evaluations')
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!snap.exists) {
        setState(() => _loadingExisting = false);
        return;
      }
      final data = snap.data() as Map<String, dynamic>;
      final cmd = (data['command'] as String?) ?? '';
      final brigade = (data['brigade'] as String?) ?? '';
      final candName = (data['candidateName'] as String?) ?? '';
      final candNumber = (data['candidateNumber'] as num?)?.toInt();

      // ✅ Load original creator's name (use stored name, no extra fetch)
      final createdByName = data['createdByName'] as String?;
      final ownerUid =
          data['ownerUid'] as String? ??
          data['createdByUid'] as String?; // ✅ Load creator UID for permissions
      String? originalName = createdByName;

      setState(() {
        _selectedPikud = cmd.isNotEmpty ? cmd : _selectedPikud;
        _selectedHativa = brigade.isNotEmpty
            ? brigade
            : null; // ✅ Load brigade dropdown
        _candidateNameController.text = candName;
        _candidateNumber = candNumber;
        // ✅ FIX: Preserve existing draft ID to prevent creating duplicate with current user's UID
        _stableDraftId = id;
        // ✅ Save original creator name and UID
        _originalCreatorName = originalName;
        _originalCreatorUid =
            ownerUid; // ✅ Save creator UID for finalize permission check
      });

      // ✅ Load fields: NEW multi-field structure
      final fields = (data['fields'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final entry in fields.entries) {
        final name = entry.key;
        final meta = (entry.value as Map?)?.cast<String, dynamic>() ?? {};

        // ✅ בוחן רמה - simple score (1-10)
        if (name == 'בוחן רמה') {
          final v = meta['value'];
          final intVal = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
          setState(() {
            levelTestScore = intVal;
          });

          final hits = meta['hits'];
          final time = meta['timeSeconds'];
          if (hits != null) _hitsController.text = hits.toString();
          if (time != null) _timeSecondsController.text = time.toString();
        }
        // ✅ Multi-field categories (5 fields each)
        else if (multiFieldCategories.containsKey(name)) {
          final categoryFields = meta['fields'] as Map<String, dynamic>?;
          if (categoryFields != null) {
            setState(() {
              categoryFields.forEach((fieldName, value) {
                final intVal = (value is num)
                    ? value.toInt()
                    : int.tryParse('$value') ?? 0;
                if (multiFieldCategories[name]!.containsKey(fieldName)) {
                  multiFieldCategories[name]![fieldName] = intVal;
                }
              });
            });
          }
        }
      }
      _updateLevelTestRating();

      // ✅ NEW: Load category notes if available
      final categoryNotes = data['categoryNotes'] as Map<String, dynamic>?;
      if (categoryNotes != null) {
        categoryNotes.forEach((category, note) {
          final controller = _notesControllers[category];
          if (controller != null && note is String) {
            controller.text = note;
          }
        });
      }

      // ✅ START REAL-TIME LISTENER: Monitor concurrent edits by other admins/instructors
      _startListeningToDraft(id);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  // ✅ AUTOSAVE: Old temporary save method removed - autosave handles drafts automatically

  /// ✅ FINALIZE: Convert draft to final in same collection
  Future<void> finalizeInstructorCourseFeedback() async {
    if (!hasRequiredDetails) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש למלא את כל פרטי המיון לפני שמירה')),
      );
      return;
    }
    if (!isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להשלים את כל הרובריקות לפני סיום')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('נדרשת התחברות');
      }

      debugPrint('\n========== FINALIZE: INSTRUCTOR COURSE ==========');

      // ✅ STEP 1: Force immediate autosave if dirty
      if (_hasUnsavedChanges) {
        debugPrint('FINALIZE: Forcing immediate save of pending changes');
        await _autosaveDraft();
      }

      // Ensure we have a draft ID
      if (_stableDraftId == null) {
        debugPrint('❌ FINALIZE: No draft ID found');
        throw Exception('לא נמצא מזהה משוב');
      }

      final draftId = _stableDraftId!;
      debugPrint('FINALIZE_START draftId=$draftId');

      // ✅ PERMISSION CHECK: Only creator or admin can finalize feedback
      // This check uses cached _originalCreatorUid (loaded during initState) - NO extra Firestore read
      final isAdmin = currentUser?.role == 'Admin';
      final isCreator = _originalCreatorUid == uid;

      if (!isAdmin && !isCreator) {
        debugPrint(
          '❌ PERMISSION DENIED: User $uid cannot finalize evaluation created by $_originalCreatorUid',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('רק היוצר של המשוב או אדמין יכולים לסיים משוב'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        setState(() => _isSaving = false);
        return; // ❌ Block finalize for collaborators
      }
      debugPrint(
        '✅ PERMISSION GRANTED: User $uid (${isAdmin ? "Admin" : "Creator"}) can finalize evaluation',
      );

      // Build final feedback data (NEW STRUCTURE: multi-field categories)
      final Map<String, dynamic> fields = {};

      // ✅ בוחן רמה - simple 1-10 score
      if (levelTestScore > 0) {
        final Map<String, dynamic> meta = {
          'value': levelTestScore,
          'filledBy': uid,
          'filledAt': FieldValue.serverTimestamp(),
        };
        final hits = int.tryParse(_hitsController.text);
        final time = double.tryParse(_timeSecondsController.text);
        if (hits != null) meta['hits'] = hits;
        if (time != null) meta['timeSeconds'] = time;
        fields['בוחן רמה'] = meta;
      }

      // ✅ Multi-field categories (5 fields each)
      multiFieldCategories.forEach((categoryName, categoryFields) {
        // Only save if at least one field is filled
        if (categoryFields.values.any((v) => v > 0)) {
          final Map<String, dynamic> meta = {
            'fields': categoryFields, // Save all 5 field scores
            'average': _getCategoryAverage(
              categoryName,
            ), // Save computed average
            'filledBy': uid,
            'filledAt': FieldValue.serverTimestamp(),
          };
          fields[categoryName] = meta;
        }
      });

      // ✅ STEP 2: Atomic commit - update status to 'final' with isSuitable flag
      final docRef = FirebaseFirestore.instance
          .collection('instructor_course_evaluations')
          .doc(draftId);

      final finalDocPath = docRef.path;
      debugPrint(
        '🟢 MIUNIM_FINALIZE_WRITE: collection=instructor_course_evaluations',
      );
      debugPrint('🟢 MIUNIM_FINALIZE_WRITE: docPath=$finalDocPath');
      debugPrint('🟢 MIUNIM_FINALIZE_WRITE: evalId=$draftId');
      debugPrint(
        '🟢 MIUNIM_FINALIZE_WRITE: status=final, isSuitable=$isSuitableForInstructorCourse',
      );

      try {
        await docRef.update({
          'status': 'final',
          // ✅ DON'T update ownerUid - preserve original creator!
          'finalizedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid, // ✅ Track last editor
          'updatedByName':
              currentUser?.name ??
              '', // ✅ Track last editor name (no Firestore fetch)
          'fields': fields,
          'finalWeightedScore': finalWeightedScore,
          'isSuitable': isSuitableForInstructorCourse,
          'command': _selectedPikud ?? '',
          'brigade':
              _selectedHativa ?? '', // ✅ NEW: Save brigade dropdown selection
          'candidateName': _candidateNameController.text.trim(),
          'candidateNumber': _candidateNumber ?? 0,
          'title': _candidateNameController.text.trim(),
          // ✅ NEW: Save category notes (multi-field categories)
          'categoryNotes': {
            for (var category in multiFieldCategories.keys)
              category: _notesControllers[category]?.text.trim() ?? '',
          },
          // ✅ DON'T update createdBy* - preserve original creator!
        });

        debugPrint('✅ MIUNIM_SAVE_OK: evalId=$draftId, docPath=$finalDocPath');
        debugPrint(
          '✅ MIUNIM_SAVE_OK: status=final, isSuitable=$isSuitableForInstructorCourse',
        );
        debugPrint('=================================================\n');
      } catch (e) {
        debugPrint('❌ MIUNIM_FINALIZE_ERROR: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירת המשוב: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return; // Do NOT navigate away on error
      }

      if (!mounted) return;

      // Clear unsaved changes and lock form
      setState(() {
        _hasUnsavedChanges = false;
        _isFormLocked = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('המשוב נסגר והועבר למשובים סופיים')),
      );

      // Navigate back after short delay
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Finalize error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בסיום המשוב: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// ✅ NEW: Build multi-field category row (5 fields: ידע, עמידה מול קהל, מתודיקה, איכות הדרכה, איכות הדגמה)
  Widget _buildMultiFieldCategoryRow(String categoryName) {
    final fields = multiFieldCategories[categoryName]!;
    final average = _getCategoryAverage(categoryName);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Card(
        color: Colors.white,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category header with average
              Row(
                children: [
                  Text(
                    categoryName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (average > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: average >= 7.2 ? Colors.green : Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'ממוצע: ${average.toStringAsFixed(1)}/10',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // 5 fields, each with 1-10 scoring
              for (final fieldName in fields.keys)
                Builder(
                  builder: (context) {
                    final currentScore = fields[fieldName] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fieldName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (currentScore > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$currentScore',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 1-10 buttons
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.spaceEvenly,
                            children: List.generate(10, (index) {
                              final score = index + 1;
                              final isSelected = currentScore == score;
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected
                                      ? Colors.blueAccent
                                      : Colors.grey.shade300,
                                  foregroundColor: isSelected
                                      ? Colors.white
                                      : Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  minimumSize: const Size(40, 40),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: isSelected ? 4 : 1,
                                ),
                                onPressed: _isFormLocked
                                    ? null
                                    : () {
                                        setState(() {
                                          multiFieldCategories[categoryName]![fieldName] =
                                              score;
                                          _markFormDirty();
                                        });
                                        _scheduleAutosave();
                                      },
                                child: Text(
                                  score.toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    );
                  },
                ), // Builder closes, for loop continues
              const SizedBox(height: 8),
              // Notes field for this category
              TextField(
                controller: _notesControllers[categoryName],
                enabled: !_isFormLocked,
                decoration: const InputDecoration(
                  labelText: 'הערות',
                  hintText: 'הוסף הערות לקטגוריה זו...',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 2,
                onChanged: (_) {
                  _markFormDirty();
                  _scheduleAutosave();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelTestRow() {
    final currentRating =
        levelTestScore; // ✅ NEW: Use levelTestScore (1-10 scale)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Card(
        color: Colors.white,
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.black87),
                  const SizedBox(width: 8),
                  const Text(
                    'בוחן רמה',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (currentRating > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            currentRating >=
                                7.2 // ✅ NEW: 72% of 10 = 7.2
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'ציון: $currentRating/10', // ✅ NEW: Show /10
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hitsController,
                      enabled: !_isFormLocked,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'מספר פגיעות',
                        hintText: 'הזן מספר',
                        prefixIcon: Icon(Icons.my_location),
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                      ),
                      onChanged: (_) => _updateLevelTestRating(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _timeSecondsController,
                      enabled: !_isFormLocked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'זמן (שניות)',
                        hintText: 'הזן שניות (למשל: 9.5)',
                        prefixIcon: Icon(Icons.timer),
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                      ),
                      onChanged: (_) => _updateLevelTestRating(),
                    ),
                  ),
                ],
              ),
              if (currentRating > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        currentRating >=
                            7.2 // ✅ NEW: 72% of 10 = 7.2
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: currentRating >= 7.2
                          ? Colors.green
                          : Colors.orange,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        currentRating >= 7.2 ? Icons.check_circle : Icons.info,
                        color: currentRating >= 7.2
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currentRating >= 7.2 ? 'עובר' : 'לא עובר',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: currentRating >= 7.2
                              ? Colors.green.shade900
                              : Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'חישוב אוטומטי: נתוני פגיעות/זמן מעודכנים',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 12),
              // ✅ NEW: Notes field for בוחן רמה
              TextField(
                controller: _notesControllers['בוחן רמה'],
                enabled: !_isFormLocked,
                decoration: const InputDecoration(
                  labelText: 'הערות',
                  hintText: 'הוסף הערות לבוחן רמה...',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 2,
                onChanged: (_) {
                  _markFormDirty();
                  _scheduleAutosave();
                },
              ),
            ],
          ),
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
          title: const Text('מיון לקורס מדריכים'),
          leading: StandardBackButton(
            onPressed: () async {
              // Only show dialog if there are actual unsaved changes
              if (_hasUnsavedChanges && !_isFormLocked) {
                final shouldLeave = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('יציאה ללא שמירה'),
                    content: const Text(
                      'יש שינויים שלא נשמרו. האם אתה בטוח שברצונך לצאת?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('הישאר'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('צא בכל זאת'),
                      ),
                    ],
                  ),
                );
                if (shouldLeave != true) return;
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            tooltip: 'חזרה',
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isFormLocked) ...[
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    margin: const EdgeInsets.only(bottom: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'המשוב נסגר - לא ניתן לערוך',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_loadingExisting) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12.0),
                    child: LinearProgressIndicator(),
                  ),
                ],
                Card(
                  color: Colors.blueGrey.shade700,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'פרטי המיון',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPikud,
                          decoration: const InputDecoration(
                            labelText: 'פיקוד',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          dropdownColor: Colors.white,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                          items: _pikudOptions.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: _isFormLocked
                              ? null
                              : (String? newValue) {
                                  setState(() {
                                    _selectedPikud = newValue;
                                    _markFormDirty();
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        // ✅ NEW: Brigade dropdown (conditional - only for פיקוד צפון)
                        if (_selectedPikud == 'פיקוד צפון') ...[
                          DropdownButtonFormField<String>(
                            initialValue: _selectedHativa,
                            decoration: const InputDecoration(
                              labelText: 'חטיבה',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            dropdownColor: Colors.white,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                            ),
                            items: _hativaOptions.map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: _isFormLocked
                                ? null
                                : (String? newValue) {
                                    setState(() {
                                      _selectedHativa = newValue;
                                      _markFormDirty();
                                    });
                                  },
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _candidateNameController,
                          enabled: !_isFormLocked,
                          decoration: const InputDecoration(
                            labelText: 'שם מועמד',
                          ),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                          onChanged: (_) {
                            _markFormDirty();
                            _scheduleAutosave(); // ✅ Auto-save on candidate name change
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _candidateNumber,
                          decoration: const InputDecoration(
                            labelText: 'מספר מועמד (1-100)',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          dropdownColor: Colors.white,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                          items: List.generate(100, (index) => index + 1).map((
                            int value,
                          ) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text(value.toString()),
                            );
                          }).toList(),
                          onChanged: _isFormLocked
                              ? null
                              : (int? newValue) {
                                  setState(() {
                                    _candidateNumber = newValue;
                                    _markFormDirty();
                                  });
                                  _scheduleAutosave(); // ✅ Auto-save on candidate number change
                                },
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'שם המדריך הממשב',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _originalCreatorName ??
                                    currentUser?.name ??
                                    'לא ידוע',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'דרג את המועמד בכל קטגוריה (1-10):', // ✅ NEW: 1-10 scale
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // ✅ בוחן רמה - shown separately with special UI
                _buildLevelTestRow(),
                const SizedBox(height: 16),
                // ✅ Multi-field categories (5 fields each)
                ...multiFieldCategories.keys.map(
                  (category) => _buildMultiFieldCategoryRow(category),
                ),
                const SizedBox(height: 24),
                const Divider(),
                Card(
                  elevation: 8,
                  color: isSuitableForInstructorCourse
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSuitableForInstructorCourse
                                  ? Icons.check_circle
                                  : Icons.info_outline,
                              color: Colors.white,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'ציון סופי משוקלל',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          finalWeightedScore.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'מתוך 10.0',
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSuitableForInstructorCourse
                                    ? Icons.thumb_up
                                    : Icons.priority_high,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isSuitableForInstructorCourse
                                    ? 'מתאים לקורס מדריכים'
                                    : 'לא מתאים לקורס מדריכים',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'הקביעה אוטומטית: ${isSuitableForInstructorCourse ? "ציון מעל 7.0" : "ציון מתחת 7.0"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // ✅ AUTOSAVE INFO: Show autosave status to user
                if (_isAutosaving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'שומר אוטומטית...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                else if (!_hasUnsavedChanges && _stableDraftId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.check_circle, size: 16, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'השינויים נשמרו',
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: (_isSaving || !isFormValid || _isFormLocked)
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
                            if (confirmed == true) {
                              finalizeInstructorCourseFeedback();
                            }
                          },
                    icon: const Icon(Icons.done_all),
                    label: const Text(
                      'סיים משוב',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
