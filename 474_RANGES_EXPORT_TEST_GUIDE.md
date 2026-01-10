# 474 Ranges Export - Quick Test Guide

## Prerequisites
- Have at least 2-3 feedbacks saved in "מטווחים 474" folder
- Logged in as Admin user
- Using Web or Mobile device

---

## Test 1: Single Feedback Export (2 minutes)

### Steps:
1. Navigate to: **משובים → מטווחים 474**
2. Click any feedback to open details
3. **VERIFY**: Export button (download icon) appears in AppBar (top right)
4. Click the export button
5. **VERIFY**: Loading indicator appears briefly
6. **VERIFY**: File downloads: `474_ranges_export_YYYY-MM-DD_HH-mm.xlsx`
7. Open the Excel file
8. **VERIFY**:
   - ✅ Sheet name is: `[settlement] [date]` (e.g., "אורטל 15-01-2025")
   - ✅ Metadata section shows: Title, Date, Instructor, Settlement, Type, Count
   - ✅ Table has headers: שם חניך, [stage names], סה"כ פגיעות, סה"כ כדורים, אחוז כללי
   - ✅ "כדורים למקצה" row shows bullets per stage
   - ✅ All trainees appear as rows with hits/bullets values
   - ✅ Totals row at bottom shows correct sums
   - ✅ Percentages are calculated correctly
   - ✅ Hebrew text displays right-to-left

### Expected Result:
✅ XLSX file downloaded with complete feedback data matching on-screen display

### If Failed:
- Check browser console for errors
- Verify feedback has `folderKey == 'ranges_474'` or `folder == 'מטווחים 474'`
- Verify Firestore document has `stations` and `trainees` arrays

---

## Test 2: Multi-Select Export (3 minutes)

### Steps:
1. Navigate to: **משובים → מטווחים 474**
2. **VERIFY**: Selection toggle button (checklist icon) appears in AppBar
3. Click the selection toggle button
4. **VERIFY**:
   - ✅ Icon changes to X (close)
   - ✅ Checkboxes appear on each feedback card (left side)
   - ✅ Selection action bar appears above list
   - ✅ Shows "נבחרו: 0"
5. Click checkbox on 3 different feedbacks
6. **VERIFY**: Count updates: "נבחרו: 3"
7. Click the green "ייצוא" (Export) button in action bar
8. **VERIFY**: Loading indicator appears
9. **VERIFY**: File downloads: `474_ranges_selected_YYYY-MM-DD_HH-mm.xlsx`
10. Open the Excel file
11. **VERIFY**:
    - ✅ File has 3 sheets (one per selected feedback)
    - ✅ Each sheet name is unique: settlement + date
    - ✅ All sheets have complete data (metadata + table)
    - ✅ Data matches the on-screen feedbacks
12. Go back to the app
13. **VERIFY**: 
    - ✅ Success message appears: "הקובץ נוצר בהצלחה!"
    - ✅ Selection mode exited automatically
    - ✅ Checkboxes disappeared
14. Click selection toggle again to re-enter selection mode
15. Select 1 feedback
16. Click "בטל" (Cancel) button
17. **VERIFY**:
    - ✅ Selection mode exited
    - ✅ Selection cleared

### Expected Result:
✅ XLSX file with 3 sheets, each containing complete feedback data

### If Failed:
- Check that feedbacks have valid `id` field
- Check Firestore permissions (should allow read)
- Verify network connection (Firestore fetch may timeout)

---

## Test 3: Edge Cases (2 minutes)

### Test 3a: Export with Same Settlement + Date
1. Create 2 feedbacks with same settlement on same day
2. Multi-select both
3. Export
4. **VERIFY**: Sheet names have suffix: `אורטל 15-01-2025`, `אורטל 15-01-2025 (1)`

### Test 3b: Export with Long Settlement Name
1. Find/create feedback with very long settlement name (30+ chars)
2. Export single feedback
3. **VERIFY**: Sheet name is truncated to 31 characters

### Test 3c: Export Empty Selection
1. Enter selection mode
2. Click export WITHOUT selecting any feedbacks
3. **VERIFY**: Error message: "לא נבחרו משובים לייצוא"

### Test 3d: Non-474 Feedback (Should NOT Have Export)
1. Navigate to: **משובים → מטווחי ירי** (NOT 474)
2. Click any feedback to open details
3. **VERIFY**: NO export button in AppBar

---

## Test 4: Different Devices (5 minutes)

### Test on Web Browser:
1. Run: `flutter run -d chrome`
2. Execute Test 1 and Test 2
3. **VERIFY**: Files download to browser's Downloads folder

### Test on Android/iOS:
1. Connect device
2. Run: `flutter run -d [device]`
3. Execute Test 1 and Test 2
4. **VERIFY**: 
   - Files save to Downloads (Android) or Documents (iOS)
   - Can open files in Excel/Sheets app

---

## Performance Test (optional)

### Large Export:
1. Create 20-30 feedbacks in "מטווחים 474" folder
2. Multi-select all
3. Click export
4. **VERIFY**:
   - Export completes within 30 seconds
   - All sheets are correct
   - No timeout errors

---

## Debugging Checklist

### If Export Button Doesn't Appear:
```dart
// Check in Firestore console:
- feedback.folderKey == 'ranges_474'  OR
- feedback.folder == 'מטווחים 474'   OR
- feedback.folder == '474 Ranges'

// Check user role:
- currentUser.role == 'Admin'
```

### If Export Fails with Error:
```dart
// Check browser/app console for:
1. Firestore permission denied
2. Document doesn't exist
3. Missing stations/trainees fields
4. Network timeout

// Verify document structure:
{
  instructorName: string,
  settlement: string,
  createdAt: Timestamp,
  rangeType: string,
  attendeesCount: number,
  stations: [
    { name: string, bulletsCount: number, ... }
  ],
  trainees: [
    { 
      name: string, 
      hits: { station_0: number, station_1: number, ... } 
    }
  ]
}
```

### If Checkboxes Don't Appear:
```dart
// Verify:
1. Viewing "מטווחים 474" folder (exact match)
2. Selection mode is enabled (_selectionMode == true)
3. FeedbackListTileCard received selectionMode parameter
```

---

## Success Criteria Summary

| Test | Expected | Status |
|------|----------|--------|
| Single export button appears | ✅ Only for 474 ranges | ⏳ |
| Single export creates file | ✅ Valid XLSX with data | ⏳ |
| Selection mode toggle | ✅ Shows/hides checkboxes | ⏳ |
| Multi-select count | ✅ Updates correctly | ⏳ |
| Multi-select export | ✅ One sheet per feedback | ⏳ |
| Data accuracy | ✅ Matches on-screen | ⏳ |
| Hebrew RTL | ✅ Displays correctly | ⏳ |
| Error handling | ✅ Shows messages | ⏳ |
| Web download | ✅ Works | ⏳ |
| Mobile save | ✅ Works | ⏳ |

---

## Completion

After all tests pass:
- [ ] Mark all checkboxes in main implementation doc
- [ ] Update README.md with new export feature
- [ ] Create user documentation
- [ ] Deploy to production

---

**Test Duration**: ~12-15 minutes for complete test suite  
**Recommended**: Run on both Web and Mobile before production deployment

