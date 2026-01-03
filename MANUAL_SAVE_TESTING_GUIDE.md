# Testing Guide: Manual Save Draft Fix

## Quick Start Testing

### Test 1: Basic Save Draft (Web - Chrome)
**Duration**: 2 minutes

1. **Start app**: `flutter run -d chrome`
2. **Navigate**: Exercises → מטווחים → Select range type
3. **Enter data**:
   - Attendees: `3`
   - Station 1: Name "רמות", Bullets `10`
   - Trainee 1: Name "ישראל כהן", Hits `7`
   - Trainee 2: Name "דני לוי", Hits `8`
   - Trainee 3: Name "משה אברהם", Hits `9`
4. **Save**: Click "שמור זמנית" button
5. **Verify**: Green success message appears
6. **Check console**: Look for:
   ```
   ✅ First trainee name saved: "ישראל כהן"
   ✅ VERIFIED: Trainee count matches
   ```
7. **Reload**: Press F5 or navigate away and return
8. **Expected**: All 3 names and hit values restored

---

### Test 2: No Autosave Verification
**Duration**: 1 minute

1. **Enter data** in text fields
2. **Wait 3 seconds** without clicking any button
3. **Check console**: Should see NO messages like:
   - ❌ "TEMP_SAVE"
   - ❌ "SAVE_DRAFT"
   - ❌ "Saving temporary feedback"
4. **Type more** in different fields
5. **Wait another 3 seconds**
6. **Expected**: Still NO automatic save logs

---

### Test 3: Data Persistence Across Sessions
**Duration**: 3 minutes

1. **Session 1**:
   - Enter 5 trainees with names and scores
   - Add 2 stations with different bullet counts
   - Click "שמור זמנית"
   - Close browser tab completely

2. **Session 2** (new tab):
   - Navigate to same range type
   - **Expected**: All 5 trainees, 2 stations, and scores restored

3. **Verify console**:
   ```
   LOAD_START: uid=[user_id] module=[type]
   LOAD: Loaded doc with [X] trainees, [Y] stations
   ```

---

### Test 4: Multi-Field Rapid Entry (Desktop - Windows)
**Duration**: 2 minutes

1. **Rapid typing test**:
   - Click trainee name field, type fast: "אבגדהוזחטיכלמנ"
   - Immediately tab to hits field, type: "15"
   - Tab to next trainee, type name fast
   - Tab to hits, type number
   - Repeat for 3 trainees without pausing

2. **Save immediately**: Click "שמור זמנית" right after last entry

3. **Check logs**: Should see all names captured:
   ```
   SAVE_DRAFT: trainee[0]: name="אבגדהוזחטיכלמנ", hits={0: 15}
   ```

4. **Reload and verify**: All rapid-entry data persisted

---

### Test 5: Mobile View (if available)
**Duration**: 2 minutes

1. **Start**: `flutter run -d [android/ios device]`
2. **Enter data** using mobile keyboard
3. **Switch between fields** quickly
4. **Save**: Tap "שמור זמנית"
5. **Expected**: Same persistence behavior as web

---

## Diagnostic Log Reference

### ✅ SUCCESS Logs (What You Want to See)

#### On Button Click:
```
========== SAVE DRAFT (MANUAL) START ==========
SAVE_DRAFT: Unfocused all fields
SAVE_DRAFT: attendeesCount=3
SAVE_DRAFT: trainees.length=3
SAVE_DRAFT: trainee[0]: name="ישראל כהן", hits={0: 7}
SAVE_DRAFT: trainee[1]: name="דני לוי", hits={0: 8}
SAVE_DRAFT: Writing to Firestore...
✅ SAVE_DRAFT: Write OK
✅ First trainee name saved: "ישראל כהן"
✅ First trainee hits saved: {0: 7}
✅ VERIFIED: Trainee count matches
========== SAVE DRAFT END ==========
```

#### On Page Load:
```
LOAD_START: uid=abc123 module=range path=feedbacks/abc123_range_רמות
LOAD: Loaded doc with 3 trainees, 1 stations
LOAD: settlement=קצרין, attendeesCount=3
LOAD: Restored 3 trainees
```

---

### ❌ FAILURE Logs (What to Watch For)

