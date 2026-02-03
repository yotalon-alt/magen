// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// סקריפט להעלאת נתוני חניכים ל-Firestore
/// משתמש ב-Firebase Admin SDK דרך REST API
void main() async {
  print('\n🚀 העלאת נתונים ל-Firestore...\n');

  // קריאת הנתונים מקובץ JSON
  final jsonFile = File('trainees_data.json');
  if (!jsonFile.existsSync()) {
    print('❌ קובץ trainees_data.json לא נמצא!');
    print('   הרץ קודם: dart run import_trainees.dart');
    exit(1);
  }

  final jsonString = jsonFile.readAsStringSync();
  final Map<String, dynamic> data = json.decode(jsonString);

  print('📋 נמצאו ${data.length} יישובים');
  print('');

  // יצירת קובץ JavaScript להעלאה דרך Firebase Console
  final jsOutput = StringBuffer();
  jsOutput.writeln('// קוד להעלאה ל-Firestore');
  jsOutput.writeln('// הרץ בקונסולת הדפדפן של Firebase Console');
  jsOutput.writeln('');
  jsOutput.writeln('const data = ${json.encode(data)};');
  jsOutput.writeln('');
  jsOutput.writeln('async function uploadToFirestore() {');
  jsOutput.writeln('  const db = firebase.firestore();');
  jsOutput.writeln('  let count = 0;');
  jsOutput.writeln('  ');
  jsOutput.writeln(
      '  for (const [settlement, trainees] of Object.entries(data)) {');
  jsOutput.writeln(
      '    await db.collection("settlement_trainees").doc(settlement).set({');
  jsOutput.writeln('      settlementName: settlement,');
  jsOutput.writeln('      trainees: trainees,');
  jsOutput.writeln(
      '      updatedAt: firebase.firestore.FieldValue.serverTimestamp()');
  jsOutput.writeln('    });');
  jsOutput.writeln('    count++;');
  jsOutput.writeln(
      '    console.log(`✅ \${count}. \${settlement}: \${trainees.length} חניכים`);');
  jsOutput.writeln('  }');
  jsOutput.writeln('  ');
  jsOutput.writeln('  console.log(`\\n🎉 הועלו \${count} יישובים בהצלחה!`);');
  jsOutput.writeln('}');
  jsOutput.writeln('');
  jsOutput.writeln('uploadToFirestore();');

  File('upload_firestore.js').writeAsStringSync(jsOutput.toString());
  print('✅ נוצר קובץ: upload_firestore.js');

  // יצירת קובץ Dart להעלאה מתוך האפליקציה
  final dartOutput = StringBuffer();
  dartOutput.writeln('// קוד Dart להעלאה ל-Firestore');
  dartOutput.writeln('// הוסף לאפליקציה והרץ פעם אחת');
  dartOutput.writeln('');
  dartOutput.writeln("import 'package:cloud_firestore/cloud_firestore.dart';");
  dartOutput.writeln('');
  dartOutput.writeln('Future<void> uploadSettlementTrainees() async {');
  dartOutput.writeln('  final Map<String, List<String>> data = {');

  for (final entry in data.entries) {
    final settlement = entry.key;
    final trainees = (entry.value as List).cast<String>();
    final traineesStr =
        trainees.map((t) => "'${t.replaceAll("'", "\\'")}'").join(', ');
    dartOutput.writeln("    '$settlement': [$traineesStr],");
  }

  dartOutput.writeln('  };');
  dartOutput.writeln('');
  dartOutput.writeln('  int count = 0;');
  dartOutput.writeln('  for (final entry in data.entries) {');
  dartOutput.writeln('    await FirebaseFirestore.instance');
  dartOutput.writeln("        .collection('settlement_trainees')");
  dartOutput.writeln('        .doc(entry.key)');
  dartOutput.writeln('        .set({');
  dartOutput.writeln("          'settlementName': entry.key,");
  dartOutput.writeln("          'trainees': entry.value,");
  dartOutput.writeln("          'updatedAt': FieldValue.serverTimestamp(),");
  dartOutput.writeln('        });');
  dartOutput.writeln('    count++;');
  dartOutput.writeln(
      "    print('✅ \$count. \${entry.key}: \${entry.value.length} חניכים');");
  dartOutput.writeln('  }');
  dartOutput.writeln("  print('\\n🎉 הועלו \$count יישובים בהצלחה!');");
  dartOutput.writeln('}');

  File('upload_firestore.dart').writeAsStringSync(dartOutput.toString());
  print('✅ נוצר קובץ: upload_firestore.dart');

  print('');
  print('=' * 60);
  print('📋 הוראות העלאה:');
  print('=' * 60);
  print('');
  print('אפשרות 1: מתוך האפליקציה (מומלץ)');
  print('   1. העתק את הקוד מ-upload_firestore.dart');
  print('   2. הוסף לקובץ main.dart');
  print('   3. קרא ל-uploadSettlementTrainees() פעם אחת');
  print('');
  print('אפשרות 2: מתוך Firebase Console');
  print('   1. פתח את Firebase Console');
  print('   2. לך ל-Firestore Database');
  print('   3. פתח את כלי המפתחים (F12)');
  print('   4. העתק והדבק את הקוד מ-upload_firestore.js');
  print('');
  print('=' * 60);
}
