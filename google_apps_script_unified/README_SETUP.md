# הוראות התקנה - ייצוא משובים אחיד ל-Google Sheets

## שלב 1: יצירת Google Sheet קבוע

1. **פתח Google Sheets**: https://sheets.google.com
2. **צור גיליון חדש** ריק
3. **שנה את שם הגיליון** ל-"משובים מאוחדים" או שם אחר
4. **העתק את מזהה הגיליון** מה-URL:
   - URL: `https://docs.google.com/spreadsheets/d/[SPREADSHEET_ID]/edit`
   - העתק את החלק `[SPREADSHEET_ID]`

## שלב 2: הגדרת Google Apps Script

1. **פתח Google Apps Script**: https://script.google.com
2. **צור פרויקט חדש** ושם אותו "Feedback Export Unified"
3. **העתק את הקוד** מ-`google_apps_script_unified/Code.gs`
4. **עדכן את SPREADSHEET_ID**:
   ```javascript
   const SPREADSHEET_ID = 'הכנס_את_המזהה_שלך_כאן';
   ```
5. **שמור** את הקובץ (Ctrl+S)

## שלב 3: פרסום כ-Web App

1. **לחץ "Deploy"** → **"New deployment"**
2. **בחר "Web app"** כסוג
3. **הגדרות**:
   - **Description**: Feedback Export Unified API
   - **Execute as**: Me (החשבון שלך)
   - **Who has access**: Anyone
4. **לחץ "Deploy"**
5. **העתק את ה-Web app URL** שקיבלת

## שלב 4: הרשאות Google Drive

בפעם הראשונה שתריץ את הסקריפט:
1. Google תבקש אישור הרשאות
2. לחץ "Review permissions"
3. בחר את החשבון שלך
4. לחץ "Advanced" → "Go to Feedback Export Unified (unsafe)"
5. לחץ "Allow"

## שלב 5: עדכון הקוד ב-Flutter

1. **פתח** `lib/feedback_export_service.dart`
2. **מצא** את השורה:
   ```dart
   static const String unifiedScriptUrl = 'YOUR_UNIFIED_SCRIPT_URL_HERE';
   ```
3. **החלף** ב-URL שהעתקת
4. **שמור** את הקובץ

## בדיקה

1. **הרץ את האפליקציה**
2. **פתח משוב** כלשהו
3. **לחץ "ייצוא ל-Google Sheets"**
4. **בדוק** שהנתונים נוספו ל-Google Sheet הקבוע