# Long Range Feedback - Regression Testing Guide

## Overview
This guide validates the critical fixes for long range feedback folder preservation and points persistence.

**Fixed Issues:**
1. **Folder Mis-Classification Bug** (lines 1467-1483): Draft save incorrectly matched 'מטווחי ירי' to 'ranges_474' due to substring matching
2. **Points Persistence** (verified): Student-entered points are stored/loaded AS-IS without conversion

---

## Test Environment Setup

### Prerequisites
- Flutter app running (debug mode recommended for console logs)
- Firebase Firestore accessible
- Admin or Instructor account logged in
- Access to both folder options:
  - 'מטווחים 474'
  - 'מטווחי ירי'

### Console Log Monitoring
Enable console logging to verify points verification:
```
╔═══ LONG RANGE FINAL SAVE ═══╗
║ ⚠️  POINTS VERIFICATION: Values stored AS-IS, NO division/multiplication
║ 👤 Trainee[0]: "שם חניך" → totalPoints=45 (RAW values={0: 15, 1: 30})
║    ↳ Station[0]: value=15 (stored/displayed AS-IS)
╚══════════════════════════════════════════════════╝
```

---

## Path A: Direct Save Flow (Fill Once → Final Save)

### Objective
Verify that a new long range feedback saves folder data correctly and preserves student points without conversion.

### Test Steps

#### 1. Create New Long Range Feedback
- Navigate to: `תרגילים` → `מטווחים` → `אימון טווחים ארוכים`
- Fill mandatory fields:
  - **יישוב**: Select any settlement (e.g., 'קצרין')
  - **תרחיש**: Enter scenario description (e.g., 'אימון ראשון')
  - **מדריך**: Should auto-populate with logged-in instructor name
  - **תיקייה**: Select **'מטווחי ירי'** (CRITICAL - tests the folder fix)

#### 2. Add Stages
- Click "הוסף מקצה"
- **Stage 1:**
  - שם מקצה: `100 מטר`
  - מספר כדורים: `5` → This will display **מקסימום נקודות: 50**
- **Stage 2:**
  - שם מקצה: `200 מטר`
  - מספר כדורים: `7` → This will display **מקסימום נקודות: 70**

**Expected Display:** Stage headers show `maxPoints = bulletsCount * 10` (display-only calculation)

#### 3. Add Trainees
- Click "הוסף חניך"
- **Trainee 1:**
  - שם: `אביב כהן`
  - Stage 1 (100 מטר): Enter `35` points
  - Stage 2 (200 מטר): Enter `55` points
- **Trainee 2:**
  - שם: `דני לוי`
  - Stage 1: Enter `42` points
  - Stage 2: Enter `63` points

**Critical:** These are POINTS (not hits). They should be stored AS-IS.

#### 4. Final Save
- Click **"שמירה סופית"**
- Wait for success message

#### 5. Console Log Verification
Check console for:
```
╔═══ LONG RANGE FINAL SAVE ═══╗
║ Folder Mapping:
║   rangeFolder: "מטווחי ירי"
║   draftFolderKey: "shooting_ranges"
║   draftFolderLabel: "מטווחי ירי"
║ ⚠️  POINTS VERIFICATION: Values stored AS-IS, NO division/multiplication
║ 👤 Trainee[0]: "אביב כהן" → totalPoints=90 (RAW values={0: 35, 1: 55})
║    ↳ Station[0]: value=35 (stored/displayed AS-IS)
║ 👤 Trainee[1]: "דני לוי" → totalPoints=105 (RAW values={0: 42, 1: 63})
║    ↳ Station[0]: value=42 (stored/displayed AS-IS)
╚══════════════════════════════════════════════════╝
```

**Verify:**
- ✅ `draftFolderKey: "shooting_ranges"` (NOT "ranges_474")
- ✅ `draftFolderLabel: "מטווחי ירי"`
- ✅ Point values match entered data (35, 55, 42, 63)

#### 6. Navigate to Feedbacks Page
- Go to: `משובים` tab
- Select folder: **'מטווחי ירי'**
- Find the newly created feedback (look for 'קצרין' settlement)

**Expected Results:**
- ✅ Feedback appears in **'מטווחי ירי'** folder (NOT in 'מטווחים 474')
- ✅ Blue tag label shows: **'טווח ארוך'**
- ✅ Settlement: 'קצרין'
- ✅ Date matches current date

#### 7. Open Feedback Details
- Click on the feedback card
- Scroll to trainee data table

**Expected Results:**
- ✅ **Stage 1 header:** Shows "100 מטר - מקסימום נקודות: 50"
- ✅ **Stage 2 header:** Shows "200 מטר - מקסימום נקודות: 70"
- ✅ **Trainee 1 (אביב כהן):**
  - Stage 1: `35` (NOT 3.5, NOT 350)
  - Stage 2: `55` (NOT 5.5, NOT 550)
