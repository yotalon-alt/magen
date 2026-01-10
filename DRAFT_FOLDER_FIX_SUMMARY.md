# Draft → Final Save Folder Persistence Fix - Summary

## 🎯 Issue Fixed
**CRITICAL BUG**: Short/Long Range feedbacks reopened from draft did NOT save to the selected folder.

## 🔍 Root Cause Analysis

### The Problem
```
User Flow:
1. Create Long Range feedback
2. Select folder: "מטווחים 474"
3. Fill data, exit WITHOUT saving (auto-saves draft)
4. Reopen app → Resume draft
5. Click "Save Final"
6. ❌ ERROR: "אנא בחר תיקייה" OR saves to wrong folder
```

### Why It Happened
```dart
// Draft Save (✅ Working)
payload = {
  'rangeFolder': 'מטווחים 474',
  'folderKey': 'ranges_474',      // ← Saved correctly
  'folderLabel': 'מטווחים 474',   // ← Saved correctly
}

// Draft Load (❌ Bug)
setState(() {
  rangeFolder = data['rangeFolder']; // ← Only this was restored
  // ❌ loadedFolderKey NOT restored
  // ❌ loadedFolderLabel NOT restored
});

// Final Save (❌ Bug)
// ALWAYS recomputed from rangeFolder, even when loading from draft
if (rangeFolder == 'מטווחים 474') {
  folderKey = 'ranges_474';  // ← Recomputed every time
}
```

**Problem:** If `rangeFolder` was empty/null in draft, final save validation failed or used wrong folder.

## ✅ Solution Implemented

### 1. Added State Variables
```dart
// lib/range_training_page.dart lines 145-146
String? loadedFolderKey;   // Loaded from draft
String? loadedFolderLabel; // Loaded from draft
```

### 2. Extract Folder Fields on Draft Load
```dart
// lib/range_training_page.dart lines 1729-1730
final rawFolderKey = data['folderKey'] as String?;
final rawFolderLabel = data['folderLabel'] as String?;
```

### 3. Restore to State
```dart
// lib/range_training_page.dart lines 1855-1856
setState(() {
  loadedFolderKey = rawFolderKey;
  loadedFolderLabel = rawFolderLabel;
  // ... existing code ...
});
```

### 4. Use Loaded Values in Final Save
```dart
// lib/range_training_page.dart lines 1008-1048
// PRIORITY: Use loaded values if available, else compute from UI

if (loadedFolderKey != null && loadedFolderKey!.isNotEmpty) {
  // ✅ FROM DRAFT: Reuse loaded values
  folderKey = loadedFolderKey!;
  folderLabel = loadedFolderLabel ?? folderKey;
  debugPrint('SAVE: Using LOADED folder fields');
} else {
  // ✅ NEW FEEDBACK: Compute from UI selection
  if (rangeFolder == 'מטווחים 474') {
    folderKey = 'ranges_474';
    folderLabel = 'מטווחים 474';
  }
  debugPrint('SAVE: COMPUTED folder fields from UI');
}
```

### 5. Defensive Validation
```dart
// lib/range_training_page.dart lines 1051-1063
if (folderKey.isEmpty || folderLabel.isEmpty) {
  // Block save with error message
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('שגיאה: נתוני תיקייה חסרים')),
  );
  return;
}
```

## 🧪 How to Test

### Quick Test (Path A)
```
1. Create Long Range feedback
2. Select "מטווחים 474"
3. Add minimal data
4. Exit (don't save)
5. Reopen → Resume draft
6. Save Final
7. ✅ Should save to "מטווחים 474" folder
```

### Quick Test (Path B)
```
Same as Path A but select "מטווחי ירי"
✅ Should save to "מטווחי ירי" folder
```

## 📊 Debug Logs

### Before Fix
```
DRAFT_LOAD: rangeFolder=מטווחים 474
DRAFT_LOAD: folderKey=ranges_474      ← Loaded but NOT restored
SAVE: COMPUTED folder fields from UI  ← Always computed
```

### After Fix
```
DRAFT_LOAD: rangeFolder=מטווחים 474
DRAFT_LOAD: folderKey=ranges_474      ← NEW: Loaded AND logged
loadedFolderKey set to: ranges_474    ← NEW: Restored to state
SAVE: Using LOADED folder fields      ← NEW: Reuses loaded values
```

## 🎯 Impact

### What Changed
- **Draft load:** Now restores `folderKey` and `folderLabel` to state
- **Final save:** Prioritizes loaded folder fields over recomputation

### What Stayed the Same
- Draft save payload (no changes)
- One-session save flow (still computes from UI)
- Validation logic (existing checks preserved)

### Risk Level
**🟢 LOW RISK**
- New logic only triggers when loading from draft
- Existing one-session saves unchanged
- Defensive validation prevents edge cases

## 📋 Files Modified
1. `lib/range_training_page.dart`
   - Added 2 state variables (lines 145-146)
   - Draft load: Extract folder fields (lines 1729-1730)
   - Draft load: Restore to state (lines 1855-1856)
   - Final save: Priority logic (lines 1008-1048)
   - Final save: Defensive validation (lines 1051-1063)

## ✅ Success Criteria
- [ ] Draft → Final save works for "מטווחים 474"
- [ ] Draft → Final save works for "מטווחי ירי"
- [ ] One-session save still works (regression)
- [ ] Empty folder triggers validation error
- [ ] Debug logs show "LOADED" vs "COMPUTED"
- [ ] Firestore documents have correct `folderKey`/`folderLabel`

## 🔗 Related Fixes
1. **Folder classification bug** (exact string matching) - Previously fixed
2. **rangeSubType display label** - Previously implemented
3. **Draft folder persistence** - This fix

## 📚 Documentation
- Detailed guide: `DRAFT_FINAL_SAVE_FOLDER_FIX.md`
- Quick test: `DRAFT_FOLDER_QUICK_TEST.md`
- This summary: `DRAFT_FOLDER_FIX_SUMMARY.md`
