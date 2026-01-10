# Draft → Final Save Folder Persistence Fix

## Problem Statement
**CRITICAL BUG**: When Short Range or Long Range feedback is reopened from draft, final save does not persist it to the selected folder. Saving works ONLY when completed in one session.

### Root Cause
1. Draft save: Stored `folderKey`, `folderLabel`, and `rangeFolder` ✅
2. Draft load: Only restored `rangeFolder` to state ❌
3. Final save: **RECOMPUTED** `folderKey`/`folderLabel` from `rangeFolder` every time ⚠️
4. If `rangeFolder` was empty/null during draft save, draft stored `''` (empty string)
5. On draft load, `rangeFolder` was set to `''`, failing validation at final save

## Solution Implemented

### 1. Added State Variables (lines 145-146)
```dart
String? loadedFolderKey; // ✅ Folder ID loaded from draft (if any)
String? loadedFolderLabel; // ✅ Folder label loaded from draft (if any)
```

### 2. Draft Load: Extract Folder Fields (lines 1729-1730)
```dart
final rawFolderKey = data['folderKey'] as String?; // ✅ Load folder ID
final rawFolderLabel = data['folderLabel'] as String?; // ✅ Load folder label
```

### 3. Draft Load: Restore to State (lines 1855-1856)
```dart
loadedFolderKey = rawFolderKey; // ✅ Store loaded folder ID (can be null)
loadedFolderLabel = rawFolderLabel; // ✅ Store loaded folder label (can be null)
```

### 4. Final Save: Use Loaded Values (lines 1008-1048)
**PRIORITY LOGIC:**
1. **IF loaded from draft**: Use `loadedFolderKey` and `loadedFolderLabel` (don't recompute)
2. **ELSE**: Compute from `rangeFolder` UI selection

```dart
// Check if folder fields were loaded from draft
if (loadedFolderKey != null && loadedFolderKey!.isNotEmpty) {
  // ✅ REUSE LOADED VALUES - Don't recompute to avoid bugs
  folderKey = loadedFolderKey!;
  folderLabel = loadedFolderLabel ?? folderKey;
  folderId = folderKey;
  debugPrint('SAVE: Using LOADED folder fields');
} else {
  // ✅ COMPUTE FROM UI SELECTION (new feedback)
  final uiFolderValue = (rangeFolder ?? '').toString();
  // ... existing logic ...
  debugPrint('SAVE: COMPUTED folder fields from UI');
}
```

### 5. Added Defensive Validation (lines 1051-1063)
```dart
// ✅ CRITICAL VALIDATION: Ensure folder fields are never empty
if (folderKey.isEmpty || folderLabel.isEmpty) {
  debugPrint('❌ SAVE ERROR: Empty folder fields!');
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('שגיאה פנימית: נתוני תיקייה חסרים. אנא בחר תיקייה מחדש.'),
      backgroundColor: Colors.red,
    ),
  );
  return;
}
```

## Testing Requirements

### Test Case 1: Path A - Draft → Final Save (מטווחים 474)
**Steps:**
1. Login as instructor
2. Create new Long Range feedback
3. Select folder: "מטווחים 474"
4. Select settlement: any
5. Enter attendees count: 10
6. Add stages (at least 1)
7. Enter trainee data
8. **Exit WITHOUT saving** (draft auto-saves)
9. Reopen app → Resume draft
10. Verify folder selection shows "מטווחים 474"
11. Click "Save Final"
12. Check Firestore:
    - Document should exist in 'feedbacks' collection
    - `folderKey` = 'ranges_474'
    - `folderLabel` = 'מטווחים 474'
    - `isTemporary` = false

**Expected Result:** ✅ Feedback saved to correct folder, no errors

### Test Case 2: Path B - Draft → Final Save (מטווחי ירי)
**Same as Path A but select "מטווחי ירי"**

**Expected Firestore fields:**
- `folderKey` = 'shooting_ranges'
- `folderLabel` = 'מטווחי ירי'

### Test Case 3: Short Range - Draft → Final
**Steps:**
1. Create new Short Range feedback
2. Select folder: "מטווחי ירי"
3. Add stages, trainees, data
4. Exit → Resume draft
5. Final save

**Expected:** ✅ Saved to 'shooting_ranges' folder

### Test Case 4: Empty Folder Edge Case
**Steps:**
1. Create feedback but DON'T select folder (leave empty)
2. Exit (auto-saves draft)
3. Reopen draft
4. Try to save final

**Expected:** ❌ Validation error: "אנא בחר תיקייה"

### Test Case 5: One-Session Save (Regression)
**Steps:**
1. Create new feedback
2. Select folder, fill all data
3. Save final **without exiting**

**Expected:** ✅ Still works (uses computed folder fields)

## Debug Logging

### Draft Load Logs
```
DRAFT_LOAD: rangeFolder=מטווחים 474
DRAFT_LOAD: folderKey=ranges_474
DRAFT_LOAD: folderLabel=מטווחים 474
```

### Final Save Logs (from draft)
```
SAVE: Using LOADED folder fields: folderKey=ranges_474 folderLabel=מטווחים 474
```

### Final Save Logs (new feedback)
```
SAVE: COMPUTED folder fields from UI: folderKey=ranges_474 folderLabel=מטווחים 474
```

### Error Logs (if folder empty)
```
❌ SAVE ERROR: Empty folder fields! folderKey="" folderLabel=""
```

## Files Modified
1. `lib/range_training_page.dart`
   - Lines 145-146: Added state variables
   - Lines 1729-1730: Draft load extracts folder fields
   - Lines 1733-1734: Debug logging
   - Lines 1855-1856: Restore folder fields to state
   - Lines 1008-1048: Priority folder field logic
   - Lines 1051-1063: Defensive validation

## Verification Checklist
- [ ] Draft save includes `folderKey` and `folderLabel` (already working)
- [ ] Draft load extracts `folderKey` and `folderLabel` from Firestore (NEW)
- [ ] Draft load restores folder fields to state (NEW)
- [ ] Final save uses loaded folder fields if available (NEW)
- [ ] Final save computes folder fields if NOT loaded (existing logic)
- [ ] Validation blocks save if folder fields empty (NEW)
- [ ] Debug logs show "LOADED" vs "COMPUTED" folder fields (NEW)
- [ ] Path A test passes (מטווחים 474)
- [ ] Path B test passes (מטווחי ירי)
- [ ] Short Range test passes
- [ ] Empty folder edge case handled
- [ ] One-session save still works (regression)

## Impact Analysis
**Scope:** ONLY Short Range and Long Range feedbacks
**Risk:** Low - new logic only triggers when loading from draft
**Backward Compatibility:** ✅ Maintained - existing one-session saves unchanged

## Related Issues
- Previously fixed: Folder classification bug (exact matching)
- Previously implemented: `rangeSubType` field for display labels
- This fix: Draft → final save folder persistence

## Next Steps
1. Test all 5 test cases
2. Verify debug logs show correct priority
3. Check Firestore documents have correct folder fields
4. Verify feedbacks appear in correct folder in UI
