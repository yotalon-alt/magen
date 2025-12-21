/**
 * Google Apps Script - ייצוא משובים אחיד ל-Google Sheets קבוע
 *
 * הוראות התקנה:
 * 1. פתח https://script.google.com
 * 2. צור פרויקט חדש ושם אותו "Feedback Export Unified"
 * 3. העתק את הקוד הזה
 * 4. שנה את SPREADSHEET_ID למזהה של ה-Google Sheet שלך
 * 5. פרסם כ-Web App:
 *    - Execute as: Me
 *    - Who has access: Anyone
 * 6. העתק את ה-URL והכנס אותו ב-Flutter בקובץ feedback_export_service.dart
 */

// מזהה ה-Google Sheet הקבוע (שנה את זה!)
const SPREADSHEET_ID = 'YOUR_SPREADSHEET_ID_HERE';

function doPost(e) {
  try {
    // פרסור הנתונים מה-POST
    const data = JSON.parse(e.postData.contents);
    const feedbacks = data.feedbacks || [];

    if (!SPREADSHEET_ID || SPREADSHEET_ID === 'YOUR_SPREADSHEET_ID_HERE') {
      return ContentService
        .createTextOutput(JSON.stringify({
          success: false,
          error: 'SPREADSHEET_ID לא מוגדר. עדכן את הקוד ב-Google Apps Script.'
        }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // פתיחת ה-Google Sheet הקבוע
    const spreadsheet = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = spreadsheet.getSheets()[0]; // גיליון ראשון

    // הוספת כותרת אם הגיליון ריק
    if (sheet.getLastRow() === 0) {
      const headers = [
        'type',
        'date',
        'command',
        'brigade',
        'settlement',
        'traineeName',
        'rangeName',
        'totalHits',
        'totalShots',
        'scores',
        'notes'
      ];
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);

      // עיצוב כותרת
      const headerRange = sheet.getRange(1, 1, 1, headers.length);
      headerRange.setBackground('#4285f4');
      headerRange.setFontColor('#ffffff');
      headerRange.setFontWeight('bold');
      headerRange.setHorizontalAlignment('center');
      headerRange.setVerticalAlignment('middle');
      headerRange.setWrap(true);

      // הקפאת שורת כותרת
      sheet.setFrozenRows(1);
    }

    // הוספת כל משוב כשורה חדשה
    const startRow = sheet.getLastRow() + 1;
    const rows = [];

    for (const feedback of feedbacks) {
      const row = [
        feedback.type || '',
        feedback.date || '',
        feedback.command || '',
        feedback.brigade || '',
        feedback.settlement || '',
        feedback.traineeName || '',
        feedback.rangeName || '',
        feedback.totalHits || '',
        feedback.totalShots || '',
        feedback.scores || '',
        feedback.notes || ''
      ];
      rows.push(row);
    }

    // כתיבת כל השורות בבת אחת
    if (rows.length > 0) {
      sheet.getRange(startRow, 1, rows.length, rows[0].length).setValues(rows);

      // התאמת רוחב עמודות אוטומטית
      for (let i = 1; i <= rows[0].length; i++) {
        sheet.autoResizeColumn(i);
      }
    }

    return ContentService
      .createTextOutput(JSON.stringify({
        success: true,
        message: `הוספו ${rows.length} משובים בהצלחה`,
        spreadsheetUrl: spreadsheet.getUrl()
      }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService
      .createTextOutput(JSON.stringify({
        success: false,
        error: error.toString()
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function doGet(e) {
  return ContentService
    .createTextOutput('Feedback Export Unified API is running')
    .setMimeType(ContentService.MimeType.TEXT);
}