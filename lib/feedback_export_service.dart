import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:cloud_firestore/cloud_firestore.dart';

/// שירות ייצוא משובים ל-Google Sheets
/// תומך גם במשובים כלליים וגם במשובי מטווחים
class FeedbackExportService {
  // URL של Google Apps Script Web App
  // הערה: יש להחליף ב-URL האמיתי שלך
  static const String scriptUrl = 'YOUR_GOOGLE_APPS_SCRIPT_WEB_APP_URL_HERE';

  /// ייצוא משוב רגיל (לא מטווחים)
  static Future<String?> exportRegularFeedback({
    required BuildContext context,
    required String feedbackId,
  }) async {
    try {
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
    required BuildContext context,
    required String feedbackId,
  }) async {
    try {
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
          (sum, station) => sum + ((station['bulletsCount'] as int?) ?? 0),
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
        (sum, station) => sum + ((station['bulletsCount'] as int?) ?? 0),
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
  static Future<String?> exportFeedback({
    required BuildContext context,
    required String feedbackId,
  }) async {
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
        return await exportRangeFeedback(
          context: context,
          feedbackId: feedbackId,
        );
      } else {
        return await exportRegularFeedback(
          context: context,
          feedbackId: feedbackId,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// ייצוא מרובה של משובים (למשובי מטווחים בעיקר)
  static Future<String?> exportMultipleFeedbacks({
    required BuildContext context,
    required List<dynamic> feedbacks, // List<FeedbackModel>
  }) async {
    try {
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
            (sum, station) => sum + ((station['bulletsCount'] as int?) ?? 0),
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
    required BuildContext context,
    required List<dynamic> feedbacks,
  }) async {
    try {
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
                final stationHits = hits?[i.toString()] ?? 0;
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
}
