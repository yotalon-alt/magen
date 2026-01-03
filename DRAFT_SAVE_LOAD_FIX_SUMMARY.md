# Draft Save/Load Fix Summary for Range and Surprise Drills

## Completed Changes ✅

### 1. TraineeRowModel - Single Source of Truth ✅
- Created `TraineeRowModel` class with:
  - `index`: trainee row number
  - `name`: trainee name
  - `values`: Map<int, int> for all numeric data (hits/scores)
  - `getValue()/setValue()` methods
  - `toFirestore()/fromFirestore()` serialization

### 2. State Refactoring ✅  
- Replaced `List<Trainee> trainees` + `List<int> traineeNumbers` 
- With `List<TraineeRowModel> traineeRows` (single source of truth)
- Added `Timer? _autoSaveTimer` for debounced autosave

### 3. Autosave Mechanism ✅
- Implemented `_scheduleAutoSave()` with 600ms debounce
- Called on every data change (name edits, value edits, row count changes)
- Timer cancelled in dispose()

### 4. Atomic Draft Save ✅
- Completely rewrote `_saveTemporarily()`:
  - Uses deterministic draft ID: `{uid}_{module}_{rangeType}`
  - Saves full payload with `traineeRows` data
  - Read-back verification
  - Comprehensive debug logs
  - Updates same doc (no duplicates)

### 5. Atomic Draft Load ✅
- Completely rewrote `_loadExistingTemporaryFeedback()`:
  - Loads doc first
  - Rebuilds `traineeRows` from Firestore using `TraineeRowModel.fromFirestore()`
  - NO default empty rows after load
  - Comprehensive debug logs

### 6. Helper Methods Updated ✅
- `_getTraineeTotalHits()` - uses traineeRows
- `_getTraineeTotalPoints()` - uses traineeRows  
- `_getTraineeAveragePoints()` - uses traineeRows
- `_updateAttendeesCount()` - uses traineeRows + triggers autosave
- `_removeStation()` - uses traineeRows + triggers autosave
- `_saveToFirestore()` - uses traineeRows for final save

### 7. UI Updates (Partial) ✅
- Mobile layout number column: uses traineeRows ✅
- Mobile layout name column: uses traineeRows + autosave ✅  
- Mobile layout values: **NEEDS COMPLETION** ⚠️
- Desktop summary columns: **NEEDS COMPLETION** ⚠️

---

## Remaining Work ⚠️

### Mobile Layout - Station Value Inputs
**File**: `lib/range_training_page.dart`  
**Line**: ~1527

**Current Code** (WRONG - uses old `trainees.map((trainee)`):
```dart
                                      ...trainees.map((trainee) {
                                        return Container(
                                          height: 60,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: TextField(
                                            controller:
                                                TextEditingController(
                                                    text:
                                                        (trainee.hits[stationIndex] ??
                                                                0) ==
                                                            0
                                                        ? ''
                                                        : trainee
                                                              .hits[stationIndex]
                                                              .toString(),
                                                  )
```

**Required Code** (CORRECT - uses `traineeRows`):
```dart
                                      ...traineeRows.asMap().entries.map((entry) {
                                        final traineeIndex = entry.key;
                                        final row = entry.value;
                                        final currentValue = row.getValue(stationIndex);
                                        return Container(
                                          height: 60,
                                          padding: const EdgeInsets.all(4.0),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: TextField(
                                            controller:
                                                TextEditingController(
                                                    text:
                                                        currentValue == 0
                                                        ? ''
                                                        : currentValue.toString(),
                                                  )
```

**And in onChanged**:
```dart
                                              setState(() {
                                                row.setValue(stationIndex, score);
                                              });
                                              // ✅ Trigger autosave
                                              _scheduleAutoSave();
```

### Desktop Summary Columns
Need to replace 4 instances of `...trainees.asMap().entries.map` in summary columns (lines ~1680, ~1739, ~1811, ~1866) with `...traineeRows.asMap().entries.map`.

### Desktop Table Body  
**Line**: ~2040
Replace desktop table trainee name and values to use `traineeRows`:

```dart
                  ...traineeRows.asMap().entries.map((entry) {
                    final traineeIndex = entry.key;
                    final row = entry.value;
                    return Row(
```

---

## Testing Checklist

### Draft Save Test
1. Open Range Short/Long or Surprise Drills
2. Enter trainee names and values
3. Wait 600ms - should see "✅ שמירה אוטומטית" snackbar
4. Check console logs:
   - `DRAFT_SAVE: traineeRows.length=X`
   - `DRAFT_SAVE: row[0]: name="..." values={...}`
   - `DRAFT_SAVE: Verified trainees.length=X`

### Draft Load Test
1. Navigate away from form
2. Return to form (via temp feedbacks list)
3. Check console logs:
   - `DRAFT_LOAD: traineeRows.length=X`
   - `DRAFT_LOAD: row[0]: name="..." values={...}`
4. Verify ALL data restored (names + values)

### Cross-Platform Test
- Test on web AND mobile
- Verify same behavior (no platform-specific caching)
- Check debug logs show same data on both

### Autosave Test
1. Type in name field → wait 600ms → check logs
2. Type in value field → wait 600ms → check logs  
3. Change attendees count → check logs
4. Remove station → check logs

---

## Debug Log Format

### Save Logs
```
========== ✅ DRAFT_SAVE START ==========
DRAFT_SAVE: mode=surprise rangeType=הפתעה
DRAFT_SAVE: draftId={uid}_surprise_drill_הפתעה
DRAFT_SAVE: Serializing 5 trainee rows...
DRAFT_SAVE:   row[0]: name="חניך 1" values={0: 8, 1: 9, 2: 7}
DRAFT_SAVE: payload.trainees.length=5
DRAFT_SAVE: Write complete
DRAFT_SAVE: Verified trainees.length=5
========== ✅ DRAFT_SAVE END ==========
```

### Load Logs
```
========== ✅ DRAFT_LOAD START ==========
DRAFT_LOAD: id={draftId}
DRAFT_LOAD: rawTrainees.length=5
DRAFT_LOAD:   row[0]: name="חניך 1" values={0: 8, 1: 9, 2: 7}
DRAFT_LOAD: Loaded 5 trainee rows
DRAFT_LOAD: traineeRows.length=5
========== ✅ DRAFT_LOAD END (SUCCESS) ==========
```

---

## Key Principles

1. **Single Source of Truth**: `traineeRows` is THE model. Controllers sync TO it, not FROM it.
2. **Atomic Operations**: Save/load ENTIRE document. No partial saves.
3. **Deterministic IDs**: Same draftId = update existing doc. No duplicates.
4. **Read-back Verification**: Always verify writes succeeded.
5. **Loud Failures**: Debug logs must show WHAT failed and WHERE.
6. **No Default Rows After Load**: Only create rows from Firestore data.

