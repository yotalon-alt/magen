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

      // גיליון מתאימים
      final suitableSheet = excel['מתאימים'];
      _addInstructorCourseHeaders(suitableSheet);

      // גיליון לא מתאימים
      final notSuitableSheet = excel['לא מתאימים'];
      _addInstructorCourseHeaders(notSuitableSheet);

      // טעינת נתונים משתי הקולקציות
      final suitableFeedbacks = await _loadInstructorCourseFeedbacks(
        'suitable',
      );
      final notSuitableFeedbacks = await _loadInstructorCourseFeedbacks(
        'not_suitable',
      );

      // הוספת נתונים לגיליונות
      for (final feedback in suitableFeedbacks) {
        _addInstructorCourseRow(suitableSheet, feedback);
      }

      for (final feedback in notSuitableFeedbacks) {
        _addInstructorCourseRow(notSuitableSheet, feedback);
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

  /// הוספת כותרות לגיליון משובי קורס מדריכים
  static void _addInstructorCourseHeaders(Sheet sheet) {
    sheet.appendRow([
      TextCellValue('ID'),
      TextCellValue('שם מועמד'),
      TextCellValue('מספר מועמד'),
      TextCellValue('מדריך'),
      TextCellValue('פיקוד'),
      TextCellValue('חטיבה'),
      TextCellValue('בוחן רמה'),
      TextCellValue('הדרכה טובה'),
      TextCellValue('הדרכת מבנה'),
      TextCellValue('יבשים'),
      TextCellValue('תרגיל הפתעה'),
      TextCellValue('ממוצע'),
      TextCellValue('תאריך יצירה'),
    ]);
  }

  /// הוספת שורה של משוב קורס מדריכים
  static void _addInstructorCourseRow(
    Sheet sheet,
    Map<String, dynamic> feedback,
  ) {
    final scores = feedback['scores'] as Map<String, dynamic>? ?? {};
    sheet.appendRow([
      TextCellValue(feedback['id'] ?? ''),
      TextCellValue(feedback['candidateName'] ?? ''),
      IntCellValue(feedback['candidateNumber'] ?? 0),
      TextCellValue(feedback['instructorName'] ?? ''),
      TextCellValue(feedback['command'] ?? ''),
      TextCellValue(feedback['brigade'] ?? ''),
      DoubleCellValue(scores['levelTest']?.toDouble() ?? 0.0),
      DoubleCellValue(scores['goodInstruction']?.toDouble() ?? 0.0),
      DoubleCellValue(scores['structureInstruction']?.toDouble() ?? 0.0),
      DoubleCellValue(scores['dryPractice']?.toDouble() ?? 0.0),
      DoubleCellValue(scores['surpriseExercise']?.toDouble() ?? 0.0),
      DoubleCellValue(feedback['averageScore']?.toDouble() ?? 0.0),
      TextCellValue(feedback['createdAt']?.toString() ?? ''),
    ]);
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
