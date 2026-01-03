# Instructor Course Selection - Save Flow Fix

## Issues Fixed

### A) Final feedback remains in TEMP collection
**Problem**: After clicking "Save Feedback" (final), feedback stayed in `instructor_course_screenings` (temp) and didn't appear in final list.

**Root Cause**: The `finalizeScreeningAndCreateFeedback()` function was a stub (empty implementation). No final collection write or temp cleanup occurred.

**Solution**: Implemented proper `finalizeInstructorCourseFeedback()` function that:
- Creates document in **`instructor_course_feedbacks`** collection (final)
- Deletes temp draft from **`instructor_course_screenings`** collection
- Adds proper `module`, `type`, `isTemporary` fields

---

### B) Exit dialog appears after successful save
**Problem**: "Exit without saving?" dialog appeared even after clicking save and getting success message.

**Root Cause**: Exit logic checked `hasDraft` property (whether temp doc exists) instead of tracking actual unsaved changes.

**Solution**: 
- Added **`_hasUnsavedChanges`** boolean flag
- Set to `true` on any field edit
- Set to `false` after successful temp OR final save
- Exit dialog only shows if `_hasUnsavedChanges == true`

---

### C) Form not locked after final save
**Problem**: User could still edit form after finalization, potentially causing data inconsistency.

**Root Cause**: No form locking mechanism existed.

**Solution**:
- Added **`_isFormLocked`** boolean flag
- Set to `true` after successful finalization
- All input fields disabled when `_isFormLocked == true`
- Visual indicator shows "המשוב נסגר - לא ניתן לערוך"

---

## Implementation Details

### Data Model & Collections

**TEMP Collection**: `instructor_course_screenings`
- Status: `'draft'`
- Used for autosave/work in progress
- Implicit `isTemporary: true`

**FINAL Collection**: `instructor_course_feedbacks`
- Status: `'finalized'`
- Contains completed, locked feedbacks
- Explicit `isTemporary: false`
- Additional fields: `module`, `type`, `finalWeightedScore`, `isSuitable`

### Save Functions

#### 1. `saveInstructorCourseTempFeedback()` - Temporary Save

**Purpose**: Save work in progress (autosave/draft)

**Collection**: `instructor_course_screenings`

**Document Fields**:
```dart
{
  'status': 'draft',
  'courseType': 'miunim',
  'createdAt': Timestamp,
  'updatedAt': Timestamp,
  'createdBy': uid,
  'command': 'פיקוד צפון',
  'brigade': 'חטיבה 474',
  'candidateName': 'דוד כהן',
  'candidateNumber': 42,
  'fields': {
    'בוחן רמה': {value: 4, hits: 9, timeSeconds: 10},
    'תרגיל הפתעה': {value: 5},
    // ... other categories
  }
}
```

**Console Output**:
```
========== TEMP SAVE: INSTRUCTOR COURSE ==========
SAVE: collection=instructor_course_screenings
SAVE: docId=abc123xyz
SAVE: status=draft
SAVE: isTemporary=true (implicit)
=================================================
```

**State Changes After Save**:
- `_hasUnsavedChanges = false` ✅ Prevents exit dialog
- Form remains editable ✅

---

#### 2. `finalizeInstructorCourseFeedback()` - Final Save

**Purpose**: Finalize and move to completed feedbacks

**Collection**: `instructor_course_feedbacks`

**Document Fields** (NEW document in final collection):
```dart
{
  'status': 'finalized',
  'courseType': 'miunim',
  'createdAt': Timestamp,
  'finalizedAt': Timestamp,
  'createdBy': uid,
  'command': 'פיקוד צפון',
  'brigade': 'חטיבה 474',
  'candidateName': 'דוד כהן',
  'candidateNumber': 42,
  'fields': {/* all categories */},
  'finalWeightedScore': 4.2,
  'isSuitable': true,
  'module': 'instructor_course_selection',
  'type': 'instructor_course_feedback',
  'isTemporary': false  // ← Explicit final marker
}
```

**Console Output**:
```
========== FINAL SAVE: INSTRUCTOR COURSE ==========
SAVE: collection=instructor_course_feedbacks
SAVE: docId=xyz789abc (NEW auto-generated ID)
SAVE: module=instructor_course_selection
SAVE: type=instructor_course_feedback
SAVE: isTemporary=false
SAVE: status=finalized
===================================================
SAVE: Deleting temp draft: abc123xyz
SAVE: Temp draft deleted successfully
```

