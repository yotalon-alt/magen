import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart'; // for FeedbackModel

/// שירות ייצוא משובים ל-Google Sheets
/// תומך גם במשובים כלליים וגם במשובי מטווחים
class FeedbackExportService {
  // URL של Google Apps Script Web App
  // הערה: יש להחליף ב-URL האמיתי שלך
  static const String scriptUrl = 'YOUR_GOOGLE_APPS_SCRIPT_WEB_APP_URL_HERE';

  /// ייצוא משוב רגיל (לא מטווחים)
  static Future<String?> exportRegularFeedback({
    required String feedbackId,
  }) async {
    try {
      // Guard: ensure scriptUrl is configured
      if (scriptUrl.isEmpty || scriptUrl.startsWith('YOUR_')) {
        throw Exception(
          'כתובת Google Apps Script אינה מוגדרת. עדכן את scriptUrl בקובץ השירות.',
        );
      }
      // טעינת המשוב מ-Firestore
      final doc = await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(feedbackId)
          .get();

      if (!doc.exists) {
        throw Exception('משוב לא נמצא');
      }

      final data = doc.data()!;
      final now = DateTime.now();
      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? now;

      final sheetTitle =
          'משוב ${data['exercise'] ?? ''} - ${DateFormat('yyyy-MM-dd_HH-mm').format(createdAt)}';

      // בניית טבלה למשוב רגיל
      final List<List<dynamic>> rows = [
        // כותרות
        [
          'תאריך יצירה',
          'מדריך',
          'תרגיל',
          'תיקייה',
          'תפקיד',
          'שם נבדק',
          'יישוב',
          'תרחיש',
        ],
        // נתונים
        [
          dateFormat.format(createdAt),
          data['instructorName'] ?? '',
          data['exercise'] ?? '',
          data['folder'] ?? '',
          data['role'] ?? '',
          data['name'] ?? '',
          data['settlement'] ?? '',
          data['scenario'] ?? '',
        ],
      ];

      // הוספת ציונים אם קיימים
      final scores = data['scores'] as Map<String, dynamic>?;
      if (scores != null && scores.isNotEmpty) {
        rows.add(['']); // שורה ריקה
        rows.add(['קריטריונים', 'ציון', 'הערה']);

        scores.forEach((criterion, score) {
          final notes = data['notes'] as Map<String, dynamic>?;
          final note = notes?[criterion] ?? '';
          rows.add([criterion, score.toString(), note]);
        });
      }

      // שליחה ל-Google Apps Script
      final response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'title': sheetTitle,
              'data': rows,
              'targetEmail': 'הלון@gmail.com',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final sheetUrl = result['url'] as String?;

        if (sheetUrl != null && sheetUrl.isNotEmpty) {
          return sheetUrl;
        } else {
          throw Exception('לא התקבל URL לקובץ');
        }
      } else {
        throw Exception('שגיאה ביצירת הקובץ: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// ייצוא משוב מטווחים
  static Future<String?> exportRangeFeedback({
    required String feedbackId,
  }) async {
    try {
      // Guard: ensure scriptUrl is configured
      if (scriptUrl.isEmpty || scriptUrl.startsWith('YOUR_')) {
        throw Exception(
          'כתובת Google Apps Script אינה מוגדרת. עדכן את scriptUrl בקובץ השירות.',
        );
      }
      // טעינת המשוב מ-Firestore
      final doc = await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(feedbackId)
          .get();

      if (!doc.exists) {
        throw Exception('משוב לא נמצא');
      }

      final data = doc.data()!;
      final now = DateTime.now();
      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? now;

      // קביעת שם סוג המטווח להצגה
      final rangeType = data['rangeType'] ?? 'לא ידוע';
      final rangeDisplayName = rangeType == 'קצרים'
          ? 'טווח קצר'
          : rangeType == 'ארוכים'
          ? 'טווח רחוק'
          : rangeType == 'הפתעה'
          ? 'תרגילי הפתעה'
          : 'מטווח $rangeType';
      final sheetTitle =
          '$rangeDisplayName - ${DateFormat('yyyy-MM-dd_HH-mm').format(createdAt)}';

      // קריאת נתוני מקצים וחניכים
      final stations =
          (data['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final trainees =
          (data['trainees'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final attendeesCount = data['attendeesCount'] ?? 0;
      final settlement = data['settlement'] ?? '';
      final instructor = data['instructorName'] ?? '';

      // בניית שורת כותרות
      final List<String> headers = [
        'תאריך',
        'יישוב/מחלקה',
        'מדריך',
        'מספר נוכחים',
        'סוג מטווח',
        'שם חניך',
      ];

      // הוספת עמודות מקצים
      for (var station in stations) {
        final stationName = station['name'] ?? 'מקצה';
        headers.add('$stationName (פגיעות)');
        headers.add('$stationName (כדורים)');
      }

      headers.add('ס"כ פגיעות/כדורים');
      headers.add('אחוז פגיעות');

      // בניית שורות נתונים
      final List<List<dynamic>> rows = [headers];

      for (var trainee in trainees) {
        final traineeName = trainee['name'] ?? '';
        final hits = trainee['hits'] as Map<String, dynamic>? ?? {};
        final totalHits = trainee['totalHits'] ?? 0;

        final List<dynamic> row = [
          dateFormat.format(createdAt),
          settlement,
          instructor,
          attendeesCount.toString(),
          rangeType,
          traineeName,
        ];

        // הוספת פגיעות וכדורים לכל מקצה
        for (int j = 0; j < stations.length; j++) {
          final stationHits = hits['station_$j'] ?? 0;
          final stationBullets = stations[j]['bulletsCount'] ?? 0;
          row.add(stationHits.toString());
          row.add(stationBullets.toString());
        }

        // חישוב סה"כ כדורים
        final totalBullets = stations.fold<int>(
          0,
          (acc, station) => acc + ((station['bulletsCount'] as int?) ?? 0),
        );

        row.add('$totalHits/$totalBullets');

        // חישוב אחוז פגיעות
        final percentage = totalBullets > 0
            ? ((totalHits / totalBullets) * 100).toStringAsFixed(1)
            : '0.0';
        row.add('$percentage%');

        rows.add(row);
      }

      // חישוב סה"כ כדורים
      final totalBullets = stations.fold<int>(
        0,
        (acc, station) => acc + ((station['bulletsCount'] as int?) ?? 0),
      );

      // חישוב סה"כ פגיעות
      int totalHits = 0;
      for (var trainee in trainees) {
        totalHits += (trainee['totalHits'] as num?)?.toInt() ?? 0;
      }

      // חישוב אחוז כללי
      final overallPercentage = totalBullets > 0
          ? ((totalHits / totalBullets) * 100).toStringAsFixed(1)
          : '0.0';

      // הוספת שורות ריקות ומקטע סיכום כללי
      rows.add([]); // שורה ריקה
      rows.add(['']); // שורה ריקה נוספת
      rows.add(['סיכום כללי', '', '', '', '', '', '', '']);
      rows.add(['סך הכל פגיעות/כדורים:', '$totalHits/$totalBullets']);
      rows.add(['אחוז פגיעה כללי:', '$overallPercentage%']);

      // שליחה ל-Google Apps Script
      final response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'title': sheetTitle,
              'data': rows,
              'targetEmail': 'הלון@gmail.com',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final sheetUrl = result['url'] as String?;

        if (sheetUrl != null && sheetUrl.isNotEmpty) {
          return sheetUrl;
        } else {
          throw Exception('לא התקבל URL לקובץ');
        }
      } else {
        throw Exception('שגיאה ביצירת הקובץ: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// פונקציה כללית לייצוא - מזהה אוטומטית את סוג המשוב
  static Future<String?> exportFeedback({required String feedbackId}) async {
    try {
      // טעינת המשוב כדי לזהות את הסוג
      final doc = await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(feedbackId)
          .get();

      if (!doc.exists) {
        throw Exception('משוב לא נמצא');
      }

      final data = doc.data()!;
      final exercise = data['exercise'] as String?;

      // זיהוי אוטומטי: אם התרגיל הוא "מטווחים" יש לייצא כמשוב מטווחים
      if (exercise == 'מטווחים' &&
          data.containsKey('stations') &&
          data.containsKey('trainees')) {
        return await exportRangeFeedback(feedbackId: feedbackId);
      } else {
        return await exportRegularFeedback(feedbackId: feedbackId);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// ייצוא מרובה של משובים (למשובי מטווחים בעיקר)
  static Future<String?> exportMultipleFeedbacks({
    required List<dynamic> feedbacks, // List<FeedbackModel>
  }) async {
    try {
      // Guard: ensure scriptUrl is configured
      if (scriptUrl.isEmpty || scriptUrl.startsWith('YOUR_')) {
        throw Exception(
          'כתובת Google Apps Script אינה מוגדרת. עדכן את scriptUrl בקובץ השירות.',
        );
      }
      if (feedbacks.isEmpty) {
        throw Exception('אין משובים לייצוא');
      }

      final now = DateTime.now();
      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
      final sheetTitle =
          'משובי מטווחים – ${DateFormat('yyyy-MM-dd_HH-mm').format(now)}';

      // טבלה מרוכזת לכל המשובים
      final List<List<dynamic>> allRows = [
        // כותרות ראשיות
        [
          'תאריך יצירה',
          'מדריך',
          'יישוב/מחלקה',
          'סוג מטווח',
          'מספר נוכחים',
          'שם חניך',
          'סה"כ פגיעות',
          'סה"כ כדורים',
          'אחוז הצלחה',
        ],
      ];

      // עבור על כל משוב
      for (final feedback in feedbacks) {
        // טעינת הנתונים המלאים מ-Firestore
        try {
          final doc = await FirebaseFirestore.instance
              .collection('feedbacks')
              .doc(feedback.id)
              .get();

          if (!doc.exists) continue;

          final data = doc.data()!;
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? now;
          final rangeType = data['rangeType'] ?? '';
          final settlement = data['settlement'] ?? '';
          final instructor = data['instructorName'] ?? '';
          final attendeesCount = data['attendeesCount'] ?? 0;

          final stations =
              (data['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final trainees =
              (data['trainees'] as List?)?.cast<Map<String, dynamic>>() ?? [];

          // חישוב סה"כ כדורים
          final totalBullets = stations.fold<int>(
            0,
            (acc, station) => acc + ((station['bulletsCount'] as int?) ?? 0),
          );

          // הוספת שורה לכל חניך
          for (var trainee in trainees) {
            final traineeName = trainee['name'] ?? '';
            final totalHits = trainee['totalHits'] ?? 0;
            final percentage = totalBullets > 0
                ? ((totalHits / totalBullets) * 100).toStringAsFixed(1)
                : '0.0';

            allRows.add([
              dateFormat.format(createdAt),
              instructor,
              settlement,
              rangeType,
              attendeesCount.toString(),
              traineeName,
              totalHits.toString(),
              totalBullets.toString(),
              '$percentage%',
            ]);
          }
        } catch (e) {
          debugPrint('שגיאה בעיבוד משוב ${feedback.id}: $e');
          continue;
        }
      }

      if (allRows.length <= 1) {
        throw Exception('לא נמצאו נתונים לייצוא');
      }

      // שליחה ל-Google Apps Script
      final response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'title': sheetTitle,
              'data': allRows,
              'targetEmail': 'הלון@gmail.com',
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final sheetUrl = result['url'] as String?;

        if (sheetUrl != null && sheetUrl.isNotEmpty) {
          return sheetUrl;
        } else {
          throw Exception('לא התקבל URL לקובץ');
        }
      } else {
        throw Exception('שגיאה ביצירת הקובץ: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// ייצוא מרובה משובים - כל משוב בגיליון/טאב נפרד
  /// מתאים לייצוא עם בחירה מרובה
  static Future<String?> exportMultipleFeedbacksToSeparateSheets({
    required List<dynamic> feedbacks,
  }) async {
    try {
      // Guard: ensure scriptUrl is configured
      if (scriptUrl.isEmpty || scriptUrl.startsWith('YOUR_')) {
        throw Exception(
          'כתובת Google Apps Script אינה מוגדרת. עדכן את scriptUrl בקובץ השירות.',
        );
      }
      if (feedbacks.isEmpty) {
        throw Exception('לא נבחרו משובים לייצוא');
      }

      final now = DateTime.now();
      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

      // יצירת רשימת גיליונות (sheets)
      final List<Map<String, dynamic>> sheets = [];

      for (final feedback in feedbacks) {
        try {
          final feedbackId = feedback.id;
          if (feedbackId == null || feedbackId.isEmpty) {
            debugPrint('⚠️ דילוג על משוב ללא ID');
            continue;
          }

          // טעינת נתוני המשוב מ-Firestore
          final doc = await FirebaseFirestore.instance
              .collection('feedbacks')
              .doc(feedbackId)
              .get()
              .timeout(const Duration(seconds: 10));

          if (!doc.exists) {
            debugPrint('⚠️ משוב $feedbackId לא נמצא ב-Firestore');
            continue;
          }

          final data = doc.data()!;
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? now;
          final folder = data['folder'] ?? '';
          final isRange = folder == 'מטווחי ירי';

          // שם הגיליון
          final sheetName = isRange
              ? '${data['settlement'] ?? ''} ${DateFormat('dd-MM').format(createdAt)}'
              : '${data['name'] ?? ''} ${data['exercise'] ?? ''}';

          List<List<dynamic>> rows;

          if (isRange) {
            // משוב מטווחים - טבלת חניכים
            final stations =
                (data['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final trainees =
                (data['trainees'] as List?)?.cast<Map<String, dynamic>>() ?? [];

            // כותרות
            final List<String> headers = [
              'תאריך',
              'יישוב',
              'מדריך',
              'נוכחים',
              'חניך',
            ];
            for (final station in stations) {
              headers.add(station['name'] ?? '');
            }
            headers.addAll(['סה"כ פגיעות', 'סה"כ כדורים', 'אחוז הצלחה']);

            rows = [headers.cast<dynamic>()];

            // נתוני חניכים
            for (final trainee in trainees) {
              final traineeName = trainee['name'] ?? '';
              final hits = (trainee['hits'] as Map?)?.cast<String, dynamic>();

              int totalHits = 0;
              int totalBullets = 0;

              final List<dynamic> row = [
                dateFormat.format(createdAt),
                data['settlement'] ?? '',
                data['instructorName'] ?? '',
                data['attendeesCount']?.toString() ?? '',
                traineeName,
              ];

              // פגיעות לכל מקצה
              for (int i = 0; i < stations.length; i++) {
                // Use consistent key format: 'station_<index>'
                final stationHits = hits?['station_$i'] ?? 0;
                final bullets = stations[i]['bulletsCount'] ?? 0;

                totalHits += (stationHits as num).toInt();
                totalBullets += (bullets as num).toInt();

                row.add('$stationHits/$bullets');
              }

              // סיכומים
              row.add(totalHits.toString());
              row.add(totalBullets.toString());

              final percentage = totalBullets > 0
                  ? ((totalHits / totalBullets) * 100).toStringAsFixed(1)
                  : '0.0';
              row.add('$percentage%');

              rows.add(row);
            }
          } else {
            // משוב רגיל - קריטריונים וציונים
            rows = [
              // כותרות
              ['תאריך', 'מדריך', 'תרגיל', 'תפקיד', 'נבדק', 'יישוב'],
              // נתונים
              [
                dateFormat.format(createdAt),
                data['instructorName'] ?? '',
                data['exercise'] ?? '',
                data['role'] ?? '',
                data['name'] ?? '',
                data['settlement'] ?? '',
              ],
            ];

            // ציונים
            final scores = data['scores'] as Map<String, dynamic>?;
            if (scores != null && scores.isNotEmpty) {
              rows.add(['']); // שורה ריקה
              rows.add(['קריטריון', 'ציון', 'הערה']);

              scores.forEach((criterion, score) {
                final notes = data['notes'] as Map<String, dynamic>?;
                final note = notes?[criterion] ?? '';
                rows.add([criterion, score.toString(), note]);
              });
            }
          }

          sheets.add({
            'name': sheetName.substring(
              0,
              sheetName.length > 30 ? 30 : sheetName.length,
            ),
            'data': rows,
          });
        } catch (e) {
          debugPrint('❌ שגיאה בעיבוד משוב ${feedback.id}: $e');
          continue;
        }
      }

      if (sheets.isEmpty) {
        throw Exception('לא הצליח לעבד אף משוב');
      }

      // כותרת הקובץ
      final fileTitle =
          'ייצוא משובים - ${DateFormat('yyyy-MM-dd_HH-mm').format(now)} (${sheets.length} גיליונות)';

      // שליחה ל-Google Apps Script
      final response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'title': fileTitle,
              'sheets': sheets, // שליחת מערך גיליונות במקום data בודד
              'targetEmail': 'הלון@gmail.com',
              'multipleSheets': true, // דגל לזיהוי ייצוא מרובה
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final sheetUrl = result['url'] as String?;

        if (sheetUrl != null && sheetUrl.isNotEmpty) {
          return sheetUrl;
        } else {
          throw Exception('לא התקבל URL לקובץ');
        }
      } else {
        throw Exception('שגיאה ביצירת הקובץ: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// פתיחת קובץ ב-Google Sheets
  static Future<void> openGoogleSheet(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('לא ניתן לפתוח את הקובץ');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// שמירת הערכת מועמד לקורס מדריכים בפורמט דינמי
  /// payload דוגמה:
  /// {
  ///   "courseType": "instructor",
  ///   "candidateId": "12345",
  ///   "fields": {
  ///     "ירי": {"value": 4, "filledBy": "yotam", "filledAt": "2025-12-19T10:00:00Z"},
  ///     "קבלת החלטות": {"value": 5, "filledBy": "chen", "filledAt": null}
  ///   },
  ///   "isFinalLocked": false
  /// }
  static Future<void> saveInstructorCandidateEvaluation(
    Map<String, dynamic> payload,
  ) async {
    // Validate basic structure
    final String courseType = (payload['courseType'] ?? '').toString();
    if (courseType.toLowerCase() != 'instructor') {
      throw Exception('courseType חייב להיות "instructor"');
    }

    final String candidateId = (payload['candidateId'] ?? '').toString();
    if (candidateId.isEmpty) {
      throw Exception('candidateId חסר או ריק');
    }

    final Map<String, dynamic> fields =
        (payload['fields'] as Map?)?.cast<String, dynamic>() ?? {};

    // Normalize fields: ensure value, filledBy, filledAt types are safe
    final Map<String, dynamic> normalizedFields = {};
    for (final entry in fields.entries) {
      final key = entry.key;
      final val = (entry.value as Map?)?.cast<String, dynamic>() ?? {};
      final dynamic value = val['value'];
      final String? filledBy = val['filledBy']?.toString();

      // Normalize filledAt: allow String ISO, Timestamp, or null
      Timestamp? filledAtTs;
      final filledAt = val['filledAt'];
      if (filledAt is Timestamp) {
        filledAtTs = filledAt;
      } else if (filledAt is String && filledAt.isNotEmpty) {
        final parsed = DateTime.tryParse(filledAt);
        if (parsed != null) {
          filledAtTs = Timestamp.fromDate(parsed.toUtc());
        }
      }

      normalizedFields[key] = {
        'value': value,
        'filledBy':
            filledBy ??
            FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            '',
        'filledAt': filledAtTs ?? FieldValue.serverTimestamp(),
      };
    }

    // Lock flag
    final bool isFinalLocked = (payload['isFinalLocked'] as bool?) ?? false;

    // Build document
    final Map<String, dynamic> docData = {
      'courseType': 'instructor',
      'candidateId': candidateId,
      'fields': normalizedFields,
      'isFinalLocked': isFinalLocked,
      'updatedBy':
          FirebaseAuth.instance.currentUser?.email ??
          FirebaseAuth.instance.currentUser?.uid ??
          '',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Persist under a dedicated collection keyed by candidateId
    // Path: instructor_course_candidates/{candidateId}
    await FirebaseFirestore.instance
        .collection('instructor_course_candidates')
        .doc(candidateId)
        .set(docData, SetOptions(merge: true));
  }

  /// עדכון סטטוס נעילה סופי למועמד
  static Future<void> setCandidateFinalLock(
    String candidateId,
    bool lock,
  ) async {
    if (candidateId.isEmpty) {
      throw Exception('candidateId חסר או ריק');
    }
    await FirebaseFirestore.instance
        .collection('instructor_course_candidates')
        .doc(candidateId)
        .set({
          'isFinalLocked': lock,
          'updatedBy':
              FirebaseAuth.instance.currentUser?.email ??
              FirebaseAuth.instance.currentUser?.uid ??
              '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// עדכון שדה יחיד עבור מועמד (עם בדיקת נעילה)
  static Future<void> updateCandidateField({
    required String candidateId,
    required String fieldName,
    required int value,
  }) async {
    if (candidateId.isEmpty) {
      throw Exception('candidateId חסר או ריק');
    }
    if (fieldName.isEmpty) {
      throw Exception('fieldName חסר או ריק');
    }

    final docRef = FirebaseFirestore.instance
        .collection('instructor_course_candidates')
        .doc(candidateId);

    // בדיקת נעילה לפני עדכון
    final snap = await docRef.get().timeout(const Duration(seconds: 10));
    final locked = (snap.data()?['isFinalLocked'] as bool?) ?? false;
    if (locked) {
      throw Exception('שגיאה: הטופס נעול לעריכה');
    }

    // עדכון נקודתי לשדה: value, filledBy, filledAt
    final String userId =
        FirebaseAuth.instance.currentUser?.email ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';

    await docRef.set({
      'courseType': 'instructor',
      'candidateId': candidateId,
      'fields': {
        fieldName: {
          'value': value,
          'filledBy': userId,
          'filledAt': FieldValue.serverTimestamp(),
        },
      },
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// שמירת שדה יחיד במיון לקורס מדריכים (collection: instructor_course_screenings)
  static Future<void> saveScreeningField({
    required String screeningId,
    required String fieldName,
    required int value,
    required String instructorId,
  }) async {
    if (screeningId.isEmpty) {
      throw Exception('screeningId חסר או ריק');
    }
    if (fieldName.isEmpty) {
      throw Exception('fieldName חסר או ריק');
    }

    final ref = FirebaseFirestore.instance
        .collection('instructor_course_screenings')
        .doc(screeningId);

    // צור את המסמך אם אינו קיים כדי למנוע שגיאת update
    final snap = await ref.get().timeout(const Duration(seconds: 10));
    if (!snap.exists) {
      await ref.set({
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': instructorId,
      }, SetOptions(merge: true));
    }

    // אם יש שדה נעילה במסמך, כבד אותו
    final locked = (snap.data()?['isFinalLocked'] as bool?) ?? false;
    if (locked) {
      throw Exception('שגיאה: הטופס נעול לעריכה');
    }

    await ref.update({
      'fields.$fieldName.value': value,
      'fields.$fieldName.filledBy': instructorId,
      'fields.$fieldName.filledAt': FieldValue.serverTimestamp(),
      'updatedBy': instructorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// עדכון שדה עם היסטוריה (Batch) עבור מסמך מיון
  static Future<void> saveFieldWithHistory({
    required String screeningId,
    required String fieldName,
    required int value,
    required String instructorId,
  }) async {
    if (screeningId.isEmpty) {
      throw Exception('screeningId חסר או ריק');
    }
    if (fieldName.isEmpty) {
      throw Exception('fieldName חסר או ריק');
    }

    final ref = FirebaseFirestore.instance
        .collection('instructor_course_screenings')
        .doc(screeningId);

    // Ensure document exists to avoid update failure
    final snap = await ref.get().timeout(const Duration(seconds: 10));
    if (!snap.exists) {
      await ref.set({
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': instructorId,
      }, SetOptions(merge: true));
    }

    // Respect lock if present
    final locked = (snap.data()?['isFinalLocked'] as bool?) ?? false;
    if (locked) {
      throw Exception('שגיאה: הטופס נעול לעריכה');
    }

    final historyRef = ref.collection('history').doc();
    final batch = FirebaseFirestore.instance.batch();

    // Use set with merge to avoid failures if keys are missing
    batch.set(ref, {
      'fields': {
        fieldName: {
          'value': value,
          'filledBy': instructorId,
          'filledAt': FieldValue.serverTimestamp(),
        },
      },
      'updatedBy': instructorId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(historyRef, {
      'field': fieldName,
      'value': value,
      'action': 'filled',
      'by': instructorId,
      'at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    // אל תשנה סטטוס באופן אוטומטי. סיום משוב חייב להיות מפורש דרך UI.
  }

  // Note: auto-completion removed to require explicit completion via UI.

  /// Admin: set screening lock and optionally status
  static Future<void> setScreeningLock({
    required String screeningId,
    required bool lock,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection('instructor_course_screenings')
        .doc(screeningId);
    await ref.set({
      'isFinalLocked': lock,
      'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (lock) {
      // If locked, ensure status completed (transitional state before classification)
      await ref.set({'status': 'completed'}, SetOptions(merge: true));
    }
  }

  /// Admin: change screening status explicitly
  static Future<void> setScreeningStatus({
    required String screeningId,
    required String status, // 'in_progress' | 'completed'
  }) async {
    final ref = FirebaseFirestore.instance
        .collection('instructor_course_screenings')
        .doc(screeningId);
    await ref.set({
      'status': status,
      'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Finalize a screening: ensure all fields filled, mark completed, and
  /// save ONLY under Resources collections for Instructor Course selection.
  static Future<void> finalizeScreeningAndCreateFeedback({
    required String screeningId,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection('instructor_course_screenings')
        .doc(screeningId);

    final snap = await ref.get().timeout(const Duration(seconds: 10));
    if (!snap.exists) {
      throw Exception('מסמך מיון לא נמצא');
    }
    final data = snap.data() as Map<String, dynamic>;

    // Verify all fields have values
    final fields = (data['fields'] as Map?)?.cast<String, dynamic>() ?? {};
    bool allFilled = true;
    final Map<String, int> scores = {};
    for (final entry in fields.entries) {
      final meta = (entry.value as Map?)?.cast<String, dynamic>() ?? {};
      final v = meta['value'];
      if (v == null) {
        allFilled = false;
        break;
      }
      final intVal = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      scores[entry.key] = intVal;
    }
    if (!allFilled) {
      throw Exception('לא ניתן לסיים: לא כל השדות מולאו');
    }

    // Avoid duplicate finalization
    if ((data['finalFeedbackId'] as String?)?.isNotEmpty == true) {
      // Already finalized; ensure classified status remains consistent
      return;
    }

    // Map Hebrew category names to canonical keys expected by resources pages
    int levelTest = scores['בוחן רמה'] ?? 0;
    int goodInstruction = scores['הדרכה טובה'] ?? 0;
    int structureInstruction = scores['הדרכת מבנה'] ?? 0;
    int dryPractice = scores['יבשים'] ?? 0;
    int surpriseExercise = scores['תרגיל הפתעה'] ?? 0;

    // Compute weighted average score consistent with form page
    const Map<String, double> weights = {
      'levelTest': 0.15,
      'surpriseExercise': 0.25,
      'dryPractice': 0.20,
      'goodInstruction': 0.20,
      'structureInstruction': 0.20,
    };
    double weightedSum = 0.0;
    weightedSum += (levelTest.toDouble()) * (weights['levelTest'] ?? 0.0);
    weightedSum +=
        (surpriseExercise.toDouble()) * (weights['surpriseExercise'] ?? 0.0);
    weightedSum += (dryPractice.toDouble()) * (weights['dryPractice'] ?? 0.0);
    weightedSum +=
        (goodInstruction.toDouble()) * (weights['goodInstruction'] ?? 0.0);
    weightedSum +=
        (structureInstruction.toDouble()) *
        (weights['structureInstruction'] ?? 0.0);

    final averageScore = weightedSum; // 1..5 range
    final isSuitable = averageScore >= 3.6;

    // Build payload for Resources collections
    final instructorName =
        (data['createdByName'] as String?) ??
        FirebaseAuth.instance.currentUser?.email ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';
    final resourcePayload = {
      'createdAt': FieldValue.serverTimestamp(),
      'instructorName': instructorName,
      'instructorId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'candidateName':
          (data['candidateName'] as String?) ??
          (data['title'] as String?) ??
          'מועמד',
      'candidateNumber': (data['candidateNumber'] as num?)?.toInt(),
      'command': (data['command'] as String?) ?? '',
      'brigade': (data['brigade'] as String?) ?? '',
      'averageScore': averageScore,
      'isSuitable': isSuitable,
      'screeningId': screeningId,
      'scores': {
        'levelTest': levelTest,
        'goodInstruction': goodInstruction,
        'structureInstruction': structureInstruction,
        'dryPractice': dryPractice,
        'surpriseExercise': surpriseExercise,
      },
    };

    final collectionPath = isSuitable
        ? 'instructor_course_selection_suitable'
        : 'instructor_course_selection_not_suitable';

    final resRef = await FirebaseFirestore.instance
        .collection(collectionPath)
        .add(resourcePayload);

    // Mark screening completed and link the final resource doc id + category
    await ref.set({
      // Set unified classified status after writing to Resources
      'status': isSuitable ? 'classified_fit' : 'classified_unfit',
      'isFinalLocked': true,
      'finalFeedbackId': resRef.id,
      'finalCategory': isSuitable ? 'suitable' : 'not_suitable',
      'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// ייצוא מאוחד של כל סוגי המשובים ל-Google Sheet קבוע
  /// מקבל רשימת משובים ומפרסם אותם ל-Google Apps Script
  static Future<String?> exportFeedbacksToGoogleSheets({
    required List<FeedbackModel> feedbacks,
  }) async {
    try {
      // Guard: ensure scriptUrl is configured
      if (scriptUrl.isEmpty || scriptUrl.startsWith('YOUR_')) {
        throw Exception(
          'כתובת Google Apps Script אינה מוגדרת. עדכן את scriptUrl בקובץ השירות.',
        );
      }

      if (feedbacks.isEmpty) {
        throw Exception('אין משובים לייצוא');
      }

      // בניית payload מאוחד
      final List<Map<String, dynamic>> unifiedData = [];

      for (final feedback in feedbacks) {
        // בדיקה אם זה משוב מטווחים (יש לו rangeName או attendeesCount > 0)
        final isRangeFeedback =
            feedback.folder == 'מטווחי ירי' || (feedback.attendeesCount > 0);

        if (isRangeFeedback) {
          // משוב מטווחים - צריך לטעון נתונים נוספים מ-Firestore
          final doc = await FirebaseFirestore.instance
              .collection('feedbacks')
              .doc(feedback.id)
              .get();

          if (doc.exists) {
            final data = doc.data()!;
            final stations =
                (data['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final trainees =
                (data['trainees'] as List?)?.cast<Map<String, dynamic>>() ?? [];

            // חישוב סך הכל פגיעות וכדורים
            int totalHits = 0;
            int totalBullets = 0;

            for (final trainee in trainees) {
              totalHits += (trainee['totalHits'] as num?)?.toInt() ?? 0;
            }

            for (final station in stations) {
              totalBullets +=
                  ((station['bulletsCount'] as num?)?.toInt() ?? 0) *
                  trainees.length;
            }

            // יצירת רשומת נתונים מאוחדת למשוב מטווחים
            unifiedData.add({
              'type': 'range',
              'date': feedback.createdAt.toIso8601String(),
              'command': feedback.commandText,
              'brigade': feedback.commandStatus,
              'settlement': feedback.settlement,
              'traineeName': feedback.name,
              'rangeName': feedback.exercise,
              'totalHits': totalHits,
              'totalShots': totalBullets,
              'scores': feedback.scores.map(
                (k, v) => MapEntry(k, v.toString()),
              ),
              'notes': feedback.notes.map((k, v) => MapEntry(k, v)),
            });
          }
        } else {
          // משוב רגיל - יצירת רשומת נתונים מאוחדת
          unifiedData.add({
            'type': 'regular',
            'date': feedback.createdAt.toIso8601String(),
            'command': feedback.commandText,
            'brigade': feedback.commandStatus,
            'settlement': feedback.settlement,
            'traineeName': feedback.name,
            'rangeName': feedback.exercise,
            'totalHits': null,
            'totalShots': null,
            'scores': feedback.scores.map((k, v) => MapEntry(k, v.toString())),
            'notes': feedback.notes.map((k, v) => MapEntry(k, v)),
          });
        }
      }

      // שליחת הנתונים ל-Google Apps Script
      final response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'action': 'exportFeedbacks',
              'data': unifiedData,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('שגיאת שרת: ${response.statusCode} - ${response.body}');
      }

      final responseData = json.decode(response.body);
      final sheetUrl = responseData['sheetUrl'] as String?;

      if (sheetUrl == null || sheetUrl.isEmpty) {
        throw Exception('לא התקבל URL של הגיליון');
      }

      return sheetUrl;
    } catch (e) {
      debugPrint('Error exporting feedbacks: $e');
      rethrow;
    }
  }
}
