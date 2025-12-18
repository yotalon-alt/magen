import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';

class InstructorCourseFeedbackPage extends StatefulWidget {
  const InstructorCourseFeedbackPage({super.key});

  @override
  State<InstructorCourseFeedbackPage> createState() =>
      _InstructorCourseFeedbackPageState();
}

class _InstructorCourseFeedbackPageState
    extends State<InstructorCourseFeedbackPage> {
  // Fixed fields
  String? _selectedPikud;
  final List<String> _pikudOptions = ['פיקוד צפון', 'פיקוד מרכז', 'פיקוד דרום'];

  final TextEditingController _hativaController = TextEditingController();
  final TextEditingController _candidateNameController =
      TextEditingController();
  int? _candidateNumber;

  // Level test specific fields
  final TextEditingController _hitsController = TextEditingController();
  final TextEditingController _timeSecondsController = TextEditingController();

  // Categories with scores (1-5)
  final Map<String, int> categories = {
    'בוחן רמה': 0,
    'הדרכה טובה': 0,
    'הדרכת מבנה': 0,
    'יבשים': 0,
    'תרגיל הפתעה': 0,
  };

  // Calculate rating for level test based on hits and time
  // Uses linear interpolation for precise scoring between extremes
  int _calculateLevelTestRating() {
    final hits = int.tryParse(_hitsController.text) ?? 0;
    final timeSeconds = int.tryParse(_timeSecondsController.text) ?? 0;

    // No input = no score
    if (hits == 0 && timeSeconds == 0) return 0;

    // Auto-fail conditions
    if (hits < 6) {
      return 1; // Less than 6 hits = always fail
    }
    if (timeSeconds > 15 && hits < 8) {
      return 1; // Over 15 sec with <8 hits = fail
    }

    // Perfect score: 7 seconds, 10 hits
    if (timeSeconds <= 7 && hits >= 10) return 5;

    // Worst passing score: 15 seconds, 6 hits (barely passing)
    if (timeSeconds >= 15 || hits <= 6) return 1;

    // Linear interpolation between extremes
    // Time factor: 7 sec (best) to 15 sec (worst) = 0 to 1
    double timeFactor = (timeSeconds - 7) / (15 - 7); // 0 (best) to 1 (worst)
    timeFactor = timeFactor.clamp(0.0, 1.0);

    // Hits factor: 10 hits (best) to 6 hits (worst) = 0 to 1
    double hitsFactor = (10 - hits) / (10 - 6); // 0 (best) to 1 (worst)
    hitsFactor = hitsFactor.clamp(0.0, 1.0);

    // Combined factor (average of both factors)
    double combinedFactor = (timeFactor + hitsFactor) / 2;

    // Convert to score: 0 factor = 5, 1 factor = 1
    double rawScore = 5 - (combinedFactor * 4); // 5 down to 1

    // Round to nearest integer and ensure within bounds
    int finalScore = rawScore.round().clamp(1, 5);

    return finalScore;
  }

  // Update level test rating when hits or time changes
  void _updateLevelTestRating() {
    setState(() {
      categories['בוחן רמה'] = _calculateLevelTestRating();
    });
  }

  // Weights for weighted average calculation
  static const Map<String, double> _categoryWeights = {
    'בוחן רמה': 0.15, // levelTest = 15%
    'תרגיל הפתעה': 0.25, // surpriseExercise = 25%
    'יבשים': 0.20, // dryStructure = 20%
    'הדרכה טובה': 0.20, // goodInstruction = 20%
    'הדרכת מבנה': 0.20, // otherComponent = 20%
  };

  // Saving state
  bool _isSaving = false;

  // Calculate weighted final score (1-5)
  // This is a weighted average where each component (1-5) is multiplied by its weight
  // Result is always between 1-5 (not a sum, not percentage)
  double get finalWeightedScore {
    // Check if all categories have scores
    bool allScored = true;
    for (final category in _categoryWeights.keys) {
      final score = categories[category] ?? 0;
      if (score == 0) {
        allScored = false;
        break;
      }
    }

    // Return 0 if not all categories are scored
    if (!allScored) return 0.0;

    // Calculate weighted average: sum of (score × weight)
    // Since weights sum to 1.0 (100%), the result is naturally between 1-5
    double weightedSum = 0.0;

    _categoryWeights.forEach((category, weight) {
      final score = categories[category] ?? 0;
      weightedSum += score * weight;
    });

    return weightedSum;
  }

  // Determine if candidate is suitable for instructor course
  bool get isSuitableForInstructorCourse {
    return finalWeightedScore >= 3.6;
  }

  // Calculate average score in real-time (kept for compatibility)
  double get averageScore {
    final scores = categories.values.where((score) => score > 0).toList();
    if (scores.isEmpty) return 0.0;
    final sum = scores.reduce((a, b) => a + b);
    return sum / scores.length;
  }

  // Validate all categories are scored
  bool get isFormValid {
    return categories.values.every((score) => score > 0);
  }

  @override
  void dispose() {
    _hativaController.dispose();
    _candidateNameController.dispose();
    _hitsController.dispose();
    _timeSecondsController.dispose();
    super.dispose();
  }

  Future<void> _saveFeedback() async {
    // Prevent double submission
    if (_isSaving) {
      debugPrint('⚠️ Save already in progress');
      return;
    }

    // Validate required fields
    if (_selectedPikud == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אנא בחר פיקוד'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return;
    }

    if (_hativaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אנא מלא חטיבה'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return;
    }

    if (_candidateNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אנא מלא שם מועמד'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return;
    }

    if (_candidateNumber == null ||
        _candidateNumber! < 1 ||
        _candidateNumber! > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אנא בחר מספר מועמד (1-100)'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return;
    }

    // Validate all categories are scored
    if (!isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אנא דרג את כל הקטגוריות'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // ✅ Correct collection path - determined automatically by weighted score
      final String collectionPath = isSuitableForInstructorCourse
          ? 'instructor_course_selection_suitable'
          : 'instructor_course_selection_not_suitable';

      debugPrint('📝 Saving to: $collectionPath');
      debugPrint(
        '   finalWeightedScore: ${finalWeightedScore.toStringAsFixed(1)}',
      );
      debugPrint(
        '   isSuitable: $isSuitableForInstructorCourse (auto-determined)',
      );
      debugPrint('   averageScore: ${averageScore.toStringAsFixed(2)}');

      // Prepare scores map with weighted final score
      final scores = {
        'levelTest': categories['בוחן רמה'] ?? 0,
        'levelTestHits': int.tryParse(_hitsController.text) ?? 0,
        'levelTestTimeSeconds': int.tryParse(_timeSecondsController.text) ?? 0,
        'goodInstruction': categories['הדרכה טובה'] ?? 0,
        'structureInstruction': categories['הדרכת מבנה'] ?? 0,
        'dryPractice': categories['יבשים'] ?? 0,
        'surpriseExercise': categories['תרגיל הפתעה'] ?? 0,
        'finalScore': finalWeightedScore,
        'isFitForInstructorCourse': isSuitableForInstructorCourse,
      };

      // Get current user's UID
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('User not authenticated');
      }

      // Prepare document data (isSuitable determined automatically)
      final feedbackData = {
        'command': _selectedPikud ?? '',
        'brigade': _hativaController.text.trim(),
        'candidateName': _candidateNameController.text.trim(),
        'candidateNumber': _candidateNumber ?? 0,
        'instructorName': currentUser?.name ?? 'לא ידוע',
        'instructorId': uid, // Add instructorId for security rules
        'scores': scores,
        'averageScore': averageScore,
        'finalWeightedScore': finalWeightedScore,
        'isSuitable': isSuitableForInstructorCourse,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save to top-level collection
      final docRef = await FirebaseFirestore.instance
          .collection(collectionPath)
          .add(feedbackData);

      debugPrint('✅ Feedback saved successfully!');
      debugPrint('   Collection: $collectionPath');
      debugPrint('   Document ID: ${docRef.id}');

      if (!mounted) return;

      // Show success message with automatic determination
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSuitableForInstructorCourse
                ? 'משוב נשמר! ציון משוקלל: ${finalWeightedScore.toStringAsFixed(1)} - מתאים לקורס מדריכים'
                : 'משוב נשמר! ציון משוקלל: ${finalWeightedScore.toStringAsFixed(1)} - לא מתאים לקורס מדריכים',
          ),
          backgroundColor: isSuitableForInstructorCourse
              ? Colors.green
              : Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: const Duration(seconds: 4),
        ),
      );

      // Navigate back
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Error saving feedback: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בשמירה: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildCategoryRow(String category) {
    // Special handling for level test
    if (category == 'בוחן רמה') {
      return _buildLevelTestRow();
    }

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
                    onPressed: () =>
                        setState(() => categories[category] = score),
                    child: Text(
                      score.toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (score == 1 || score == 5)
                    Text(
                      score == 1 ? 'נמוך ביותר' : 'גבוה ביותר',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
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
        color: Colors.purple.shade50,
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.purple),
                  const SizedBox(width: 8),
                  const Text(
                    'בוחן רמה',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
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
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'מספר פגיעות',
                        hintText: 'הזן מספר',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: Icon(Icons.my_location),
                      ),
                      onChanged: (_) => _updateLevelTestRating(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _timeSecondsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'זמן (שניות)',
                        hintText: 'הזן שניות',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: Icon(Icons.timer),
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
                Text(
                  'חישוב אוטומטי: ${_hitsController.text} פגיעות ב-${_timeSecondsController.text} שניות',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fixed fields section
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
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedPikud = newValue;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _hativaController,
                          decoration: const InputDecoration(
                            labelText: 'חטיבה',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          style: const TextStyle(color: Colors.black),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _candidateNameController,
                          decoration: const InputDecoration(
                            labelText: 'שם מועמד',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          style: const TextStyle(color: Colors.black),
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
                          onChanged: (int? newValue) {
                            setState(() {
                              _candidateNumber = newValue;
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
                                  color: Colors.grey,
                                  fontSize: 12,
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

                // Categories
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

                // Weighted Final Score Display with Auto-Determination
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

                // Save Button
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveFeedback,
                    icon: _isSaving
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
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving ? 'שומר...' : 'שמור משוב',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSuitableForInstructorCourse
                          ? Colors.green
                          : Colors.orange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Info text
                Text(
                  isSuitableForInstructorCourse
                      ? 'המשוב יישמר ב: instructor_course_selection_suitable'
                      : 'המשוב יישמר ב: instructor_course_selection_not_suitable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
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
