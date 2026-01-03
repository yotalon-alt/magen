# Draft Autosave - Quick Test Guide

## 🚀 Quick Verification (2 minutes)

### Test 1: Autosave Works
1. `flutter run -d chrome`
2. Navigate: Exercises → מטווחים → קצרים
3. Enter settlement, set attendees to `3`
4. Type trainee name: "ישראל כהן"
5. **Wait 1 second** (don't click anything)
6. **Expected**: 
   - Console shows `⏱️ AUTOSAVE: Draft save triggered`
   - Green message: "טיוטה נשמרה בהצלחה"

### Test 2: Data Persists
1. Continue from Test 1
2. Add 2 more trainee names
3. Enter hit values in table
4. Press **Back button** immediately (don't wait)
5. Navigate back to קצרים
6. **Expected**: All 3 names and hit values restored

### Test 3: Manual Button Works
1. Enter new trainee data
2. Click "שמור זמנית" button
3. **Expected**: 
   - Console shows `🖱️ MANUAL_DRAFT_CLICK`
   - Green confirmation message
   - Firestore has updated document

---

## ✅ Success Indicators

### Console Logs (Good):
```
⏱️ AUTOSAVE: Draft save triggered
========== DRAFT_SAVE START ==========
DRAFT_SAVE: Unfocused all fields
DRAFT_SAVE: trainees.length=3
DRAFT_SAVE: trainee[0]: name="ישראל כהן", hits={0: 8}
✅ DRAFT_SAVE: Write OK
✅ VERIFIED: 3 trainees persisted
```

### Firestore Document:
- Path: `feedbacks/{uid}_range_קצרים`
- Field `status`: `"temporary"`
- Field `trainees`: Array with 3 objects
- First trainee has populated `name` and `hits`

---

## ❌ Failure Signs

### No Autosave:
- Type for 5+ seconds, no console logs
- **Fix**: Check `_canSaveTemporarily` (settlement + attendees set)

### Empty Names After Reload:
- Trainees exist but names are `""`
- **Fix**: Verify unfocus is being called (should see in logs)

### Multiple Rapid Saves:
- Autosave firing every 100ms
- **Fix**: Verify debounce timer is 900ms

---

## 📊 Expected Behavior

| Action | Autosave Delay | Result |
|--------|----------------|--------|
| Type trainee name | 900ms after last keystroke | Draft saved |
| Change hit value | 900ms after last change | Draft saved |
| Add/remove attendees | 900ms | Draft saved |
| Click "שמור זמנית" | Immediate | Draft saved |
| Press back button | Immediate (on dispose) | Draft saved |

---

## 🔍 Firestore Verification

1. Open Firebase Console
2. Navigate: Firestore Database → feedbacks
3. Find document: `{your_uid}_range_קצרים`
4. Verify fields:
   - `status`: "temporary"
   - `folder`: "מטווחים - משוב זמני"
   - `trainees[0].name`: Your entered name
   - `trainees[0].hits.station_0`: Your entered value

---

## ⚡ Quick Checklist

- [ ] Autosave fires 1 second after typing stops
- [ ] Manual button saves immediately
- [ ] Back button triggers save on exit
- [ ] Data survives page reload
- [ ] Console shows green checkmarks (✅)
- [ ] Firestore document has complete data
- [ ] No errors in console

---

**Time to Test**: ~2 minutes  
**Pass Criteria**: All 3 tests pass, Firestore has complete data  
**Key Log**: `✅ VERIFIED: X trainees persisted`
