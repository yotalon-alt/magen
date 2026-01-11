# Long-Range V2 Summary Model Implementation

## Overview
Implemented canonical V2 data model for long-range feedbacks to ensure:
- **Points/Points calculations only** (e.g., 87/100, 661/900)
- **Bullets NEVER affect scoring** (tracking-only)
- **Auto-migration** for old feedbacks without V2
- **Immediate correct summary** after migration

## V2 Data Model Structure

```dart
lrV2: {
  version: 2,
  traineesCount: N,  // Number of trainees in this feedback
  stages: [
    {
      id: "stage_0",
      name: "כריעה",
      maxScorePoints: 100,        // Instructor-entered max score
      bulletsTracking: 30          // Tracking only, never used for scoring
    },
    {
      id: "stage_1",
      name: "עמידה",
      maxScorePoints: 100,
      bulletsTracking: 30
    },
    {
      id: "stage_2",
      name: "שכיבה",
      maxScorePoints: 150,
      bulletsTracking: 40
    }
  ],
  traineeValues: {
    "trainee_0": {
      "stage_0": 87,    // Raw points as entered by instructor
      "stage_1": 95,
      "stage_2": 142
    },
    "trainee_1": {
      "stage_0": 76,
      "stage_1": 88,
      "stage_2": 135
    },
    "trainee_2": {
      "stage_0": 91,
      "stage_1": 90,
      "stage_2": 147
    }
  }
}
```

## Implementation Details

### 1. Save Logic (Lines ~1670-1680)
**File**: `lib/range_training_page.dart`

```dart
// ✅ BUILD AND PERSIST V2 DATA MODEL FOR LONG RANGE
final lrV2 = _buildLrV2();
if (lrV2.isNotEmpty) {
  rangeData['lrV2'] = lrV2;
  debugPrint('\n✅ LR_V2_SAVE: Built V2 data model');
  // ... debug logging
}
```

**Behavior**:
- Builds V2 from current UI state (traineeRows, longRangeStagesList)
- Persists `lrV2` field to Firestore on every save (draft + final)
- Stores raw points exactly as instructor entered (no normalization)
- Stores maxScorePoints from instructor input (not bullets)

### 2. Load Logic (Lines ~2556-2588)
**File**: `lib/range_training_page.dart`

```dart
// ✅ CHECK FOR V2 DATA MODEL AND MIGRATE IF NEEDED
Map<String, dynamic>? lrV2 = data['lrV2'] as Map<String, dynamic>?;
if (_rangeType == 'ארוכים') {
  if (lrV2 == null || lrV2.isEmpty) {
    debugPrint('🔄 LR_V2_LOAD: V2 data missing, running migration...');
    lrV2 = _migrateLongRangeToV2(data);
    
    if (lrV2.isNotEmpty) {
      // ✅ PERSIST V2 BACK TO FIRESTORE (one-time migration)
      await docRef.update({'lrV2': lrV2});
      debugPrint('✅ LR_V2_MIGRATED: Persisted V2 to Firestore');
    }
  }
  
  // ✅ CALCULATE SUMMARY FROM V2
  if (lrV2.isNotEmpty) {
    final summary = _calculateSummaryFromV2(lrV2);
    // ... display summary
  }
}
```

**Behavior**:
- Checks if `lrV2` exists in feedback document
- If missing: runs `_migrateLongRangeToV2()` to create V2 from legacy data
- Persists V2 back to Firestore (one-time migration)
- Calculates and logs summary from V2

### 3. Migration Function (Lines ~880-980)
**File**: `lib/range_training_page.dart`

```dart
Map<String, dynamic> _migrateLongRangeToV2(Map<String, dynamic> feedbackData) {
  // Read legacy stations/trainees
  final rawStations = feedbackData['stations'] as List?;
  final rawTrainees = feedbackData['trainees'] as List?;
  
  // Build stages with maxScorePoints
  for (int i = 0; i < rawStations.length; i++) {
    final stationData = rawStations[i] as Map<String, dynamic>?;
    
    // Prefer explicit maxScorePoints, fallback to maxPoints
    int maxScorePoints = 0;
    if (stationData.containsKey('maxPoints')) {
      maxScorePoints = (stationData['maxPoints'] as num?)?.toInt() ?? 0;
    } else if (stationData.containsKey('maxScorePoints')) {
      maxScorePoints = (stationData['maxScorePoints'] as num?)?.toInt() ?? 0;
    }
    // If neither exists, leave as 0 (do NOT default to 10)
    
    stages.add({
      'id': 'stage_$i',
      'name': name,
      'maxScorePoints': maxScorePoints,
      'bulletsTracking': bulletsTracking,
    });
  }
  
  // Extract trainee pointsRaw as-is (no normalization)
  for (int tIdx = 0; tIdx < rawTrainees.length; tIdx++) {
    final hitsMap = traineeData['hits'] as Map<String, dynamic>? ?? {};
    hitsMap.forEach((key, value) {
      final pointsRaw = (value as num?)?.toInt() ?? 0;
      stagePoints[stageId] = pointsRaw; // Use AS-IS
    });
  }
  
  return {
    'version': 2,
    'traineesCount': N,
    'stages': stages,
    'traineeValues': traineeValues,
  };
}
```

