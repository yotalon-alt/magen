# Quick Test Plan - Trainee Table Persistence

## 🎯 Goal
Verify that trainee names and scores persist after temporary save → navigate away → return.

## 🧪 Test Scenarios

### Test 1: Range Training (Short) - Basic Persistence
**Steps:**
1. Open "Range Training" → Select "קצרים" (Short)
2. Enter settlement: "קצרין"
3. Set attendees count: 3
4. Add 2 stations: "רמות" (10 bullets), "שלשות" (15 bullets)
5. Enter trainee data:
   - Row 1: Name "דני", Hits: 8, 12
   - Row 2: Name "אורי", Hits: 7, 14
   - Row 3: Name "רועי", Hits: 9, 13
6. Wait 3 seconds (autosave triggers)
7. Look for "המשוב נשמר באופן זמני" message
8. Navigate back to feedbacks list
9. Open the temp feedback again

**Expected Result:**
✅ All trainee names appear: דני, אורי, רועי  
✅ All scores appear: 8/12, 7/14, 9/13  
✅ Settlement: קצרין  
✅ Attendees: 3  
✅ Stations: רמות (10), שלשות (15)

### Test 2: Surprise Drills - Score Persistence
**Steps:**
1. Open "Range Training" → Select "הפתעה" (Surprise)
2. Enter command: "אוגדה 36"
3. Enter brigade: "חטיבה 474"
4. Set attendees count: 2
5. Add 3 principles: "קשר עין", "בחירת ציר", "איום עיקרי"
6. Enter scores (1-10 scale):
   - Row 1: Name "יוסי", Scores: 8, 7, 9
   - Row 2: Name "משה", Scores: 9, 8, 10
7. Wait for autosave
8. Navigate back
9. Return to temp feedback

**Expected Result:**
✅ Names: יוסי, משה  
✅ Scores: 8/7/9, 9/8/10  
✅ Command: אוגדה 36  
✅ Brigade: חטיבה 474

### Test 3: Edge Case - Empty Scores
**Steps:**
1. Open range training (any type)
2. Enter 2 trainee names: "אבי", "גדי"
3. Leave all scores empty (0)
4. Save and navigate away
5. Return to feedback

**Expected Result:**
✅ Names appear: אבי, גדי  
✅ Score fields are EMPTY (not "0")  
✅ Can enter scores after reload

### Test 4: Multiple Edit Cycles
**Steps:**
1. Create temp feedback with 1 trainee "טל", score 5
2. Save → return → verify
3. Edit: change name to "טלי", score to 8
4. Save → return → verify
5. Add 2nd trainee "רון", score 7
6. Save → return → verify

**Expected Result:**
✅ First reload: "טל" with 5  
✅ Second reload: "טלי" with 8  
✅ Third reload: "טלי" (8), "רון" (7)

## 🔍 Debug Console Verification

When saving, you should see in console:
```
💾 Saving temporary feedback...
   attendeesCount: 3, trainees: 3, stations: 2
📤 SAVING TRAINEES:
   Total trainees: 3
   First trainee name: "דני"
   First trainee hits: {0: 8, 1: 12}
   Updating existing temp doc: <doc-id>
✅ Temp save complete (update)
```

When loading, you should see:
```
🔵 Loading temporary feedback: <doc-id>
📥 Document loaded, parsing data...
   Loaded attendeesCount: 3
   Loaded 3 trainees
     Trainee 0: "דני" with 2 hits
     Trainee 1: "אורי" with 2 hits
     Trainee 2: "רועי" with 2 hits
✅ Load complete: 3 attendees, 3 trainees, 2 stations
```

## 🐛 How to Spot Failures

### ❌ BUG STILL EXISTS if:
- Names are empty after reload
- Scores show 0 or empty when they should have values
- Only first/last row persists
- Data disappears after multiple save cycles

### ✅ FIX SUCCESSFUL if:
- All names persist exactly as entered
- All scores persist exactly as entered
- Empty scores stay empty (don't become "0")
- Data survives multiple edit/save/reload cycles

## 📱 Testing Platforms

Test on:
- [ ] Chrome (Web)
- [ ] Android Device/Emulator
- [ ] iOS Device/Simulator (if available)

All platforms should behave identically.

## ⚡ Quick Smoke Test (2 minutes)

Minimum test to confirm fix:
1. Open any range type
2. Enter 1 trainee: name "Test", score 5
3. Wait for autosave message
4. Go back
5. Re-open
6. **VERIFY**: "Test" appears with score 5

If this passes ✅ → Fix is working!  
If this fails ❌ → Check console logs for errors

---

**Test Date**: ___________  
**Tester**: ___________  
**Result**: ⬜ PASS  /  ⬜ FAIL  
**Notes**: ___________