#### Data Loss Indicators:
```
⚠️ WARNING: First trainee has no name in payload!
❌ CRITICAL: First trainee has NO NAME after save!
❌ MISMATCH: Saved 0 but expected 3
```

#### If You See These:
1. Check if unfocus is being called
2. Verify 100ms delay exists
3. Ensure TextEditingController values are being read after unfocus

---

## Manual Firestore Inspection

### Check Saved Document
1. Open Firebase Console: https://console.firebase.google.com
2. Navigate: Firestore Database → feedbacks collection
3. Find document: `{uid}_range_{rangeType}` or `{uid}_surprise_{rangeType}`
4. Verify fields:
   ```json
   {
     "status": "temporary",
     "trainees": [
       {
         "name": "ישראל כהן",  ← Should have actual name
         "hits": {"0": 7},      ← Should have actual scores
         "totalHits": 7
       }
     ],
     "attendeesCount": 3,
     "createdAt": [timestamp]
   }
   ```

### Red Flags:
- ❌ Empty `trainees` array
- ❌ Trainees with `"name": ""` (empty strings)
- ❌ Missing `hits` field
- ❌ `attendeesCount` = 0

---

## Performance Validation

### Before Fix (Broken Autosave):
- **Firestore writes**: 10-20 per minute (every keystroke triggered debounced save)
- **Data captured**: Stale/empty values
- **User experience**: Constant network activity, data loss

### After Fix (Manual Save Only):
- **Firestore writes**: 1 per button click
- **Data captured**: Complete, fresh values after unfocus
- **User experience**: No background saves, predictable behavior

---

## Edge Cases to Test

### 1. Empty Attendees Count
- Set attendees to 0
- **Expected**: Save button disabled, no crash

### 2. Special Characters in Names
- Enter: "א׳ב׳ג׳ד׳ה׳"
- **Expected**: Hebrew punctuation persists correctly

### 3. Large Numbers in Hits
- Enter: "999" in hits field
- **Expected**: Stored as number, not truncated

### 4. Rapid Back Navigation
- Enter data, click Save, immediately press Back
- **Expected**: No crash, data saved before navigation

---

## Regression Testing

### Verify Not Broken:
1. **Final Save** (blue button) still works
2. **Load on init** still restores data
3. **Station add/remove** still functional
4. **Trainee add/remove** still functional

---

## Success Definition

### ✅ Test PASSES When:
1. All trainee names persist after page reload
2. All hit values persist correctly
3. No autosave logs appear during typing
4. Console shows successful verification logs
5. Firestore document contains all entered data
6. Green success message appears on save

### ❌ Test FAILS When:
1. Trainee names are empty after reload
2. Hit values are 0 or missing after reload
3. Autosave logs appear while typing
4. Console shows "CRITICAL" or "MISMATCH" errors
5. Firestore document is empty or incomplete

---

## Quick Checklist

- [ ] Web Chrome: 3 trainees with names/hits → save → reload → all restored
- [ ] Desktop Windows: Same test
- [ ] No autosave during typing (wait 3+ seconds, no logs)
- [ ] Rapid entry test: type fast, save immediately, all captured
- [ ] Firestore console shows complete document
- [ ] Console logs show green checkmarks (✅)
- [ ] Reload test passes 3/3 times

---

## Troubleshooting

### Problem: Names still empty after save
**Solution**: 
1. Check if `FocusScope.of(context).unfocus()` is being called
2. Verify 100ms delay exists: `await Future.delayed(const Duration(milliseconds: 100))`
3. Ensure `trainees[i].name` is being set from controller in `onChanged`

### Problem: Autosave still happening
**Solution**:
1. Search entire file for `_scheduleAutosave` (should find 0 matches)
2. Search for `_autosaveTimer` (should find 0 matches)
3. Restart app to clear old code

### Problem: Green message shows but data not in Firestore
**Solution**:
1. Check Firestore rules (must allow write for authenticated users)
2. Verify `docRef.set()` is not throwing silent errors
3. Look for `SAVE_DRAFT_FAIL` in console

---

**Testing Time**: ~10 minutes for full suite
**Critical Tests**: Test 1 (basic save) and Test 2 (no autosave)
**Pass Criteria**: 100% data persistence across reloads