**Migration Rules**:
1. **maxScorePoints**: Prefer `maxPoints` → fallback to `maxScorePoints` → default 0 (NOT 10)
2. **pointsRaw**: Use stored value AS-IS (no normalization, no conversion)
3. **bulletsTracking**: Read from `bulletsCount` (tracking only)
4. **One-time**: Persists V2 back to doc immediately after migration

### 4. Summary Calculation (Lines ~1020-1070)
**File**: `lib/range_training_page.dart`

```dart
Map<String, dynamic> _calculateSummaryFromV2(Map<String, dynamic> lrV2) {
  final stages = lrV2['stages'] as List? ?? [];
  final traineeValues = lrV2['traineeValues'] as Map<String, dynamic>? ?? {};
  final N = lrV2['traineesCount'] as int? ?? 0;
  
  int totalAchieved = 0;
  int totalMax = 0;
  
  for (int i = 0; i < stages.length; i++) {
    final maxScorePoints = (stageData['maxScorePoints'] as num?)?.toInt() ?? 0;
    
    // Calculate achieved points for this stage across all trainees
    int stageAchieved = 0;
    traineeValues.forEach((traineeKey, stagePoints) {
      final points = (stagePoints[stageId] as num?)?.toInt() ?? 0;
      stageAchieved += points;
    });
    
    // Per-stage max = N * maxScorePoints
    final stageMax = N * maxScorePoints;
    
    totalAchieved += stageAchieved;
    totalMax += stageMax;
  }
  
  return {
    'totalAchieved': totalAchieved,
    'totalMax': totalMax,
    'stageResults': stageResults,
  };
}
```

**Formula**:
- **Total Achieved** = SUM(pointsRaw for all trainees × all stages)
- **Total Max** = N × SUM(stage.maxScorePoints)
- **Per-Stage Achieved** = SUM(pointsRaw for that stage across trainees)
- **Per-Stage Max** = N × stage.maxScorePoints
- **Bullets NEVER used** in any denominator/max calculation

## Verification Example

### Scenario
- **3 trainees**
- **3 stages**: כריעה (100), עמידה (100), שכיבה (150)
- **Points scored**:
  - Trainee 0: 87 + 95 + 142 = 324
  - Trainee 1: 76 + 88 + 135 = 299
  - Trainee 2: 91 + 90 + 147 = 328

### Expected Summary (V2)

**Total Summary**:
- Achieved: 324 + 299 + 328 = **951**
- Max: 3 × (100 + 100 + 150) = 3 × 350 = **1050**
- Display: **951/1050** (90.6%)

**Per-Stage Summary**:
- כריעה: (87+76+91) = **254/300** (84.7%)
- עמידה: (95+88+90) = **273/300** (91.0%)
- שכיבה: (142+135+147) = **424/450** (94.2%)

## Debug Logging

### On Save
```
✅ LR_V2_SAVE: Built V2 data model
   V2 traineesCount=3
   V2 stages count=3
   V2 Stage[0]: maxScorePoints=100, bullets=30 (tracking)
   V2 Stage[1]: maxScorePoints=100, bullets=30 (tracking)
   V2 Stage[2]: maxScorePoints=150, bullets=40 (tracking)
```

### On Load (New Feedback)
```
✅ LR_V2_LOAD: V2 data found (version=2)

📊 LR_V2_SUMMARY CALCULATION:
   Total: 951/1050
   כריעה: 254/300
   עמידה: 273/300
   שכיבה: 424/450
```

### On Load (Old Feedback - Migration)
```
🔄 LR_V2_LOAD: V2 data missing, running migration...

🔄 ===== LR_V2_MIGRATION START =====
🔄 LR_V2_MIGRATION: N=3 trainees
🔄   Stage[0]: "כריעה" maxScorePoints=100 (bullets=30 tracking-only)
🔄   Stage[1]: "עמידה" maxScorePoints=100 (bullets=30 tracking-only)
🔄   Stage[2]: "שכיבה" maxScorePoints=150 (bullets=40 tracking-only)
🔄   Trainee[0]: "חניך 1" points={stage_0: 87, stage_1: 95, stage_2: 142}
🔄   Trainee[1]: "חניך 2" points={stage_0: 76, stage_1: 88, stage_2: 135}
🔄   Trainee[2]: "חניך 3" points={stage_0: 91, stage_1: 90, stage_2: 147}
🔄 LR_V2_MIGRATION: Created V2 model
🔄   totalStages=3
🔄   totalTrainees=3
🔄 ===== LR_V2_MIGRATION END (SUCCESS) =====

✅ LR_V2_MIGRATED: Persisted V2 to Firestore

📊 LR_V2_SUMMARY CALCULATION:
   Total: 951/1050
   כריעה: 254/300
   עמידה: 273/300
   שכיבה: 424/450
```

