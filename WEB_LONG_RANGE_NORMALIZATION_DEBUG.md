# 🔍 WEB Long Range Normalization Bug - Debug Logging Guide

## ❌ REPORTED BUG
**Platform**: WEB ONLY (mobile is correct)  
**Affected**: Long Range (טווח רחוק) feedback  
**Symptom**: Points entered (75, 100) become normalized to (7, 10) after save/exit/reopen  
**Timing**: Values are correct WHILE EDITING, but become wrong AFTER save/reload cycle

---

## ✅ DEBUG LOGS ADDED

I've added **comprehensive WEB-specific debug logs** at **EVERY critical checkpoint** in the data flow to identify WHERE the /10 normalization happens:

### 📍 Checkpoint 1: Firestore Raw Data (fromFirestore method)
**Lines 5199-5240**  
**Logs**:
- `🌐 WEB_FROMFIRESTORE: trainee="..." RAW valuesRaw={...}` - Shows RAW Firestore data BEFORE parsing
- `🌐 WEB_FROMFIRESTORE_PARSE: station_0: raw=75 (type=int) → parsed=75` - Shows each value parsing step
- `🌐 WEB_FROMFIRESTORE_RESULT: trainee="..." FINAL values={0: 75}` - Shows FINAL values after parsing

**Purpose**: Verify if Firestore is STORING correct values (75) or normalized values (7)

---

### 📍 Checkpoint 2: After fromFirestore Call (load function)
**Lines 2160-2180**  
**Existing logs** (already in place):
- `🌐 WEB LR_RAW_AFTER_LOAD: trainee="..." values={0: 75}` - Shows values right after fromFirestore()
- `╔═══ LONG RANGE POINTS LOAD VERIFICATION ═══╗` - Summary box

**Purpose**: Verify if values remain correct immediately after deserialization

---

### 📍 Checkpoint 3: Before setState (entering UI state)
**Lines 2220-2240** ✅ **NEW**  
**Logs**:
```
╔═══ WEB LR: VALUES ENTERING setState ═══╗
║ Row[0]: "John"
║   values map: {0: 75, 1: 100}
║   ⚠️ station[0] = 75 ← THIS WILL ENTER STATE
║   ✅ Looks correct (not divided)
║   ⚠️ station[1] = 100 ← THIS WILL ENTER STATE
║   ✅ Looks correct (not divided)
╚═══════════════════════════════════════╝
```

**Purpose**: Verify if values entering `traineeRows` state are correct BEFORE they become part of the widget tree

---

### 📍 Checkpoint 4: Build Method (before controller creation)
**Lines 3730-3755** ✅ **NEW**  
**Logs**:
```
🌐 WEB_BUILD: trainee="John" station=0 currentValue=75
   Source: row.values[0]=75
   Will create controller with initialValue="75"
   ✅ currentValue=75 looks correct (not divided)
```

**Purpose**: Verify if `row.getValue(stationIndex)` returns correct value from state during build

---

### 📍 Checkpoint 5: Controller Creation (_getController)
**Lines 315-355** (existing)  
**Logs**:
- `🌐 LR_WEB_CONTROLLER_CREATE: RAW value="75" (must be points, not normalized)`

**Purpose**: Verify if controller is initialized with correct text

---

### 📍 Checkpoint 6: Controller Text Sync (build method)
**Lines 4047-4070** (existing)  
**Logs**:
- `🌐 LR_WEB_SYNC: Correcting controller.text from "7" to "75" (raw points)`

**Purpose**: Verify if WEB sync fix catches any discrepancies

---

## 🧪 TEST PROCEDURE

### Step 1: Clear Browser Cache & Reload
1. Open Chrome DevTools (F12)
2. Right-click Reload button → **Empty Cache and Hard Reload**
3. This ensures you're running the NEW debug-instrumented code

### Step 2: Create New Long Range Feedback
1. Navigate to: תרגילים → מטווחים → טווח רחוק
2. Fill in:
   - יישוב: Any settlement
   - Add 1-2 trainees
   - Add 2 stages (default: רמות, שלשות)
   - Enter point values: **75** in station 0, **100** in station 1

### Step 3: Save and Exit
1. Click "שמור וסיים" button
2. Wait for save confirmation
3. Return to feedbacks list

### Step 4: Reopen the Feedback
1. Find the feedback you just created
2. Click to reopen it in EDIT mode
3. **WATCH THE BROWSER CONSOLE**

### Step 5: Analyze Debug Output
Look for the checkpoint logs in this order:

