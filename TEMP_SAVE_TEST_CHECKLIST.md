# Quick Test Checklist for Temp-Save Desktop/Web Fix

## Before Testing
- [ ] Ensure you're running on desktop/web (Chrome recommended)
- [ ] Open browser DevTools console (F12)
- [ ] Clear any existing temp data (optional: check Firestore console first)

## Test Steps

### 1. Navigate to Range Training
- [ ] Click תרגילים (Exercises)
- [ ] Click מטווחים (Ranges)
- [ ] Click טווח קצר (Short Range) or טווח רחוק (Long Range)

### 2. Fill Form
- [ ] Select יישוב (Settlement): Pick any settlement
- [ ] Enter כמות נוכחים (Attendees): Enter **3**
- [ ] Add מקצה (Station): Select "הרמות" with **10** bullets
- [ ] Fill trainee 1: Name "חניך א", hits **8**
- [ ] Fill trainee 2: Name "חניך ב", hits **6**
- [ ] Fill trainee 3: Name "חניך ג", hits **7**

### 3. Click שמור זמנית (Save Temporarily)
**Expected Console Output:**
```
TEMP_SAVE_CLICK module=range key=קצרים user=<uid> email=<email>
TEMP_SAVE_CLICK platform=web
TEMP_SAVE_CLICK trainees=3 stations=1
========== TEMP_SAVE START ==========
TEMP_SAVE: module=range path=feedbacks/<uid>_range_קצרים
TEMP_SAVE_START path=feedbacks/<uid>_range_קצרים
TEMP_SAVE: Writing to Firestore...
TEMP_SAVE_OK
TEMP_SAVE_READBACK exists=true keys=[...]
TEMP_SAVE_VERIFY: traineesLen=3
✅ VERIFIED: Trainee count matches
========== TEMP_SAVE END ==========
```

**Check for:**
- [ ] `TEMP_SAVE_CLICK` appears
- [ ] `platform=web` is shown
- [ ] `TEMP_SAVE_OK` appears (NOT `TEMP_SAVE_FAIL`)
- [ ] `TEMP_SAVE_READBACK exists=true`
- [ ] `✅ VERIFIED` messages appear
- [ ] SnackBar shows "המשוב נשמר באופן זמני"

### 4. Navigate Back
- [ ] Click back button (or navigate to תרגילים → מטווחים → טווח קצר)

**Expected Console Output:**
```
========== TEMP_LOAD START ==========
TEMP_LOAD: user=<uid> email=<email>
TEMP_LOAD: path=feedbacks/<uid>_range_קצרים
TEMP_LOAD: fullPath=feedbacks/<uid>_range_קצרים
TEMP_LOAD: got document, exists=true
TEMP_LOAD: rawTrainees.length=3
TEMP_LOAD: firstTraineeRaw={name: חניך א, ...}
TEMP_LOAD: ✅ Load complete
========== TEMP_LOAD END (SUCCESS) ==========
```

**Check for:**
- [ ] `TEMP_LOAD: got document, exists=true`
- [ ] `rawTrainees.length=3`
- [ ] `✅ Load complete`

### 5. Verify UI Restored
- [ ] יישוב field shows selected settlement
- [ ] כמות נוכחים shows **3**
- [ ] Trainee 1: Name is "חניך א", hits shows **8**
- [ ] Trainee 2: Name is "חניך ב", hits shows **6**
- [ ] Trainee 3: Name is "חניך ג", hits shows **7**
- [ ] Station "הרמות" with **10** bullets is shown

## Success Criteria
✅ **ALL** checklist items above are checked
✅ **NO** error messages in console
✅ **NO** `TEMP_SAVE_FAIL` in logs
✅ **NO** `MISMATCH` warnings in logs
✅ All trainee names and values are restored exactly

## Failure Investigation

### If TEMP_SAVE_FAIL appears:
1. Copy the full error message
2. Check error type:
   - `permission-denied`: Check Firestore rules
   - `network`: Check internet connection
   - Other: Report error details

### If exists=false on readback:
1. Check Firestore Console: https://console.firebase.google.com/
2. Navigate to Firestore Database
3. Look for collection: `feedbacks`
4. Look for document: `<your-uid>_range_קצרים`
5. Verify document exists and has correct data

### If data not restored on load:
1. Check console for `TEMP_LOAD` logs
2. Verify `exists=true`
3. Verify `rawTrainees.length` matches
4. Check if path matches between SAVE and LOAD
5. Verify user ID is same (`<uid>` should match)

### If trainees are empty after save:
1. Check `TEMP_SAVE: traineesPayload.length=...` - should be 3
2. Check `TEMP_SAVE: firstTrainee=...` - should show name
3. If payload is empty, check form state before clicking save

## Report Format

**Platform:** Desktop Web / Chrome v120
**Status:** ✅ Pass / ❌ Fail

**Test Results:**
- Save Click: ✅/❌
- Firestore Write: ✅/❌
- Readback Verification: ✅/❌
- Load on Return: ✅/❌
- UI Restoration: ✅/❌

**Logs:** (paste relevant logs or "No errors")

**Screenshots:** (if UI doesn't restore correctly)
