# Long Range Single Source of Truth - Quick Test Guide

## What Changed
**Long Range now uses bullets count as single source of truth:**
- Input field changed from "נקודות מקסימום" to "מספר כדורים"
- Max points calculated automatically: `maxPoints = bulletsCount × 10`
- All displays, validations, and calculations use the same computed maxPoints

---

## 1-Minute Smoke Test

### Test: Create New Long Range Feedback
1. **Start app** → Navigate to: תרגילים → מטווחים → טווחים ארוכים
2. **Add stage**: Click "הוסף מקצה" → Select "רמות"
3. **Enter bullets**: In "מספר כדורים" field, type: `15`
4. **Verify display**: Under stage name, should show: `150 נק׳`
5. **Add trainee**: Click "הוסף חניך", enter name: "דני"
6. **Check table header**: Above "רמות" column, should show: `150`
7. **Enter points**: In table cell for דני/רמות, type: `120`
8. **Verify**: Should accept (120 < 150)
9. **Try invalid**: Type: `160`
10. **Verify error**: Should show: "נקודות לא יכולות לעלות על 150 נקודות"

### Expected Results
✅ Input field label: "מספר כדורים"
✅ Hint text: "הזן מספר כדורים (נקודות = כדורים × 10)"
✅ Stage card shows: "150 נק׳" (15 × 10)
✅ Table header shows: "150" (15 × 10)
✅ Validation uses 150 as max (15 × 10)

---

## Full Test Scenarios

### Scenario 1: Multiple Stages with Different Bullet Counts
**Goal**: Verify each stage independently calculates maxPoints

Steps:
1. Create feedback → Add 3 stages:
   - רמות: 20 bullets → should show 200 points
   - שלשות: 10 bullets → should show 100 points
   - עפדיו: 5 bullets → should show 50 points
2. Add trainee "אלי"
3. Check table headers:
   - Column 1: 200
   - Column 2: 100
   - Column 3: 50
4. Enter points:
   - רמות: 180 → ✅ valid
   - שלשות: 95 → ✅ valid
   - עפדיו: 48 → ✅ valid
5. Try invalid:
   - רמות: 210 → ❌ error (> 200)
   - שלשות: 105 → ❌ error (> 100)

**Pass Criteria**: Each stage enforces its own computed maxPoints

---

### Scenario 2: Change Bullets Count After Entry
**Goal**: Verify maxPoints updates everywhere when bullets change

Steps:
1. Create feedback → Add stage "חץ": 10 bullets (100 points)
2. Add trainee "יוני"
3. Enter 90 points → ✅ valid
4. Go back to stage card, change bullets: 10 → 5
5. Check stage card: Should show 50 נק׳ (5 × 10)
6. Check table header: Should show 50
7. Existing cell value (90) now invalid → should show error
8. Change cell to 45 → ✅ valid (< 50)

**Pass Criteria**: All maxPoints references update instantly when bullets change

---

### Scenario 3: Save and Reload
**Goal**: Verify data persists correctly

Steps:
1. Create feedback with stage "קשת": 8 bullets
2. Verify shows 80 נק׳
3. Click "שמור זמנית" (temp save)
4. Reload the app (close and reopen)
5. Navigate back to drafts, open same feedback
6. Verify stage still shows: 80 נק׳
7. Verify table header shows: 80

**Pass Criteria**: bullets count and computed maxPoints persist

---

### Scenario 4: Backward Compatibility (Old Data)
**Goal**: Verify migration from old maxPoints-only data

**Setup** (requires Firestore access):
1. Manually create old-format feedback in Firestore:
```json
{
  "longRangeStages": [
    {
      "name": "רמות",
      "maxPoints": 150,
      "bulletsCount": 0
    }
  ]
}
```

**Test**:
1. Load this feedback in app
2. Open stage card
3. **Expected**: "מספר כדורים" field should show: `15` (150 / 10)
4. **Expected**: Stage display shows: `150 נק׳`
5. Change bullets to 20
6. **Expected**: Shows `200 נק׳`
7. Save and reload
8. **Expected**: Still shows 20 bullets / 200 points

**Pass Criteria**: Old data migrates to new schema seamlessly

---

## Common Issues & Troubleshooting

### Issue: Header shows "0" even after entering bullets
**Cause**: Stage card not refreshing
**Fix**: Check `setState()` is called in `onChanged` handler

### Issue: Validation error shows wrong maxPoints
**Cause**: Validation using old maxPoints field instead of getter
**Fix**: Verify lines 3305, 3531 use `stage.maxPoints` (which is now the getter)

### Issue: Old data doesn't migrate
**Cause**: `fromJson` not deriving bulletsCount correctly
**Fix**: Check backward compatibility logic in `LongRangeStageModel.fromJson`

---

## Regression Test Checklist

### Core Functionality (Must Pass)
- [ ] Create new Long Range feedback
- [ ] Add stage with bullets count
- [ ] Display shows correct maxPoints (bullets × 10)
- [ ] Table header shows correct maxPoints
- [ ] Validation enforces correct maxPoints
- [ ] Total calculation uses correct maxPoints
- [ ] Percentage calculation correct

### Edge Cases
- [ ] bullets = 0 → maxPoints = 0
- [ ] bullets = 1 → maxPoints = 10
- [ ] bullets = 100 → maxPoints = 1000
- [ ] Change bullets count → all displays update
- [ ] Multiple stages → each has correct maxPoints

### Integration
- [ ] Save temporary feedback → reload → data intact
- [ ] Finalize feedback → saves to Firestore correctly
- [ ] Export to XLSX → maxPoints column correct

### Surprise Drills (No Changes)
- [ ] Surprise drills still use dynamic maxPoints
- [ ] Surprise export still matches UI
- [ ] No regression in Surprise functionality

---

## Success Criteria

### Must Have
✅ User enters bullets (not points) in stage card
✅ maxPoints = bullets × 10 everywhere
✅ Header, validation, totals all synchronized
✅ Old data migrates automatically

### Should Have
✅ Hint text explains relationship clearly
✅ Error messages show correct maxPoints
✅ No compilation errors in `flutter analyze`

### Nice to Have
✅ Clear documentation for future maintainers
✅ Test guide for QA team
✅ Backward compatibility verified

---

## Next Steps After Testing

If all tests pass:
1. ✅ Mark Long Range as complete
2. ✅ Document in release notes
3. ✅ Update user guide (bullets input, not points)

If issues found:
1. Document exact steps to reproduce
2. Check which component fails (UI, model, validation, totals)
3. Fix and retest

---

## Quick Verification Commands

```bash
# Check compilation
flutter analyze

# Run on device
flutter run

# Hot reload after changes
r (in running app)

# Full restart
R (in running app)
```

---

## Contact

Questions? Check:
- `LONG_RANGE_SINGLE_SOURCE_FIX.md` - Technical details
- `.github/copilot-instructions.md` - Project conventions
- `lib/range_training_page.dart` lines 38-85 - Model code
