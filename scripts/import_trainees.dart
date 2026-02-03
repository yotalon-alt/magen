// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings

// סקריפט ייבוא חניכים מאקסל ל-Firestore
// מבנה הקובץ: כל גיליון = יישוב, עמודה 1 = שם פרטי, עמודה 2 = שם משפחה

import 'dart:io';
import 'package:excel/excel.dart';

void main() async {
  final file = File('trainees.xlsx');

  if (!file.existsSync()) {
    print('❌ קובץ לא נמצא: trainees.xlsx');
    exit(1);
  }

  final bytes = file.readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  print('\n📊 קריאת קובץ אקסל...\n');
  print('גיליונות שנמצאו: ${excel.tables.keys.toList()}');
  print('');

  // מבנה הנתונים לייבוא
  final Map<String, List<String>> settlementTrainees = {};

  for (final sheetName in excel.tables.keys) {
    final sheet = excel.tables[sheetName];
    if (sheet == null) continue;

    // דלג על גיליונות עם שמות מיוחדים
    if (sheetName.startsWith('_') || sheetName.toLowerCase() == 'sheet1') {
      print('⏭️ דילוג על גיליון: $sheetName');
      continue;
    }

    final trainees = <String>[];

    // עובר על כל השורות (מדלג על שורה ראשונה אם זו כותרת)
    bool isFirstRow = true;

    for (final row in sheet.rows) {
      // בדיקה אם יש נתונים בשורה
      if (row.isEmpty) continue;

      // שם פרטי - עמודה 0
      final firstNameCell = row.isNotEmpty ? row[0] : null;
      final firstName = firstNameCell?.value?.toString().trim() ?? '';

      // שם משפחה - עמודה 1
      final lastNameCell = row.length > 1 ? row[1] : null;
      final lastName = lastNameCell?.value?.toString().trim() ?? '';

      // דלג על שורה ראשונה אם נראית ככותרת
      if (isFirstRow) {
        isFirstRow = false;
        final lowerFirst = firstName.toLowerCase();
        if (lowerFirst.contains('שם') ||
            lowerFirst.contains('פרטי') ||
            lowerFirst.contains('name') ||
            lowerFirst.contains('first')) {
          print('   📋 $sheetName: דילוג על שורת כותרת');
          continue;
        }
      }

      // דלג על שורות ריקות
      if (firstName.isEmpty && lastName.isEmpty) continue;

      // חיבור שם מלא
      String fullName;
      if (firstName.isNotEmpty && lastName.isNotEmpty) {
        fullName = '$firstName $lastName';
      } else if (firstName.isNotEmpty) {
        fullName = firstName;
      } else {
        fullName = lastName;
      }

      // נקה רווחים כפולים
      fullName = fullName.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (fullName.isNotEmpty) {
        trainees.add(fullName);
      }
    }

    if (trainees.isNotEmpty) {
      settlementTrainees[sheetName] = trainees;
      print('✅ $sheetName: ${trainees.length} חניכים');
      for (int i = 0; i < trainees.length && i < 5; i++) {
        print('   ${i + 1}. ${trainees[i]}');
      }
      if (trainees.length > 5) {
        print('   ... ועוד ${trainees.length - 5} חניכים');
      }
      print('');
    } else {
      print('⚠️ $sheetName: אין חניכים');
    }
  }

  print('\n' + '=' * 50);
  print('📊 סיכום:');
  print('=' * 50);
  print('יישובים: ${settlementTrainees.length}');

  int totalTrainees = 0;
  settlementTrainees.forEach((settlement, trainees) {
    totalTrainees += trainees.length;
  });
  print('סה"כ חניכים: $totalTrainees');
  print('=' * 50);

  // יצירת קוד Firestore להעתקה
  print('\n\n📋 קוד להעלאה ל-Firestore:');
  print('=' * 50);
  print('העתק את הקוד הבא והרץ אותו באפליקציה (או ב-Firebase Console):\n');

  print('final Map<String, List<String>> data = {');
  settlementTrainees.forEach((settlement, trainees) {
    final traineesList = trainees.map((t) => "'$t'").join(', ');
    print("  '$settlement': [$traineesList],");
  });
  print('};');

  print('\n// קוד להעלאה:');
  print('for (final entry in data.entries) {');
  print('  await FirebaseFirestore.instance');
  print("      .collection('settlement_trainees')");
  print('      .doc(entry.key)');
  print('      .set({');
  print("        'settlementName': entry.key,");
  print("        'trainees': entry.value,");
  print("        'updatedAt': FieldValue.serverTimestamp(),");
  print('      });');
  print('  print(\'✅ \${entry.key}: \${entry.value.length} חניכים\');');
  print('}');

  // שמירה לקובץ JSON
  print('\n\n📁 שומר לקובץ JSON...');
  final jsonFile = File('trainees_data.json');
  final jsonContent = StringBuffer();
  jsonContent.writeln('{');
  final entries = settlementTrainees.entries.toList();
  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final traineesList = entry.value.map((t) => '"$t"').join(', ');
    final comma = i < entries.length - 1 ? ',' : '';
    jsonContent.writeln('  "${entry.key}": [$traineesList]$comma');
  }
  jsonContent.writeln('}');
  jsonFile.writeAsStringSync(jsonContent.toString());
  print('✅ נשמר ב: trainees_data.json');
}
