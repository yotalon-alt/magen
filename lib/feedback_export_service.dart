import 'dart:convert';
import 'dart:io';
import 'package:universal_html/html.dart' as html;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // for feedbackStorage and FeedbackModel

/// שירות ייצוא משובים לקובץ מקומי
/// יוצר קובץ XLSX עם כל המשובים מהאפליקציה
class FeedbackExportService {
  /// ייצוא כל המשובים לקובץ XLSX מקומי
  /// Web: הורדה ישירה לדפדפן
  /// Mobile: שמירה לתיקיית Downloads/Documents
  static Future<void> exportAllFeedbacksToXlsx() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['משובים'];

      // כותרות
      sheet.appendRow([
        TextCellValue('ID'),
        TextCellValue('תפקיד'),
        TextCellValue('שם'),
        TextCellValue('תרגיל'),
        TextCellValue('ציונים'),
        TextCellValue('הערות'),
        TextCellValue('קריטריונים'),
        TextCellValue('תאריך יצירה'),
        TextCellValue('מדריך'),
        TextCellValue('תפקיד מדריך'),
        TextCellValue('טקסט פקודה'),
        TextCellValue('סטטוס פקודה'),
        TextCellValue('תיקייה'),
        TextCellValue('תרחיש'),
        TextCellValue('יישוב'),
        TextCellValue('מספר נוכחים'),
      ]);

      // נתונים
      for (final feedback in feedbackStorage) {
        sheet.appendRow([
          TextCellValue(feedback.id ?? ''),
          TextCellValue(feedback.role),
          TextCellValue(feedback.name),
          TextCellValue(feedback.exercise),
          TextCellValue(json.encode(feedback.scores)),
          TextCellValue(json.encode(feedback.notes)),
          TextCellValue(json.encode(feedback.criteriaList)),
          TextCellValue(feedback.createdAt.toIso8601String()),
          TextCellValue(feedback.instructorName),
          TextCellValue(feedback.instructorRole),
          TextCellValue(feedback.commandText),
          TextCellValue(feedback.commandStatus),
          TextCellValue(feedback.folder),
          TextCellValue(feedback.scenario),
          TextCellValue(feedback.settlement),
          IntCellValue(feedback.attendeesCount),
        ]);
      }

