# 🧪 Quick Test Guide - Draft Save/Load

## 5-Minute Smoke Test

### Test 1: Basic Save & Load (2 min)

1. **Open the app** → Navigate to "תרגילים" → "מטווחים" → Choose "אימון קצר"

2. **Fill in data**:
   - Settlement: `קצרין`
   - Add station: Name `מקצה 1`, Bullets `10`
   - Add trainee row (will auto-appear)
   - Trainee name: `ישראל ישראלי`
   - Enter hits: `8`

3. **Wait 1 second** (for autosave debounce)

4. **Check console**:
   ```
   ✅ DRAFT_SAVE: traineeRows.length=1
   DRAFT_SAVE: row[0]: name='ישראל ישראלי' values={0: 8}
   ```

5. **Navigate away**: Click "בית" in bottom nav

6. **Return**: "תרגילים" → "מטווחים" → "אימון קצר"

7. **Check console**:
   ```
   ✅ DRAFT_LOAD: traineeRows.length=1
   DRAFT_LOAD: row[0]: name='ישראל ישראלי' values={0: 8}
   ```

8. **Verify UI**: Name and hits should be restored

**✅ PASS**: Data persisted and loaded correctly  
**❌ FAIL**: Missing data or no console logs

---

### Test 2: Debounce Works (1 min)

1. **Start from Test 1** (with existing draft)

2. **Type trainee name rapidly**: `דוד כהן משה לוי`

3. **Watch console**: Should see NO saves during typing

4. **Stop typing for 1 second**

5. **Check console**: Should see ONE save log:
   ```
   ✅ DRAFT_SAVE: traineeRows.length=1
   DRAFT_SAVE: row[0]: name='דוד כהן משה לוי' values={0: 8}
   ```

**✅ PASS**: Only one save after typing stopped  
**❌ FAIL**: Multiple saves during typing

---

### Test 3: Multiple Trainees (2 min)

1. **Continue from Test 2**

2. **Add more data**:
   - Add station: `מקצה 2`, Bullets `15`
   - Add 2 more trainee rows (click "+" or enter data in empty row)
   - Fill in names and hits for all 3 trainees

3. **Wait 1 second**

4. **Check console**: Should show all 3 rows:
   ```
   ✅ DRAFT_SAVE: traineeRows.length=3
   DRAFT_SAVE: row[0]: name='...' values={0: X, 1: Y}
   DRAFT_SAVE: row[1]: name='...' values={0: X, 1: Y}
   DRAFT_SAVE: row[2]: name='...' values={0: X, 1: Y}
   ```

5. **Reload page** (F5 or navigate away/back)

6. **Verify**: All 3 trainees with all values restored

**✅ PASS**: All data persisted  
**❌ FAIL**: Missing rows or values

---

## Expected Console Output Examples

### First Save (Empty → Data):
```
✅ DRAFT_SAVE: traineeRows.length=1
DRAFT_SAVE: row[0]: name='ישראל ישראלי' values={0: 8}
DRAFT_SAVE: Read back - trainees count: 1
```

### Subsequent Save (Data → More Data):
```
✅ DRAFT_SAVE: traineeRows.length=3
DRAFT_SAVE: row[0]: name='ישראל ישראלי' values={0: 8, 1: 12}
DRAFT_SAVE: row[1]: name='דוד כהן' values={0: 6, 1: 10}
DRAFT_SAVE: row[2]: name='משה לוי' values={0: 7, 1: 9}
DRAFT_SAVE: Read back - trainees count: 3
```

### Load on Page Open:
```
✅ DRAFT_LOAD: traineeRows.length=3
DRAFT_LOAD: row[0]: name='ישראל ישראלי' values={0: 8, 1: 12}
DRAFT_LOAD: row[1]: name='דוד כהן' values={0: 6, 1: 10}
DRAFT_LOAD: row[2]: name='משה לוי' values={0: 7, 1: 9}
```

### No Draft (First Time):
```
⚠️ DRAFT_LOAD: No draft found
```

---

## Common Issues & Solutions

### ❌ Issue: No console logs at all
**Cause**: Console is closed or filtered  
**Fix**: Open browser DevTools (F12), check Console tab, clear filters

### ❌ Issue: "DRAFT_SAVE" appears but "Read back" missing
**Cause**: Firestore write succeeded but read-back failed  
**Fix**: Check Firestore rules (user must have read permission)

### ❌ Issue: Data doesn't load on page return
**Cause**: Draft document not found  
**Fix**: Check console for "No draft found" or Firestore error message

### ❌ Issue: Multiple saves during typing
**Cause**: Debounce not working  
**Fix**: Verify `_scheduleAutoSave()` cancels existing timer before creating new one

### ❌ Issue: Wrong values after load
**Cause**: Partial save or load  
**Fix**: Check console logs - should show complete row data in both SAVE and LOAD

---

## Full Test Script (Copy-Paste)

```
TEST SESSION: Draft Save/Load
Date: [Fill in]
Tester: [Fill in]
Platform: [ ] Web Chrome  [ ] Web Edge  [ ] iOS  [ ] Android

Test 1 - Basic Save & Load:
[ ] Data entered
[ ] Console shows DRAFT_SAVE
[ ] Navigated away
[ ] Returned
[ ] Console shows DRAFT_LOAD
[ ] Data restored in UI
Result: [ ] PASS  [ ] FAIL

Test 2 - Debounce:
[ ] Typed rapidly
[ ] No saves during typing
[ ] Single save after stop
Result: [ ] PASS  [ ] FAIL

Test 3 - Multiple Trainees:
[ ] Added 3 trainees
[ ] Console shows all 3 rows
[ ] Reloaded page
[ ] All 3 trainees restored
Result: [ ] PASS  [ ] FAIL

Overall: [ ] PASS  [ ] FAIL
Notes:
```

---

## Advanced Tests (Optional)

### Test: Station Remove
1. Add 3 stations with data
2. Remove middle station
3. Wait for autosave
4. Reload
5. Verify: 2 stations remain, correct data

### Test: Large Dataset
1. Add 10 stations
2. Add 20 trainees
3. Fill all cells
4. Wait for autosave
5. Reload
6. Verify: All 200 values restored

### Test: Concurrent Sessions
1. Open page in 2 tabs
2. Edit in Tab 1
3. Wait for save
4. Reload Tab 2
5. Verify: Tab 2 sees Tab 1's changes

---

## Success Criteria

✅ All 3 basic tests pass  
✅ Console logs match expected format  
✅ No data loss after reload  
✅ Only one save per edit session  
✅ Same behavior on web and mobile  

If all criteria met: **READY FOR PRODUCTION** 🚀
