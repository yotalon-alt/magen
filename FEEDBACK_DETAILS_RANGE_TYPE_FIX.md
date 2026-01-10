# Feedback Details Range Type Display Fix

## Summary
Updated the Feedback Details page to display "טווח:" (Range:) with the range type (קצר/ארוך) instead of "תפקיד:" (Role:) for shooting range feedbacks.

## Changes Made

### File: `lib/main.dart` (lines 4543-4556)

**Before:**
```dart
Text('תפקיד: ${feedback.role}'),
```

**After:**
```dart
// Conditional display: "טווח:" for shooting ranges, "תפקיד:" for others
(feedback.folderKey == 'shooting_ranges' ||
        feedback.folderKey == 'ranges_474' ||
        feedback.folder == 'מטווחי ירי' ||
        feedback.folder == 'מטווחים 474' ||
        feedback.module == 'shooting_ranges')
    ? Text(
        'טווח: ${feedback.rangeSubType.isNotEmpty ? feedback.rangeSubType : 'לא ידוע'}',
      )
    : Text('תפקיד: ${feedback.role}'),
```

### Detection Logic
The code checks multiple fields to ensure backward compatibility:
- `folderKey == 'shooting_ranges'` (new schema)
- `folderKey == 'ranges_474'` (new schema for 474 ranges)
- `folder == 'מטווחי ירי'` (legacy schema for general ranges)
- `folder == 'מטווחים 474'` (legacy schema for 474 ranges)
- `module == 'shooting_ranges'` (alternative field)

### Data Source
- **Field used:** `feedback.rangeSubType`
- **Populated by:** `FeedbackModel.fromMap()` at line 253
- **Firestore field:** `rangeSubType`
- **Expected values:** 
  - 'טווח קצר' (Short Range)
  - 'טווח רחוק' (Long Range)
- **Fallback:** 'לא ידוע' (Unknown) if `rangeSubType` is empty

## Testing Checklist

### ✅ Prerequisites
1. Have at least one shooting range feedback saved:
   - Short range (טווח קצר)
   - Long range (טווח רחוק)
   - 474 ranges (מטווחים 474)
2. Have at least one non-range feedback (מעגל פתוח, מעגל פרוץ, etc.)

### Test Cases

#### Test 1: Short Range Feedback
1. Navigate to **משובים** tab
2. Select folder **מטווחי ירי**
3. Open a short range feedback
4. **Expected:**
   - Header shows: `טווח: טווח קצר`
   - Should NOT show: `תפקיד:`

#### Test 2: Long Range Feedback
1. Navigate to **משובים** tab
2. Select folder **מטווחי ירי**
3. Open a long range feedback
4. **Expected:**
   - Header shows: `טווח: טווח רחוק`
   - Should NOT show: `תפקיד:`

#### Test 3: 474 Ranges Feedback
1. Navigate to **משובים** tab
2. Select folder **מטווחים 474**
3. Open any 474 range feedback
4. **Expected:**
   - Header shows: `טווח: [טווח קצר או טווח רחוק]`
   - Should NOT show: `תפקיד:`

#### Test 4: Non-Range Feedback (Regression Test)
1. Navigate to **משובים** tab
2. Select folder **משובים – כללי** or **מחלקות ההגנה – חטיבה 474**
3. Open a feedback for מעגל פתוח, מעגל פרוץ, or סריקות רחוב
4. **Expected:**
   - Header shows: `תפקיד: [role]` (e.g., רבש"ץ, מפקד מחלקה)
   - Should NOT show: `טווח:`

#### Test 5: Empty rangeSubType Fallback
1. If you have an old range feedback without `rangeSubType` populated:
   - Open the feedback
   - **Expected:** Header shows: `טווח: לא ידוע`

### Visual Verification Points
- [ ] Correct Hebrew label ("טווח:" vs "תפקיד:")
- [ ] Correct value displayed (range type vs role)
- [ ] Proper text styling (consistent with other fields)
- [ ] No layout shifts or UI breaks
- [ ] Works on both mobile and desktop layouts

## Verification Commands

### Check for Compilation Errors
```bash
flutter analyze lib/main.dart
```

### Run the App
```bash
flutter run -d chrome
```

## Expected Console Output
No special debug output expected. The change is purely UI display logic.

## Rollback Instructions
If issues occur, revert to:
```dart
Text('תפקיד: ${feedback.role}'),
```

## Related Files
- `lib/main.dart` - FeedbackDetailsPage (line 4543)
- `lib/main.dart` - FeedbackModel.fromMap (line 253) - populates rangeSubType
- `lib/range_training_page.dart` - Sets rangeSubType when saving range feedbacks

## Implementation Notes
1. **Backward Compatible:** Checks both new schema (`folderKey`, `module`) and legacy schema (`folder`)
2. **Safe Fallback:** Shows 'לא ידוע' if `rangeSubType` is empty
3. **No Breaking Changes:** Non-range feedbacks continue to show role as before
4. **Data Already Available:** `rangeSubType` field already exists in FeedbackModel and is populated from Firestore

## Next Steps
After verifying this fix works correctly:
1. Continue debugging the long-range score division bug (75→7, 100→10)
2. Run the debug session with the extensive logging added to `range_training_page.dart`
3. Identify the exact location where the value transformation occurs

---
**Status:** ✅ Implementation Complete - Ready for Testing
**Created:** 2025-01-XX
**Related Issue:** "Update 'Feedback Details' header fields for shooting ranges"
