import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';
import 'feedback_export_service.dart';

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

  int _calculateLevelTestRating() {
    final hits = int.tryParse(_hitsController.text) ?? 0;
    final timeSeconds = int.tryParse(_timeSecondsController.text) ?? 0;
    if (hits == 0 && timeSeconds == 0) return 0;
    if (hits < 6) return 1;
    if (timeSeconds > 15 && hits < 8) return 1;
    if (timeSeconds <= 7 && hits >= 10) return 5;
    if (timeSeconds >= 15 || hits <= 6) return 1;
    double timeFactor = (timeSeconds - 7) / (15 - 7);
    timeFactor = timeFactor.clamp(0.0, 1.0);
    double hitsFactor = (10 - hits) / (10 - 6);
    hitsFactor = hitsFactor.clamp(0.0, 1.0);
    double combinedFactor = (timeFactor + hitsFactor) / 2;
    double rawScore = 5 - (combinedFactor * 4);
    return rawScore.round().clamp(1, 5);
  }

  void _updateLevelTestRating() {
    setState(() {
      categories['בוחן רמה'] = _calculateLevelTestRating();
    });
  }

  static const Map<String, double> _categoryWeights = {
    'בוחן רמה': 0.15,
    'תרגיל הפתעה': 0.25,
    'יבשים': 0.20,
    'הדרכה טובה': 0.20,
    'הדרכת מבנה': 0.20,
  };

  bool _isSaving = false;

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
    final name = _candidateNameController.text.trim();
    final number = _candidateNumber;
    return pikud.isNotEmpty && name.isNotEmpty && number != null;
  }

  @override
  void dispose() {
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
          .collection('instructor_course_screenings')
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

  Future<bool> _saveFeedback({bool allowAutoFinalize = true}) async {
    if (_isSaving) {
      debugPrint('⚠️ Save already in progress');
      return false;
    }
    setState(() => _isSaving = true);
    try {
      if (!hasRequiredDetails) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('יש למלא את כל פרטי המיון לפני שמירה'),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
            ),
          );
        }
        setState(() => _isSaving = false);
        return false;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('נדרשת התחברות');
      }
      final coll = FirebaseFirestore.instance.collection(
        'instructor_course_screenings',
      );
      final ref =
          (_existingScreeningId != null && _existingScreeningId!.isNotEmpty)
          ? coll.doc(_existingScreeningId)
          : coll.doc();
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
            final time = int.tryParse(_timeSecondsController.text);
            if (hits != null) meta['hits'] = hits;
            if (time != null) meta['timeSeconds'] = time;
          }
          fields[name] = meta;
        }
      });
      final payload = {
        'status': 'draft',
        'courseType': 'miunim',
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
        'createdBy': uid,
        'createdByName': FirebaseAuth.instance.currentUser?.email ?? '',
        'command': _selectedPikud ?? '',
        'brigade': _hativaController.text.trim(),
        'candidateName': _candidateNameController.text.trim(),
        'candidateNumber': _candidateNumber ?? 0,
        'title': _candidateNameController.text.trim().isNotEmpty
            ? _candidateNameController.text.trim()
            : 'מועמד',
        if (fields.isNotEmpty) 'fields': fields,
      };
      if (_existingScreeningId == null || _existingScreeningId!.isEmpty) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      await ref.set(payload, SetOptions(merge: true));
      _existingScreeningId ??= ref.id;
      if (allowAutoFinalize && isFormValid) {
        try {
          await FeedbackExportService.finalizeScreeningAndCreateFeedback(
            screeningId: _existingScreeningId!,
          );
          if (!mounted) return true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('המשוב נסגר והועבר אוטומטית לדף המשובים'),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
            ),
          );
          Navigator.pop(context);
          return true;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('שגיאה בסגירת המשוב: ${e.toString()}'),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              ),
            );
          }
        }
      }
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נשמר כמשוב בתהליך (draft)'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בשמירה: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _finalizeIfComplete() async {
    if (_existingScreeningId == null || _existingScreeningId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא ניתן לסיים ללא מזהה משוב')),
      );
      return;
    }
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
    try {
      final saved = await _saveFeedback(allowAutoFinalize: false);
      if (!saved) return;
      setState(() => _isSaving = true);
      await FeedbackExportService.finalizeScreeningAndCreateFeedback(
        screeningId: _existingScreeningId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('המשוב נסגר והסיווג בוצע אוטומטית')),
      );
      Navigator.pop(context);
    } catch (e) {
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
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'זמן (שניות)',
                        hintText: 'הזן שניות',
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
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedPikud = newValue;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _hativaController,
                          decoration: const InputDecoration(labelText: 'חטיבה'),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _candidateNameController,
                          decoration: const InputDecoration(
                            labelText: 'שם מועמד',
                          ),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
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
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            await _saveFeedback();
                          },
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
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving || !isFormValid
                        ? null
                        : _finalizeIfComplete,
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
