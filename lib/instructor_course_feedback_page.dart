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

  final TextEditingController _hativaController = TextEditingController();
  final TextEditingController _candidateNameController =
      TextEditingController();
  int? _candidateNumber;

  final TextEditingController _hitsController = TextEditingController();
  final TextEditingController _timeSecondsController = TextEditingController();

  final Map<String, int> categories = {
    'בוחן רמה': 0,
    'הדרכה טובה': 0,
    'הדרכת מבנה': 0,
    'יבשים': 0,
    'תרגיל הפתעה': 0,
  };

  /// Calculate hitsScore for בוחן רמה
  /// NEW LOGIC for hits 4/5/6: 4→1, 5→2, 6→3
  /// EXISTING LOGIC for other values: scaled 1-5 based on hits (6-10 range)
  double _calculateHitsScore(int hits) {
    // ✅ NEW: Special scoring for hits 4, 5, 6
    if (hits == 4) {
      debugPrint('🎯 BOHEN_REMA: hits=4 → hitsScore=1 (NEW LOGIC)');
      return 1.0;
    }
    if (hits == 5) {
      debugPrint('🎯 BOHEN_REMA: hits=5 → hitsScore=2 (NEW LOGIC)');
      return 2.0;
    }
    if (hits == 6) {
      debugPrint('🎯 BOHEN_REMA: hits=6 → hitsScore=3 (NEW LOGIC)');
      return 3.0;
    }

    // ✅ EXISTING LOGIC for other hits values (0-3, 7-10+)
    if (hits <= 0) return 0.0;
    if (hits < 4) return 1.0; // hits 1-3 → score 1
    if (hits >= 10) return 5.0; // hits 10+ → score 5
    // hits 7-9: interpolate between 3.5 and 5
    // Linear scale: 7→4, 8→4.5, 9→5 (approx)
    final hitsScore = 3.0 + ((hits - 6) / 4.0) * 2.0; // 7→3.5, 8→4, 9→4.5
    debugPrint(
      '🎯 BOHEN_REMA: hits=$hits → hitsScore=${hitsScore.toStringAsFixed(2)} (EXISTING LOGIC)',
    );
    return hitsScore.clamp(1.0, 5.0);
  }

  /// Calculate timeScore for בוחן רמה (MODIFIED - accepts decimal seconds)
  /// Scale: 7 seconds or less → 5, 15 seconds or more → 1
  double _calculateTimeScore(double timeSeconds) {
    if (timeSeconds <= 0) return 0.0;
    if (timeSeconds <= 7) {
      debugPrint(
        '⏱️ BOHEN_REMA: time=${timeSeconds}s → timeScore=5 (EXISTING LOGIC)',
      );
      return 5.0;
    }
    if (timeSeconds >= 15) {
      debugPrint(
        '⏱️ BOHEN_REMA: time=${timeSeconds}s → timeScore=1 (EXISTING LOGIC)',
      );
      return 1.0;
    }
    // Linear interpolation between 7s (score 5) and 15s (score 1)
    final timeFactor = (timeSeconds - 7) / (15 - 7); // 0 at 7s, 1 at 15s
    final timeScore = 5.0 - (timeFactor * 4.0); // 5 at 7s, 1 at 15s
    debugPrint(
      '⏱️ BOHEN_REMA: time=${timeSeconds}s → timeScore=${timeScore.toStringAsFixed(2)} (EXISTING LOGIC)',
    );
    return timeScore.clamp(1.0, 5.0);
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
    debugPrint('🔵🔵🔵 BOHEN_REMA FINAL CALCULATION 🔵🔵🔵');
    debugPrint('   hits=$hits → hitsScore=${hitsScore.toStringAsFixed(2)}');
    debugPrint(
      '   time=${timeSeconds}s → timeScore=${timeScore.toStringAsFixed(2)}',
    );
    debugPrint(
      '   finalScore = (0.5 × ${hitsScore.toStringAsFixed(2)}) + (0.5 × ${timeScore.toStringAsFixed(2)}) = ${finalScore.toStringAsFixed(2)}',
    );
    debugPrint('   rounded = ${finalScore.round().clamp(1, 5)}');
    debugPrint('🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵');
    debugPrint('');

    return finalScore.round().clamp(1, 5);
  }

  void _updateLevelTestRating() {
    setState(() {
      categories['בוחן רמה'] = _calculateLevelTestRating();
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

      // Build fields map
      final Map<String, dynamic> fields = {};
      categories.forEach((name, score) {
        if (score > 0) {
          final Map<String, dynamic> meta = {
            'value': score,
            'filledBy': uid,
            'filledAt': FieldValue.serverTimestamp(),
          };
          if (name == 'בוחן רמה') {
            final hits = int.tryParse(_hitsController.text);
            final time = double.tryParse(_timeSecondsController.text);
            if (hits != null) meta['hits'] = hits;
            if (time != null) meta['timeSeconds'] = time;
          }
          fields[name] = meta;
        }
      });

      // Resolve instructor's Hebrew full name from Firestore
      String resolvedCreatorName =
          FirebaseAuth.instance.currentUser?.email ?? '';
      String resolvedUpdaterName = resolvedCreatorName;
      if (uid.isNotEmpty) {
        resolvedCreatorName = await resolveUserHebrewName(uid);
        resolvedUpdaterName = resolvedCreatorName;
      }

      final draftData = {
        'status': 'draft',
        'ownerUid': uid, // Required for rules and queries
        'courseType': 'miunim',
        'createdAt': _existingScreeningId == _stableDraftId
            ? FieldValue.serverTimestamp()
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'createdByUid': uid,
        'createdByName': resolvedCreatorName,
        'updatedByUid': uid, // ✅ Track last editor
        'updatedByName': resolvedUpdaterName, // ✅ Track last editor name
        'command': _selectedPikud ?? '',
        'brigade': _hativaController.text.trim(),
        'candidateName': _candidateNameController.text.trim(),
        'candidateNumber': _candidateNumber ?? 0,
        'title': _candidateNameController.text.trim(),
        'fields': fields,
        'finalWeightedScore': finalWeightedScore,
        'isSuitable': isSuitableForInstructorCourse,
        'module': 'instructor_course_selection',
        'type': 'instructor_course_feedback',
      };
      // Remove null createdAt if this is an update
      if (draftData['createdAt'] == null) {
        draftData.remove('createdAt');
      }

      // ✅ Save to single collection: instructor_course_evaluations
      final docRef = FirebaseFirestore.instance
          .collection('instructor_course_evaluations')
          .doc(_stableDraftId);

      final draftDocPath = docRef.path;
      debugPrint(
        '🔵 MIUNIM_AUTOSAVE_WRITE: collection=instructor_course_evaluations',
      );
      debugPrint('🔵 MIUNIM_AUTOSAVE_WRITE: docPath=$draftDocPath');
      debugPrint('🔵 MIUNIM_AUTOSAVE_WRITE: evalId=$_stableDraftId');
      debugPrint('🔵 MIUNIM_AUTOSAVE_WRITE: status=draft, ownerUid=$uid');
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

  static const Map<String, double> _categoryWeights = {
    'בוחן רמה': 0.15,
    'תרגיל הפתעה': 0.25,
    'יבשים': 0.20,
    'הדרכה טובה': 0.20,
    'הדרכת מבנה': 0.20,
  };

  bool _isSaving = false;
  Timer? _autosaveTimer;
  bool _isAutosaving = false;
  String? _stableDraftId; // Stable draft document ID for this session

  double get finalWeightedScore {
    for (final category in _categoryWeights.keys) {
      final score = categories[category] ?? 0;
      if (score == 0) return 0.0;
    }
    double weightedSum = 0.0;
    _categoryWeights.forEach((category, weight) {
      final score = categories[category] ?? 0;
      weightedSum += score * weight;
    });
    return weightedSum;
  }

  bool get isSuitableForInstructorCourse => finalWeightedScore >= 3.6;
  bool get isFormValid => categories.values.every((score) => score > 0);

  bool get hasRequiredDetails {
    final pikud = (_selectedPikud ?? '').trim();
    final hativa = _hativaController.text.trim();
    final name = _candidateNameController.text.trim();
    final number = _candidateNumber;
    return pikud.isNotEmpty &&
        hativa.isNotEmpty &&
        name.isNotEmpty &&
        number != null;
  }

  // Check if draft exists
  bool get hasDraft =>
      _existingScreeningId != null && _existingScreeningId!.isNotEmpty;

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _hativaController.dispose();
    _candidateNameController.dispose();
    _hitsController.dispose();
    _timeSecondsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _existingScreeningId = widget.screeningId;
    if (_existingScreeningId != null && _existingScreeningId!.isNotEmpty) {
      _loadExistingScreening(_existingScreeningId!);
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
      setState(() {
        _selectedPikud = cmd.isNotEmpty ? cmd : _selectedPikud;
        _hativaController.text = brigade;
        _candidateNameController.text = candName;
        _candidateNumber = candNumber;
      });
      final fields = (data['fields'] as Map?)?.cast<String, dynamic>() ?? {};
      final Map<String, int> newCats = Map<String, int>.from(categories);
      for (final entry in fields.entries) {
        final name = entry.key;
        final meta = (entry.value as Map?)?.cast<String, dynamic>() ?? {};
        final v = meta['value'];
        final intVal = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
        if (newCats.containsKey(name)) newCats[name] = intVal;
        if (name == 'בוחן רמה') {
          final hits = meta['hits'];
          final time = meta['timeSeconds'];
          if (hits != null) _hitsController.text = hits.toString();
          if (time != null) _timeSecondsController.text = time.toString();
        }
      }
      setState(() {
        newCats.forEach((k, v) => categories[k] = v);
      });
      _updateLevelTestRating();
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

      // Build final feedback data
      final Map<String, dynamic> fields = {};
      categories.forEach((name, score) {
        if (score > 0) {
          final Map<String, dynamic> meta = {
            'value': score,
            'filledBy': uid,
            'filledAt': FieldValue.serverTimestamp(),
          };
          if (name == 'בוחן רמה') {
            final hits = int.tryParse(_hitsController.text);
            final time = double.tryParse(_timeSecondsController.text);
            if (hits != null) meta['hits'] = hits;
            if (time != null) meta['timeSeconds'] = time;
          }
          fields[name] = meta;
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
        '🟢 MIUNIM_FINALIZE_WRITE: status=final, isSuitable=$isSuitableForInstructorCourse, ownerUid=$uid',
      );

      // Resolve instructor's Hebrew full name from Firestore
      String resolvedCreatorName =
          FirebaseAuth.instance.currentUser?.email ?? '';
      String resolvedUpdaterName = resolvedCreatorName;
      if (uid.isNotEmpty) {
        resolvedCreatorName = await resolveUserHebrewName(uid);
        resolvedUpdaterName = resolvedCreatorName;
      }

      try {
        await docRef.update({
          'status': 'final',
          'ownerUid': uid, // Ensure ownerUid is set
          'finalizedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid, // ✅ Track last editor
          'updatedByName': resolvedUpdaterName, // ✅ Track last editor name
          'fields': fields,
          'finalWeightedScore': finalWeightedScore,
          'isSuitable': isSuitableForInstructorCourse,
          'command': _selectedPikud ?? '',
          'brigade': _hativaController.text.trim(),
          'candidateName': _candidateNameController.text.trim(),
          'candidateNumber': _candidateNumber ?? 0,
          'title': _candidateNameController.text.trim(),
          'createdByUid': uid,
          'createdByName': resolvedCreatorName,
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

  Widget _buildCategoryRow(String category) {
    if (category == 'בוחן רמה') return _buildLevelTestRow();
    final currentScore = categories[category] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            category,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceEvenly,
            children: [1, 2, 3, 4, 5].map((score) {
              final isSelected = currentScore == score;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected
                          ? Colors.blueAccent
                          : Colors.grey.shade300,
                      foregroundColor: isSelected ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: isSelected ? 4 : 1,
                    ),
                    onPressed: _isFormLocked
                        ? null
                        : () {
                            setState(() {
                              categories[category] = score;
                              _markFormDirty();
                            });
                            _scheduleAutosave();
                          },
                    child: Text(
                      score.toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (score == 1 || score == 5) ...[
                    const SizedBox(height: 4),
                    Text(
                      score == 1 ? 'נמוך ביותר' : 'גבוה ביותר',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelTestRow() {
    final currentRating = categories['בוחן רמה'] ?? 0;
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
                        color: currentRating >= 4
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'ציון: $currentRating',
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
                    color: currentRating >= 4
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: currentRating >= 4 ? Colors.green : Colors.orange,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        currentRating >= 4 ? Icons.check_circle : Icons.info,
                        color: currentRating >= 4
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currentRating >= 4 ? 'עובר' : 'לא עובר',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: currentRating >= 4
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
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
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
                        TextField(
                          controller: _hativaController,
                          enabled: !_isFormLocked,
                          decoration: const InputDecoration(labelText: 'חטיבה'),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                          onChanged: (_) => _markFormDirty(),
                        ),
                        const SizedBox(height: 12),
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
                          onChanged: (_) => _markFormDirty(),
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
                                currentUser?.name ?? 'לא ידוע',
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
                  'דרג את המועמד בכל קטגוריה (1-5):',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ...categories.keys.map(
                  (category) => _buildCategoryRow(category),
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
                          'מתוך 5.0',
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
                          'הקביעה אוטומטית: ${isSuitableForInstructorCourse ? "ציון מעל 3.6" : "ציון מתחת 3.6"}',
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
                const SizedBox(height: 32),
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
                        : finalizeInstructorCourseFeedback,
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
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
