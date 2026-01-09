# Criteria Scope Separation Fix

## Problem
The feedback form was showing ALL criteria (including Street Scan-specific criteria) for ALL exercises (מעגל פתוח, מעגל פרוץ, סריקות רחוב). This caused confusion as instructors could select street scan criteria for exercises where they didn't apply.

## Solution
Refactored the criteria system to be **exercise-specific** using a computed getter:

### Code Changes in `lib/main.dart`

**Before:**
- Single shared `availableCriteria` list for all exercises
- All 14 criteria available regardless of exercise type

**After:**
- Two static criteria lists:
  - `_baseCriteria` (9 items): Used by מעגל פתוח and מעגל פרוץ
  - `_streetScanCriteria` (5 items): Additional criteria for סריקות רחוב only
- Computed `availableCriteria` getter that returns appropriate list based on `selectedExercise`
- Helper method `_initializeCriteriaForExercise()` to reinitialize maps when exercise changes

## Criteria Distribution

### מעגל פתוח & מעגל פרוץ (9 criteria)
1. פוש
2. הכרזה
3. הפצה
4. מיקום המפקד
5. מיקום הכוח
6. חיילות פרט
7. מקצועיות המחלקה
8. הבנת האירוע
9. תפקוד באירוע

### סריקות רחוב (14 criteria)
**All 9 base criteria PLUS:**
10. אבטחה היקפית
11. שמירה על קשר בתוך הכוח הסורק
12. שליטה בכוח
13. יצירת גירוי והאזנה לשטח
14. עבודה ממרכז הרחוב והחוצה

## Testing Checklist
- [ ] Open feedback form for מעגל פתוח → Verify only 9 base criteria appear
- [ ] Open feedback form for מעגל פרוץ → Verify only 9 base criteria appear
- [ ] Open feedback form for סריקות רחוב → Verify all 14 criteria appear
- [ ] Switch between exercises → Verify criteria update correctly
- [ ] Submit feedback for each exercise type → Verify only selected criteria are saved

## Impact
- **UX Improvement**: Instructors only see relevant criteria for each exercise
- **Data Quality**: Prevents accidental selection of irrelevant criteria
- **Maintainability**: Clear separation of base vs exercise-specific criteria

## Files Modified
- `lib/main.dart` (FeedbackFormPage):
  - Replaced `availableCriteria` list with computed getter
  - Added `_baseCriteria` and `_streetScanCriteria` static constants
  - Added `_initializeCriteriaForExercise()` helper method

## Verification
```bash
flutter analyze
```
Result: ✅ No issues found!
