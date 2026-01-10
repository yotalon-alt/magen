# Long Range Single Source of Truth Fix

## Problem Statement
Long Range feedback had TWO different values for max points:
1. **Header display** (line 2904): `station.bulletsCount * 10` (inline calculation)
2. **Model field** (line 2482): `stage.maxPoints` (user-entered value)

These could diverge, causing inconsistency between what the header shows and what validations/totals use.

## Root Cause
The UI had a "נקודות מקסימום" input field where users entered points directly, but:
- The `bulletsCount` field was never set (stayed at 0)
- The header tried to display `bulletsCount * 10`, which was always 0
- The relationship between bullets and points (bullets × 10 = points) was broken

## Solution
**Established `bulletsCount` as the single source of truth with computed `maxPoints` getter.**

### Changes Made

#### 1. LongRangeStageModel (lines 38-85)
**Before:**
```dart
class LongRangeStageModel {
  String name;
  int maxPoints;        // User-entered field
  int achievedPoints;
  bool isManual;
  int bulletsCount;     // Never used
  
  LongRangeStageModel({
    required this.name,
    this.maxPoints = 0,
    ...
  });
}
```

**After:**
```dart
class LongRangeStageModel {
  String name;
  int get maxPoints => bulletsCount * 10;  // Computed getter
  int achievedPoints;
  bool isManual;
  int bulletsCount;  // Source of truth
  
  LongRangeStageModel({
    required this.name,
    this.bulletsCount = 0,  // No maxPoints parameter
    ...
  });
}
```

**Key improvements:**
- `maxPoints` is now a **computed getter**, not a stored field
- Formula: `maxPoints = bulletsCount × 10` (always synchronized)
- Constructor simplified (no maxPoints parameter)
- Backward compatibility in `fromJson`: derives `bulletsCount` from old `maxPoints` data

#### 2. UI Input Field (lines 2455-2484)
**Before:**
```dart
TextField(
  controller: TextEditingController(
    text: stage.maxPoints > 0 ? stage.maxPoints.toString() : '',
  ),
  decoration: const InputDecoration(
    labelText: 'נקודות מקסימום',  // Max points
    hintText: 'הזן מספר נקודות',
  ),
  onChanged: (value) {
    setState(() {
      stage.maxPoints = int.tryParse(value) ?? 0;  // Direct assignment
    });
  },
),
```

**After:**
```dart
TextField(
  controller: TextEditingController(
    text: stage.bulletsCount > 0 ? stage.bulletsCount.toString() : '',
  ),
  decoration: const InputDecoration(
    labelText: 'מספר כדורים',  // Number of bullets
    hintText: 'הזן מספר כדורים (נקודות = כדורים × 10)',
  ),
  onChanged: (value) {
    setState(() {
      stage.bulletsCount = int.tryParse(value) ?? 0;
      // maxPoints is automatically computed from bulletsCount
    });
  },
),
```

**Key improvements:**
- Users now enter **bullets** (physical concept), not points (abstract)
- Hint text explains the relationship: `points = bullets × 10`
- `maxPoints` updates automatically via the computed getter

## Verification Points

### ✅ Single Source of Truth
- **Input**: `stage.bulletsCount` (user enters bullets count)
- **Display**: `stage.maxPoints` (computed as `bulletsCount * 10`)
- **Validation** (lines 3305, 3531): Uses `stage.maxPoints` (now computed)
- **Totals** (line 812): Uses `stage.maxPoints` (now computed)
- **Headers** (lines 2904, 3857): Display `station.bulletsCount * 10` (same formula as getter)

### ✅ Consistency Guarantees
1. Header shows: `bulletsCount * 10`
2. Input validates against: `maxPoints = bulletsCount * 10`
3. Total calculation sums: `maxPoints = bulletsCount * 10`
4. **All three use the same source (bulletsCount) and formula**

### ✅ Backward Compatibility
`fromJson` handles old data:
```dart
final resolvedBulletsCount = bulletsCount > 0
    ? bulletsCount  // Use existing bullets count
    : (directMaxPoints != null && directMaxPoints > 0
        ? (directMaxPoints / 10).round()  // Derive from old maxPoints
        : 0);
```

## Testing Checklist

### Unit Tests
- [ ] Create Long Range stage with `bulletsCount = 5`
- [ ] Verify `stage.maxPoints == 50` (computed getter)
- [ ] Change `bulletsCount` to 10
- [ ] Verify `stage.maxPoints == 100` (auto-updated)

### UI Tests
1. **Create new Long Range feedback**
   - [ ] Add stage "רמות"
   - [ ] Enter "20" in "מספר כדורים" field
   - [ ] Verify header shows "200" below stage name
   - [ ] Verify table header shows "200"

2. **Input validation**
   - [ ] Try entering points > maxPoints in table cell
   - [ ] Verify error message shows correct maxPoints value
   - [ ] Change bullets count
   - [ ] Verify maxPoints updates in error message

3. **Total calculation**
   - [ ] Add trainee with points in stage
   - [ ] Verify percentage = (points / maxPoints) * 100
   - [ ] Change bullets count
   - [ ] Verify percentage recalculates correctly

4. **Backward compatibility**
   - [ ] Load old feedback with `maxPoints` but no `bulletsCount`
   - [ ] Verify `bulletsCount` derived correctly (maxPoints / 10)
   - [ ] Verify display and calculations work

### Edge Cases
- [ ] `bulletsCount = 0` → `maxPoints = 0` (no division by zero)
- [ ] `bulletsCount = 1` → `maxPoints = 10`
- [ ] `bulletsCount = 999` → `maxPoints = 9990`

## Files Modified
- `lib/range_training_page.dart`:
  - Lines 38-85: `LongRangeStageModel` class
  - Lines 2455-2484: UI input field (bullets instead of max points)

## Related Files (No Changes Needed)
- `lib/feedback_export_service.dart`: Uses `stage.maxPoints` (still works with getter)
- Table headers (lines 2904, 3857): Already calculate `bulletsCount * 10`
- Validation (lines 3305, 3531): Already use `stage.maxPoints`
- Totals (line 812): Already sum `stage.maxPoints`

## Benefits
1. **Consistency**: Header, validation, and totals always show the same maxPoints
2. **Clarity**: Users think in bullets (physical), not abstract points
3. **Maintainability**: Single calculation formula (`× 10`) in one place
4. **Safety**: Impossible for maxPoints to be out of sync with bulletsCount
5. **Backward compatibility**: Old data migrates seamlessly

## Migration Notes
Existing feedbacks in Firestore with:
- `maxPoints` but no `bulletsCount`: Will derive `bulletsCount = maxPoints / 10`
- Both fields: Will use `bulletsCount` as source of truth
- Neither field: Defaults to `bulletsCount = 0, maxPoints = 0`

No manual data migration needed!