      // שמירה וייצוא
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          'feedbacks_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      if (kIsWeb) {
        // Web: יצירת blob וייצוא דרך browser
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile: שמירה לתיקיית Downloads
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getDownloadsDirectory();
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
        } else {
          throw Exception('פלטפורמה לא נתמכת');
        }

        if (directory == null) {
          throw Exception('לא ניתן לקבל תיקיית שמירה');
        }

        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
      }
    } catch (e) {
      debugPrint('Error exporting to XLSX: $e');
      rethrow;
    }
  }

  /// ייצוא משובי קורס מדריכים לקובץ XLSX עם שני גיליונות
  /// גיליון "מתאימים" וגיליון "לא מתאימים"
  static Future<void> exportInstructorCourseFeedbacksToXlsx() async {
    try {
      final excel = Excel.createExcel();

      // טעינת נתונים משתי הקולקציות
      final suitableFeedbacks = await _loadInstructorCourseFeedbacks(
        'suitable',
      );
      final notSuitableFeedbacks = await _loadInstructorCourseFeedbacks(
        'not_suitable',
      );

      // יצירת גיליון מתאימים עם כותרות דינמיות
      if (suitableFeedbacks.isNotEmpty) {
        final suitableSheet = excel['מתאימים'];
        _addDynamicHeadersAndRows(suitableSheet, suitableFeedbacks);
      }

      // יצירת גיליון לא מתאימים עם כותרות דינמיות
      if (notSuitableFeedbacks.isNotEmpty) {
        final notSuitableSheet = excel['לא מתאימים'];
        _addDynamicHeadersAndRows(notSuitableSheet, notSuitableFeedbacks);
      }

      // שמירה וייצוא
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          'instructor_course_feedbacks_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      if (kIsWeb) {
        // Web: יצירת blob וייצוא דרך browser
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile: שמירה לתיקיית Downloads
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getDownloadsDirectory();
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
        } else {
          throw Exception('פלטפורמה לא נתמכת');
        }

        if (directory == null) {
          throw Exception('לא ניתן לקבל תיקיית שמירה');
        }

        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
      }
    } catch (e) {
      debugPrint('Error exporting instructor course feedbacks to XLSX: $e');
      rethrow;
    }
  }

  /// הוספת כותרות דינמיות ושורות נתונים לגיליון
  static void _addDynamicHeadersAndRows(
    Sheet sheet,
    List<Map<String, dynamic>> feedbacks,
  ) {
    if (feedbacks.isEmpty) return;

    // קביעת כותרות דינמיות על בסיס הנתונים בפועל
    final columnOrder = <String>[];
    final columnSet = <String>{};

    // איסוף כל השדות מכל המשובים
    for (final feedback in feedbacks) {
      for (final key in feedback.keys) {
        if (!columnSet.contains(key)) {
          columnSet.add(key);
          columnOrder.add(key);
        }
      }
    }

    // הוספת כותרות בגיליון
    final headerRow = columnOrder.map((key) => TextCellValue(key)).toList();
    sheet.appendRow(headerRow);

    // הוספת נתונים לכל משוב
    for (final feedback in feedbacks) {
      final row = <CellValue>[];
      for (final key in columnOrder) {
        final value = feedback[key];
        if (value == null) {
          row.add(TextCellValue(''));
        } else if (value is int) {
          row.add(IntCellValue(value));
        } else if (value is double) {
          row.add(DoubleCellValue(value));
        } else if (value is bool) {
          row.add(TextCellValue(value ? 'כן' : 'לא'));
        } else if (value is Map || value is List) {
          // המרת Map/List ל-JSON string
          row.add(TextCellValue(json.encode(value)));
        } else {
          row.add(TextCellValue(value.toString()));
        }
      }
      sheet.appendRow(row);
    }
  }

  /// טעינת משובי קורס מדריכים מקולקציה ספציפית
  static Future<List<Map<String, dynamic>>> _loadInstructorCourseFeedbacks(
    String category,
  ) async {
    final collectionPath = category == 'suitable'
        ? 'instructor_course_selection_suitable'
        : 'instructor_course_selection_not_suitable';

    final snapshot = await FirebaseFirestore.instance
        .collection(collectionPath)
        .orderBy('createdAt', descending: true)
        .get()
        .timeout(const Duration(seconds: 15));

    final feedbacks = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['id'] = doc.id;
      feedbacks.add(data);
    }

    return feedbacks;
  }

  /// ייצוא משובים נבחרים מקורס מדריכים לקובץ XLSX
  static Future<void> exportSelectedInstructorCourseFeedbacksToXlsx(
    List<Map<String, dynamic>> selectedFeedbacks,
    String categoryName,
  ) async {
    try {
      if (selectedFeedbacks.isEmpty) {
        throw Exception('לא נבחרו משובים לייצוא');
      }

      final excel = Excel.createExcel();
      final sheet = excel[categoryName];

      // קביעת כותרות דינמיות על בסיס הנתונים בפועל
      // שימוש בסדר ההופעה של השדות במשוב הראשון כבסיס לסדר העמודות
      final columnOrder = <String>[];
      final columnSet = <String>{};

      // איסוף כל השדות מכל המשובים הנבחרים
      for (final feedback in selectedFeedbacks) {
        for (final key in feedback.keys) {
          if (!columnSet.contains(key)) {
            columnSet.add(key);
            columnOrder.add(key);
          }
        }
      }

      // הוספת כותרות בגיליון
      final headerRow = columnOrder.map((key) => TextCellValue(key)).toList();
      sheet.appendRow(headerRow);

      // הוספת נתונים לכל משוב
      for (final feedback in selectedFeedbacks) {
        final row = <CellValue>[];
        for (final key in columnOrder) {
          final value = feedback[key];
          if (value == null) {
            row.add(TextCellValue(''));
          } else if (value is int) {
            row.add(IntCellValue(value));
          } else if (value is double) {
            row.add(DoubleCellValue(value));
          } else if (value is bool) {
            row.add(TextCellValue(value ? 'כן' : 'לא'));
          } else if (value is Map || value is List) {
            // המרת Map/List ל-JSON string
            row.add(TextCellValue(json.encode(value)));
          } else {
            row.add(TextCellValue(value.toString()));
          }
        }
        sheet.appendRow(row);
      }

      // שמירה וייצוא
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          'instructor_course_feedbacks_${categoryName}_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      if (kIsWeb) {
        // Web: יצירת blob וייצוא דרך browser
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile: שמירה לתיקיית Downloads
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getDownloadsDirectory();
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
        } else {
          throw Exception('פלטפורמה לא נתמכת');
        }

        if (directory == null) {
          throw Exception('לא ניתן לקבל תיקיית שמירה');
        }

        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
      }
    } catch (e) {
      debugPrint(
        'Error exporting selected instructor course feedbacks to XLSX: $e',
      );
      rethrow;
    }
  }

  // Stub methods for screening functionality (to avoid breaking existing code)
  static Future<void> finalizeScreeningAndCreateFeedback({
    required String screeningId,
  }) async {
    // Stub implementation - screening functionality removed
    debugPrint(
      'finalizeScreeningAndCreateFeedback: stub implementation called with screeningId: $screeningId',
    );
  }

  static Future<void> saveFieldWithHistory({
    required String screeningId,
    required String fieldName,
    required dynamic value,
    required String instructorId,
  }) async {
    // Stub implementation - screening functionality removed
    debugPrint(
      'saveFieldWithHistory: stub implementation called with screeningId: $screeningId, fieldName: $fieldName, value: $value, instructorId: $instructorId',
    );
  }

  static Future<void> setScreeningLock({
    required String screeningId,
    required bool lock,
  }) async {
    // Stub implementation - screening functionality removed
    debugPrint(
      'setScreeningLock: stub implementation called with screeningId: $screeningId, lock: $lock',
    );
  }
}
