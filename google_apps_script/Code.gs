/**
 * Google Apps Script - יצירת Google Sheets ממערכת המטווחים
 * 
 * הוראות התקנה:
 * 1. פתח https://script.google.com
 * 2. צור פרויקט חדש
 * 3. העתק את הקוד הזה
 * 4. פרסם כ-Web App:
 *    - Execute as: Me (הלון@gmail.com)
 *    - Who has access: Anyone
 * 5. העתק את ה-URL שקיבלת והחלף אותו ב-range_training_page.dart
 *    בשורה: const scriptUrl = 'YOUR_GOOGLE_APPS_SCRIPT_WEB_APP_URL_HERE';
 */

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const title = data.title || 'מטווחים';
    const multipleSheets = data.multipleSheets || false;
    const targetEmail = data.targetEmail || 'הלון@gmail.com';
    
    // יצירת Google Sheet חדש
    const spreadsheet = SpreadsheetApp.create(title);
    
    if (multipleSheets && data.sheets) {
      // ייצוא מרובה - כל משוב בגיליון נפרד
      const sheets = data.sheets;
      
      // מחיקת הגיליון הראשון שנוצר אוטומטית
      const defaultSheet = spreadsheet.getSheets()[0];
      
      // יצירת גיליון לכל משוב
      sheets.forEach((sheetData, index) => {
        let sheet;
        
        if (index === 0) {
          // שימוש בגיליון הראשון הקיים
          sheet = defaultSheet;
          sheet.setName(sheetData.name || `משוב ${index + 1}`);
        } else {
          // יצירת גיליון חדש
          sheet = spreadsheet.insertSheet(sheetData.name || `משוב ${index + 1}`);
        }
        
        const rows = sheetData.data || [];
        
        if (rows.length > 0 && rows[0].length > 0) {
          // כתיבת הנתונים
          sheet.getRange(1, 1, rows.length, rows[0].length).setValues(rows);
          
          // עיצוב שורת הכותרת
          const headerRange = sheet.getRange(1, 1, 1, rows[0].length);
          headerRange.setBackground('#4285f4');
          headerRange.setFontColor('#ffffff');
          headerRange.setFontWeight('bold');
          headerRange.setHorizontalAlignment('center');
          
          // התאמת רוחב עמודות
          for (let i = 1; i <= rows[0].length; i++) {
            sheet.autoResizeColumn(i);
          }
          
          // הקפאת שורת הכותרת
          sheet.setFrozenRows(1);
        }
      });
    } else {
      // ייצוא בודד - גיליון אחד
      const rows = data.data || [];
      const sheet = spreadsheet.getActiveSheet();
      
      // כתיבת הנתונים
      if (rows.length > 0) {
        sheet.getRange(1, 1, rows.length, rows[0].length).setValues(rows);
        
        // עיצוב שורת הכותרת
        const headerRange = sheet.getRange(1, 1, 1, rows[0].length);
        headerRange.setBackground('#4285f4');
        headerRange.setFontColor('#ffffff');
        headerRange.setFontWeight('bold');
        headerRange.setHorizontalAlignment('center');
        
        // התאמת רוחב עמודות
        for (let i = 1; i <= rows[0].length; i++) {
          sheet.autoResizeColumn(i);
        }
        
        // הקפאת שורת הכותרת
        sheet.setFrozenRows(1);
      }
    }
    
    // שיתוף הקובץ עם המשתמש המטרה (אופציונלי)
    // spreadsheet.addEditor(targetEmail);
    
    // החזרת URL של הקובץ
    const url = spreadsheet.getUrl();
    
    return ContentService.createTextOutput(
      JSON.stringify({
        success: true,
        url: url,
        spreadsheetId: spreadsheet.getId()
      })
    ).setMimeType(ContentService.MimeType.JSON);
    
  } catch (error) {
    return ContentService.createTextOutput(
      JSON.stringify({
        success: false,
        error: error.toString()
      })
    ).setMimeType(ContentService.MimeType.JSON);
  }
}

function doGet(e) {
  return ContentService.createTextOutput(
    'Google Apps Script for Range Training Export is running.'
  );
}
