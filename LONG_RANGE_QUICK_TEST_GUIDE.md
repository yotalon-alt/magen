# Long Range Single-Stage Quick Test Guide

## Overview
This guide provides a rapid testing workflow for the new Long Range single-stage selection feature.

**Estimated Time**: 10-15 minutes

---

## Prerequisites
```bash
cd d:\ravvshatz_feedback\flutter_application_1
flutter pub get
flutter run -d chrome  # or your preferred device
```

---

## Test Sequence

### 1. Basic UI Test (2 minutes)
1. Navigate to **Exercises → Range Feedback**
2. Select **Range Type**: `ארוכים` (Long Range)
3. ✅ **Verify**: Dropdown appears with label "בחר מקצה"
4. ✅ **Verify**: Dropdown shows 9 options:
   - עמידה 50 (מקס׳ 80)
   - כריעה 50 (מקס׳ 80)
   - שכיבה 50 (מקס׳ 80)
   - כריעה 100 (מקס׳ 80)
   - שכיבה 100 (מקס׳ 80)
   - כריעה 150 (מקס׳ 60)
   - שכיבה 150 (מקס׳ 60)
   - ילמ 50 (מקס׳ 60)
   - מקצה ידני
5. ✅ **Verify**: No "הוסף מקצה" button visible
6. ✅ **Verify**: No station list/removal buttons

---

### 2. Predefined Stage Selection (2 minutes)
1. Select **כריעה 100 (מקס׳ 80)**
2. ✅ **Verify**: Table appears with single column header
3. ✅ **Verify**: Column header shows "כריעה 100 (מקס׳ 80)"
4. Add a trainee name: "חייל טסט"
5. Enter score: 6
6. ✅ **Verify**: Input accepts number
7. ✅ **Verify**: Cannot enter more than 8 (bullets count)

---

### 3. Manual Stage Test (3 minutes)
1. Change dropdown to **מקצה ידני**
2. ✅ **Verify**: Two text fields appear:
   - "שם מקצה ידני" (RTL text input)
   - "מספר כדורים" (numeric input)
3. Enter stage name: "מקצה מיוחד"
4. Enter bullets count: 12
5. ✅ **Verify**: Table header updates to "מקצה מיוחד (מקס׳ 120)"
6. Add trainee and enter score: 10
7. ✅ **Verify**: Max bullets validation is 12

---

### 4. Validation Test (2 minutes)
1. Clear stage selection (select placeholder if available)
2. Try to save
3. ✅ **Verify**: Error message: "אנא בחר מקצה עבור מטווח ארוך"
4. Select "מקצה ידני" but leave name empty
5. Try to save
6. ✅ **Verify**: Error message: "אנא הזן שם למקצה הידני"
7. Enter name but set bullets to 0
8. Try to save
9. ✅ **Verify**: Error message: "אנא הזן מספר כדורים חוקי למקצה הידני"

---

### 5. Save & Load Test (3 minutes)
1. Fill valid Long Range feedback:
   - Stage: שכיבה 150 (מקס׳ 60)
   - Trainee: "חייל בדיקה"
   - Score: 5
   - Settlement: Test settlement
2. Click **שמור משוב סופי**
3. ✅ **Verify**: Success message appears
4. Navigate away (go to home)
5. Navigate back to **Exercises → Range Feedback**
6. Select **ארוכים** again
7. ✅ **Verify**: Form is empty (new feedback)
8. Go to **Feedbacks** page
9. Open the saved feedback
10. ✅ **Verify**: Shows correct stage, trainee, and score

---

### 6. Autosave Test (2 minutes)
1. Create new Long Range feedback
2. Select stage: **עמידה 50 (מקס׳ 80)**
3. Add trainee: "טסט אוטומטי"
4. Wait 1 second (autosave delay)
5. Refresh the page (F5)
6. Navigate back to **Exercises → Range Feedback**
7. Select **ארוכים**
8. ✅ **Verify**: Draft restored with correct stage
9. ✅ **Verify**: Trainee name restored
10. ✅ **Verify**: Stage dropdown shows selected stage

---

