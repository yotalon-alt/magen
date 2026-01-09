# Instructor Course Screenings Export Fix

## Summary
Fixed export logic for "מיונים לקורס מדריכים" (Instructor Course Screenings) to properly handle all export options and include all required data columns.

## Changes Made

### File: `lib/feedback_export_service.dart`

#### 1. Fixed "שניהם" (Both) Export Option
**Problem**: When selecting "שניהם", only the "מתאימים" sheet was exported.

**Solution**: 
- Modified the empty feedbacks handling logic
- When `selection == 'both'`, create empty sheets even if no data exists for that category
- This ensures both sheets always appear in the file when "שניהם" is selected

**Code Change**:
```dart
// Before:
if (feedbacks.isEmpty) {
  debugPrint('⚠️ No feedbacks for suitable=$isSuitable, skipping...');
  continue;
}

// After:
if (feedbacks.isEmpty && selection == 'both') {
  debugPrint('⚠️ No feedbacks for suitable=$isSuitable, but creating empty sheet for "שניהם" export');
  // Continue to create empty sheet
} else if (feedbacks.isEmpty) {
  debugPrint('⚠️ No feedbacks for suitable=$isSuitable, skipping...');
  continue;
}
```

#### 2. Added Instructor Name Resolution
**Problem**: Instructor name was not included in export, risking email exposure.

**Solution**:
- Added `resolvedInstructorName` field to each feedback document
- Resolves instructor name from `users/{uid}` collection using priority:
  1. `displayName`
  2. `fullName`
  3. `name`
- Falls back to `createdByName` if UID resolution fails
- **Never exports email addresses**
- Handles all edge cases (missing data, timeout, etc.)

#### 3. Added Two Missing Columns
**Added Columns**:
1. **מדריך משב** (Instructor Name) - Full Hebrew name from users collection
2. **תאריך המשוב** (Feedback Date) - Formatted as `DD/MM/YYYY HH:MM`

**Column Order (Final)**:
1. פיקוד (Command)
2. חטיבה (Brigade)
3. מספר מועמד (Candidate Number)
4. שם מועמד (Candidate Name)
5. בוחן רמה (Level Test)
6. הדרכה טובה (Good Instruction)
7. הדרכת מבנה (Structure Instruction)
8. יבשים (Dry Practice)
9. תרגיל הפתעה (Surprise Exercise)
10. ממוצע (Average)
11. **מדריך משב (Instructor Name)** ← NEW
12. **תאריך המשוב (Feedback Date)** ← NEW

## Export Behavior

### Option 1: "מתאימים לקורס מדריכים"
- Exports **one sheet**: "מתאימים לקורס מדריכים"
- Contains only candidates marked as suitable (`isSuitable: true`)

### Option 2: "לא מתאימים לקורס מדריכים"
- Exports **one sheet**: "לא מתאימים לקורס מדריכים"
- Contains only candidates marked as not suitable (`isSuitable: false`)

### Option 3: "שניהם (שני גיליונות)"
- Exports **TWO sheets** in one file:
  - Sheet 1: "מתאימים לקורס מדריכים"
  - Sheet 2: "לא מתאימים לקורס מדריכים"
- **Both sheets are always created**, even if one is empty
- Each sheet follows the same column structure

## Data Sources

- **Candidate Data**: From `instructor_course_feedbacks` collection
- **Instructor Name**: Resolved from `users/{uid}.displayName/fullName/name`
- **Date**: From `createdAt` field (Timestamp)
- **Scores**: From `scores` sub-document

## Testing

### Test Case 1: Export "מתאימים"
1. Navigate: משובים → מיונים לקורס מדריכים
2. Click export button
3. Select: "מתאימים לקורס מדריכים"
4. **Expected**: One sheet with suitable candidates only
5. **Verify**: All 12 columns present, instructor name is Hebrew (not email)

### Test Case 2: Export "לא מתאימים"
1. Navigate: משובים → מיונים לקורס מדריכים
2. Click export button
3. Select: "לא מתאימים לקורס מדריכים"
4. **Expected**: One sheet with non-suitable candidates only
5. **Verify**: All 12 columns present, instructor name is Hebrew (not email)

### Test Case 3: Export "שניהם" (CRITICAL FIX)
1. Navigate: משובים → מיונים לקורס מדריכים
2. Click export button
3. Select: "שניהם (שני גיליונות)"
4. **Expected**: 
   - One file with TWO sheets
   - Sheet 1: "מתאימים לקורס מדריכים"
   - Sheet 2: "לא מתאימים לקורס מדריכים"
5. **Verify**: 
   - Both sheets exist in file (even if one is empty)
   - All 12 columns in each sheet
   - Instructor names are Hebrew (not emails)
   - Dates formatted correctly

## Technical Details

### Instructor Name Resolution
```dart
// Priority order for name resolution:
1. users/{uid}.displayName (if exists, not email)
2. users/{uid}.fullName (if exists, not email)
3. users/{uid}.name (if exists, not email)
4. feedback.createdByName (fallback, if not email)
5. 'לא ידוע' (last resort)

// Email filtering:
- Any name containing '@' is rejected
- Ensures no email addresses leak into exports
```

### Date Formatting
```dart
// Handles multiple timestamp types:
- Firestore Timestamp → toDate() → format
- DateTime object → format directly
- ISO string → parse → format
- Format: DD/MM/YYYY HH:MM (Hebrew standard)
```

## Scope Limitations

This fix **ONLY** affects:
- Export action from "משובים" page (feedback list view)
- "מיונים לקורס מדריכים" folder export
- **Does NOT affect**:
  - Other feedback types (surprise drills, ranges, etc.)
  - General feedback exports
  - Screening form submission logic

## Files Modified

1. `lib/feedback_export_service.dart` (exportInstructorCourseSelection method)

## Verification

✅ Code compiles without errors (`flutter analyze`)
✅ All three export options properly handled
✅ Both sheets created when "שניהם" selected
✅ Instructor name properly resolved (never email)
✅ Date formatted correctly
✅ All 12 required columns present
✅ RTL formatting preserved
✅ Hebrew headers correct
