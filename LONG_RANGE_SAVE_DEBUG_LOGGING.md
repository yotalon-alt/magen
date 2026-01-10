# Long Range Save Debug Logging Implementation

## Summary
Added comprehensive debug logging to track Long Range trainee score values through the save/exit pipeline to identify where 75→7 and 100→10 transformations occur.

## Changes Made

### File: `lib/range_training_page.dart`

#### Change 1: Pre-Serialization Debug Logging (line ~1156)
**Location:** Before trainee data serialization in `_saveToFirestore()`

**Added:**
```dart
// ⚠️ DEBUG: Log before normalization for Long Range
if (_rangeType == 'ארוכים') {
  debugPrint('\n╔═══ LONG RANGE SAVE: BEFORE SERIALIZATION ═══╗');
  debugPrint('║ RangeType: $_rangeType');
  debugPrint('║ Total trainees: ${traineeRows.length}');
  for (int i = 0; i < traineeRows.length && i < 3; i++) {
    final row = traineeRows[i];
    debugPrint('║ Trainee[$i]: "${row.name}"');
    debugPrint('║   RAW values from model: ${row.values}');
  }
  debugPrint('╚═════════════════════════════════════════════╝\n');
}
```

**Purpose:**
- Logs the RAW values directly from `traineeRows` model BEFORE any serialization
- Shows what the user actually entered and what's stored in the UI model
- First checkpoint to verify no early transformation

#### Change 2: Post-Serialization Debug Logging (line ~1183)
**Location:** After trainee data is built into `traineesData` list

**Added:**
```dart
// ⚠️ DEBUG: Log after serialization for Long Range
if (_rangeType == 'ארוכים' && traineesData.isNotEmpty) {
  debugPrint('\n╔═══ LONG RANGE SAVE: AFTER SERIALIZATION ═══╗');
  debugPrint('║ Total serialized: ${traineesData.length}');
  for (int i = 0; i < traineesData.length && i < 3; i++) {
    final t = traineesData[i];
    debugPrint('║ Trainee[$i]: "${t['name']}"');
    debugPrint('║   SERIALIZED hits: ${t['hits']}');
    debugPrint('║   Total hits: ${t['totalHits']}');
  }
  debugPrint('╚═════════════════════════════════════════════╝\n');
}
```

**Purpose:**
- Logs the SERIALIZED values that will be written to Firestore
- Shows the exact data structure being saved
- Second checkpoint to catch normalization during serialization

## Debugging Strategy

### Expected Console Output for 75 Points Entry

**If NO bug (values stay as-is):**
```
╔═══ LONG RANGE SAVE: BEFORE SERIALIZATION ═══╗
║ RangeType: ארוכים
║ Total trainees: 1
║ Trainee[0]: "חניך 1"
║   RAW values from model: {0: 75}
╚═════════════════════════════════════════════╝

╔═══ LONG RANGE SAVE: AFTER SERIALIZATION ═══╗
║ Total serialized: 1
║ Trainee[0]: "חניך 1"
║   SERIALIZED hits: {station_0: 75}
║   Total hits: 75
╚═════════════════════════════════════════════╝
```

**If BUG present (division by 10):**
```
╔═══ LONG RANGE SAVE: BEFORE SERIALIZATION ═══╗
║ RangeType: ארוכים
║ Total trainees: 1
║ Trainee[0]: "חניך 1"
║   RAW values from model: {0: 75}  ← ✅ Correct: 75
╚═════════════════════════════════════════════╝

╔═══ LONG RANGE SAVE: AFTER SERIALIZATION ═══╗
║ Total serialized: 1
║ Trainee[0]: "חניך 1"
║   SERIALIZED hits: {station_0: 7}  ← ❌ BUG: 75→7 (division happened!)
║   Total hits: 7
╚═════════════════════════════════════════════╝
```

### Test Procedure

1. **Setup:**
   - Run: `flutter run -d chrome`
   - Navigate to **תרגילים** → **מטווחים** → **טווח ארוך**

2. **Create Long Range Feedback:**
   - Select folder: **מטווחים 474** or **מטווחי ירי**
   - Enter settlement (יישוב)
   - Enter attendees count (נוכחים)
   - Add one stage with 10 bullets
   - Add one trainee
   - Enter score: **75**

3. **Trigger Save:**
   - Click **שמור סופית** (Save Final)
   - Watch console for debug output

4. **Analyze Console:**
   - Find the two debug blocks (BEFORE and AFTER)
   - Compare values:
     - BEFORE SERIALIZATION: Should show `{0: 75}`
     - AFTER SERIALIZATION: Check if `{station_0: 75}` or `{station_0: 7}`

5. **Identify Bug Location:**
   - If BEFORE=75 and AFTER=7 → Bug is in serialization loop (lines 1167-1172)
   - If both show 7 → Bug is earlier (in TextField or row.values storage)
   - If both show 75 → Bug is later (in Firestore write or load)

## Next Steps Based on Debug Results

### Scenario A: Bug in Serialization (BEFORE=75, AFTER=7)
- **Location:** Lines 1167-1172 where `hitsMap` is built
- **Fix:** Add conditional logic to skip normalization for Long Range
- **Code:**
  ```dart
  row.values.forEach((stationIdx, value) {
    if (value > 0) {
      // Long Range: Store points as-is (no division)
      hitsMap['station_$stationIdx'] = value;
    }
  });
  ```
  (Already correct - no division present!)

### Scenario B: Bug in Earlier Stage (both show 7)
- **Location:** Check TextField onChanged handler or row.setValue
- **Fix:** Ensure raw value is stored without division

### Scenario C: No Bug in Save (both show 75)
- **Location:** Bug must be in load path or display
- **Check:** `fromFirestore` method or TextField controller initialization

## Acceptance Criteria

After identifying and fixing the bug:

1. **Entry:** Type **75** → Display shows **75**
2. **Save:** Click שמור סופית
3. **Console:** Both debug blocks show **75**
4. **Reload:** Reopen feedback → Display shows **75**
5. **Same for 100:** All above tests pass with **100**

## Related Code Sections

- **Serialization Loop:** lines 1167-1172
- **Deserialization:** `TraineeRowModel.fromFirestore` (line 4926)
- **TextField onChanged:** lines 3835-3950 (already has debug logging)
- **Total Hits Calculation:** `_getTraineeTotalHits` (line 700)

---
**Status:** ✅ Debug Logging Implemented - Ready for Runtime Testing
**Created:** 2025-01-10
**Issue:** "LONG RANGE ONLY bug: table score cell is being normalized by /10"
