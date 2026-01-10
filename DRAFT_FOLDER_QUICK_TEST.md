# Quick Test Guide: Draft → Final Save Folder Fix

## 🎯 Test Goal
Verify that Short/Long Range feedbacks reopened from draft save to the correct folder.

## ⚡ Quick Test (5 minutes)

### Test 1: Long Range - מטווחים 474
```
1. Login as instructor
2. Exercises → מטווחים → Long Range
3. Select folder: "מטווחים 474"
4. Settlement: "קצרין"
5. Attendees: 10
6. Add 1 stage: "מקצה 1" (20 bullets, 100 points)
7. Add 1 trainee: "Test User"
8. Enter points: 50
9. ❌ DON'T CLICK SAVE - Just exit app (auto-saves draft)
10. Reopen app → Feedbacks tab
11. Look for draft (blue "טווח רחוק" label)
12. Tap draft → Resume
13. Verify folder shows "מטווחים 474"
14. Click "Save Final"
15. ✅ Check: No error, success message shown
16. Go to Feedbacks → מטווחים 474 folder
17. ✅ Check: Feedback appears in list
```

**Expected:** ✅ Feedback in "מטווחים 474" folder

### Test 2: Short Range - מטווחי ירי
```
Same as Test 1 but:
- Select Short Range
- Select folder: "מטווחי ירי"
- Add stage: "צפון" (30 bullets)
- Enter hits: 20
```

**Expected:** ✅ Feedback in "מטווחי ירי" folder

## 🐛 Debug Logs to Check

### Draft Load (Console)
```
DRAFT_LOAD: rangeFolder=מטווחים 474
DRAFT_LOAD: folderKey=ranges_474    ← NEW
DRAFT_LOAD: folderLabel=מטווחים 474  ← NEW
```

### Final Save (Console)
```
SAVE: Using LOADED folder fields: folderKey=ranges_474  ← Should say "LOADED"
```

## 🔍 Firestore Verification

### Check Document Fields
```
feedbacks/{docId}:
  ✅ folderKey: "ranges_474" OR "shooting_ranges"
  ✅ folderLabel: "מטווחים 474" OR "מטווחי ירי"
  ✅ isTemporary: false
  ✅ rangeFolder: "מטווחים 474" OR "מטווחי ירי"
```

## ❌ Known Failures (Before Fix)

### Symptom 1: Folder Empty Error
```
Error: "אנא בחר תיקייה"
Cause: rangeFolder was empty after draft load
```

### Symptom 2: Wrong Folder
```
Feedback saved to wrong folder or "משובים - כללי"
Cause: Folder fields recomputed incorrectly
```

### Symptom 3: Exception
```
Exception: Invalid folder selection: 
Cause: rangeFolder was null/empty
```

## ✅ Success Criteria

1. **No errors** when saving from draft
2. **Feedback appears** in the selected folder
3. **Debug logs show** "Using LOADED folder fields"
4. **Firestore has** correct `folderKey` and `folderLabel`

## 🔄 Regression Test (1 minute)

### One-Session Save (Should Still Work)
```
1. Create new Long Range feedback
2. Fill all data
3. Click Save Final (without exiting)
4. ✅ Check: Saves successfully
```

**Expected:** ✅ Still works (uses computed folder fields)

## 📊 Test Matrix

| Test | Type | Folder | Draft? | Expected Result |
|------|------|--------|--------|----------------|
| 1 | Long Range | 474 | Yes | ✅ Saved to 474 |
| 2 | Short Range | Shooting | Yes | ✅ Saved to Shooting |
| 3 | Long Range | 474 | No | ✅ Saved to 474 |
| 4 | Short Range | Shooting | No | ✅ Saved to Shooting |

## 🚨 If Tests Fail

### Check 1: Draft Save Payload
```dart
// In draft save logs, verify:
'folderKey': 'ranges_474' ← Must exist
'folderLabel': 'מטווחים 474' ← Must exist
```

### Check 2: Draft Load Extraction
```dart
// In draft load logs, verify:
DRAFT_LOAD: folderKey=ranges_474 ← Must show value
```

### Check 3: State Restoration
```dart
// In draft load logs after setState, verify:
loadedFolderKey = ranges_474 ← Must be set
```

### Check 4: Priority Logic
```dart
// In final save logs, verify:
SAVE: Using LOADED folder fields ← Must say "LOADED" not "COMPUTED"
```

## ⏱️ Time Estimate
- Quick test (Tests 1-2): **5 minutes**
- Firestore verification: **2 minutes**
- Regression test: **1 minute**
- **Total: ~8 minutes**
