# Long Range Division Bug - Debug Guide

## Problem
Long range score cells are being transformed:
- Type 75 → displays as 7
- Type 100 → displays as 10

Evidence suggests values are being divided by 10 somewhere in the flow.

## Debug Logging Added

### 1. **TextField Build** (lines ~3765-3783)
Shows what value is retrieved from the model and passed to the controller:
```
🔍 LONG RANGE DEBUG: Building TextField
   traineeIdx=0, stationIndex=0
   currentValue from row.getValue(0)=75
   row.values[0]=75
   controllerKey=trainee_0_station_0
   Will pass to controller: initialValue="75"
   📱 Controller.text after _getController="75"
```

### 2. **Controller Creation/Reuse** (lines ~318-327)
Shows when controller is created vs reused:
```
🆕 CONTROLLER CREATED: key=trainee_0_station_0, initialValue="75"
```
OR
```
♻️ CONTROLLER REUSED: key=trainee_0_station_0, currentText="75", wouldBeInitialValue="75"
```

### 3. **User Input** (lines ~3835-3850)
Shows the raw text typed and the parsed integer:
```
📝 LONG RANGE onChanged: rawInput="75"
   parsedScore=75
```

### 4. **Value Storage** (line ~4847)
Shows what value is actually stored in the model:
```
💾 setValue: stationIndex=0, value=75, stored=75
```

### 5. **Post-Storage Verification** (lines ~3945-3950)
Verifies the value immediately after storage:
```
   ✅ STORED: row.values[0]=75
   Verification: row.getValue(0)=75
```

---

## Test Procedure

### Step 1: Open Chrome DevTools Console
1. Press F12 to open DevTools
2. Go to "Console" tab
3. Clear the console (🚫 icon)

### Step 2: Navigate to Long Range Feedback
1. Go to "תרגילים" (Exercises)
2. Click "מטווחים" (Ranges)
3. Select "טווח רחוק" (Long Range)
4. Add at least one trainee
5. Add at least one stage

### Step 3: Type "75" in First Score Cell
**Watch the console output carefully:**

**Expected Good Flow:**
```
🔍 LONG RANGE DEBUG: Building TextField
   traineeIdx=0, stationIndex=0
   currentValue from row.getValue(0)=0
   row.values[0]=0
   controllerKey=trainee_0_station_0
   Will pass to controller: initialValue=""
   📱 Controller.text after _getController=""

🆕 CONTROLLER CREATED: key=trainee_0_station_0, initialValue=""

📝 LONG RANGE onChanged: rawInput="7"
   parsedScore=7
💾 setValue: stationIndex=0, value=7, stored=7
   ✅ STORED: row.values[0]=7
   Verification: row.getValue(0)=7

📝 LONG RANGE onChanged: rawInput="75"
   parsedScore=75
💾 setValue: stationIndex=0, value=75, stored=75
   ✅ STORED: row.values[0]=75
   Verification: row.getValue(0)=75
```

**Bad Flow (if bug exists):**
If you see the stored value change from 75 to 7 AFTER the onChanged handler, that's the bug location.

### Step 4: Observe TextField Display
After typing "75":
- **PASS**: Cell shows "75"
- **FAIL**: Cell shows "7"

If it shows "7", check the console to see:
1. Did onChanged fire again with "7"?
2. Did setValue get called with 7?
3. Did the controller text change?

### Step 5: Trigger Rebuild
Without changing focus:
1. Change the "מספר חניכים" (attendees count) field
2. Watch console for rebuild logs

**Expected:**
```
🔍 LONG RANGE DEBUG: Building TextField
   traineeIdx=0, stationIndex=0
   currentValue from row.getValue(0)=75  ← Should still be 75
   row.values[0]=75
   controllerKey=trainee_0_station_0
   Will pass to controller: initialValue="75"
   📱 Controller.text after _getController="75"  ← Should still be "75"

♻️ CONTROLLER REUSED: key=trainee_0_station_0, currentText="75", wouldBeInitialValue="75"
```