**State Changes After Finalize**:
- `_hasUnsavedChanges = false` ✅ Prevents exit dialog
- `_isFormLocked = true` ✅ Disables all inputs
- Temp document deleted ✅ Cleanup
- Navigates back after 500ms ✅

---

### Form Locking (Only Instructor Course)

**Visual Indicator** (shown when locked):
```
┌────────────────────────────────────────┐
│ 🔒 המשוב נסגר - לא ניתן לערוך          │
└────────────────────────────────────────┘
```

**Disabled Fields** (when `_isFormLocked == true`):
- ✅ פיקוד dropdown
- ✅ חטיבה text field
- ✅ שם מועמד text field
- ✅ מספר מועמד dropdown
- ✅ All category score buttons (בוחן רמה, הדרכה טובה, etc.)
- ✅ Level test inputs (hits, time)
- ✅ Save button
- ✅ Finalize button

**Still Enabled**:
- ✅ Back button (to exit)
- ✅ View final score/classification

---

### Exit Dialog Logic

**BEFORE (Broken)**:
```dart
if (hasDraft) {  // Always true if temp doc exists
  showDialog("Exit without saving?")
}
```

**AFTER (Fixed)**:
```dart
if (_hasUnsavedChanges && !_isFormLocked) {  // Only if actual changes
  showDialog("יש שינויים שלא נשמרו")
}
```

**Scenarios**:

| Scenario | `_hasUnsavedChanges` | `_isFormLocked` | Dialog Shown? |
|----------|---------------------|-----------------|---------------|
| Fresh load | `false` | `false` | ❌ No |
| User edits field | `true` | `false` | ✅ Yes |
| After temp save | `false` | `false` | ❌ No |
| After finalize | `false` | `true` | ❌ No |

---

## List Queries (Future Enhancement)

### Current State
Queries not yet updated (will be done separately). Collections exist and data is properly saved.

### Recommended Queries

**Final Feedbacks List**:
```dart
FirebaseFirestore.instance
    .collection('instructor_course_feedbacks')
    .where('isTemporary', isEqualTo: false)
    .orderBy('finalizedAt', descending: true)
```

**Temp Drafts List** (if showing in-progress):
```dart
FirebaseFirestore.instance
    .collection('instructor_course_screenings')
    .where('status', isEqualTo: 'draft')
    .orderBy('updatedAt', descending: true)
```

**Backward Compatibility** (include legacy docs):
```dart
// Include both new (with module) and legacy (without module)
feedbacks.where((f) {
  if (f.module.isNotEmpty) {
    return f.module == 'instructor_course_selection' && !f.isTemporary;
  }
  // Legacy: use folder or other field
  return f.courseType == 'miunim' && f.status == 'finalized';
})
```

---

## Field Change Tracking

**`_markFormDirty()` called on**:
- ✅ Pikud selection change
- ✅ Hativa text change
- ✅ Candidate name change
- ✅ Candidate number change
- ✅ Category score selection
- ✅ Level test hits/time input

**NOT called when**:
- ❌ Form is locked (`_isFormLocked == true`)
- ❌ Loading existing data (`_loadExistingScreening`)

---

## Testing Checklist

### Test 1: Temp Save Flow
1. Open instructor course feedback page
2. Fill candidate details (פיקוד, חטיבה, שם, מספר)
3. Fill some category scores
4. Click "שמור משוב" button
5. **Expected**:
   - ✅ Success message: "נשמר כמשוב בתהליך (draft)"
   - ✅ Console shows: `SAVE: collection=instructor_course_screenings`
   - ✅ `_hasUnsavedChanges = false`
6. Click back button
7. **Expected**:
   - ✅ NO exit dialog (saved successfully)

---

### Test 2: Exit After Temp Save
1. Open existing temp feedback
2. Edit a field (change name)
3. **Expected**: `_hasUnsavedChanges = true`
4. Click back button
5. **Expected**: ✅ Exit dialog appears
6. Choose "Stay"
7. Click "שמור משוב"
8. **Expected**: `_hasUnsavedChanges = false`
9. Click back button
10. **Expected**: ✅ NO dialog (navigates immediately)

---