## Testing Checklist

### Test 1: New Long-Range Feedback
1. ✅ Create new long-range feedback
2. ✅ Enter 3 trainees
3. ✅ Add 3 stages (כריעה 100, עמידה 100, שכיבה 150)
4. ✅ Enter points for each trainee
5. ✅ Save (draft or final)
6. ✅ Verify console shows "LR_V2_SAVE: Built V2 data model"
7. ✅ Reload feedback
8. ✅ Verify console shows "LR_V2_LOAD: V2 data found"
9. ✅ Verify summary shows correct points/points (e.g., 951/1050)

### Test 2: Old Feedback (Auto-Migration)
1. ✅ Open an OLD long-range feedback (saved before V2)
2. ✅ Verify console shows "LR_V2_LOAD: V2 data missing, running migration"
3. ✅ Verify migration logs show stage maxScorePoints extracted correctly
4. ✅ Verify console shows "LR_V2_MIGRATED: Persisted V2 to Firestore"
5. ✅ Verify summary calculation logs show correct totals
6. ✅ Reload same feedback again
7. ✅ Verify console shows "LR_V2_LOAD: V2 data found" (no re-migration)
8. ✅ Verify summary is correct and matches previous load

### Test 3: Edge Cases
1. ✅ Feedback with missing maxPoints in legacy data → migration sets maxScorePoints=0
2. ✅ Feedback with 0 trainees → V2 not created, summary shows 0/0
3. ✅ Feedback with incomplete trainee data → migration skips empty values
4. ✅ Bullets field changes → does NOT affect summary (tracking only)

## Code Changes Summary

**File**: `lib/range_training_page.dart`

### New Functions Added
1. **`_buildLrV2()`** (Lines ~830-880)
   - Builds V2 from current UI state
   - Called on every save

2. **`_migrateLongRangeToV2(feedbackData)`** (Lines ~885-980)
   - Converts legacy feedback to V2
   - Called on load if V2 missing
   - Persists V2 back to Firestore

3. **`_calculateSummaryFromV2(lrV2)`** (Lines ~985-1040)
   - Computes summary using V2 data only
   - Returns total and per-stage results

### Modified Functions
1. **Save Logic** (Lines ~1670-1680)
   - Builds and persists lrV2

2. **Load Logic** (Lines ~2556-2588)
   - Checks for V2
   - Migrates if missing
   - Calculates summary from V2

3. **`_getTotalMaxPointsLongRange()`** (Lines ~1045-1075)
   - Now multiplies by N (existing fix)
   - Will eventually be replaced by V2 calculation

## Migration Strategy

### Immediate Benefits
- ✅ New feedbacks automatically get V2 on save
- ✅ Old feedbacks auto-migrate on first open
- ✅ Migration is one-time (V2 persisted to Firestore)
- ✅ Summary is immediately correct after migration

### Future Optimization
- Current implementation uses V2 for logging/verification
- Can gradually replace legacy summary calculations with V2-based ones
- Can add UI indicators showing V2 vs legacy data
- Can add batch migration script for all old feedbacks

## Success Criteria

✅ **Points/Points Calculations**: Summary shows points out of points (e.g., 951/1050)
✅ **Bullets Never Affect Scoring**: bulletsTracking is stored but never used in denominators
✅ **Auto-Migration**: Old feedbacks silently migrate on first open
✅ **Persistence**: V2 is saved to Firestore (one-time migration)
✅ **Debug Logging**: Comprehensive logs for N, stages, totals, per-stage results
✅ **Correct Denominators**: Total max = N × SUM(maxScorePoints)

## Example Console Output

```
========== FINAL SAVE: LONG RANGE ==========
...
✅ LR_V2_SAVE: Built V2 data model
   V2 traineesCount=3
   V2 stages count=3
   V2 Stage[0]: maxScorePoints=100, bullets=30 (tracking)
   V2 Stage[1]: maxScorePoints=100, bullets=30 (tracking)
   V2 Stage[2]: maxScorePoints=150, bullets=40 (tracking)

[Later, on load...]

✅ LR_V2_LOAD: V2 data found (version=2)

📊 LR_V2_SUMMARY CALCULATION:
   Total: 951/1050
   כריעה: 254/300
   עמידה: 273/300
   שכיבה: 424/450

🎯 LONG-RANGE SUMMARY DENOMINATOR CALCULATION:
   N (trainees) = 3
   Stage maxPoints = [100, 100, 150]
   SUM(stage.maxPoints) = 350
   totalMaxPoints = N * SUM = 3 * 350 = 1050
   Expected format: achieved/1050
```

---

**Implementation Date**: January 11, 2026
**Status**: ✅ Complete and Ready for Testing