- ✅ **Trainee 2 (דני לוי):**
  - Stage 1: `42`
  - Stage 2: `63`
- ✅ **Total points** calculated correctly: 35+55=90, 42+63=105

#### 8. Firestore Verification (Optional)
- Open Firebase Console → Firestore Database
- Collection: `feedbacks`
- Find document (search by settlement 'קצרין')
- Verify fields:
  ```json
  {
    "folder": "מטווחי ירי",
    "folderKey": "shooting_ranges",
    "folderLabel": "מטווחי ירי",
    "isTemporary": false,
    "module": "shooting_ranges",
    "trainees": [
      {
        "name": "אביב כהן",
        "values": {"0": 35, "1": 55}
      },
      {
        "name": "דני לוי",
        "values": {"0": 42, "1": 63}
      }
    ]
  }
  ```

---

## Path B: Draft Save → Load → Final Save Flow

### Objective
Verify that draft auto-save preserves folder data and points, and that loading from drafts + final save maintains both.

### Test Steps

#### 1. Create New Long Range Feedback
- Navigate to: `תרגילים` → `מטווחים` → `אימון טווחים ארוכים`
- Fill fields:
  - **יישוב**: 'עפולה'
  - **תרחיש**: 'תרגול מטווח ארוך'
  - **תיקייה**: Select **'מטווחים 474'** (DIFFERENT folder from Path A)

#### 2. Add Stages
- **Stage 1:**
  - שם: `150 מטר`
  - כדורים: `6` → Max points: 60
- **Stage 2:**
  - שם: `250 מטר`
  - כדורים: `8` → Max points: 80

#### 3. Add Trainee
- **Trainee 1:**
  - שם: `רונן ישראלי`
  - Stage 1: `48` points
  - Stage 2: `65` points

#### 4. Exit WITHOUT Final Save
- Click **back button** or **navigate away**
- **DO NOT** click "שמירה סופית"
- Draft should auto-save automatically

#### 5. Console Log Verification (Draft Save)
```
═══ DRAFT SAVE: Long Range ═══
Folder Mapping:
  rangeFolder: "מטווחים 474"
  draftFolderKey: "ranges_474"
  draftFolderLabel: "מטווחים 474"
Document ID: {uid}_range_ארוכים
Draft saved successfully with isTemporary=true
```

**Verify:**
- ✅ `draftFolderKey: "ranges_474"` (NOT "shooting_ranges")
- ✅ Auto-save triggered on exit

#### 6. Navigate to Temp Feedbacks
- Go to: `משובים` → Click **"פתח טיוטות"** button
- Should see temp feedbacks list

**Expected Results:**
- ✅ Draft appears with:
  - Blue tag: **'טווח ארוך'**
  - Settlement: 'עפולה'
  - Scenario: 'תרגול מטווח ארוך'
  - **Folder badge:** "מטווחים 474" (green chip)

#### 7. Open Draft
- Click on the draft card
- Page should reload with all data

#### 8. Console Log Verification (Draft Load)
```
╔═══ LONG RANGE POINTS LOAD VERIFICATION ═══╗
║ Trainee[0]: "רונן ישראלי" RAW values={0: 48, 1: 65}
║   Station[0]: value=48 (NO conversion applied)
║   Station[1]: value=65 (NO conversion applied)
╚═══════════════════════════════════════════════╝
```

**Verify:**
- ✅ Point values loaded AS-IS: 48, 65 (NOT divided by 10)

#### 9. Verify Loaded State
- **יישוב:** Should show 'עפולה'
- **תרחיש:** Should show 'תרגול מטווח ארוך'
- **תיקייה:** Should show **'מטווחים 474'** selected
- **Stages:**
  - Stage 1: `150 מטר` - 6 כדורים - Max: 60
  - Stage 2: `250 מטר` - 8 כדורים - Max: 80
- **Trainee:**
  - Name: `רונן ישראלי`
  - Stage 1 value: `48`
  - Stage 2 value: `65`

**Critical Checks:**
- ✅ Folder selection preserved (dropdown shows 'מטווחים 474')
- ✅ Point values match original entry (48, 65)
- ✅ No corruption or data loss

#### 10. Final Save from Draft
- Click **"שמירה סופית"**
- Wait for success message

#### 11. Console Log Verification (Final Save)
```
╔═══ LONG RANGE FINAL SAVE ═══╗
║ Folder Mapping:
║   rangeFolder: "מטווחים 474"
║   draftFolderKey: "ranges_474"
║   draftFolderLabel: "מטווחים 474"
║ ⚠️  POINTS VERIFICATION: Values stored AS-IS
║ 👤 Trainee[0]: "רונן ישראלי" → totalPoints=113 (RAW values={0: 48, 1: 65})
╚══════════════════════════════════════════════════╝

Draft cleanup: Deleting temporary draft...
Draft deleted successfully
```