**If Bug:**
If `currentValue` shows 7 instead of 75, the bug is in `row.getValue()` or the storage.
If `controller.text` shows "7", the bug is in controller management.

---

## Diagnosis Matrix

| Symptom | Location | Possible Cause |
|---------|----------|----------------|
| onChanged shows "75" but cell shows "7" | Controller text | _getController modifying text |
| setValue called with 75 but row.values shows 7 | TraineeRowModel.setValue | Division in setValue method |
| row.getValue returns 7 when 75 was stored | TraineeRowModel.getValue | Division in getValue method |
| Stored as 75, rebuild shows 7 | TextField build | currentValue calculation wrong |
| Controller created with "7" when value is 75 | currentValue.toString() | currentValue already divided |

---

## Known Good Code (Verification)

### TraineeRowModel.setValue (line ~4842)
```dart
void setValue(int stationIndex, int value) {
  if (value == 0) {
    values.remove(stationIndex);
  } else {
    values[stationIndex] = value;  // ✅ Stores raw value
  }
  debugPrint('💾 setValue: stationIndex=$stationIndex, value=$value, stored=${values[stationIndex]}');
}
```
**Verification**: `stored` should equal `value` (no division)

### TraineeRowModel.getValue (line ~4841)
```dart
int getValue(int stationIndex) => values[stationIndex] ?? 0;
```
**Verification**: Returns raw value from map (no division)

### onChanged Handler (lines ~3845-3935)
```dart
final score = int.tryParse(v) ?? 0;  // Parse raw text
row.setValue(stationIndex, score);   // Store raw score
```
**Verification**: No division between parse and setValue

---

## If Bug Found

### Scenario A: Division in Controller Management
**Symptom**: Controller.text shows "7" when initialValue is "75"

**Fix Location**: `_getController` method (lines 314-328)

**Check for**:
- Text modification during creation
- Text modification during reuse
- Implicit toString() conversion that divides

### Scenario B: Division in Model
**Symptom**: setValue called with 75 but values[0] is 7

**Fix Location**: `TraineeRowModel.setValue` (line ~4842)

**Check for**:
- Division before assignment
- Type conversion that divides
- Stage.maxPoints / 10 calculation

### Scenario C: Division in Value Retrieval
**Symptom**: Stored as 75, getValue returns 7

**Fix Location**: `TraineeRowModel.getValue` (line ~4841)

**Check for**:
- Division in return statement
- Getter that computes value/10
- Stage normalization

### Scenario D: Division in Display
**Symptom**: Stored as 75, but currentValue passed to controller is 7

**Fix Location**: `currentValue = row.getValue(stationIndex)` (line ~3527)

**Check for**:
- Additional calculation before passing to controller
- Stage-based normalization
- Bullet conversion logic

---

## Additional Checks

### Check Stage Configuration
Long range stages should have:
- `bulletsCount` = actual bullets (e.g., 10)
- `maxPoints` = 100 (or actual max points)

**If maxPoints is 10 instead of 100**, that's the bug!

Verify in console:
```
Stage[0]: "עמידה 50" → bulletsCount=10, maxPoints=100  ← maxPoints should be 100, not 10
```

### Check Save/Load Logic
If values are correct initially but wrong after save/reload:

**Check toFirestore** (line ~4871):
```dart
valuesMap['station_$stationIdx'] = val;  // Should store raw val
```

**Check fromFirestore** (line ~4907):
```dart
final value = (val as num?)?.toInt() ?? 0;  // Should convert without division
```

---

## Next Steps

1. **Run the test** with Chrome DevTools Console open
2. **Type "75"** and watch the console logs
3. **Identify which log shows the transformation** (75 → 7)
4. **Report the exact line** where the value changes
5. **Fix that specific location**

The debug logs will pinpoint the EXACT location of the division bug.