```
🌐 WEB_FROMFIRESTORE: ... RAW valuesRaw={station_0: ?, station_1: ?}
🌐 WEB_FROMFIRESTORE_PARSE: station_0: raw=? → parsed=?
🌐 WEB_FROMFIRESTORE_RESULT: ... FINAL values={0: ?, 1: ?}
🌐 WEB LR_RAW_AFTER_LOAD: ... values={0: ?, 1: ?}
╔═══ WEB LR: VALUES ENTERING setState ═══╗
║   station[0] = ? ← THIS WILL ENTER STATE
║   station[1] = ? ← THIS WILL ENTER STATE
╚═══════════════════════════════════════╝
🌐 WEB_BUILD: ... currentValue=?
   Source: row.values[0]=?
```

---

## 🎯 EXPECTED RESULTS (If bug is in Firestore)

If Firestore is storing **normalized values** (7, 10):

```
🌐 WEB_FROMFIRESTORE: RAW valuesRaw={station_0: 7, station_1: 10}  ← ❌ BUG HERE
🌐 WEB_FROMFIRESTORE_PARSE: station_0: raw=7 → parsed=7
🌐 WEB_FROMFIRESTORE_RESULT: FINAL values={0: 7, 1: 10}
...
║   station[0] = 7 ← THIS WILL ENTER STATE  ← CONFIRMED: Wrong values from Firestore
```

**Diagnosis**: Bug is in the SAVE path (values are normalized BEFORE Firestore write)

---

## 🎯 EXPECTED RESULTS (If bug is in state/model)

If Firestore stores **correct values** (75, 100) but they become wrong later:

```
🌐 WEB_FROMFIRESTORE: RAW valuesRaw={station_0: 75, station_1: 100}  ← ✅ Firestore OK
🌐 WEB_FROMFIRESTORE_PARSE: station_0: raw=75 → parsed=75
🌐 WEB_FROMFIRESTORE_RESULT: FINAL values={0: 75, 1: 100}  ← ✅ Parsing OK
🌐 WEB LR_RAW_AFTER_LOAD: values={0: 75, 1: 100}  ← ✅ Load OK
╔═══ WEB LR: VALUES ENTERING setState ═══╗
║   station[0] = 7 ← THIS WILL ENTER STATE  ← ❌ BUG HERE (became 7 somehow)
```

**Diagnosis**: Bug is between fromFirestore and setState (transformation in loadedRows array)

---

## 🎯 EXPECTED RESULTS (If bug is in build/controller)

If state has **correct values** but build shows wrong:

```
╔═══ WEB LR: VALUES ENTERING setState ═══╗
║   station[0] = 75 ← THIS WILL ENTER STATE  ← ✅ State OK
╚═══════════════════════════════════════╝
🌐 WEB_BUILD: currentValue=7  ← ❌ BUG HERE (getValue returns wrong value)
   Source: row.values[0]=7
```

**Diagnosis**: Bug is in TraineeRowModel.getValue() or values map corruption

---

## 📊 REPORT BACK TO ME

After running the test, please copy/paste:

1. **Full console output** from the WEB_ logs
2. **What values you typed** (e.g., 75 and 100)
3. **What values appeared in the UI** after reload (e.g., 7 and 10)
4. **Which checkpoint** showed the wrong values FIRST

This will pinpoint the EXACT location of the bug.

---

## 🔧 NEXT STEPS AFTER DIAGNOSIS

- **If bug is in SAVE**: Fix trainee serialization in _saveToFirestore()
- **If bug is in LOAD**: Fix fromFirestore() or TraineeRowModel
- **If bug is in STATE**: Fix setState or TraineeRowModel.values
- **If bug is in BUILD**: Fix row.getValue() or controller logic

---

## ⚠️ CRITICAL NOTES

1. **Mobile vs Web**: User confirmed mobile is CORRECT, so the bug is WEB-SPECIFIC
2. **Timing**: Values are correct during EDITING, wrong after RELOAD → Bug is in save/load cycle
3. **Pattern**: 75→7, 100→10 → Consistent /10 division somewhere
4. **Existing Logs**: Save path already has extensive logging (lines 1172-1278) that should have caught this

---

## 🏁 SUMMARY

I've added **5 new WEB-specific debug checkpoints** to trace the EXACT point where 75 becomes 7.

The logs will show WHERE in the data flow the normalization happens, allowing us to apply the surgical fix in the right place.

**NO CODE CHANGES** to actual logic - only **DEBUG LOGS** to diagnose the issue.