### Test 3: Final Save Flow
1. Open temp feedback
2. Fill ALL required fields and categories
3. Click "סיים משוב" button
4. **Expected Console Output**:
   ```
   ========== FINAL SAVE: INSTRUCTOR COURSE ==========
   SAVE: collection=instructor_course_feedbacks
   SAVE: docId=<new-auto-id>
   SAVE: module=instructor_course_selection
   SAVE: type=instructor_course_feedback
   SAVE: isTemporary=false
   SAVE: status=finalized
   ===================================================
   SAVE: Deleting temp draft: <old-temp-id>
   SAVE: Temp draft deleted successfully
   ```
5. **Expected UI**:
   - ✅ Success message: "המשוב נסגר והועבר למשובים סופיים"
   - ✅ Form shows lock indicator: "🔒 המשוב נסגר - לא ניתן לערוך"
   - ✅ All inputs disabled (grayed out)
   - ✅ Auto-navigate back after 500ms

---

### Test 4: Form Locking
1. Open finalized feedback (from list)
2. **Expected**:
   - ✅ Lock indicator at top
   - ✅ All dropdowns disabled (can't select)
   - ✅ All text fields disabled (can't type)
   - ✅ All score buttons disabled (can't click)
   - ✅ "שמור משוב" button disabled
   - ✅ "סיים משוב" button disabled
3. Try clicking back button
4. **Expected**: ✅ NO dialog (navigates immediately)

---

### Test 5: Exit Without Saving
1. Open new feedback form
2. Fill some fields
3. **Do NOT click save**
4. Click back button
5. **Expected**: ✅ Dialog: "יש שינויים שלא נשמרו"
6. Choose "Exit Anyway"
7. **Expected**: ✅ Navigates back (data lost - intended)

---

### Test 6: Collections Verification (Firestore Console)

**After Temp Save**:
1. Open Firestore Console
2. Navigate to `instructor_course_screenings` collection
3. Find document with your `candidateName`
4. **Expected Fields**:
   - ✅ `status: "draft"`
   - ✅ `updatedAt: <recent timestamp>`
   - ✅ `fields: {<your scores>}`

**After Final Save**:
1. Navigate to `instructor_course_feedbacks` collection
2. Find NEW document (different ID)
3. **Expected Fields**:
   - ✅ `status: "finalized"`
   - ✅ `module: "instructor_course_selection"`
   - ✅ `type: "instructor_course_feedback"`
   - ✅ `isTemporary: false`
   - ✅ `finalWeightedScore: <number>`
   - ✅ `isSuitable: <boolean>`
4. Go back to `instructor_course_screenings`
5. **Expected**: ✅ Temp document deleted (not found)

---

## File Changes Summary

**File Modified**: `lib/instructor_course_feedback_page.dart`

**Lines Changed**: ~200 lines (comprehensive refactor)

**Key Additions**:
1. `_hasUnsavedChanges` state tracking
2. `_isFormLocked` state for post-finalization
3. `_markFormDirty()` helper method
4. `saveInstructorCourseTempFeedback()` function (renamed + logging)
5. `finalizeInstructorCourseFeedback()` function (complete implementation)
6. Exit dialog logic update (use `_hasUnsavedChanges`)
7. Form locking UI (lock indicator + disabled inputs)
8. Comprehensive console logging for debugging

---

## No Changes to Other Modules

**Confirmed**: Changes ONLY affect instructor course selection page.

**Other modules unchanged**:
- ✅ Surprise Drills (range_training_page.dart)
- ✅ Shooting Ranges (range_training_page.dart)
- ✅ General Feedbacks (main.dart)
- ✅ All other pages

---

## Success Criteria

### ✅ Final save moves item from temp to final
- Final document created in `instructor_course_feedbacks` ✅
- Temp document deleted from `instructor_course_screenings` ✅
- Proper `module`, `type`, `isTemporary` fields ✅

### ✅ Exit dialog does NOT appear after save
- `_hasUnsavedChanges = false` after temp save ✅
- `_hasUnsavedChanges = false` after final save ✅
- Dialog only when actually unsaved ✅

### ✅ Form locked after final save (instructor-course only)
- `_isFormLocked = true` after finalize ✅
- All inputs disabled ✅
- Visual indicator shown ✅
- Other modules unaffected ✅

---

**Status**: ✅ IMPLEMENTED - Ready for testing  
**Date**: January 3, 2026  
**Collections**: `instructor_course_screenings` (temp), `instructor_course_feedbacks` (final)  
**Module**: Instructor Course Selection ONLY
