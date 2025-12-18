# הוראות התקנה - ייצוא Google Sheets

## שלב 1: הגדרת Google Apps Script

1. **פתח Google Apps Script**
   - עבור ל: https://script.google.com
   - התחבר עם החשבון: הלון@gmail.com

2. **צור פרויקט חדש**
   - לחץ על "פרויקט חדש" (New Project)
   - שנה את השם ל: "Range Training Export"

3. **העתק את הקוד**
   - פתח את הקובץ: `google_apps_script/Code.gs`
   - העתק את כל התוכן
   - הדבק ב-Google Apps Script (מחק את הקוד הקיים)
   - שמור (Ctrl+S או File → Save)

4. **פרסם כ-Web App**
   - לחץ על "Deploy" → "New deployment"
   - בחר "Web app" כסוג
   - הגדרות:
     * **Description**: Range Training Export API
     * **Execute as**: Me (הלון@gmail.com)
     * **Who has access**: Anyone
   - לחץ "Deploy"
   - העתק את ה-**Web app URL** שקיבלת

5. **עדכן את הקוד ב-Flutter**
   - פתח: `lib/range_training_page.dart`
   - מצא את השורה:
     ```dart
     const scriptUrl = 'YOUR_GOOGLE_APPS_SCRIPT_WEB_APP_URL_HERE';
     ```
   - החלף את `YOUR_GOOGLE_APPS_SCRIPT_WEB_APP_URL_HERE` ב-URL שהעתקת
   - שמור את הקובץ

## שלב 2: הרשאות Google Drive

1. **בפעם הראשונה** שתריץ את הסקריפט:
   - Google תבקש ממך אישור הרשאות
   - לחץ "Review permissions"
   - בחר את החשבון: הלון@gmail.com
   - לחץ "Advanced" → "Go to Range Training Export (unsafe)"
   - לחץ "Allow"

2. **הרשאות נדרשות**:
   - יצירת Google Sheets חדשים
   - גישה ל-Google Drive שלך

## שלב 3: בדיקה

1. **בדוק שה-Script עובד**:
   - בדפדפן, עבור ל-URL של ה-Web App
   - אמורה להופיע ההודעה: "Google Apps Script for Range Training Export is running."

2. **בדוק בפלאטר**:
   - פתח את האפליקציה כ-Admin
   - מלא טופס מטווח
   - לחץ "ייצוא ל-Google Sheets"
   - וודא שהקובץ נוצר ב-Google Drive

## פתרון בעיות

### שגיאה: "Script not found"
- ודא שה-URL נכון
- ודא שפרסמת את ה-Script כ-Web App

### שגיאה: "Authorization required"
- עבור ל-Google Apps Script
- הרץ את הפונקציה `doPost` ידנית פעם אחת
- אשר את ההרשאות

### הקובץ לא נוצר
- בדוק שיש לך אינטרנט
- בדוק שה-Script פעיל ב-Google Apps Script

### הכפתור לא מופיע
- ודא שאתה מחובר כ-Admin
- בדוק ש-`currentUser?.role == 'Admin'`

## מבנה הקובץ המיוצא

הקובץ Google Sheets יכלול:

### עמודות:
1. תאריך
2. יישוב/מחלקה
3. מדריך
4. מספר נוכחים
5. סוג מטווח
6. שם חניך
7. לכל מקצה: עמודת פגיעות ועמודת כדורים
8. סה"כ פגיעות/כדורים

### עיצוב:
- שורת כותרת כחולה עם טקסט לבן
- עמודות מותאמות אוטומטית
- שורת כותרת קפואה (Frozen)

## הערות נוספות

1. **כל ייצוא יוצר קובץ חדש** - אין דריסה של קבצים קיימים
2. **שם הקובץ**: "מטווחים – תאריך – שעה"
3. **מיקום**: Google Drive של החשבון הלון@gmail.com
4. **הרשאות**: רק Admin יכול לייצא
5. **הקובץ נפתח** גם במובייל וגם בדסקטופ

## תמיכה

אם יש בעיה, בדוק:
1. את הלוגים ב-Google Apps Script (View → Logs)
2. את התגובה מה-Server בקונסול של Flutter
3. שה-URL נכון ב-`range_training_page.dart`
