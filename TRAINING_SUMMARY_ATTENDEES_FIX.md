# תיקון: שדה הנוכחים במשוב סיכום אימון

## 📋 תיאור השינוי

שונה חלק הנוכחים במשוב "סיכום אימון" מרשימה דינמית לטבלה קבועה לפי כמות, בדיוק כמו במשוב "טווח קצר".

## 🔧 שינויים שבוצעו

### 1. שינוי משתני State

**לפני:**
```dart
final List<String> attendees = [''];
```

**אחרי:**
```dart
int attendeesCount = 0;
late TextEditingController _attendeesCountController;
final Map<String, TextEditingController> _attendeeNameControllers = {};
```

### 2. שינוי פונקציות

**נמחק:**
- `_addAttendee()` - הוספת חניך לרשימה
- `_removeAttendee(int index)` - הסרת חניך מהרשימה

**נוסף:**
- `_updateAttendeesCount(int count)` - עדכון כמות הנוכחים
- `_getAttendeeController(String key, String initialValue)` - מנהל controllers לשדות הטקסט

**עודכן ב-initState:**
```dart
_attendeesCountController = TextEditingController(
  text: attendeesCount.toString(),
);
```

**עודכן ב-dispose:**
```dart
_attendeesCountController.dispose();
for (final controller in _attendeeNameControllers.values) {
  controller.dispose();
}
```

### 3. שינוי ב-UI

**לפני - רשימה דינמית:**
```dart
// כותרת "נוכחים"
// טבלה עם שדות טקסט
// כפתור "הוסף חניך"
// כפתור מחיקה לכל שורה
```

**אחרי - שדה כמות + טבלה קבועה:**
```dart
// 5. שדה "כמות נוכחים" - מספר
TextField(
  controller: _attendeesCountController,
  keyboardType: TextInputType.number,
  onChanged: (v) {
    final count = int.tryParse(v) ?? 0;
    _updateAttendeesCount(count);
  },
)

// 6. טבלה נוכחים (רק אם יש כמות > 0)
if (attendeesCount > 0) ...[
  Card(
    // טבלה עם 2 עמודות:
    // עמודת "מספר" - מספר אוטומטי בעיגול כתום
    // עמודת "שם" - שדה טקסט
  )
]
```

### 4. עדכון Validation

**שונה מ:**
```dart
final validAttendees = attendees
    .map((a) => a.trim())
    .where((a) => a.isNotEmpty)
    .toList();

if (validAttendees.isEmpty) {
  // הודעת שגיאה
}
```

**ל:**
```dart
// בדיקת כמות
if (attendeesCount == 0) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('אנא הזן כמות נוכחים')),
  );
  return;
}

// איסוף שמות מהטבלה
final List<String> validAttendees = [];
for (int i = 0; i < attendeesCount; i++) {
  final controller = _attendeeNameControllers['attendee_$i'];
  final name = controller?.text.trim() ?? '';
  if (name.isNotEmpty) {
    validAttendees.add(name);
  }
}

// בדיקת לפחות נוכח אחד
if (validAttendees.isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('אנא הזן לפחות נוכח אחד')),
  );
  return;
}
```

## 🎯 התנהגות החדשה

1. המשתמש מזין מספר בשדה "כמות נוכחים"
2. הטבלה נפתחת אוטומטית עם מספר השורות המתאים
3. כל שורה כוללת:
   - מספר סידורי בעיגול כתום (1, 2, 3...)
   - שדה טקסט לשם הנוכח
4. לא ניתן להוסיף/למחוק שורות - הטבלה נשלטת רק על ידי שדה הכמות
5. בשמירה - אוספים רק שמות שלא ריקים

## 📊 עיצוב הטבלה

הטבלה מעוצבת כמו בטווח קצר:
- רקע כהה (blueGrey.shade800)
- כותרת עם רקע blueGrey.shade700
- עמודת מספר: עיגול כתום (orangeAccent) עם מספר שחור
- עמודת שם: TextField לבן עם מסגרת

## ✅ בדיקות

```bash
flutter analyze
# תוצאה: No issues found!
```

## 📝 קבצים ששונו

- `lib/main.dart` - TrainingSummaryFormPage

## 🎨 דוגמת שימוש

1. פתח "סיכום אימון" מדף התרגילים
2. בחר יישוב
3. הזן סוג אימון
4. **הזן כמות נוכחים: 5**
5. טבלה עם 5 שורות תופיע אוטומטית
6. הזן שמות בשדות הטקסט
7. הזן סיכום
8. שמור

---
**תאריך:** ${DateTime.now().toString().split(' ')[0]}
**גרסה:** 1.0.0
