import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // autosave timer (debounced saves)
  Timer? _autosaveTimer;

  // whether the current feedback has been finalized (final save)
  final bool _isFinalized = false;

  bool _isSaving = false;
  // הייצוא יתבצע מדף המשובים בלבד

  @override
  void initState() {
    super.initState();
    instructorName = currentUser?.name ?? '';
    _settlementDisplayText = selectedSettlement ?? '';
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
    _autosaveTimer?.cancel();
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
        // schedule autosave after changes
        _scheduleAutosave();
      } else if (count < trainees.length) {
        // הסרת חניכים
        trainees = trainees.sublist(0, count);
        traineeNumbers = List<int>.generate(trainees.length, (i) => i + 1);
        _scheduleAutosave();
      }
    });
  }

  void _scheduleAutosave() {
    if (_isFinalized) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1500), () async {
      await _saveTemporarily();
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

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('משתמש לא מחובר');
      }

      // הכנת הנתונים לשמירה - אינטגרציה מלאה עם מערכת המשובים
      final String subFolder = widget.mode == 'surprise'
          ? 'תרגילי הפתעה'
          : (_rangeType == 'קצרים' ? 'דיווח קצר' : 'דיווח רחוק');

      final Map<String, dynamic> data = {
        // שדות סטנדרטיים של מערכת המשובים (תאימות מלאה)
        'exercise': widget.mode == 'surprise' ? 'תרגילי הפתעה' : 'מטווחים',
        'folder': widget.mode == 'surprise'
            ? 'משוב תרגילי הפתעה'
            : 'מטווחי ירי',
        'instructorName': instructorName,
        'instructorId': uid,
        'instructorRole': currentUser?.role ?? 'Instructor',
        'instructorUsername': currentUser?.username ?? '',
        'createdAt': FieldValue.serverTimestamp(),

        // שדות ייחודיים למטווחים
        'rangeType': _rangeType, // 'קצרים' / 'ארוכים' / 'הפתעה'
        'rangeSubFolder': subFolder, // תת-תיקייה
        'settlement': selectedSettlement,
        'attendeesCount': attendeesCount,

        // תוכן מקצועי
        'stations': stations
            .map(
              (s) => {
                'name': s.name,
                'bulletsCount': s.bulletsCount,
                'timeSeconds': s.timeSeconds,
                'hits': s.hits,
                'isManual': s.isManual,
                'isLevelTester': s.isLevelTester,
                'selectedRubrics': s.selectedRubrics,
              },
            )
            .toList(),

        'trainees': trainees.asMap().entries.map((entry) {
          final index = entry.key;
          final trainee = entry.value;

          return {
            'name': trainee.name,
            'hits': trainee.hits.map(
              (stationIdx, hits) => MapEntry('station_$stationIdx', hits),
            ),
            'totalHits': _getTraineeTotalHits(index),
            'number': traineeNumbers.length > index
                ? traineeNumbers[index]
                : index + 1,
          };
        }).toList(),

        // שדות נוספים לשמירת תאימות מלאה
        'name': selectedSettlement ?? '',
        'role': 'מטווח',
        'scores': {},
        'notes': {'general': subFolder},
        'criteriaList': [],
      };

      // שמירה ב-Firestore תחת feedbacks (אינטגריה מלאה)
      // If we are editing an existing temporary feedback, update it
      if (widget.feedbackId != null) {
        await FirebaseFirestore.instance
            .collection('feedbacks')
            .doc(widget.feedbackId)
            .update({
              ...data,
              'status': 'final',
              'folder': 'מטווחי ירי',
              'createdAt': FieldValue.serverTimestamp(),
            });
      } else {
        // new final save
        await FirebaseFirestore.instance.collection('feedbacks').add({
          ...data,
          'status': 'final',
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ המשוב נשמר בהצלחה בנתיב: משובים → מטווחים → מטווחי ירי',
          ),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה בשמירה: ${e.toString()}')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool get _canSaveTemporarily =>
      selectedSettlement != null &&
      attendeesCount > 0 &&
      stations.isNotEmpty &&
      // at least one shooting session must have a name or manual station
      stations.any((s) => s.name.trim().isNotEmpty || s.isManual);

  Future<void> _saveTemporarily() async {
    // Build data similar to final save but mark as temporary and store under feedbacks
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Determine exercise type and folder based on mode
    final String exerciseType;
    final String tempFolder;
    final String type;

    if (widget.mode == 'surprise') {
      exerciseType = 'תרגילי הפתעה';
      tempFolder = 'תרגילי הפתעה - משוב זמני';
      type = 'surprise_exercise';
    } else {
      exerciseType = 'מטווחים';
      tempFolder = 'מטווחים - משוב זמני';
      type = 'range_training';
    }

    final Map<String, dynamic> data = {
      'exercise': exerciseType,
      'folder': tempFolder,
      'status': 'temporary',
      'type': type,
      'instructorName': instructorName,
      'instructorId': uid ?? '',
      'instructorRole': currentUser?.role ?? 'Instructor',
      'rangeType': _rangeType,
      'settlement': selectedSettlement,
      'attendeesCount': attendeesCount,
      'stations': stations.map((s) => s.toJson()).toList(),
      'trainees': trainees.asMap().entries.map((entry) {
        final idx = entry.key;
        final t = entry.value;
        return {
          'name': t.name,
          'hits': t.hits.map((k, v) => MapEntry('station_$k', v)),
          'totalHits': _getTraineeTotalHits(idx),
          'number': traineeNumbers.length > idx ? traineeNumbers[idx] : idx + 1,
        };
      }).toList(),
      'name': selectedSettlement ?? '',
      'role': widget.mode == 'surprise' ? 'תרגיל הפתעה' : 'מטווח',
      'scores': {},
      'notes': {'temporary': 'שמירה זמנית'},
      'criteriaList': [],
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_editingFeedbackId != null) {
        // update existing temporary document
        await FirebaseFirestore.instance
            .collection('feedbacks')
            .doc(_editingFeedbackId)
            .update(data);
      } else {
        final ref = await FirebaseFirestore.instance
            .collection('feedbacks')
            .add(data);
        _editingFeedbackId = ref.id;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('המשוב נשמר באופן זמני')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה בשמירה זמנית: $e')));
    }
  }

  Future<void> _loadExistingTemporaryFeedback(String id) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(id)
          .get();
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      setState(() {
        selectedSettlement =
            data['settlement'] as String? ?? selectedSettlement;
        _settlementDisplayText = selectedSettlement ?? '';
        attendeesCount =
            (data['attendeesCount'] as num?)?.toInt() ?? attendeesCount;
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
        // rebuild sequential numbers according to loaded trainees
        traineeNumbers = List<int>.generate(trainees.length, (i) => i + 1);
      });
    } catch (e) {
      debugPrint('Error loading temp feedback $e');
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
                              _scheduleAutosave();
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

                const SizedBox(height: 32),

                // כפתור שמירה בלבד - ייצוא יבוצע מדף המשובים
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveToFirestore,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'שמור מטווח',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),

                const SizedBox(height: 12),
                // Finalize button: explicitly finalize temporary feedbacks
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveToFirestore,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'שמור סופי',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),

                // הערה למשתמש
                const SizedBox(height: 12),
                const Text(
                  'לייצוא לקובץ מקומי, עבור לדף המשובים ולחץ על המטווח השמור',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
              // כפתור שמירה זמנית
              if (attendeesCount > 0) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _canSaveTemporarily ? _saveTemporarily : null,
                  child: const Text('שמור זמנית'),
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
                                        _scheduleAutosave();
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
                                    _scheduleAutosave();
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
                                              _scheduleAutosave();
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
                                _scheduleAutosave();
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
                                _scheduleAutosave();
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
                                          _scheduleAutosave();
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