**Verify:**
- ✅ Folder correctly mapped to `ranges_474`
- ✅ Points preserved: 48, 65 (total: 113)
- ✅ Draft deleted after final save

#### 12. Verify in Feedbacks List
- Go to: `משובים` tab
- Select folder: **'מטווחים 474'**
- Find feedback with settlement 'עפולה'

**Expected Results:**
- ✅ Appears in **'מטווחים 474'** folder (NOT 'מטווחי ירי')
- ✅ Blue tag: **'טווח ארוך'**
- ✅ NOT in temp feedbacks list anymore

#### 13. Open Details and Verify Points
- Click feedback card
- Check trainee table:
  - Stage 1: `48` points
  - Stage 2: `65` points
  - Total: `113` points

**Expected Results:**
- ✅ All point values preserved exactly as entered
- ✅ No conversion artifacts (no decimal values, no multiplication)

---

## Regression Checks

### Test 1: Short Range Feedback (Control Test)
**Purpose:** Ensure folder fix didn't break short range flow

**Steps:**
1. Create short range feedback
2. Select 'מטווחי ירי' folder
3. Add station: 50 כדורים
4. Add trainee with hits: 35
5. Save and verify folder correct

**Expected:** No changes in behavior (control group)

---

### Test 2: 474 Ranges Folder Selection
**Purpose:** Verify exact string matching doesn't reject valid '474 Ranges' variants

**Steps:**
1. Create long range feedback
2. Select 'מטווחים 474'
3. Complete and save
4. Verify: `folderKey: "ranges_474"`, appears in correct folder

---

### Test 3: Mixed Folder Types in Same Session
**Purpose:** Ensure folder state doesn't leak between different feedbacks

**Steps:**
1. Create feedback with 'מטווחים 474'
2. Exit (auto-save draft)
3. Create NEW feedback with 'מטווחי ירי'
4. Verify second feedback has correct folder (NOT 474)

---

## Success Criteria

### ✅ All tests must pass:
- [ ] **Path A:** Direct save preserves folder and points
- [ ] **Path B:** Draft → Load → Final preserves folder and points
- [ ] **Regression 1:** Short range unchanged
- [ ] **Regression 2:** 474 folder works correctly
- [ ] **Regression 3:** No folder state leakage

### ✅ Console Logs Confirm:
- [ ] Folder mapping uses exact string matching (no .contains())
- [ ] Points logged with "NO conversion applied" message
- [ ] Draft deleted after successful final save

### ✅ Firestore Data:
- [ ] `folderKey` matches folder selection
- [ ] `trainees[].values` contains raw point integers
- [ ] `isTemporary: false` for final feedbacks
- [ ] Draft documents deleted after finalization

---

## Known Issues (Not in Scope)

1. **Blue Tag Label:** Currently under investigation (separate task)
2. **Export Schema:** May need updates for new folder fields (future enhancement)
3. **Legacy Data:** Old feedbacks without folderKey may need migration (backlog)

---

## Troubleshooting

### Issue: Folder shows wrong classification
**Check:** Console log for folder mapping
**Expected:** Exact string matching, not substring
**Fix:** Verify lines 1467-1483 have exact equality checks

### Issue: Points appear divided by 10
**Check:** Console log for "NO conversion applied"
**Expected:** RAW values={0: 48, 1: 65}
**Fix:** Should not occur with current code (no division logic exists)

### Issue: Draft not loading
**Check:** Console for "DRAFT_LOAD" messages
**Expected:** Draft loads with preserved folder selection
**Fix:** Verify draft document has rangeFolder field in Firestore

---

## Reporting Results

### Template:
```
TEST RESULTS - Long Range Regression
Date: [DATE]
Tester: [NAME]
Environment: [Web/Mobile/Desktop]

Path A: [PASS/FAIL]
  - Folder: [CORRECT/WRONG] - Expected: מטווחי ירי, Got: _____
  - Points: [CORRECT/WRONG] - Expected: 35,55,42,63, Got: _____

Path B: [PASS/FAIL]
  - Draft Save: [PASS/FAIL]
  - Draft Load: [PASS/FAIL]
  - Folder Preserved: [YES/NO] - Expected: מטווחים 474, Got: _____
  - Points Preserved: [YES/NO] - Expected: 48,65, Got: _____
  - Final Save: [PASS/FAIL]

Regressions: [ALL PASS / ISSUES FOUND]

Console Logs Attached: [YES/NO]
Screenshots: [YES/NO]

Notes: _____
```

---

## Next Steps After Testing

1. **If all tests pass:**
   - Mark folder fix as verified ✅
   - Mark points persistence as verified ✅
   - Proceed to blue label fix (separate task)

2. **If any test fails:**
   - Capture console logs
   - Screenshot UI state
   - Check Firestore document structure
   - Report exact failure case to development team
