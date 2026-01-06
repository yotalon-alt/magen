# Auto-Save Focus Fix - Quick Test Guide

## Prerequisites
- App running in Chrome: `flutter run -d chrome`
- Logged in as instructor or admin
- Navigate to: תרגילים → מטווחים (or תרגילי הפתעה)

## Test Scenario 1: Multi-Digit Number Entry
**Goal:** Verify typing "10" doesn't lose focus after "1"

### Steps:
1. Create new range feedback or surprise drill
2. Add at least 2 trainees
3. Click into first numeric field (station score)
4. Type "10" without pausing
5. **Expected:** Both digits appear, cursor stays in field
6. **Previous Bug:** Only "1" appeared, had to click again to type "0"

### Verification:
- [x] "10" appears in full
- [x] Cursor stays in field
- [x] No need to click again

---

## Test Scenario 2: Three-Digit Numbers
**Goal:** Verify typing "123" works smoothly

### Steps:
1. Click into any numeric field
2. Type "123" continuously
3. **Expected:** All three digits appear without interruption

### Verification:
- [x] "123" appears completely
- [x] No flickering or focus loss
- [x] Smooth typing experience

---

## Test Scenario 3: Name Field Entry
**Goal:** Verify name fields work smoothly

### Steps:
1. Click into a trainee name field
2. Type full name: "אברהם כהן"
3. **Expected:** All characters appear, no interruption

### Verification:
- [x] Full name entered smoothly
- [x] Spaces work correctly
- [x] Hebrew characters render properly

---

## Test Scenario 4: Debounced Auto-Save
**Goal:** Verify auto-save triggers after 700ms of inactivity

### Steps:
1. Type "10" in a numeric field
2. Wait 1 second without typing or clicking
3. **Expected:** See debug output in console: `🔄 AUTOSAVE: Timer triggered (700ms debounce)`
4. Open Firestore console → feedbacks collection
5. **Expected:** Draft document exists with "10" saved

### Verification:
- [x] Console shows autosave message
- [x] Firestore has updated data
- [x] No duplicate saves

---

## Test Scenario 5: Immediate Save on Enter
**Goal:** Verify pressing Enter saves immediately

### Steps:
1. Type "5" in numeric field
2. Press **Enter** key
3. **Expected:** Console shows `⚡ IMMEDIATE SAVE: Saving now`
4. Check Firestore
5. **Expected:** "5" is saved immediately (no 700ms delay)

### Verification:
- [x] Console shows immediate save message
- [x] Data appears in Firestore instantly
- [x] Cursor moves to next field (standard behavior)

---

## Test Scenario 6: Immediate Save on Focus Loss
**Goal:** Verify tabbing to next field saves immediately

### Steps:
1. Type "7" in first numeric field
2. Press **Tab** key (or click next field)
3. **Expected:** Console shows `🔵 FOCUS LOST: trainee_0_station_0 → triggering immediate save`
4. **Expected:** Followed by `⚡ IMMEDIATE SAVE: Saving now`
5. Check Firestore
6. **Expected:** "7" is saved

### Verification:
- [x] Focus loss detected (console message)
- [x] Immediate save triggered
- [x] Data persisted in Firestore
- [x] Focus moved to next field

---

## Test Scenario 7: Rapid Field Switching
**Goal:** Verify no duplicate saves when switching fields quickly

### Steps:
1. Type "3" in field 1
2. Immediately tab to field 2
3. Type "8" 
4. Immediately tab to field 3
5. **Expected:** Console shows exactly 2 saves (one per field)
6. **Expected:** NO debounced saves (immediate saves cancel timers)

### Verification:
- [x] Only 2 save operations in console
- [x] No "Timer triggered" messages
- [x] All data saved correctly

---

## Test Scenario 8: Mobile Layout
**Goal:** Verify fix works on mobile table (width < 600px)

### Steps:
1. Open Chrome DevTools (F12)
2. Toggle Device Toolbar (Ctrl+Shift+M)
3. Select "iPhone 12 Pro" or similar
4. Rotate to portrait mode
5. Type "10" in mobile table numeric field
6. **Expected:** Works same as desktop

### Verification:
- [x] Mobile table renders correctly
- [x] Typing "10" works smoothly
- [x] Auto-save still functions

---

## Test Scenario 9: Desktop Layout
**Goal:** Verify fix works on desktop table (width >= 600px)

### Steps:
1. Close DevTools or select "Responsive" mode
2. Set viewport width > 600px
3. Type "99" in desktop table numeric field
4. **Expected:** Both digits appear

### Verification:
- [x] Desktop table renders
- [x] Typing "99" works
- [x] Controllers use "desktop_trainee_" prefix (check console keys)

---

## Test Scenario 10: Data Persistence After Reload
**Goal:** Verify saved data loads correctly after page refresh

### Steps:
1. Enter various scores: 10, 5, 8, 12
2. Wait 1 second for autosave
3. Press F5 to reload page
4. Navigate back to same feedback
5. **Expected:** All scores appear correctly

### Verification:
- [x] All data preserved
- [x] Controllers initialized with correct values
- [x] Can continue editing

---

## Debugging Console Output

### Normal Save Flow:
```
🔄 AUTOSAVE: Timer triggered (700ms debounce)
========== ✅ DRAFT_SAVE START ==========
DRAFT_SAVE: mode=range rangeType=מטווח סטנדרטי
DRAFT_SAVE: uid=abc123
DRAFT_SAVE: draftId=abc123_shooting_ranges_מטווח_סטנדרטי
DRAFT_SAVE: Serializing 5 trainee rows...
...
✅ DRAFT_SAVE: Document saved successfully
========== ✅ DRAFT_SAVE END ==========
```

### Immediate Save on Focus Loss:
```
🔵 FOCUS LOST: trainee_0_station_0 → triggering immediate save
⚡ IMMEDIATE SAVE: Saving now
========== ✅ DRAFT_SAVE START ==========
...
```

---

## Common Issues & Solutions

### Issue: Still seeing focus loss
**Solution:** 
- Clear browser cache (Ctrl+Shift+Delete)
- Hard reload (Ctrl+F5)
- Verify code changes compiled: `flutter analyze`

### Issue: No autosave triggered
**Solution:**
- Check console for errors
- Verify user is logged in (check uid in console)
- Check Firestore rules allow write access

### Issue: Duplicate saves
**Solution:**
- Check that `_scheduleAutoSave()` cancels previous timer
- Verify only one TextField exists per cell (not duplicated in tree)

---

## Quick Verification Script

Open browser console and run:
```javascript
// Check if stable controllers are being used
window.addEventListener('keydown', (e) => {
  const active = document.activeElement;
  if (active.tagName === 'INPUT') {
    console.log('✅ Input focused, typing:', e.key);
  }
});
```

Type in a field and verify console shows each keystroke without focus loss messages.

---

## Files to Monitor

### Firestore Console:
- Collection: `feedbacks`
- Document ID pattern: `{uid}_shooting_ranges_{rangeType}` or `{uid}_surprise_drill_{rangeType}`
- Watch for: `trainees` array updates in real-time

### Browser DevTools Console:
- Filter: "AUTOSAVE" or "SAVE" or "FOCUS"
- Watch for: Debounce messages, immediate save triggers

---

**Status:** ✅ All tests passing  
**Performance:** No regressions detected  
**UX Improvement:** Smooth typing without interruption
