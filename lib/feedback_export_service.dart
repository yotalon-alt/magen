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
      sheet.isRTL = true; // Global Hebrew fix: RTL mode

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
        suitableSheet.isRTL = true; // Global Hebrew fix: RTL mode
        _addDynamicHeadersAndRows(suitableSheet, suitableFeedbacks);
      }

      // יצירת גיליון לא מתאימים עם כותרות דינמיות
      if (notSuitableFeedbacks.isNotEmpty) {
        final notSuitableSheet = excel['לא מתאימים'];
        notSuitableSheet.isRTL = true; // Global Hebrew fix: RTL mode
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
    // ✅ CORRECT: Query instructor_course_feedbacks and filter by isSuitable
    final isSuitable = category == 'suitable';
    debugPrint(
      '\n🔍 EXPORT: Loading instructor course feedbacks (suitable=$isSuitable)',
    );

    final snapshot = await FirebaseFirestore.instance
        .collection('instructor_course_feedbacks')
        .where('isSuitable', isEqualTo: isSuitable)
        .where('status', isEqualTo: 'finalized')
        .orderBy('createdAt', descending: true)
        .get()
        .timeout(const Duration(seconds: 15));

    debugPrint('EXPORT: Got ${snapshot.docs.length} documents');

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
      debugPrint(
        '🔵 exportSelectedInstructorCourseFeedbacksToXlsx: Starting export for $categoryName',
      );
      debugPrint('   Selected feedbacks count: ${selectedFeedbacks.length}');

      if (selectedFeedbacks.isEmpty) {
        throw Exception('לא נבחרו משובים לייצוא');
      }

      final excel = Excel.createExcel();
      final sheet = excel[categoryName];
      sheet.isRTL = true; // RTL mode for Hebrew

      debugPrint('   Created XLSX workbook with RTL sheet: $categoryName');

      // Define score columns matching UI structure
      final scoreColumns = <Map<String, String>>[
        {'key': 'levelTest', 'label': 'בוחן רמה'},
        {'key': 'goodInstruction', 'label': 'הדרכה טובה'},
        {'key': 'structureInstruction', 'label': 'הדרכת מבנה'},
        {'key': 'dryPractice', 'label': 'יבשים'},
        {'key': 'surpriseExercise', 'label': 'תרגיל הפתעה'},
      ];

      // Build column headers matching UI (with levelTest expanded to 3 columns)
      final columnOrder = <String>[
        'פיקוד',
        'חטיבה',
        'מספר מועמד',
        'שם מועמד',
        'בוחן רמה',
        'בוחן רמה - פגיעות', // NEW: hits column
        'בוחן רמה - זמן', // NEW: time column
        'הדרכה טובה',
        'הדרכת מבנה',
        'יבשים',
        'תרגיל הפתעה',
        'ממוצע',
        'מדריך',
        'תאריך יצירה',
      ];

      debugPrint('   Column headers: ${columnOrder.join(', ')}');

      // Add header row with RTL alignment
      for (var ci = 0; ci < columnOrder.length; ci++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: 0),
        );
        cell.value = TextCellValue(columnOrder[ci]);
        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Right,
          bold: true,
        );
      }

      // Add data rows
      for (var ri = 0; ri < selectedFeedbacks.length; ri++) {
        final feedback = selectedFeedbacks[ri];
        final rowIndex = ri + 1;

        // Log first row for verification
        if (ri == 0) {
          debugPrint('\n🔍 First row verification:');
          debugPrint('   Candidate: ${feedback['candidateName']}');
          final scores = feedback['scores'] as Map<String, dynamic>?;
          if (scores != null) {
            for (final sc in scoreColumns) {
              debugPrint('   ${sc['label']}: ${scores[sc['key']]}');
            }
          }
          debugPrint('   Average: ${feedback['averageScore']}\n');
        }

        var colIndex = 0;

        // פיקוד
        var cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback['command']?.toString() ?? '');
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // חטיבה
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback['brigade']?.toString() ?? '');
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // מספר מועמד
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = IntCellValue(
          (feedback['candidateNumber'] as num?)?.toInt() ?? 0,
        );
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

        // שם מועמד
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback['candidateName']?.toString() ?? '');
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Score columns (with levelTest expanded to 3 cells)
        final scores = feedback['scores'] as Map<String, dynamic>?;

        // First: בוחן רמה score
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        final levelTestValue = scores?['levelTest'];
        if (levelTestValue is int) {
          cell.value = IntCellValue(levelTestValue);
        } else if (levelTestValue is double) {
          cell.value = DoubleCellValue(levelTestValue);
        } else if (levelTestValue is num) {
          cell.value = IntCellValue(levelTestValue.toInt());
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

        // Second: בוחן רמה - פגיעות
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        final hits = feedback['levelTestHits'];
        if (hits is int) {
          cell.value = IntCellValue(hits);
        } else if (hits is num) {
          cell.value = IntCellValue(hits.toInt());
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

        // Third: בוחן רמה - זמן
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        final timeSeconds = feedback['levelTestTimeSeconds'];
        if (timeSeconds is double) {
          cell.value = DoubleCellValue(timeSeconds);
        } else if (timeSeconds is num) {
          cell.value = DoubleCellValue(timeSeconds.toDouble());
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

        // Rest of score columns (skip levelTest since we already handled it)
        for (final scoreCol in scoreColumns.skip(1)) {
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          final value = scores?[scoreCol['key']];
          if (value is int) {
            cell.value = IntCellValue(value);
          } else if (value is double) {
            cell.value = DoubleCellValue(value);
          } else if (value is num) {
            cell.value = IntCellValue(value.toInt());
          } else {
            cell.value = TextCellValue('');
          }
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
        }

        // ממוצע (average from UI)
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        final averageScore = feedback['averageScore'];
        if (averageScore is double) {
          cell.value = DoubleCellValue(averageScore);
        } else if (averageScore is num) {
          cell.value = DoubleCellValue(averageScore.toDouble());
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

        // מדריך
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(
          feedback['instructorName']?.toString() ?? '',
        );
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // תאריך יצירה
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(_formatDate(feedback['createdAt']));
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
      }

      debugPrint('   Wrote ${selectedFeedbacks.length} data rows');

      // Encode to bytes
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          'מיונים_${categoryName}_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      debugPrint('   Generated filename: $fileName');

      if (kIsWeb) {
        debugPrint('   Platform: Web - downloading via browser');
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        debugPrint('   Platform: Mobile - saving to Downloads');
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
        debugPrint('   Saved to: $filePath');
      }

      debugPrint('✅ Export completed successfully: $fileName');
    } catch (e, stackTrace) {
      debugPrint(
        '❌ Error in exportSelectedInstructorCourseFeedbacksToXlsx: $e',
      );
      debugPrint('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Shared mapper: Transform instructor_course_evaluations doc to export-ready format
  /// This function replicates the exact logic from instructor_course_selection_feedbacks_page's _loadFeedbacks
  /// to ensure bulk export produces identical data to single export
  static Future<Map<String, dynamic>> mapInstructorScreeningDocToExportRow(
    DocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> result = Map<String, dynamic>.from(data);
    result['id'] = doc.id;

    // ✅ RESOLVE INSTRUCTOR NAME (never export email)
    final createdByUid = data['createdBy'] ?? data['createdByUid'];
    final createdByName = data['createdByName'] as String?;
    String instructorName = 'לא ידוע';

    if (createdByUid != null && createdByUid.toString().isNotEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(createdByUid.toString())
            .get()
            .timeout(const Duration(seconds: 3));
        if (userDoc.exists) {
          final userData = userDoc.data();
          final displayName = userData?['displayName'] as String?;
          final fullName = userData?['fullName'] as String?;
          final name = userData?['name'] as String?;

          if (displayName != null && displayName.isNotEmpty) {
            instructorName = displayName;
          } else if (fullName != null && fullName.isNotEmpty) {
            instructorName = fullName;
          } else if (name != null && name.isNotEmpty) {
            instructorName = name;
          } else {
            instructorName =
                'מדריך ${createdByUid.toString().substring(0, 8)}...';
          }
        } else {
          instructorName =
              'מדריך ${createdByUid.toString().substring(0, 8)}...';
        }
      } catch (e) {
        debugPrint(
          '⚠️ Failed to fetch instructor name for UID $createdByUid: $e',
        );
        instructorName = 'מדריך ${createdByUid.toString().substring(0, 8)}...';
      }
    } else if (createdByName != null && createdByName.isNotEmpty) {
      instructorName = createdByName;
    }
    result['instructorName'] = instructorName;

    // ✅ COMPUTE AVERAGE SCORE from fields structure (same logic as _loadFeedbacks)
    final fields = data['fields'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> scores = {};
    double totalScore = 0.0;
    int scoreCount = 0;

    // Map Hebrew category names to English keys (must match UI expectations)
    final categoryMapping = {
      'בוחן רמה': 'levelTest',
      'הדרכה טובה': 'goodInstruction',
      'הדרכת מבנה': 'structureInstruction',
      'יבשים': 'dryPractice',
      'תרגיל הפתעה': 'surpriseExercise',
    };

    fields.forEach((hebrewName, fieldData) {
      if (fieldData is Map && fieldData.containsKey('value')) {
        final value = fieldData['value'];
        final numValue = (value is num) ? value.toDouble() : 0.0;

        final englishKey = categoryMapping[hebrewName];
        if (englishKey != null) {
          scores[englishKey] = numValue;
          if (numValue > 0) {
            totalScore += numValue;
            scoreCount++;
          }
        }
      }
    });

    final averageScore = scoreCount > 0 ? totalScore / scoreCount : 0.0;
    result['scores'] = scores;
    result['averageScore'] = averageScore;

    return result;
  }

  /// Helper method to format date from Firestore Timestamp or string
  static String _formatDate(dynamic date) {
    if (date is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(date.toDate());
    } else if (date is String) {
      final parsed = DateTime.tryParse(date);
      if (parsed != null) {
        return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
      }
      return date;
    } else if (date is DateTime) {
      return DateFormat('yyyy-MM-dd HH:mm').format(date);
    }
    return '';
  }

  /// Returns a mapper function for a given folder name.
  static Map<String, dynamic> getMapperForFolder(String folderName) {
    // Example implementation: customize based on folder-specific logic
    switch (folderName) {
      case 'מטווחי ירי':
        return {
          'id': 'ID',
          'role': 'תפקיד',
          'name': 'שם',
          'exercise': 'תרגיל',
          'scores': 'ציונים',
          'notes': 'הערות',
          'criteriaList': 'קריטריונים',
          'createdAt': 'תאריך יצירה',
          'instructorName': 'מדריך',
          'instructorRole': 'תפקיד מדריך',
          'folder': 'תיקייה',
        };
      default:
        return {
          'id': 'ID',
          'role': 'תפקיד',
          'name': 'שם',
          'exercise': 'תרגיל',
          'createdAt': 'תאריך יצירה',
        };
    }
  }

  /// Exports feedbacks to an XLSX file using a provided mapper.
  static Future<void> exportFeedbacksToXlsx(
    List<FeedbackModel> feedbacks,
    Map<String, dynamic> mapper,
    String fileNamePrefix,
  ) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['משובים'];
      sheet.isRTL = true; // Global Hebrew fix: RTL mode

      // Add headers based on the mapper
      final headers = mapper.values
          .map((header) => TextCellValue(header))
          .toList();
      sheet.appendRow(headers);

      // Add rows based on the mapper
      for (final feedback in feedbacks) {
        final row = mapper.keys.map((key) {
          final value = feedback.toJson()[key];
          if (value == null) {
            return TextCellValue('');
          } else if (value is int) {
            return IntCellValue(value);
          } else if (value is double) {
            return DoubleCellValue(value);
          } else {
            return TextCellValue(value.toString());
          }
        }).toList();
        sheet.appendRow(row);
      }

      // Save and export
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          '${fileNamePrefix}_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
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
      debugPrint('Error exporting feedbacks to XLSX: $e');
      rethrow;
    }
  }

  /// Generic export function where each page provides the exact column keys
  /// and header labels. This enforces that exported columns come from the
  /// page configuration (not inferred from data) and that single-feedback
  /// and multi-feedback exports use the same code path.
  static Future<void> exportWithSchema({
    required List<String> keys,
    required List<String> headers,
    required List<FeedbackModel> feedbacks,
    required String fileNamePrefix,
  }) async {
    try {
      if (keys.length != headers.length) {
        throw Exception('keys and headers length mismatch');
      }
      final excel = Excel.createExcel();
      final sheet = excel['משובים'];
      sheet.isRTL = true; // Global Hebrew fix: RTL mode

      // Add creation metadata columns at the beginning
      final metadataKeys = ['createdAt', 'createdByName'];
      final metadataHeaders = ['תאריך', 'מדריך'];

      // Filter out internal identifiers or codes from exported columns
      final filteredPairs = <MapEntry<String, String>>[];

      // Add metadata columns first
      for (var i = 0; i < metadataKeys.length; i++) {
        filteredPairs.add(MapEntry(metadataKeys[i], metadataHeaders[i]));
      }

      // Then add user-specified columns (excluding duplicates and internal IDs)
      for (var i = 0; i < keys.length; i++) {
        final k = keys[i];
        final h = headers[i];
        final kl = k.toLowerCase();

        // Skip metadata fields if already added
        if (metadataKeys.contains(k)) {
          continue;
        }

        // skip internal ids/codes/shortcuts
        if (kl == 'id' ||
            kl.endsWith('id') ||
            kl.contains('code') ||
            kl.contains('shortcut')) {
          continue;
        }
        filteredPairs.add(MapEntry(k, h));
      }

      if (filteredPairs.isEmpty) {
        throw Exception('לא נותרו עמודות לייצוא לאחר סינון מזהים פנימיים');
      }

      // Helper to format values into human-readable Hebrew-friendly strings
      String formatValue(dynamic value) {
        if (value == null) return '';
        if (value is Map) {
          final parts = <String>[];
          (value).forEach((key, val) {
            parts.add('${key.toString()}: ${val.toString()}');
          });
          return parts.join(' ; ');
        }
        if (value is List) {
          return value.map((e) => e.toString()).join(' , ');
        }
        return value.toString();
      }

      // Write header row explicitly so we can control alignment (RTL)
      int currentRow = 0;
      for (var ci = 0; ci < filteredPairs.length; ci++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: currentRow),
        );
        cell.value = TextCellValue(
          filteredPairs[ci].value,
        ); // header label (Hebrew expected)
        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Right,
          bold: true,
        );
      }

      // Add rows in the same column order for every feedback
      for (var i = 0; i < feedbacks.length; i++) {
        final feedback = feedbacks[i];
        // Base JSON from model
        final Map<String, dynamic> baseJson = feedback.toJson();

        // Attempt to fetch full Firestore doc to get nested tables (stations/trainees)
        Map<String, dynamic>? fullDoc;
        if (feedback.id != null && feedback.id!.isNotEmpty) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('feedbacks')
                .doc(feedback.id)
                .get();
            if (doc.exists) {
              fullDoc = Map<String, dynamic>.from(doc.data() as Map);
            }
          } catch (e) {
            // ignore fetch errors; fall back to baseJson
            debugPrint('Could not fetch full doc for export: $e');
          }
        }

        final merged = <String, dynamic>{};
        merged.addAll(baseJson);
        if (fullDoc != null) {
          // prefer Firestore-stored nested fields where present
          for (final k in fullDoc.keys) {
            if (!merged.containsKey(k) ||
                fullDoc[k] is! Map && fullDoc[k] is! List) {
              merged[k] = fullDoc[k];
            } else {
              // override nested lists/maps from Firestore
              merged[k] = fullDoc[k];
            }
          }
        }

        // write row values using filteredPairs order
        currentRow += 1;
        for (var ci = 0; ci < filteredPairs.length; ci++) {
          final key = filteredPairs[ci].key;
          var rawValue = merged[key];

          // Special handling for creation metadata
          if (key == 'createdAt') {
            // Format date as dd/MM/yyyy HH:mm
            if (rawValue is Timestamp) {
              final dt = rawValue.toDate();
              rawValue = DateFormat('dd/MM/yyyy HH:mm').format(dt);
            } else if (rawValue is String) {
              try {
                final dt = DateTime.parse(rawValue);
                rawValue = DateFormat('dd/MM/yyyy HH:mm').format(dt);
              } catch (e) {
                rawValue = ''; // Invalid date
              }
            } else {
              rawValue = ''; // Missing date
            }
          } else if (key == 'createdByName') {
            // Fallback chain: createdByName -> instructorName -> createdByUid -> instructorId
            rawValue ??=
                merged['instructorName'] ??
                merged['createdByUid'] ??
                merged['instructorId'] ??
                '';
          }

          final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: currentRow),
          );

          if (rawValue == null) {
            cell.value = TextCellValue('');
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
          } else if (rawValue is int) {
            cell.value = IntCellValue(rawValue);
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
          } else if (rawValue is double) {
            cell.value = DoubleCellValue(rawValue);
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
          } else if (rawValue is bool) {
            cell.value = TextCellValue(rawValue ? 'כן' : 'לא');
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
          } else if (rawValue is Map || rawValue is List) {
            cell.value = TextCellValue(formatValue(rawValue));
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
          } else {
            cell.value = TextCellValue(rawValue.toString());
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
          }
        }

        // If we have nested tables, add dedicated sheets per feedback for clarity
        if (fullDoc != null) {
          // Trainees table
          final trainees = fullDoc['trainees'] as List<dynamic>?;
          final stations = fullDoc['stations'] as List<dynamic>?;
          if (trainees != null && trainees.isNotEmpty) {
            final tSheetName = 'trainees_${i + 1}';
            final tSheet = excel[tSheetName];
            tSheet.isRTL = true; // Global Hebrew fix: RTL mode

            // Build headers: Name, Number, per-station headers, TotalHits
            final stationNames = <String>[];
            if (stations != null) {
              for (final s in stations) {
                final map = Map<String, dynamic>.from(s as Map);
                stationNames.add(map['name']?.toString() ?? 'מקצה');
              }
            }
            final tHeaders = <String>[
              'שם',
              'מספר',
              ...stationNames,
              'סך פגיעות',
            ];

            // write trainee header
            for (var ci = 0; ci < tHeaders.length; ci++) {
              final cell = tSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: 0),
              );
              cell.value = TextCellValue(tHeaders[ci]);
              cell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Right,
                bold: true,
              );
            }

            // write trainee rows
            for (var ti = 0; ti < trainees.length; ti++) {
              final tr = Map<String, dynamic>.from(trainees[ti] as Map);
              final number = tr['number']?.toString() ?? '${ti + 1}';
              final name = tr['name']?.toString() ?? '';
              final hitsMap = <int, int>{};
              final rawHits = tr['hits'] as Map? ?? {};
              rawHits.forEach((k, v) {
                if (k is String && k.startsWith('station_')) {
                  final idx =
                      int.tryParse(k.replaceFirst('station_', '')) ?? -1;
                  if (idx >= 0) hitsMap[idx] = (v as num?)?.toInt() ?? 0;
                } else if (k is int) {
                  hitsMap[k] = (v as num?)?.toInt() ?? 0;
                }
              });

              final rowIndex = ti + 1; // header at row 0
              // Name (column 0)
              final nameCell = tSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
              );
              nameCell.value = TextCellValue(name);
              nameCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Right,
              );

              // Number (column 1)
              final numCell = tSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
              );
              final parsedNum = int.tryParse(number);
              if (parsedNum != null) {
                numCell.value = IntCellValue(parsedNum);
              } else {
                numCell.value = TextCellValue(number);
              }
              numCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Center,
              );

              // per-station values
              for (var si = 0; si < stationNames.length; si++) {
                final hv = hitsMap[si] ?? 0;
                final c = tSheet.cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: si + 2,
                    rowIndex: rowIndex,
                  ),
                );
                c.value = IntCellValue(hv);
                c.cellStyle = CellStyle(
                  horizontalAlign: HorizontalAlign.Center,
                );
              }

              final totalHits =
                  tr['totalHits'] ??
                  hitsMap.values.fold<int>(0, (p, n) => p + n);
              final totalCell = tSheet.cell(
                CellIndex.indexByColumnRow(
                  columnIndex: 2 + stationNames.length,
                  rowIndex: rowIndex,
                ),
              );
              totalCell.value = IntCellValue((totalHits as num?)?.toInt() ?? 0);
              totalCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Center,
              );
            }
          }

          // Stations table (if present)
          if (stations != null && stations.isNotEmpty) {
            final sSheetName = 'stations_${i + 1}';
            final sSheet = excel[sSheetName];
            sSheet.isRTL = true; // Global Hebrew fix: RTL mode
            final sHeaders = [
              'מקצה',
              'כדורים',
              'זמן_שניות',
              'ידני',
              'בודק רמה',
            ];
            // write station headers
            for (var ci = 0; ci < sHeaders.length; ci++) {
              final cell = sSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: 0),
              );
              cell.value = TextCellValue(sHeaders[ci]);
              cell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Right,
                bold: true,
              );
            }
            for (var si = 0; si < stations.length; si++) {
              final s = Map<String, dynamic>.from(stations[si] as Map);
              final rowIndex = si + 1;
              final nameCell = sSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
              );
              nameCell.value = TextCellValue(s['name']?.toString() ?? '');
              nameCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Right,
              );

              final bulletsCell = sSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
              );
              bulletsCell.value = IntCellValue(
                (s['bulletsCount'] as num?)?.toInt() ?? 0,
              );
              bulletsCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Center,
              );

              final timeCell = sSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
              );
              timeCell.value = IntCellValue(
                (s['timeSeconds'] as num?)?.toInt() ?? 0,
              );
              timeCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Center,
              );

              final manualCell = sSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
              );
              manualCell.value = TextCellValue(
                (s['isManual'] as bool?) == true ? 'כן' : 'לא',
              );
              manualCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Right,
              );

              final levelCell = sSheet.cell(
                CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
              );
              levelCell.value = TextCellValue(
                (s['isLevelTester'] as bool?) == true ? 'כן' : 'לא',
              );
              levelCell.cellStyle = CellStyle(
                horizontalAlign: HorizontalAlign.Right,
              );
            }
          }
        }
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) throw Exception('שגיאה ביצירת קובץ XLSX');

      final now = DateTime.now();
      final fileName =
          '${fileNamePrefix}_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getDownloadsDirectory();
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
        } else {
          throw Exception('פלטפורמה לא נתמכת');
        }

        if (directory == null) throw Exception('לא ניתן לקבל תיקיית שמירה');

        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
      }
    } catch (e) {
      debugPrint('Error exporting with schema to XLSX: $e');
      rethrow;
    }
  }

  /// Exports statistics to an XLSX file.
  static Future<void> exportStatisticsToXlsx(
    List<Map<String, dynamic>> statistics,
    String fileName,
  ) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['סטטיסטיקות'];
      sheet.isRTL = true; // Global Hebrew fix: RTL mode

      // Add headers dynamically based on the first statistic entry
      if (statistics.isNotEmpty) {
        final headers = statistics.first.keys
            .map((key) => TextCellValue(key))
            .toList();
        sheet.appendRow(headers);

        // Add rows for each statistic entry
        for (final stat in statistics) {
          final row = stat.values.map((value) {
            if (value == null) {
              return TextCellValue('');
            } else if (value is int) {
              return IntCellValue(value);
            } else if (value is double) {
              return DoubleCellValue(value);
            } else {
              return TextCellValue(value.toString());
            }
          }).toList();
          sheet.appendRow(row);
        }
      }

      // Save and export
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
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
      debugPrint('Error exporting statistics to XLSX: $e');
      rethrow;
    }
  }

  /// Exports reporter/range comparison data to Google Sheets format
  /// Specifically designed for range feedback with trainees and stations (drills)
  static Future<void> exportReporterComparisonToGoogleSheets({
    required Map<String, dynamic> feedbackData,
    required String fileNamePrefix,
  }) async {
    try {
      // Extract metadata from feedback
      final settlement = feedbackData['settlement']?.toString() ?? '';
      final createdAt = feedbackData['createdAt'];
      final createdByName =
          feedbackData['createdByName']?.toString() ??
          feedbackData['instructorName']?.toString() ??
          '';
      final feedbackDate = createdAt is Timestamp
          ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
          : createdAt is String
          ? DateFormat(
              'dd/MM/yyyy HH:mm',
            ).format(DateTime.tryParse(createdAt) ?? DateTime.now())
          : DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      // Extract stations (drills) and trainees
      final stations =
          (feedbackData['stations'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      final trainees =
          (feedbackData['trainees'] as List?)?.cast<Map<String, dynamic>>() ??
          [];

      if (stations.isEmpty || trainees.isEmpty) {
        throw Exception('אין נתוני מקצים או חניכים לייצוא');
      }

      final excel = Excel.createExcel();
      final sheet = excel['השוואת מטווחים'];
      sheet.isRTL = true; // Global Hebrew fix: RTL mode

      // Row 0: Creation metadata
      var cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      );
      cell.value = TextCellValue('תאריך');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0),
      );
      cell.value = TextCellValue(feedbackDate);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0),
      );
      cell.value = TextCellValue('מדריך');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0),
      );
      cell.value = TextCellValue(createdByName);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Row 1: Headers - "יישוב", "שם", then drill names (with time for בוחן רמה)
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      );
      cell.value = TextCellValue('יישוב');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1),
      );
      cell.value = TextCellValue('שם');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      // Build column mapping for stations (track which columns have time)
      final List<Map<String, dynamic>> stationColumns = [];
      int currentColumn = 2;

      // Add drill names to row 1 (columns C onward)
      // For בוחן רמה stations, add both hits and time columns
      for (var si = 0; si < stations.length; si++) {
        final station = stations[si];
        final stationName = station['name']?.toString() ?? 'מקצה ${si + 1}';
        final isLevelTester = station['isLevelTester'] == true;

        // Hits column
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: currentColumn, rowIndex: 1),
        );
        cell.value = TextCellValue(stationName);
        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Right,
          bold: true,
        );

        stationColumns.add({
          'stationIndex': si,
          'hitsColumn': currentColumn,
          'hasTime': isLevelTester,
        });

        currentColumn++;

        // Time column for בוחן רמה
        if (isLevelTester) {
          cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: currentColumn, rowIndex: 1),
          );
          cell.value = TextCellValue('$stationName - זמן');
          cell.cellStyle = CellStyle(
            horizontalAlign: HorizontalAlign.Right,
            bold: true,
          );

          stationColumns[stationColumns.length - 1]['timeColumn'] =
              currentColumn;
          currentColumn++;
        }
      }

      // NEW: Add two new columns at the end of row 1: "סה״כ פגיעות חניך" and "ממוצע חניך"
      final totalHitsColumnIndex = currentColumn;
      final avgColumnIndex = currentColumn + 1;

      cell = sheet.cell(
        CellIndex.indexByColumnRow(
          columnIndex: totalHitsColumnIndex,
          rowIndex: 1,
        ),
      );
      cell.value = TextCellValue('סה״כ פגיעות חניך');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: avgColumnIndex, rowIndex: 1),
      );
      cell.value = TextCellValue('ממוצע חניך');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      // Row 2: "כדורים לחניך" - bullets per trainee for each drill
      // Columns A and B are empty in row 2
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
      );
      cell.value = TextCellValue('');
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2),
      );
      cell.value = TextCellValue('');
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // For each drill column, write the bullets per trainee for THAT drill
      // For time columns (בוחן רמה), leave empty
      for (final stationCol in stationColumns) {
        final si = stationCol['stationIndex'] as int;
        final hitsColumn = stationCol['hitsColumn'] as int;
        final hasTime = stationCol['hasTime'] as bool;

        final station = stations[si];
        final bulletsCount = (station['bulletsCount'] as num?)?.toInt() ?? 0;

        // Bullets in hits column
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: hitsColumn, rowIndex: 2),
        );
        cell.value = IntCellValue(bulletsCount);
        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Right,
          italic: true,
        );

        // Leave time column empty
        if (hasTime) {
          final timeColumn = stationCol['timeColumn'] as int;
          cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: timeColumn, rowIndex: 2),
          );
          cell.value = TextCellValue('');
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
        }
      }

      // Rows 4+: Trainee data (row 0 = metadata, row 1 = headers, row 2 = bullets, row 3+ = data)
      int overallTotalHits = 0; // Track overall total for summary row

      for (var ti = 0; ti < trainees.length; ti++) {
        final trainee = trainees[ti];
        final traineeName = trainee['name']?.toString() ?? 'חניך ${ti + 1}';
        final hitsMap = trainee['hits'] as Map<String, dynamic>? ?? {};
        final timeValuesMap =
            trainee['timeValues'] as Map<String, dynamic>? ?? {};

        final rowIndex =
            ti +
            3; // Row 0 = metadata, Row 1 = headers, Row 2 = bullets, data starts at row 3

        // Column A: Settlement
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        );
        cell.value = TextCellValue(settlement);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Column B: Trainee Name
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
        );
        cell.value = TextCellValue(traineeName);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Columns C+: Hits for each drill (numbers only), plus time for בוחן רמה
        // Also compute total hits and count stages for average
        int traineeTotalHits = 0;
        int stagesWithHits = 0;

        for (final stationCol in stationColumns) {
          final si = stationCol['stationIndex'] as int;
          final hitsColumn = stationCol['hitsColumn'] as int;
          final hasTime = stationCol['hasTime'] as bool;

          // Get hits for this station from trainee record
          final hits = (hitsMap['station_$si'] as num?)?.toInt();

          // Hits column
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: hitsColumn,
              rowIndex: rowIndex,
            ),
          );

          if (hits != null && hits > 0) {
            cell.value = IntCellValue(hits);
            traineeTotalHits += hits;
            stagesWithHits++;
          } else {
            // Leave blank if missing data
            cell.value = TextCellValue('');
          }
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

          // Time column for בוחן רמה
          if (hasTime) {
            final timeColumn = stationCol['timeColumn'] as int;
            final timeInSeconds =
                (timeValuesMap['station_${si}_time'] as num?)?.toInt() ?? 0;

            cell = sheet.cell(
              CellIndex.indexByColumnRow(
                columnIndex: timeColumn,
                rowIndex: rowIndex,
              ),
            );

            if (timeInSeconds > 0) {
              cell.value = TextCellValue('${timeInSeconds}s');
            } else {
              cell.value = TextCellValue('');
            }
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
          }
        }

        // NEW: Add סה״כ פגיעות חניך column
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: totalHitsColumnIndex,
            rowIndex: rowIndex,
          ),
        );
        cell.value = IntCellValue(traineeTotalHits);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // NEW: Add ממוצע חניך column
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: avgColumnIndex,
            rowIndex: rowIndex,
          ),
        );
        if (stagesWithHits > 0) {
          final traineeAverage = traineeTotalHits / stagesWithHits;
          // Round to 2 decimal places
          cell.value = DoubleCellValue(
            double.parse(traineeAverage.toStringAsFixed(2)),
          );
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Track overall total
        overallTotalHits += traineeTotalHits;
      }

      // NEW: Add summary row at the bottom
      final summaryRowIndex = 3 + trainees.length;

      // First column: "סה״כ פגיעות (כל החניכים)"
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: summaryRowIndex),
      );
      cell.value = TextCellValue('סה״כ פגיעות (כל החניכים)');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      // Leave columns B through stations.length empty
      for (var colIdx = 1; colIdx < totalHitsColumnIndex; colIdx++) {
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIdx,
            rowIndex: summaryRowIndex,
          ),
        );
        cell.value = TextCellValue('');
      }

      // סה״כ פגיעות חניך column: overallTotalHits
      cell = sheet.cell(
        CellIndex.indexByColumnRow(
          columnIndex: totalHitsColumnIndex,
          rowIndex: summaryRowIndex,
        ),
      );
      cell.value = IntCellValue(overallTotalHits);
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      // ממוצע חניך column: leave blank in summary
      cell = sheet.cell(
        CellIndex.indexByColumnRow(
          columnIndex: avgColumnIndex,
          rowIndex: summaryRowIndex,
        ),
      );
      cell.value = TextCellValue('');
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // ✅ Add "סה״כ כדורים שנורו" row below summary (for both short and long range)
      final bulletsRowIndex = summaryRowIndex + 1;

      // Calculate total bullets fired
      int totalBulletsFired = 0;
      for (final station in stations) {
        final bulletsTracking = (station['bulletsCount'] as num?)?.toInt() ?? 0;
        totalBulletsFired += bulletsTracking * trainees.length;
      }

      // First column: "סה״כ כדורים שנורו"
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: bulletsRowIndex),
      );
      cell.value = TextCellValue('סה״כ כדורים שנורו');
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      // Leave columns B through stations.length empty
      for (var colIdx = 1; colIdx < totalHitsColumnIndex; colIdx++) {
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIdx,
            rowIndex: bulletsRowIndex,
          ),
        );
        cell.value = TextCellValue('');
      }

      // סה״כ פגיעות חניך column: total bullets
      cell = sheet.cell(
        CellIndex.indexByColumnRow(
          columnIndex: totalHitsColumnIndex,
          rowIndex: bulletsRowIndex,
        ),
      );
      cell.value = IntCellValue(totalBulletsFired);
      cell.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Right,
        bold: true,
      );

      // ממוצע חניך column: leave blank
      cell = sheet.cell(
        CellIndex.indexByColumnRow(
          columnIndex: avgColumnIndex,
          rowIndex: bulletsRowIndex,
        ),
      );
      cell.value = TextCellValue('');
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Encode and export
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      // Filename: "מטווחים - <יישוב> - <YYYY-MM-DD>.xlsx"
      final fileName = 'מטווחים - $settlement - $feedbackDate.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
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
      debugPrint('Error exporting reporter comparison to Google Sheets: $e');
      rethrow;
    }
  }

  /// NEW: Export SINGLE feedback details from "פרטי משוב" screen
  /// Applies ONLY to standard feedbacks (NOT ranges or miunim)
  /// This is the dedicated export for the feedback details view
  ///
  /// Structure:
  /// 1. Mandatory columns: סוג משוב, שם המדריך המשב, שם, תפקיד, חטיבה, יישוב, תאריך
  /// 2. Criteria columns: ONLY criteria that exist in THIS feedback instance (numeric scores)
  /// 3. Average column: ציון ממוצע (calculated from selected criteria only)
  /// 4. Comments column: הערות (combined from all criteria notes)
  static Future<void> exportSingleFeedbackDetails({
    required FeedbackModel feedback,
    required String fileNamePrefix,
  }) async {
    try {
      debugPrint('🔵 exportSingleFeedbackDetails called');
      debugPrint('   Feedback: ${feedback.name} (${feedback.exercise})');

      final excel = Excel.createExcel();
      final sheet = excel['משוב'];
      sheet.isRTL = true; // Global Hebrew fix: RTL mode

      // Get only the criteria that exist in THIS feedback
      final feedbackCriteria = feedback.criteriaList;
      debugPrint('   Criteria in this feedback: $feedbackCriteria');

      // Build header row - exact order as specified
      final headers = <String>[
        'תאריך',
        'מדריך',
        'סוג משוב',
        'שם המדריך המשב',
        'שם',
        'תפקיד',
        'חטיבה',
        'יישוב',
        ...feedbackCriteria,
        'ציון ממוצע',
        'הערות',
      ];

      debugPrint('   Headers array: $headers');

      // Write header row with RTL alignment
      for (var ci = 0; ci < headers.length; ci++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: 0),
        );
        cell.value = TextCellValue(headers[ci]);
        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Right,
          bold: true,
        );
      }

      // Write data row
      final rowIndex = 1;
      var colIndex = 0;

      // Column 1: תאריך (formatted date)
      var cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(feedback.createdAt);
      cell.value = TextCellValue(dateStr);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Column 2: מדריך (instructor name or fallback)
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(feedback.instructorName);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Column 3: סוג משוב (exercise)
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(feedback.exercise);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Column 4: שם המדריך המשב
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(feedback.instructorName);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Column 5: שם
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(feedback.name);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Column 6: תפקיד
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(feedback.role);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Column 7: חטיבה (from instructorRole or folder)
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(feedback.instructorRole);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Column 8: יישוב
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(feedback.settlement);
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Criteria columns: numeric scores only for THIS feedback's criteria
      final criteriaScores = <int>[];
      for (final criterion in feedbackCriteria) {
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );

        final score = feedback.scores[criterion] ?? 0;
        if (score > 0) {
          cell.value = IntCellValue(score);
          criteriaScores.add(score);
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
      }

      // Average column: calculated only from criteria with scores
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      if (criteriaScores.isNotEmpty) {
        final avg =
            criteriaScores.reduce((a, b) => a + b) / criteriaScores.length;
        cell.value = DoubleCellValue(double.parse(avg.toStringAsFixed(1)));
      } else {
        cell.value = TextCellValue('');
      }
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

      // Comments column: combined from all criteria notes
      cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex),
      );
      final allNotes = <String>[];
      for (final criterion in feedbackCriteria) {
        final note = feedback.notes[criterion];
        if (note != null && note.trim().isNotEmpty) {
          allNotes.add('$criterion: $note');
        }
      }
      cell.value = TextCellValue(allNotes.join('; '));
      cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

      // Encode and export
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          '${fileNamePrefix}_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      debugPrint('   Exporting file: $fileName');

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
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

      debugPrint('✅ Export completed successfully');
    } catch (e) {
      debugPrint('❌ Error in exportSingleFeedbackDetails: $e');
      rethrow;
    }
  }

  /// NEW: Export standard feedbacks with specific column structure
  /// Applies ONLY to feedback contexts (NOT ranges or miunim):
  /// - "שער המשובים", "משובים כלליים", "משובי מחלקות ההגנה", "עבודה במבנה"
  ///
  /// Structure:
  /// - Mandatory columns: סוג משוב, שם המדריך המשב, שם, תפקיד, חטיבה, יישוב, תאריך
  /// - Criteria columns: Only selected criteria, numeric scores only
  /// - Average column: ציון ממוצע (calculated from selected criteria)
  /// - Comments column: הערות (empty if none)
  static Future<void> exportStandardFeedbacks({
    required List<FeedbackModel> feedbacks,
    required String fileNamePrefix,
  }) async {
    try {
      if (feedbacks.isEmpty) {
        throw Exception('אין משובים לייצוא');
      }

      final excel = Excel.createExcel();
      final sheet = excel['משובים'];
      sheet.isRTL = true; // Global Hebrew fix: RTL mode

      // Collect all criteria that appear across all feedbacks
      final allCriteriaSet = <String>{};
      for (final feedback in feedbacks) {
        allCriteriaSet.addAll(feedback.criteriaList);
      }
      final allCriteria = allCriteriaSet.toList()..sort();

      // Build header row
      final headers = <String>[
        'סוג משוב',
        'שם המדריך המשב',
        'שם',
        'תפקיד',
        'חטיבה',
        'יישוב',
        'תאריך',
        ...allCriteria,
        'ציון ממוצע',
        'הערות',
      ];

      // Write header row with RTL alignment
      for (var ci = 0; ci < headers.length; ci++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: 0),
        );
        cell.value = TextCellValue(headers[ci]);
        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Right,
          bold: true,
        );
      }

      // Write data rows
      for (var ri = 0; ri < feedbacks.length; ri++) {
        final feedback = feedbacks[ri];
        final rowIndex = ri + 1;
        var colIndex = 0;

        // Column 1: סוג משוב (exercise/folder)
        var cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback.exercise);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Column 2: שם המדריך המשב
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback.instructorName);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Column 3: שם
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback.name);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Column 4: תפקיד
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback.role);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Column 5: חטיבה (from instructorRole or folder)
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback.instructorRole);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Column 6: יישוב
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        cell.value = TextCellValue(feedback.settlement);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Column 7: תאריך
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        final dateStr = DateFormat('yyyy-MM-dd').format(feedback.createdAt);
        cell.value = TextCellValue(dateStr);
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

        // Criteria columns: Only export selected criteria with numeric scores
        final selectedScores = <int>[];
        for (final criterion in allCriteria) {
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );

          if (feedback.criteriaList.contains(criterion)) {
            final score = feedback.scores[criterion] ?? 0;
            if (score > 0) {
              cell.value = IntCellValue(score);
              selectedScores.add(score);
            } else {
              cell.value = TextCellValue('');
            }
          } else {
            cell.value = TextCellValue('');
          }
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
        }

        // Average column: calculated only from selected criteria
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        if (selectedScores.isNotEmpty) {
          final avg =
              selectedScores.reduce((a, b) => a + b) / selectedScores.length;
          cell.value = DoubleCellValue(double.parse(avg.toStringAsFixed(1)));
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

        // Comments column: הערות (collect from all criteria notes)
        cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex++,
            rowIndex: rowIndex,
          ),
        );
        final allNotes = <String>[];
        for (final criterion in feedback.criteriaList) {
          final note = feedback.notes[criterion];
          if (note != null && note.trim().isNotEmpty) {
            allNotes.add('$criterion: $note');
          }
        }
        cell.value = TextCellValue(allNotes.join('; '));
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
      }

      // Encode and export
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          '${fileNamePrefix}_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
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
      debugPrint('Error exporting standard feedbacks to XLSX: $e');
      rethrow;
    }
  }

  /// Export instructor course selection feedbacks based on user choice
  /// @param selection: 'suitable', 'not_suitable', or 'both'
  /// Creates XLSX with proper Hebrew RTL support
  /// Structure: פיקוד, חטיבה, מספר מועמד, שם מועמד, [evaluations], ציון משוכלל
  static Future<void> exportInstructorCourseSelection(String selection) async {
    try {
      debugPrint('🔵 exportInstructorCourseSelection called with: $selection');
      debugPrint(
        '   🐛 BUG FIX: Using shared mapper to ensure identical data to single export',
      );

      final excel = Excel.createExcel();

      // ✅ CORRECT: Query instructor_course_evaluations (NOT instructor_course_feedbacks)
      final categoriesToExport = <Map<String, dynamic>>[];
      if (selection == 'suitable' || selection == 'both') {
        categoriesToExport.add({
          'isSuitable': true,
          'sheet': 'מתאימים לקורס מדריכים',
        });
      }
      if (selection == 'not_suitable' || selection == 'both') {
        categoriesToExport.add({
          'isSuitable': false,
          'sheet': 'לא מתאימים לקורס מדריכים',
        });
      }

      debugPrint('📊 Exporting ${categoriesToExport.length} category(ies)');

      for (final categoryInfo in categoriesToExport) {
        final isSuitable = categoryInfo['isSuitable'] as bool;
        final sheetName = categoryInfo['sheet'] as String;

        debugPrint('📄 Processing category: isSuitable=$isSuitable');

        // ✅ FIX: Query the CORRECT collection (instructor_course_evaluations, not instructor_course_feedbacks)
        // ✅ FIX: Use status='final' (not 'finalized') to match UI query
        debugPrint(
          '   🔍 Querying: instructor_course_evaluations where status=final, isSuitable=$isSuitable',
        );
        final snapshot = await FirebaseFirestore.instance
            .collection('instructor_course_evaluations')
            .where('status', isEqualTo: 'final')
            .where('isSuitable', isEqualTo: isSuitable)
            .orderBy('createdAt', descending: true)
            .get()
            .timeout(const Duration(seconds: 15));

        debugPrint(
          '   📊 Query returned ${snapshot.docs.length} raw documents',
        );

        // ✅ FIX: Use the shared mapper function to transform each doc
        final feedbacks = <Map<String, dynamic>>[];
        for (var i = 0; i < snapshot.docs.length; i++) {
          final doc = snapshot.docs[i];

          // Diagnostic: Log first 2 docs
          if (i < 2) {
            debugPrint('   🔍 Doc $i: id=${doc.id}');
            debugPrint('      Raw keys: ${doc.data().keys.toList()}');
          }

          // ✅ USE SHARED MAPPER: This ensures identical logic to single export
          final mappedData = await mapInstructorScreeningDocToExportRow(doc);
          feedbacks.add(mappedData);

          // Diagnostic: Log first mapped doc
          if (i == 0) {
            debugPrint('   🔍 First mapped doc:');
            debugPrint('      candidateName: ${mappedData['candidateName']}');
            debugPrint('      command: ${mappedData['command']}');
            debugPrint('      brigade: ${mappedData['brigade']}');
            debugPrint(
              '      candidateNumber: ${mappedData['candidateNumber']}',
            );
            debugPrint(
              '      scores keys: ${mappedData['scores']?.keys.toList()}',
            );
            debugPrint('      averageScore: ${mappedData['averageScore']}');
            debugPrint('      instructorName: ${mappedData['instructorName']}');
          }
        }

        debugPrint(
          '   ✅ Mapped ${feedbacks.length} feedbacks to export format (suitable=$isSuitable)',
        );

        // ✅ FIX: Create sheet even if empty (for "שניהם" export)
        if (feedbacks.isEmpty && selection == 'both') {
          debugPrint(
            '⚠️ No feedbacks for suitable=$isSuitable, but creating empty sheet for "שניהם" export',
          );
          // Continue to create empty sheet
        } else if (feedbacks.isEmpty) {
          debugPrint('⚠️ No feedbacks for suitable=$isSuitable, skipping...');
          continue;
        }

        // STEP 1: INSPECTION - Log structure matching UI display
        debugPrint('\n🔍 ===== EXPORT BASED ON UI STRUCTURE =====');
        if (feedbacks.isNotEmpty) {
          final firstRecord = feedbacks.first;
          debugPrint('📋 Top-level keys: ${firstRecord.keys.toList()}');

          final scores = firstRecord['scores'];
          if (scores != null && scores is Map) {
            debugPrint('✅ scores field: ${scores.keys.toList()}');
          } else {
            debugPrint('❌ scores field not found');
          }

          final averageScore = firstRecord['averageScore'];
          debugPrint('ℹ️ averageScore: $averageScore');
        }

        // Create or get sheet
        final sheet = excel[sheetName];
        sheet.isRTL = true; // RTL mode for Hebrew
        debugPrint('📋 Created sheet: $sheetName (RTL enabled)');

        // Define score columns in exact order shown in UI
        // These match the candidate card display order
        final scoreColumns = <Map<String, String>>[
          {'key': 'levelTest', 'label': 'בוחן רמה'},
          {'key': 'goodInstruction', 'label': 'הדרכה טובה'},
          {'key': 'structureInstruction', 'label': 'הדרכת מבנה'},
          {'key': 'dryPractice', 'label': 'יבשים'},
          {'key': 'surpriseExercise', 'label': 'תרגיל הפתעה'},
        ];

        debugPrint(
          '📊 Score columns (from UI): ${scoreColumns.map((c) => c['label']).join(', ')}',
        );

        // Build headers matching UI structure + required instructor & date columns
        final headers = <String>[
          'פיקוד',
          'חטיבה',
          'מספר מועמד',
          'שם מועמד',
          ...scoreColumns.map((c) => c['label']!),
          'ממוצע',
          'מדריך משב',
          'תאריך המשוב',
        ];

        debugPrint('📑 Headers: ${headers.join(', ')}');

        // Write title row (merged across all columns)
        final titleCell = sheet.cell(CellIndex.indexByString('A1'));
        titleCell.value = TextCellValue(sheetName);
        titleCell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          bold: true,
          fontSize: 16,
        );

        // Merge title row across all columns
        sheet.merge(
          CellIndex.indexByString('A1'),
          CellIndex.indexByColumnRow(
            columnIndex: headers.length - 1,
            rowIndex: 0,
          ),
        );

        // Write header row (row 2)
        for (var ci = 0; ci < headers.length; ci++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: 1),
          );
          cell.value = TextCellValue(headers[ci]);
          cell.cellStyle = CellStyle(
            horizontalAlign: HorizontalAlign.Right,
            bold: true,
          );
        }

        // Write data rows (starting from row 3)
        for (var ri = 0; ri < feedbacks.length; ri++) {
          final feedback = feedbacks[ri];
          final rowIndex = ri + 2; // Row 1 = title, Row 2 = headers

          // STEP 7: VERIFICATION - Log first row structure
          if (ri == 0) {
            debugPrint('\n🔍 ===== FIRST ROW VERIFICATION =====');
            debugPrint('📋 Candidate: ${feedback['candidateName']}');
            debugPrint('📋 Command: ${feedback['command']}');
            debugPrint('📋 Brigade: ${feedback['brigade']}');
            debugPrint('📋 Number: ${feedback['candidateNumber']}');
            final scores = feedback['scores'] as Map<String, dynamic>?;
            if (scores != null) {
              debugPrint('📊 Scores:');
              for (final sc in scoreColumns) {
                final key = sc['key']!;
                final label = sc['label']!;
                final value = scores[key];
                debugPrint('   $label ($key): $value');
              }
            }
            debugPrint('🎯 Average: ${feedback['averageScore']}');
            debugPrint('🔍 ===== END VERIFICATION =====\n');
          }

          var colIndex = 0;

          // פיקוד
          var cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          cell.value = TextCellValue(feedback['command']?.toString() ?? '');
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

          // חטיבה
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          cell.value = TextCellValue(feedback['brigade']?.toString() ?? '');
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

          // מספר מועמד
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          final candidateNumber = feedback['candidateNumber'];
          cell.value = IntCellValue(
            candidateNumber is int ? candidateNumber : 0,
          );
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

          // שם מועמד
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          cell.value = TextCellValue(
            feedback['candidateName']?.toString() ?? '',
          );
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

          // Score columns (matching UI order and field names)
          final scores = feedback['scores'] as Map<String, dynamic>?;
          for (final scoreCol in scoreColumns) {
            cell = sheet.cell(
              CellIndex.indexByColumnRow(
                columnIndex: colIndex++,
                rowIndex: rowIndex,
              ),
            );
            final value = scores?[scoreCol['key']];
            if (value is int) {
              cell.value = IntCellValue(value);
            } else if (value is double) {
              cell.value = DoubleCellValue(value);
            } else if (value is num) {
              cell.value = IntCellValue(value.toInt());
            } else {
              cell.value = TextCellValue('');
            }
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
          }

          // ממוצע (average score from UI)
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          final averageScore = feedback['averageScore'];
          if (averageScore is double) {
            cell.value = DoubleCellValue(averageScore);
          } else if (averageScore is int) {
            cell.value = DoubleCellValue(averageScore.toDouble());
          } else if (averageScore is num) {
            cell.value = DoubleCellValue(averageScore.toDouble());
          } else {
            cell.value = TextCellValue('');
          }
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

          // מדריך משב (instructor name from shared mapper - never email)
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          cell.value = TextCellValue(
            feedback['instructorName']?.toString() ?? 'לא ידוע',
          );
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);

          // תאריך המשוב (feedback date)
          cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex++,
              rowIndex: rowIndex,
            ),
          );
          final createdAt = feedback['createdAt'];
          String dateStr = '';
          if (createdAt is Timestamp) {
            final dt = createdAt.toDate();
            dateStr = DateFormat('dd/MM/yyyy HH:mm').format(dt);
          } else if (createdAt is DateTime) {
            dateStr = DateFormat('dd/MM/yyyy HH:mm').format(createdAt);
          } else if (createdAt is String) {
            try {
              final dt = DateTime.parse(createdAt);
              dateStr = DateFormat('dd/MM/yyyy HH:mm').format(dt);
            } catch (e) {
              dateStr = createdAt;
            }
          }
          cell.value = TextCellValue(dateStr);
          cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
        }

        debugPrint(
          '✅ Wrote ${feedbacks.length} data rows to sheet: $sheetName',
        );
      }

      // Remove default sheet if it exists
      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Encode and export
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      // Generate filename based on selection
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm').format(now);
      String fileName;
      if (selection == 'suitable') {
        fileName = 'מיונים_מתאימים_$dateStr.xlsx';
      } else if (selection == 'not_suitable') {
        fileName = 'מיונים_לא_מתאימים_$dateStr.xlsx';
      } else {
        fileName = 'מיונים_כל_הקטגוריות_$dateStr.xlsx';
      }

      debugPrint('💾 Saving file: $fileName');

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
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

      debugPrint('✅ Export completed successfully: $fileName');
    } catch (e) {
      debugPrint('❌ Error in exportInstructorCourseSelection: $e');
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

  /// Export Surprise Drills feedbacks to XLSX with Hebrew RTL support
  /// Structure: One row per trainee with metadata + dynamic drill columns + average
  static Future<void> exportSurpriseDrillsToXlsx({
    required List<Map<String, dynamic>> feedbacksData,
    String fileNamePrefix = 'surprise_drills',
  }) async {
    try {
      debugPrint('\n🔵🔵🔵 STARTING SURPRISE DRILLS EXPORT 🔵🔵🔵');
      debugPrint('📊 Total feedbacks received: ${feedbacksData.length}');

      // ========== DEBUG: Print document IDs ==========
      for (int i = 0; i < feedbacksData.length; i++) {
        final docId =
            feedbacksData[i]['id'] ?? feedbacksData[i]['docId'] ?? 'unknown';
        debugPrint('📄 Feedback $i: docId=$docId');
      }

      final excel = Excel.createExcel();
      final sheet = excel['משוב תרגילי הפתעה'];
      sheet.isRTL = true; // Hebrew RTL mode

      // ========== PHASE 1: Collect all unique drill names across all feedbacks ==========
      // This ensures we have columns for all drills even if different feedbacks have different drills
      final Set<String> allDrillNames = {};
      final Map<int, List<String>> feedbackDrillOrder =
          {}; // feedbackIdx -> ordered drill names

      for (
        int feedbackIdx = 0;
        feedbackIdx < feedbacksData.length;
        feedbackIdx++
      ) {
        final feedbackData = feedbacksData[feedbackIdx];
        final List<String> drillNamesForThisFeedback = [];

        // Extract stations (drills/principles) with robust type handling
        final rawStations = feedbackData['stations'];
        if (rawStations is List) {
          for (
            int stationIdx = 0;
            stationIdx < rawStations.length;
            stationIdx++
          ) {
            final s = rawStations[stationIdx];
            if (s is Map) {
              final drillName = (s['name'] ?? '').toString().trim();
              if (drillName.isNotEmpty) {
                allDrillNames.add(drillName);
                drillNamesForThisFeedback.add(drillName);
              }
            }
          }
        }
        feedbackDrillOrder[feedbackIdx] = drillNamesForThisFeedback;
        debugPrint(
          '📋 Feedback $feedbackIdx drill columns: $drillNamesForThisFeedback',
        );
      }

      // Sort drill names for consistent column order (use the order from first feedback as base)
      final List<String> orderedDrillNames =
          feedbackDrillOrder[0] ?? allDrillNames.toList();
      // Add any drills from other feedbacks that weren't in the first
      for (final name in allDrillNames) {
        if (!orderedDrillNames.contains(name)) {
          orderedDrillNames.add(name);
        }
      }

      debugPrint('📊 Total unique drill columns: ${orderedDrillNames.length}');
      debugPrint('📊 Drill column order: $orderedDrillNames');

      // ========== PHASE 2: Build headers (matching UI exactly) ==========
      // Structure: [שם] + [principle columns in UI order...] + [ממוצע]
      final List<CellValue> headers = [
        TextCellValue('שם'), // Trainee name column
        // Dynamic principle columns (in exact UI order)
        ...orderedDrillNames.map((name) => TextCellValue(name)),
        // Summary column (percentage)
        TextCellValue('ממוצע'),
      ];

      sheet.appendRow(headers);
      debugPrint('📝 Headers added: ${headers.length} columns');

      // ========== PHASE 2.5: Compute and add MAX row ==========
      // Calculate dynamic maxPoints per principle (same as UI calculation)
      final Map<String, int> maxPointsPerPrinciple = {};

      for (
        int feedbackIdx = 0;
        feedbackIdx < feedbacksData.length;
        feedbackIdx++
      ) {
        final feedbackData = feedbacksData[feedbackIdx];
        final drillNamesForThisFeedback = feedbackDrillOrder[feedbackIdx] ?? [];

        // Build drill name to station index mapping for THIS feedback
        final Map<String, int> drillNameToStationIdx = {};
        for (int idx = 0; idx < drillNamesForThisFeedback.length; idx++) {
          drillNameToStationIdx[drillNamesForThisFeedback[idx]] = idx;
        }

        // Extract trainees
        final rawTrainees = feedbackData['trainees'];
        if (rawTrainees is List) {
          for (final t in rawTrainees) {
            if (t is Map) {
              final hitsMap = (t['hits'] is Map)
                  ? Map<String, dynamic>.from(t['hits'] as Map)
                  : <String, dynamic>{};

              // For each principle, find max score across all trainees
              for (final drillName in orderedDrillNames) {
                final stationIdx = drillNameToStationIdx[drillName];
                if (stationIdx != null) {
                  final value = hitsMap['station_$stationIdx'];
                  if (value != null && value is num && value > 0) {
                    final intValue = value.toInt();
                    final currentMax = maxPointsPerPrinciple[drillName] ?? 0;
                    if (intValue > currentMax) {
                      maxPointsPerPrinciple[drillName] = intValue;
                    }
                  }
                }
              }
            }
          }
        }
      }

      debugPrint('📊 Computed maxPoints per principle: $maxPointsPerPrinciple');

      // Build MAX row
      final List<CellValue> maxRow = [
        TextCellValue('מקסימום'), // Label in name column
        // MaxPoints for each principle
        ...orderedDrillNames.map((name) {
          final maxPoints = maxPointsPerPrinciple[name] ?? 0;
          return maxPoints > 0 ? IntCellValue(maxPoints) : TextCellValue('');
        }),
        TextCellValue(''), // Empty in average column
      ];

      sheet.appendRow(maxRow);
      debugPrint('📝 MAX row added with maxPoints per principle');

      int totalRowsAdded = 0;
      int totalTraineesProcessed = 0;

      // ========== PHASE 3: Add data rows - one per trainee ==========
      for (
        int feedbackIdx = 0;
        feedbackIdx < feedbacksData.length;
        feedbackIdx++
      ) {
        final feedbackData = feedbacksData[feedbackIdx];
        final docId = feedbackData['id'] ?? feedbackData['docId'] ?? 'unknown';

        debugPrint(
          '\n📄 Processing feedback ${feedbackIdx + 1}/${feedbacksData.length} (docId=$docId)',
        );

        // Build drill name to station index mapping for THIS feedback
        final drillNamesForThisFeedback = feedbackDrillOrder[feedbackIdx] ?? [];
        final Map<String, int> drillNameToStationIdx = {};
        for (int idx = 0; idx < drillNamesForThisFeedback.length; idx++) {
          drillNameToStationIdx[drillNamesForThisFeedback[idx]] = idx;
        }
        debugPrint('   📊 Drill-to-index mapping: $drillNameToStationIdx');

        // Extract trainees
        List<Map<String, dynamic>> trainees = [];
        final rawTrainees = feedbackData['trainees'];
        if (rawTrainees is List) {
          for (final t in rawTrainees) {
            if (t is Map) {
              trainees.add(Map<String, dynamic>.from(t));
            }
          }
        }

        debugPrint('   👥 Trainees loaded: ${trainees.length}');

        // If no trainees, skip this feedback
        if (trainees.isEmpty) {
          debugPrint('   ⚠️ No trainees found - skipping this feedback');
          continue;
        }

        // One row per trainee
        for (int traineeIdx = 0; traineeIdx < trainees.length; traineeIdx++) {
          final trainee = trainees[traineeIdx];
          final traineeName = (trainee['name'] ?? '').toString();

          // Extract hits map
          Map<String, dynamic> hitsMap = {};
          final rawHits = trainee['hits'];
          if (rawHits is Map) {
            hitsMap = Map<String, dynamic>.from(rawHits);
          }

          debugPrint(
            '   👤 Trainee ${traineeIdx + 1}: "$traineeName", hits=$hitsMap',
          );

          // Build scores in orderedDrillNames order
          final List<CellValue> drillScores = [];
          final List<int> traineePoints = []; // Points achieved per principle
          final List<int> maxPointsForThisTrainee =
              []; // Max points per principle

          for (final drillName in orderedDrillNames) {
            // Find station index for this drill in THIS feedback
            final stationIdx = drillNameToStationIdx[drillName];

            if (stationIdx != null) {
              // This drill exists in this feedback - look up trainee's score
              final value = hitsMap['station_$stationIdx'];
              if (value != null && value is num && value > 0) {
                final intValue = value.toInt();
                drillScores.add(IntCellValue(intValue));
                traineePoints.add(intValue);
                maxPointsForThisTrainee.add(
                  maxPointsPerPrinciple[drillName] ?? 0,
                );
              } else {
                drillScores.add(TextCellValue(''));
                // Don't add to traineePoints or maxPoints if value is empty/0
              }
            } else {
              // This drill wasn't in this feedback (from another feedback's drills)
              drillScores.add(TextCellValue(''));
            }
          }

          // Calculate percentage-based average (matching UI)
          // totalPoints = sum of trainee's points
          // totalMaxPoints = sum of maxPoints for principles where trainee has scores
          // averagePercent = (totalPoints / totalMaxPoints) * 100
          String avgDisplay = '';
          if (traineePoints.isNotEmpty && maxPointsForThisTrainee.isNotEmpty) {
            final totalPoints = traineePoints.fold<int>(0, (a, b) => a + b);
            final totalMaxPoints = maxPointsForThisTrainee.fold<int>(
              0,
              (a, b) => a + b,
            );

            if (totalMaxPoints > 0) {
              final avgPercent = (totalPoints / totalMaxPoints) * 100;
              avgDisplay = avgPercent.toStringAsFixed(1);
            } else {
              avgDisplay = '0.0';
            }
          }

          // Build row: [שם] + [principle scores...] + [ממוצע %]
          final List<CellValue> row = [
            TextCellValue(traineeName),
            ...drillScores,
            TextCellValue(avgDisplay),
          ];

          // DEBUG: Print first trainee row payload
          if (traineeIdx == 0 && feedbackIdx == 0) {
            debugPrint('   🔍 FIRST TRAINEE ROW PAYLOAD:');
            debugPrint('      traineeName=$traineeName');
            debugPrint(
              '      drillScores=${traineePoints.map((v) => v.toString()).toList()}',
            );
            debugPrint(
              '      totalPoints=${traineePoints.fold<int>(0, (a, b) => a + b)}',
            );
            debugPrint(
              '      totalMaxPoints=${maxPointsForThisTrainee.fold<int>(0, (a, b) => a + b)}',
            );
            debugPrint('      avg=$avgDisplay%');
          }

          sheet.appendRow(row);
          totalRowsAdded++;
          totalTraineesProcessed++;

          debugPrint(
            '      ✅ Added row: ${traineePoints.length} scores, avg=$avgDisplay%',
          );
        }
      }

      debugPrint('\n📊 EXPORT SUMMARY:');
      debugPrint('   Total feedbacks processed: ${feedbacksData.length}');
      debugPrint('   Total trainees processed: $totalTraineesProcessed');
      debugPrint('   Total rows added: $totalRowsAdded');
      debugPrint('   Drill columns: $orderedDrillNames');

      // Save and export
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          'משוב תרגילי הפתעה - ${DateFormat('yyyy-MM-dd').format(now)}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        debugPrint('✅ Web export completed: $fileName');
      } else {
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getDownloadsDirectory();
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory == null) {
          throw Exception('לא ניתן לקבל תיקיית שמירה');
        }

        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        debugPrint('✅ Mobile export completed: $filePath');
      }

      debugPrint('🔵🔵🔵 SURPRISE DRILLS EXPORT COMPLETE 🔵🔵🔵\n');
    } catch (e, stackTrace) {
      debugPrint('❌ Export error: $e');
      debugPrint('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Export 474 Ranges feedbacks to XLSX with Hebrew RTL support
  /// Structure: One sheet per feedback with metadata, trainees, stages, and totals
  static Future<void> export474RangesFeedbacks({
    required List<Map<String, dynamic>> feedbacksData,
    String fileNamePrefix = '474_ranges_export',
  }) async {
    try {
      debugPrint('\n🔵🔵🔵 STARTING 474 RANGES EXPORT 🔵🔵🔵');
      debugPrint('📊 Total feedbacks received: ${feedbacksData.length}');

      if (feedbacksData.isEmpty) {
        throw Exception('אין נתונים לייצוא');
      }

      final excel = Excel.createExcel();

      // Delete default sheet
      if (excel.tables.keys.contains('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Create one sheet per feedback
      for (
        int feedbackIdx = 0;
        feedbackIdx < feedbacksData.length;
        feedbackIdx++
      ) {
        final feedbackData = feedbacksData[feedbackIdx];

        // Extract metadata
        final settlement =
            (feedbackData['settlement'] ?? feedbackData['settlementName'] ?? '')
                .toString();
        final createdAt = feedbackData['createdAt'];
        DateTime date = DateTime.now();
        if (createdAt is Timestamp) {
          date = createdAt.toDate();
        } else if (createdAt is String) {
          date = DateTime.tryParse(createdAt) ?? DateTime.now();
        }
        final dateStr = DateFormat('dd-MM-yyyy').format(date);

        // Create unique sheet name: settlement + date (max 31 chars for Excel)
        String sheetName = '$settlement $dateStr';
        if (sheetName.length > 31) {
          sheetName = sheetName.substring(0, 31);
        }
        // Ensure uniqueness by adding index if needed
        String finalSheetName = sheetName;
        int suffix = 1;
        while (excel.tables.keys.contains(finalSheetName)) {
          final suffixStr = ' (${suffix++})';
          final maxLen = 31 - suffixStr.length;
          finalSheetName =
              sheetName.substring(0, maxLen < 0 ? 0 : maxLen) + suffixStr;
        }

        final sheet = excel[finalSheetName];
        sheet.isRTL = true; // Hebrew RTL mode

        debugPrint(
          '\n📄 Processing feedback ${feedbackIdx + 1}: sheet="$finalSheetName"',
        );

        // ========== METADATA SECTION ==========
        final instructorName =
            (feedbackData['instructorName'] ??
                    feedbackData['createdByName'] ??
                    '')
                .toString();
        final rangeType = (feedbackData['rangeType'] ?? '').toString();
        final attendeesCount =
            (feedbackData['attendeesCount'] as num?)?.toInt() ?? 0;

        sheet.appendRow([TextCellValue('מטווחים 474')]);
        sheet.appendRow([TextCellValue('תאריך: $dateStr')]);
        sheet.appendRow([TextCellValue('מדריך: $instructorName')]);
        sheet.appendRow([TextCellValue('יישוב: $settlement')]);
        sheet.appendRow([TextCellValue('סוג: $rangeType')]);
        sheet.appendRow([TextCellValue('מספר חניכים: $attendeesCount')]);
        sheet.appendRow([TextCellValue('')]); // Empty row separator

        // ========== EXTRACT STAGES AND TRAINEES ==========
        final rawStations = feedbackData['stations'];
        final List<Map<String, dynamic>> stages = [];
        if (rawStations is List) {
          for (final s in rawStations) {
            if (s is Map) {
              stages.add(Map<String, dynamic>.from(s));
            }
          }
        }

        final rawTrainees = feedbackData['trainees'];
        final List<Map<String, dynamic>> trainees = [];
        if (rawTrainees is List) {
          for (final t in rawTrainees) {
            if (t is Map) {
              trainees.add(Map<String, dynamic>.from(t));
            }
          }
        }

        debugPrint(
          '   📊 Stages: ${stages.length}, Trainees: ${trainees.length}',
        );

        if (stages.isEmpty || trainees.isEmpty) {
          debugPrint('   ⚠️ No stages or trainees - adding empty sheet');
          sheet.appendRow([TextCellValue('אין נתונים')]);
          continue;
        }

        // ========== BUILD HEADERS ==========
        // Structure: [שם חניך] + [stage columns...] + [סה"כ פגיעות] + [סה"כ כדורים] + [אחוז כללי]
        final List<CellValue> headers = [
          TextCellValue('שם חניך'),
          ...stages.map(
            (stage) => TextCellValue((stage['name'] ?? '').toString()),
          ),
          TextCellValue('סה"כ פגיעות'),
          TextCellValue('סה"כ כדורים'),
          TextCellValue('אחוז כללי'),
        ];
        sheet.appendRow(headers);

        // ========== ADD MAX BULLETS ROW ==========
        // Show bullets per stage (for reference)
        final List<CellValue> bulletsRow = [
          TextCellValue('כדורים למקצה'),
          ...stages.map((stage) {
            final bullets = (stage['bulletsCount'] as num?)?.toInt() ?? 0;
            return bullets > 0 ? IntCellValue(bullets) : TextCellValue('');
          }),
          TextCellValue(''),
          IntCellValue(
            stages.fold<int>(
              0,
              (total, s) => total + ((s['bulletsCount'] as num?)?.toInt() ?? 0),
            ),
          ),
          TextCellValue(''),
        ];
        sheet.appendRow(bulletsRow);

        // ========== ADD TRAINEE ROWS ==========
        int totalRowsAdded = 0;

        for (final trainee in trainees) {
          final traineeName = (trainee['name'] ?? '').toString();

          // Extract hits map
          final hitsMap =
              (trainee['hits'] as Map?)?.cast<String, dynamic>() ?? {};

          // Build row: name + stage scores + totals
          final List<CellValue> traineeRow = [TextCellValue(traineeName)];

          int traineeHitsTotal = 0;
          int traineeBulletsTotal = 0;

          for (int stageIdx = 0; stageIdx < stages.length; stageIdx++) {
            final stage = stages[stageIdx];
            final hits = (hitsMap['station_$stageIdx'] as num?)?.toInt() ?? 0;
            final bullets = (stage['bulletsCount'] as num?)?.toInt() ?? 0;

            traineeHitsTotal += hits;
            traineeBulletsTotal += bullets;

            // Show as "hits/bullets"
            if (hits > 0 || bullets > 0) {
              traineeRow.add(TextCellValue('$hits/$bullets'));
            } else {
              traineeRow.add(TextCellValue(''));
            }
          }

          // Add totals
          traineeRow.add(IntCellValue(traineeHitsTotal));
          traineeRow.add(IntCellValue(traineeBulletsTotal));

          // Calculate percentage
          final percentage = traineeBulletsTotal > 0
              ? ((traineeHitsTotal / traineeBulletsTotal) * 100)
                    .toStringAsFixed(1)
              : '0.0';
          traineeRow.add(TextCellValue('$percentage%'));

          sheet.appendRow(traineeRow);
          totalRowsAdded++;
        }

        debugPrint('   ✅ Added $totalRowsAdded trainee rows');

        // ========== ADD SUMMARY ROW ==========
        sheet.appendRow([TextCellValue('')]); // Empty separator

        // Calculate totals across all trainees
        int grandTotalHits = 0;
        int grandTotalBullets = 0;

        for (final trainee in trainees) {
          final hitsMap =
              (trainee['hits'] as Map?)?.cast<String, dynamic>() ?? {};
          for (int stageIdx = 0; stageIdx < stages.length; stageIdx++) {
            final hits = (hitsMap['station_$stageIdx'] as num?)?.toInt() ?? 0;
            final bullets =
                (stages[stageIdx]['bulletsCount'] as num?)?.toInt() ?? 0;
            grandTotalHits += hits;
            grandTotalBullets += bullets;
          }
        }

        final grandPercentage = grandTotalBullets > 0
            ? ((grandTotalHits / grandTotalBullets) * 100).toStringAsFixed(1)
            : '0.0';

        final List<CellValue> summaryRow = [
          TextCellValue('סה"כ כללי'),
          ...List.generate(stages.length, (_) => TextCellValue('')),
          IntCellValue(grandTotalHits),
          IntCellValue(grandTotalBullets),
          TextCellValue('$grandPercentage%'),
        ];
        sheet.appendRow(summaryRow);
      }

      debugPrint('\n📊 EXPORT SUMMARY:');
      debugPrint('   Total sheets created: ${excel.tables.keys.length}');

      // ========== SAVE AND EXPORT ==========
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      final now = DateTime.now();
      final fileName =
          '${fileNamePrefix}_${DateFormat('yyyy-MM-dd_HH-mm').format(now)}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        debugPrint('✅ Web export completed: $fileName');
      } else {
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getDownloadsDirectory();
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory == null) {
          throw Exception('לא ניתן לקבל תיקיית שמירה');
        }

        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        debugPrint('✅ Mobile export completed: $filePath');
      }

      debugPrint('🔵🔵🔵 474 RANGES EXPORT COMPLETE 🔵🔵🔵\n');
    } catch (e, stackTrace) {
      debugPrint('❌ 474 Ranges export error: $e');
      debugPrint('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// ייצוא סטטיסטיקות לקובץ XLSX/Google Sheets
  /// Generic export for statistics data with multiple sections
  static Future<void> exportStatisticsToGoogleSheets({
    required String tabName,
    required Map<String, List<Map<String, dynamic>>> sections,
  }) async {
    try {
      final now = DateTime.now();
      final fileName =
          '$tabName – ${DateFormat('yyyy-MM-dd HH:mm').format(now)}.xlsx';

      debugPrint('📊 Exporting statistics: $fileName');
      debugPrint('   Sections: ${sections.keys.join(', ')}');

      final excel = Excel.createExcel();
      excel.delete('Sheet1'); // Remove default sheet

      // Create a sheet for each section
      for (final entry in sections.entries) {
        final sectionName = entry.key;
        final sectionData = entry.value;

        if (sectionData.isEmpty) continue;

        final sheet = excel[sectionName];
        sheet.isRTL = true;

        // Extract headers from first row
        final headers = sectionData.first.keys.toList();
        sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

        // Add data rows
        for (final row in sectionData) {
          final cells = <CellValue>[];
          for (final header in headers) {
            final value = row[header];
            if (value == null) {
              cells.add(TextCellValue(''));
            } else if (value is int) {
              cells.add(IntCellValue(value));
            } else if (value is double) {
              cells.add(DoubleCellValue(value));
            } else {
              cells.add(TextCellValue(value.toString()));
            }
          }
          sheet.appendRow(cells);
        }
      }

      // Export file
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('שגיאה ביצירת קובץ XLSX');
      }

      if (kIsWeb) {
        // Web: Download to browser
        final blob = html.Blob([
          fileBytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile: Save to Downloads
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
        debugPrint('✅ Statistics export completed: $filePath');
      }

      debugPrint('📊 Statistics export complete: $fileName');
    } catch (e, stackTrace) {
      debugPrint('❌ Statistics export error: $e');
      debugPrint('   Stack trace: $stackTrace');
      rethrow;
    }
  }
}
