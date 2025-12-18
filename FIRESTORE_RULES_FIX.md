# Firestore Security Rules - תיקון הרשאות

## הבעיה שזוהתה

הקוד ניסה לכתוב לנתיב שגוי:
```
feedbacks/instructor_course_selection/suitable
```

זה נתיב לא תקין ב-Firestore (מנסה ליצור collection בתוך document בלי שה-document קיים).

## הפתרון

שינינו את ה-collections לנתיבים ברמה הראשית:
- `instructor_course_selection_suitable`
- `instructor_course_selection_not_suitable`

## Firestore Security Rules הנדרשות

הוסף את הכללים הבאים ל-`firestore.rules`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Existing rules for feedbacks collection
    match /feedbacks/{feedbackId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
                   && request.auth.uid == request.resource.data.instructorId;
    }
    
    // NEW: Rules for instructor course selection - suitable candidates
    match /instructor_course_selection_suitable/{docId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null 
                    && request.auth.uid == request.resource.data.instructorId;
      allow update, delete: if request.auth != null 
                            && request.auth.uid == resource.data.instructorId;
    }
    
    // NEW: Rules for instructor course selection - not suitable candidates
    match /instructor_course_selection_not_suitable/{docId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null 
                    && request.auth.uid == request.resource.data.instructorId;
      allow update, delete: if request.auth != null 
                            && request.auth.uid == resource.data.instructorId;
    }
    
    // Users collection (if exists)
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## שלבי הפעלה

1. **בקונסול Firebase**:
   - עבור ל-Firestore Database
   - לחץ על "Rules"
   - הוסף את הכללים לעיל
   - לחץ "Publish"

2. **ודא שהמשתמש מחובר**:
   - הקוד כעת בודק `FirebaseAuth.instance.currentUser?.uid`
   - אם המשתמש לא מחובר, תזרק שגיאה

3. **בדיקה**:
   - נסה לשמור משוב חדש
   - ודא שההודעה מציינת את ה-collection הנכון
   - בדוק ב-Firestore Console שהמסמך נוצר תחת:
     - `instructor_course_selection_suitable` או
     - `instructor_course_selection_not_suitable`

## שינויים בקוד

### קבצים ששונו:
1. `lib/instructor_course_feedback_page.dart`:
   - תיקון collection path
   - הוספת `instructorId` לכל document
   - הוספת בדיקת authentication
   
2. `lib/instructor_course_selection_feedbacks_page.dart`:
   - תיקון collection path בקריאה

### מה השתנה:
```dart
// ❌ BEFORE (שגוי):
'feedbacks/instructor_course_selection/suitable'

// ✅ AFTER (תקין):
'instructor_course_selection_suitable'
```

## הערות חשובות

1. **Data Migration**: אם יש נתונים ישנים תחת הנתיב הישן, צריך להעביר אותם.
2. **Authentication**: ודא שכל משתמש מחובר לפני שמירת משוב.
3. **Index**: אם צריך לסנן לפי `instructorId`, יש ליצור composite index ב-Firestore.
