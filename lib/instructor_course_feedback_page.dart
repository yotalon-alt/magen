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

  // Categories with scores (1-5)
  final Map<String, int> categories = {
    'בוחן רמה': 0,
    'הדרכה טובה': 0,
    'הדרכת מבנה': 0,
    'יבשים': 0,
    'תרגיל הפתעה': 0,
  };

  // Is suitable for instructors course
  bool isSuitable = false;

  // Saving state
  bool _isSaving = false;

  // Calculate average score in real-time
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
      // ✅ Correct collection path - top-level collections
      final String collectionPath = isSuitable
          ? 'instructor_course_selection_suitable'
          : 'instructor_course_selection_not_suitable';

      debugPrint('📝 Saving to: $collectionPath');
      debugPrint('   isSuitable: $isSuitable');
      debugPrint('   averageScore: ${averageScore.toStringAsFixed(2)}');

      // Prepare scores map
      final scores = {
        'levelTest': categories['בוחן רמה'] ?? 0,
        'goodInstruction': categories['הדרכה טובה'] ?? 0,
        'structureInstruction': categories['הדרכת מבנה'] ?? 0,
        'dryPractice': categories['יבשים'] ?? 0,
        'surpriseExercise': categories['תרגיל הפתעה'] ?? 0,
      };

      // Get current user's UID
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('User not authenticated');
      }

      // Prepare document data
      final feedbackData = {
        'command': _selectedPikud ?? '',
        'brigade': _hativaController.text.trim(),
        'candidateName': _candidateNameController.text.trim(),
        'candidateNumber': _candidateNumber ?? 0,
        'instructorName': currentUser?.name ?? 'לא ידוע',
        'instructorId': uid, // Add instructorId for security rules
        'scores': scores,
        'averageScore': averageScore,
        'isSuitable': isSuitable,
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

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSuitable
                ? 'המועמד מתאים לקורס מדריכים'
                : 'המועמד לא מתאים לקורס מדריכים',
          ),
          backgroundColor: isSuitable ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [1, 2, 3, 4, 5].map((score) {
              final isSelected = currentScore == score;
              return ElevatedButton(
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
                onPressed: () => setState(() => categories[category] = score),
                child: Text(
                  score.toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '1 – הציון הנמוך ביותר',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                ),
              ),
              Text(
                '5 – הציון הגבוה ביותר',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
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
        appBar: AppBar(title: const Text('מיון לקורס מדריכים')),
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

                // Average Score Display
                Card(
                  color: Colors.blueGrey.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'ציון ממוצע',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          averageScore.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'מתוך 5.00',
                          style: TextStyle(fontSize: 14, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Divider(),

                // Suitability Checkbox
                Card(
                  color: isSuitable
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  child: CheckboxListTile(
                    title: const Text(
                      'מתאים לקורס מדריכים',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      isSuitable
                          ? 'המועמד יישמר כמתאים'
                          : 'המועמד יישמר כלא מתאים',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    value: isSuitable,
                    onChanged: (value) {
                      setState(() => isSuitable = value ?? false);
                    },
                    activeColor: Colors.white,
                    checkColor: Colors.green.shade700,
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
                      backgroundColor: isSuitable ? Colors.green : Colors.red,
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
                  isSuitable
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
