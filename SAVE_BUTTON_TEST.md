# Save Button Test Checklist

## Prerequisites
- [ ] App running on desktop/web (Chrome recommended)
- [ ] Browser DevTools console open (F12)
- [ ] User logged in as Instructor or Admin
- [ ] Internet connection active

## Test 1: Surprise Drill Save ✓

### Setup
- [ ] Navigate: תרגילים → תרגילי הפתעה
- [ ] Select יישוב: קצרין
- [ ] Enter כמות נוכחים: **3**
- [ ] Add עיקרון: "קשר עין"
- [ ] Trainee 1: Name "חניך א", Score **5**
- [ ] Trainee 2: Name "חניך ב", Score **4**
- [ ] Trainee 3: Name "חניך ג", Score **5**

### Execute
- [ ] Click blue "שמור תרגיל הפתעה" button

### Verify UI
- [ ] Button immediately shows spinner + "שומר..."
- [ ] Button is disabled (can't click again)
- [ ] After ~1-2 seconds: Green SnackBar "✅ המשוב נשמר בהצלחה - תרגילי הפתעה"
- [ ] Screen navigates back to previous page

### Verify Console Logs
```
✓ SAVE_CLICK type=surprise mode=surprise
✓ SAVE_CLICK uid=<your-uid> email=<your-email>
✓ SAVE_CLICK platform=web
✓ SAVE_CLICK trainees=3 stations=1
✓ SAVE: Writing to collection=feedbacks (surprise)
✓ SAVE: Write completed, path=feedbacks/<doc-id>
✓ SAVE_READBACK: exists=true
✓ SAVE_READBACK: traineesCount=3
✓ ✅ SAVE VERIFIED: Document persisted successfully
✓ SAVE: Navigation complete
✓ ========== SAVE END ==========
```

### Verify Firestore
- [ ] Open: https://console.firebase.google.com/
- [ ] Navigate to: Firestore Database → feedbacks
- [ ] Find new document (sort by timestamp)
- [ ] Check fields:
  - [ ] `folder: "משוב תרגילי הפתעה"`
  - [ ] `exercise: "תרגילי הפתעה"`
  - [ ] `status: "final"`
  - [ ] `settlement: "קצרין"`
  - [ ] `trainees: [3 items]`
  - [ ] First trainee has `name: "חניך א"` and `hits: {"station_0": 5}`

---

## Test 2: Range Save (Short) ✓

### Setup
- [ ] Navigate: תרגילים → מטווחים → טווח קצר
- [ ] Select יישוב: רמות
- [ ] Enter כמות נוכחים: **2**
- [ ] Add מקצה: "הרמות" with **10** bullets
- [ ] Trainee 1: Name "לוחם א", Hits **8**
- [ ] Trainee 2: Name "לוחם ב", Hits **6**

### Execute
- [ ] Click blue "שמור מטווח" button

### Verify UI
- [ ] Button shows spinner + "שומר..."
- [ ] Button is disabled
- [ ] Green SnackBar: "✅ המשוב נשמר בהצלחה - מטווחים"
- [ ] Screen navigates back

### Verify Console Logs
```
✓ SAVE_CLICK type=range_short mode=range
✓ SAVE_CLICK trainees=2 stations=1
✓ SAVE: Writing to collection=feedbacks (range)
✓ SAVE_READBACK: exists=true
✓ SAVE_READBACK: traineesCount=2
✓ ✅ SAVE VERIFIED
```

### Verify Firestore
- [ ] New document with:
  - [ ] `folder: "מטווחי ירי"`
  - [ ] `exercise: "מטווחים"`
  - [ ] `rangeType: "קצרים"`
  - [ ] `rangeSubFolder: "דיווח קצר"`
  - [ ] `status: "final"`
  - [ ] `trainees: [2 items]`
  - [ ] `stations: [1 item with bulletsCount: 10]`

---

## Test 3: Error Handling ✓

### Setup
- [ ] Fill valid form (either surprise or range)

### Execute - Method A (Disconnect Internet)
- [ ] Disconnect internet/WiFi
- [ ] Click Save button

### OR Execute - Method B (Modify Rules)
- [ ] Temporarily change Firestore rules to deny write
- [ ] Click Save button

### Verify UI
- [ ] Button shows spinner + "שומר..." briefly
- [ ] Red SnackBar appears with error message
- [ ] Error message contains actual error (not generic)
- [ ] User stays on form (doesn't navigate)
- [ ] Button becomes enabled again (can retry)

### Verify Console Logs
```
✓ SAVE_CLICK type=...
✓ ❌ ========== SAVE ERROR ==========
✓ SAVE_ERROR: <actual error message>
✓ SAVE_ERROR_STACK: <stack trace>
```

### Cleanup
- [ ] Reconnect internet OR revert Firestore rules
- [ ] Retry save - should succeed

---

## Test 4: Double-Tap Prevention ✓

### Setup
- [ ] Fill valid form (any type)

### Execute
- [ ] Click Save button **5 times rapidly**

### Verify
- [ ] Button becomes disabled after first click
- [ ] Only **one** SnackBar appears
- [ ] Console shows only **one** SAVE_CLICK sequence
- [ ] Firestore shows only **one** new document

---

## Test 5: Empty Data Handling ✓

### Setup
- [ ] Navigate to any form
- [ ] Enter כמות נוכחים: **3**
- [ ] Add station/principle
- [ ] Fill only Trainee 1: Name "חניך א", Hits **5**
- [ ] Leave Trainee 2 and 3 **completely empty**

### Execute
- [ ] Click Save (should fail validation)

### Verify
- [ ] Red SnackBar: "אנא הזן שם לחניך 2"
- [ ] Form doesn't save
- [ ] No document created

### Fix & Retry
- [ ] Fill all 3 trainee names
- [ ] Leave some hits as **0**
- [ ] Click Save

### Verify
- [ ] Save succeeds
- [ ] Firestore document has 3 trainees
- [ ] Trainee `hits` only includes non-zero values
  - Example: If trainee has hits 8,0,7 for 3 stations
  - Saved: `{"station_0": 8, "station_2": 7}`
  - NOT saved: station_1 (because it's 0)

---

## Test 6: Update Existing Temporary ✓

### Setup
- [ ] Create temp feedback (click "שמור זמנית")
- [ ] Navigate back and reload same type
- [ ] Modify some trainee names/values
- [ ] Click blue Save button

### Verify
- [ ] Console shows: `SAVE: Writing to collection=feedbacks`
- [ ] Green SnackBar appears
- [ ] Firestore shows **updated** document (not new)
- [ ] Timestamp updated
- [ ] Status changed from "temporary" to "final"

---

## Results Summary

| Test | Status | Notes |
|------|--------|-------|
| 1. Surprise Save | ✅/❌ | |
| 2. Range Save | ✅/❌ | |
| 3. Error Handling | ✅/❌ | |
| 4. Double-Tap Prevention | ✅/❌ | |
| 5. Empty Data | ✅/❌ | |
| 6. Update Temporary | ✅/❌ | |

## Common Issues & Solutions

### Issue: "אנא בחר יישוב/מחלקה"
**Cause:** Settlement not selected
**Fix:** Click יישוב field and select a settlement

### Issue: "אנא הזן שם לחניך X"
**Cause:** Trainee name is empty
**Fix:** Fill all trainee names before saving

### Issue: SAVE_ERROR: permission-denied
**Cause:** Firestore rules or authentication issue
**Fix:** 
1. Check you're logged in
2. Verify Firestore rules allow write to `feedbacks` collection
3. Check browser console for auth errors

### Issue: Button stays disabled after error
**Cause:** `_isSaving` not reset
**Fix:** This shouldn't happen with current code (finally block resets it)
**Report:** If this occurs, it's a bug

### Issue: No console logs appear
**Cause:** DevTools not open or filtered
**Fix:** 
1. Press F12 to open DevTools
2. Click "Console" tab
3. Clear any filters
4. Try save again

### Issue: SnackBar disappears too fast
**Cause:** Duration is 2 seconds for success
**Solution:** This is intentional for good UX, but you can check Firestore to confirm

## Sign-Off

**Tester Name:** ___________________

**Date:** ___________________

**Platform:** Desktop ☐ Web ☐ Mobile ☐

**Browser:** Chrome ☐ Firefox ☐ Edge ☐ Safari ☐

**All Tests Passed:** Yes ☐ No ☐

**Issues Found:** ___________________
