import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart'; // for currentUser and golanSettlements

/// מסך מטווח עם טבלה דינמית
class RangeTrainingPage extends StatefulWidget {
  final String rangeType; // 'קצרים' / 'ארוכים' / 'הפתעה'

  const RangeTrainingPage({super.key, required this.rangeType});

  @override
  State<RangeTrainingPage> createState() => _RangeTrainingPageState();
}

class _RangeTrainingPageState extends State<RangeTrainingPage> {
  // רשימת מקצים קבועה
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
  ];

  String? selectedSettlement;
  String instructorName = '';
  int attendeesCount = 0;

  // רשימת מקצים - כל מקצה מכיל שם + מספר כדורים
  List<RangeStation> stations = [];

  // רשימת חניכים - כל חניך מכיל שם + פגיעות למקצה
  List<Trainee> trainees = [];

  bool _isSaving = false;
  // הייצוא יתבצע מדף המשובים בלבד

  @override
  void initState() {
    super.initState();
    instructorName = currentUser?.name ?? '';
    // מקצה ברירת מחדל אחד
    stations.add(RangeStation(name: '', bulletsCount: 0));
  }

  void _updateAttendeesCount(int count) {
    setState(() {
      attendeesCount = count;

      // יצירת רשימת חניכים לפי הכמות
      if (count > trainees.length) {
        // הוספת חניכים
        for (int i = trainees.length; i < count; i++) {
          trainees.add(Trainee(name: '', hits: {}));
        }
      } else if (count < trainees.length) {
        // הסרת חניכים
        trainees = trainees.sublist(0, count);
      }
    });
  }

  void _addStation() {
    setState(() {
      stations.add(RangeStation(name: '', bulletsCount: 0));
    });
  }

  void _removeStation(int index) {
    if (stations.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('חייב להיות לפחות מקצה אחד')),
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

  // ⚠️ פונקציות הייצוא הוסרו - הייצוא יבוצע רק מדף המשובים (Admin בלבד)
  // יצוא ל-Google Sheets יתבצע על משובים שכבר נשמרו בלבד

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

    // וידוא שכל המקצים מוגדרים
    for (int i = 0; i < stations.length; i++) {
      if (stations[i].name.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('אנא הזן שם למקצה ${i + 1}')));
        return;
      }
      if (stations[i].bulletsCount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('אנא הזן מספר כדורים למקצה ${i + 1}')),
        );
        return;
      }
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
      final String subFolder = widget.rangeType == 'קצרים'
          ? 'דיווח קצר'
          : widget.rangeType == 'ארוכים'
          ? 'דיווח רחוק'
          : 'תרגילי הפתעה';

      final Map<String, dynamic> data = {
        // שדות סטנדרטיים של מערכת המשובים (תאימות מלאה)
        'exercise': 'מטווחים',
        'folder': 'מטווחי ירי',
        'instructorName': instructorName,
        'instructorId': uid,
        'instructorRole': currentUser?.role ?? 'Instructor',
        'instructorUsername': currentUser?.username ?? '',
        'createdAt': FieldValue.serverTimestamp(),

        // שדות ייחודיים למטווחים
        'rangeType': widget.rangeType, // 'קצרים' / 'ארוכים' / 'הפתעה'
        'rangeSubFolder': subFolder, // תת-תיקייה
        'settlement': selectedSettlement,
        'attendeesCount': attendeesCount,

        // תוכן מקצועי
        'stations': stations
            .map((s) => {'name': s.name, 'bulletsCount': s.bulletsCount})
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
          };
        }).toList(),

        // שדות נוספים לשמירת תאימות מלאה
        'name': selectedSettlement ?? '',
        'role': 'מטווח',
        'scores': {},
        'notes': {'general': '$subFolder'},
        'criteriaList': [],
      };

      // שמירה ב-Firestore תחת feedbacks (אינטגרציה מלאה)
      await FirebaseFirestore.instance.collection('feedbacks').add(data);

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

  @override
  Widget build(BuildContext context) {
    // קביעת שם המטווח להצגה
    final String rangeTitle = widget.rangeType == 'קצרים'
        ? 'טווח קצר'
        : widget.rangeType == 'ארוכים'
        ? 'טווח רחוק'
        : 'תרגילי הפתעה';

    return Scaffold(
      appBar: AppBar(
        title: Text(rangeTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.pop(context),
        ),
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
              DropdownButtonFormField<String>(
                initialValue: selectedSettlement,
                hint: const Text('יישוב / מחלקה'),
                decoration: const InputDecoration(
                  labelText: 'יישוב / מחלקה',
                  border: OutlineInputBorder(),
                ),
                items: golanSettlements
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => selectedSettlement = v),
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

              // כותרת מקצים
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'מקצים',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addStation,
                    icon: const Icon(Icons.add),
                    label: const Text('הוסף מקצה'),
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
                              'מקצה ${index + 1}',
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
                        DropdownButtonFormField<String>(
                          initialValue: station.name.isEmpty
                              ? null
                              : station.name,
                          hint: const Text('בחר מקצה'),
                          decoration: const InputDecoration(
                            labelText: 'שם המקצה',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: availableStations
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              station.name = v ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 8),
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
                    ),
                  ),
                );
              }),

              const SizedBox(height: 32),

              // טבלת חניכים - מוצגת רק אם יש נוכחים
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

                // הערה למשתמש
                const SizedBox(height: 12),
                const Text(
                  'לייצוא ל-Google Sheets, עבור לדף המשובים ולחץ על המטווח השמור',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        border: TableBorder.all(color: Colors.grey.shade400, width: 1),
        columns: [
          // עמודת שם החניך
          const DataColumn(
            label: Text('חניך', style: TextStyle(fontWeight: FontWeight.bold)),
          ),

          // עמודות המקצים
          ...stations.asMap().entries.map((entry) {
            final index = entry.key;
            final station = entry.value;

            return DataColumn(
              label: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    station.name.isEmpty ? 'מקצה ${index + 1}' : station.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(${station.bulletsCount} כדורים)',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }),

          // עמודת סיכום פגיעות
          const DataColumn(
            label: Text(
              'פגיעות/כדורים',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),

          // עמודת אחוז פגיעות
          const DataColumn(
            label: Text(
              'אחוז פגיעות',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
        ],

        rows: trainees.asMap().entries.map((entry) {
          final traineeIndex = entry.key;
          final trainee = entry.value;

          return DataRow(
            cells: [
              // שם החניך
              DataCell(
                SizedBox(
                  width: 100,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'שם',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onChanged: (v) {
                      setState(() {
                        trainee.name = v;
                      });
                    },
                  ),
                ),
              ),

              // תאי פגיעות למקצים
              ...stations.asMap().entries.map((stationEntry) {
                final stationIndex = stationEntry.key;
                final station = stationEntry.value;

                return DataCell(
                  SizedBox(
                    width: 60,
                    child: TextField(
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '0',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      onChanged: (v) {
                        final hits = int.tryParse(v) ?? 0;

                        // בדיקה שהפגיעות לא עולות על מספר הכדורים
                        if (hits > station.bulletsCount) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'פגיעות לא יכולות לעלות על ${station.bulletsCount} כדורים',
                              ),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                          return;
                        }

                        setState(() {
                          trainee.hits[stationIndex] = hits;
                        });
                      },
                    ),
                  ),
                );
              }),

              // סיכום פגיעות/כדורים החניך
              DataCell(
                Text(
                  '${_getTraineeTotalHits(traineeIndex)}/${_getTotalBullets()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),

              // אחוז פגיעות (חישוב אוטומטי)
              DataCell(
                Builder(
                  builder: (_) {
                    final totalHits = _getTraineeTotalHits(traineeIndex);
                    final totalBullets = _getTotalBullets();
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
                    );
                  },
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// מודל מקצה
class RangeStation {
  String name;
  int bulletsCount;

  RangeStation({required this.name, required this.bulletsCount});
}

/// מודל חניך
class Trainee {
  String name;
  Map<int, int> hits; // מפה: אינדקס מקצה -> מספר פגיעות

  Trainee({required this.name, required this.hits});
}