### 7. Mobile Responsive Test (1 minute)
1. Open Chrome DevTools (F12)
2. Toggle device toolbar (Ctrl+Shift+M)
3. Select iPhone or Android device
4. Navigate to Long Range feedback
5. Select a stage
6. Add trainee and score
7. ✅ **Verify**: Table scrolls horizontally
8. ✅ **Verify**: Header shows "(מקס׳ X)" correctly
9. ✅ **Verify**: All inputs are tap-friendly

---

### 8. Isolation Test (2 minutes)
1. Navigate to **Exercises → Range Feedback**
2. Select **Range Type**: `קצרים` (Short Range)
3. ✅ **Verify**: Multi-station UI appears (unchanged)
4. ✅ **Verify**: Can add/remove stations
5. Navigate to **Exercises → Surprise Drills**
6. ✅ **Verify**: Multi-principle UI appears (unchanged)
7. ✅ **Verify**: Can add/remove principles

---

## Expected Results Summary

### ✅ All Pass Criteria
- [x] Long Range shows single dropdown (not multi-station)
- [x] 9 predefined stages display with max points
- [x] Manual stage shows two input fields
- [x] Table headers show "(מקס׳ X)" instead of bullets
- [x] Validation prevents invalid submissions
- [x] Save creates correct Firestore document
- [x] Autosave preserves stage selection
- [x] Draft restoration works correctly
- [x] Mobile view displays properly
- [x] Short Range unchanged (multi-station)
- [x] Surprise mode unchanged (multi-principle)

---

## Troubleshooting

### Issue: Dropdown doesn't show
**Check**: Ensure `_rangeType == 'ארוכים'` is selected

### Issue: Manual inputs don't appear
**Check**: Ensure dropdown value is exactly "מקצה ידני"

### Issue: Table shows bullets instead of max points
**Check**: Lines 2013-2032 in `range_training_page.dart`

### Issue: Autosave doesn't restore stage
**Check**: Lines 1241-1398 for load logic

### Issue: Old feedbacks don't load
**Check**: Backward compatibility logic (Lines 1360-1398)

---

## Quick Debug Commands

### Check Firestore Document Structure
```javascript
// In browser console after save
firebase.firestore().collection('feedbacks')
  .where('rangeType', '==', 'ארוכים')
  .orderBy('createdAt', 'desc')
  .limit(1)
  .get()
  .then(snapshot => {
    snapshot.forEach(doc => console.log(doc.data()));
  });
```

### Expected Document
```json
{
  "rangeType": "ארוכים",
  "selectedLongRangeStage": "כריעה 100",
  "longRangeManualStageName": "",
  "longRangeManualBulletsCount": 0,
  "stations": [
    {"name": "כריעה 100", "bulletsCount": 8}
  ],
  "trainees": [
    {
      "name": "חייל טסט",
      "hits": {"station_0": 6},
      "totalHits": 6
    }
  ],
  "settlement": "...",
  "status": "final",
  "createdAt": "...",
  "instructorId": "..."
}
```

---

## Test Report Template

```
Long Range Single-Stage Test Results
Date: _____________
Tester: ___________

1. Basic UI:           [ ] PASS  [ ] FAIL  Notes: ________________
2. Predefined Stage:   [ ] PASS  [ ] FAIL  Notes: ________________
3. Manual Stage:       [ ] PASS  [ ] FAIL  Notes: ________________
4. Validation:         [ ] PASS  [ ] FAIL  Notes: ________________
5. Save & Load:        [ ] PASS  [ ] FAIL  Notes: ________________
6. Autosave:          [ ] PASS  [ ] FAIL  Notes: ________________
7. Mobile View:        [ ] PASS  [ ] FAIL  Notes: ________________
8. Isolation:          [ ] PASS  [ ] FAIL  Notes: ________________

Overall: [ ] PASS  [ ] FAIL

Issues Found:
1. ________________________________________________________
2. ________________________________________________________
3. ________________________________________________________

Recommendations:
_____________________________________________________________
_____________________________________________________________
```

---

## Success Criteria
All 8 tests must PASS for feature to be considered complete and ready for production.

---

## Next Steps After Testing
1. ✅ If all tests pass: Deploy to production
2. ❌ If tests fail: Report issues with test number and description
3. 📝 Document any edge cases discovered during testing
