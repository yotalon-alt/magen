# Atomic Temporary Save Implementation
**Module**: Shooting Ranges & Surprise Drills  
**File**: `lib/range_training_page.dart`  
**Date**: 2025-01-XX  
**Scope**: ONLY affects temporary feedback saves for Shooting Ranges and Surprise Drills modules

---

## 🎯 Objective

**Problem**: Temporary saves were using autosave with debounced timer, causing data loss and missing trainee information in Firestore.

**Solution**: Implement atomic temporary save with:
- ✅ NO autosave - manual "Temporary Save" button ONLY
- ✅ Force UI commit before serialization
- ✅ Hard validation before write (throws blocking errors)
- ✅ Single write to Firestore
- ✅ Mandatory read-back verification
- ✅ UI rehydration from verified Firestore data
- ✅ Fail loudly with blocking error dialogs

---

## 🔧 Implementation Details

### 1. Removed ALL Autosave Mechanisms

**Before**:
```dart
Timer? _draftAutosaveTimer;
String _autosaveStatus = ''; // 'saving', 'saved', or empty
DateTime? _lastSaveTime;

void _scheduleDraftSave() {
  _draftAutosaveTimer?.cancel();
  _draftAutosaveTimer = Timer(const Duration(milliseconds: 900), () async {
    await _saveTemporarily();
  });
}

// Called from:
// - Every TextField onChange
// - dispose() method
// - attendees count change
```

**After**:
```dart
// ALL REMOVED:
// - Timer declaration
// - Autosave status variables
// - _scheduleDraftSave() function
// - All calls to _scheduleDraftSave()
// - Autosave on dispose
// - Autosave status UI indicator
```

### 2. Atomic Temporary Save Flow

**New `_saveTemporarily()` Function**:

```dart
Future<void> _saveTemporarily() async {
  // Step 1: Force UI commit
  FocusManager.instance.primaryFocus?.unfocus();
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Step 2: Serialize trainees from committed UI state
  final traineesPayload = trainees.map((t) => {
    'index': i,
    'name': t.name.trim(),
    'values': t.hits.map((k, v) => MapEntry('station_$k', v)),
  }).toList();
  
  // Step 3: HARD VALIDATION (throws on failure)
  if (traineesPayload.isEmpty) {
    await showDialog(...); // Blocking error dialog
    throw Exception('TEMP_SAVE_VALIDATION_FAIL: trainees.length == 0');
  }
  
  final hasValidData = traineesPayload.any((t) => 
    t['name'].isNotEmpty && t['values'].isNotEmpty
  );
  if (!hasValidData) {
    await showDialog(...); // Blocking error dialog
    throw Exception('TEMP_SAVE_VALIDATION_FAIL: No valid trainee data');
  }
  
  // Step 4: Build Firestore payload
  final payload = {
    'status': 'temporary',
    'module': moduleType,
    'updatedAt': FieldValue.serverTimestamp(),
    'trainees': traineesPayload,
    'instructorId': uid,
    'rangeType': _rangeType,
    'settlement': selectedSettlement,
    'stations': stations.map((s) => s.toJson()).toList(),
    'attendeesCount': attendeesCount,
    'isTemporary': true,
  };
  
  // Step 5: Write ONCE to Firestore
  final docRef = FirebaseFirestore.instance.collection('feedbacks').doc(docId);
  await docRef.set(payload, SetOptions(merge: false)); // Complete overwrite
  
  // Step 6: READ-BACK VERIFICATION (mandatory)
  final verifySnap = await docRef.get();
  
  // Assert: document exists
  if (!verifySnap.exists) {
    await showDialog(...); // Blocking error dialog
    throw Exception('TEMP_SAVE_VERIFY_FAIL: Document not found');
  }
  
  // Assert: trainees array exists and matches
  final verifyTrainees = verifySnap.data()['trainees'];
  if (verifyTrainees.length != traineesPayload.length) {
    await showDialog(...); // Blocking error dialog
    throw Exception('TEMP_SAVE_VERIFY_FAIL: Count mismatch');
  }
  
  // Assert: at least one trainee has numeric data
  final hasNumericData = verifyTrainees.any((t) => 
    t['values'] != null && t['values'].isNotEmpty
  );
  if (!hasNumericData) {
    await showDialog(...); // Blocking error dialog
    throw Exception('TEMP_SAVE_VERIFY_FAIL: No numeric data');
  }
  
  // Step 7: Rehydrate UI from verified Firestore data
  trainees.clear();
  traineeNumbers.clear();
  for (final traineeData in verifyTrainees) {
    final hits = <int, int>{};
    final values = traineeData['values'] as Map;
    for (final entry in values.entries) {
      if (entry.key.startsWith('station_')) {
        final stationIdx = int.parse(entry.key.replaceFirst('station_', ''));
        hits[stationIdx] = entry.value;
      }
    }
    trainees.add(Trainee(name: traineeData['name'], hits: hits));
    traineeNumbers.add(traineeData['index'] + 1);
  }
  setState(() {});
  
  // Step 8: Success logging
  debugPrint("TEMP_SAVE_OK trainees=${trainees.length} valuesPresent=true");
}
```

### 3. Updated UI

**Before**:
- Single "Finalize Save" button
- Autosave status indicator (spinner/checkmark)
- Message: "הטיוטה נשמרת אוטומטית"

**After**:
- Two buttons:
  1. **"שמירה זמנית"** (Temporary Save) - Blue/Grey - Validates and saves to temp
  2. **"שמירה סופית"** (Finalize Save) - Orange - Finalizes and archives
- No autosave indicator
- Updated message: "שמירה זמנית: שומר את הנתונים לטיוטה (עם אימות מלא). שמירה סופית: משלים את המשוב ושולח לארכיון."

### 4. Firestore Schema

**Document Path**: `feedbacks/{userId}_{moduleType}_{rangeType}`

**Payload Structure**:
```json
{
  "status": "temporary",
  "module": "shooting_ranges" | "surprise_drill",
  "updatedAt": "serverTimestamp()",
  "trainees": [
    {
      "index": 0,
      "name": "חניך 1",
      "values": {
        "station_0": 15,
        "station_1": 18,
        "station_2": 20
      }
    }
  ],
  "instructorId": "uid123",
  "instructorName": "מדריך",
  "rangeType": "רמות" | "שלשות" | etc,
  "settlement": "קצרין",
  "stations": [
    {
      "name": "רמות",
      "bulletsCount": 20,
      "timeSeconds": 300,
      "isManual": false,
      "isLevelTester": true,
      "selectedRubrics": []
    }
  ],
  "attendeesCount": 10,
  "isTemporary": true,
  "folder": "מטווחי ירי" | "משוב תרגילי הפתעה"
}
```

---

## ✅ Validation Rules

### Pre-Write Validation

1. **User ID exists**: `uid != null && uid.isNotEmpty`
   - **Fail**: Blocking dialog "משתמש לא מחובר - לא ניתן לשמור"
   - **Throw**: `Exception('TEMP_SAVE_FAIL: No user ID')`

2. **Trainees array not empty**: `traineesPayload.isNotEmpty`
   - **Fail**: Blocking dialog "אין חניכים לשמירה"
   - **Throw**: `Exception('TEMP_SAVE_VALIDATION_FAIL: trainees.length == 0')`

3. **At least one valid trainee**: `hasValidData = true`
   - Valid = `name.isNotEmpty && values.isNotEmpty`
   - **Fail**: Blocking dialog "חייב להיות לפחות חניך אחד עם שם וציונים"
   - **Throw**: `Exception('TEMP_SAVE_VALIDATION_FAIL: No valid trainee data')`

### Post-Write Verification

4. **Document exists**: `verifySnap.exists == true`
   - **Fail**: Blocking dialog "המסמך לא נמצא אחרי השמירה"
   - **Throw**: `Exception('TEMP_SAVE_VERIFY_FAIL: Document not found')`

5. **Data not null**: `verifyData != null`
   - **Fail**: Blocking dialog "נתוני המסמך ריקים"
   - **Throw**: `Exception('TEMP_SAVE_VERIFY_FAIL: Data is null')`

6. **Trainees array exists**: `verifyTrainees != null && !isEmpty`
   - **Fail**: Blocking dialog "נתוני חניכים חסרים"
   - **Throw**: `Exception('TEMP_SAVE_VERIFY_FAIL: trainees missing')`

7. **Count matches**: `verifyTrainees.length == traineesPayload.length`
   - **Fail**: Blocking dialog "מספר חניכים לא תואם"
   - **Throw**: `Exception('TEMP_SAVE_VERIFY_FAIL: Count mismatch')`

8. **Numeric data present**: At least one trainee has non-empty `values` map
   - **Fail**: Blocking dialog "חסרים נתונים נומריים"
   - **Throw**: `Exception('TEMP_SAVE_VERIFY_FAIL: No numeric data')`

---

## 🔍 Debugging Logs

### Success Flow:
```
========== TEMP_SAVE_ATOMIC START ==========
TEMP_SAVE: UI committed (unfocused)
TEMP_SAVE: attendeesCount=10
TEMP_SAVE: trainees.length=10
TEMP_SAVE: stations.length=3
TEMP_SAVE: module=shooting_ranges docId=uid123_shooting_ranges_רמות
TEMP_SAVE: rangeType=רמות settlement=קצרין
TEMP_SAVE: trainee[0] name="חניך 1" values={station_0: 15, station_1: 18}
TEMP_SAVE: trainee[1] name="חניך 2" values={station_0: 20, station_1: 17}
TEMP_SAVE: VALIDATION START
✅ VALIDATION PASSED: trainees=10 hasValidData=true
TEMP_SAVE: payload keys=[status, module, updatedAt, trainees, ...]
TEMP_SAVE: Writing to feedbacks/uid123_shooting_ranges_רמות
✅ TEMP_SAVE: Write complete
TEMP_SAVE: Read-back verification...
✅ VERIFY_OK: trainees=10 valuesPresent=true
TEMP_SAVE: Rehydrating UI from Firestore data
TEMP_SAVE_REHYDRATE: trainee[0] name="חניך 1" hits={0: 15, 1: 18}
TEMP_SAVE_REHYDRATE: trainee[1] name="חניך 2" hits={0: 20, 1: 17}
TEMP_SAVE_OK trainees=10 valuesPresent=true
========== TEMP_SAVE_ATOMIC END ==========
```

### Failure Examples:

**Validation Failure (no trainees)**:
```
========== TEMP_SAVE_ATOMIC START ==========
TEMP_SAVE: UI committed (unfocused)
TEMP_SAVE: attendeesCount=0
TEMP_SAVE: trainees.length=0
❌ VALIDATION FAILED: No trainees
[Blocking dialog shown]
Exception: TEMP_SAVE_VALIDATION_FAIL: trainees.length == 0
```

**Validation Failure (no valid data)**:
```
TEMP_SAVE: trainee[0] name="" values={}
TEMP_SAVE: trainee[1] name="" values={}
❌ VALIDATION FAILED: No trainee with name AND values
[Blocking dialog shown]
Exception: TEMP_SAVE_VALIDATION_FAIL: No valid trainee data
```

**Verification Failure (count mismatch)**:
```
✅ TEMP_SAVE: Write complete
TEMP_SAVE: Read-back verification...
❌ VERIFY_FAIL: Count mismatch: 8 != 10
[Blocking dialog shown]
Exception: TEMP_SAVE_VERIFY_FAIL: Count mismatch
```

---

## 🧪 Testing Checklist

### Manual Testing Required:

1. **Valid Save Flow**:
   - [ ] Create feedback with 3 trainees
   - [ ] Fill in names and hit values
   - [ ] Click "שמירה זמנית"
   - [ ] Verify success snackbar appears
   - [ ] Verify console shows `TEMP_SAVE_OK` log
   - [ ] Check Firestore document has correct data

2. **Validation - Empty Trainees**:
   - [ ] Set attendees count to 0
   - [ ] Click "שמירה זמנית"
   - [ ] Verify blocking dialog appears
   - [ ] Verify save does NOT proceed

3. **Validation - No Names or Values**:
   - [ ] Add 3 trainees but leave all fields empty
   - [ ] Click "שמירה זמנית"
   - [ ] Verify blocking dialog appears
   - [ ] Verify save does NOT proceed

4. **NO Autosave**:
   - [ ] Type in trainee name field
   - [ ] Wait 2 seconds
   - [ ] Verify NO Firestore write occurs (check logs)
   - [ ] Verify NO autosave indicator appears

5. **NO Save on Dispose**:
   - [ ] Create feedback with data
   - [ ] Navigate away (back button)
   - [ ] Verify NO Firestore write occurs (check logs)

6. **UI Rehydration**:
   - [ ] Save feedback with data
   - [ ] Close and reopen the page
   - [ ] Verify all trainee data is restored correctly

---

## 🚨 Known Limitations

1. **Controller Pattern**: TextField controllers are created inline in build method, so we cannot read directly from controllers. Instead, we:
   - Force UI commit with `FocusManager.instance.primaryFocus?.unfocus()`
   - Wait 100ms for commit to propagate to model
   - Serialize from model (`trainees` list)

2. **Blocking Dialogs**: Error dialogs are non-dismissible (`barrierDismissible: false`). User MUST acknowledge the error by tapping the button.

3. **Network Failures**: If Firestore write succeeds but read-back fails (network issue), the data IS persisted but UI will show error. User should retry or reload.

---

## 📊 Impact Assessment

### What Changed:
- ✅ `lib/range_training_page.dart`: 300+ lines modified
  - Removed: Timer, autosave logic, status indicator
  - Rewritten: `_saveTemporarily()` function (300 lines)
  - Added: Temporary Save button, blocking error dialogs
  - Modified: 10+ TextField onChange handlers

### What Did NOT Change:
- ❌ Instructor Course Selection module (different file, out of scope)
- ❌ Finalize Save flow (`_saveToFirestore()` unchanged)
- ❌ Data models (`Trainee`, `RangeStation` unchanged)
- ❌ Load temporary feedback flow (unchanged)

### Files Modified:
1. `lib/range_training_page.dart` - Complete autosave removal and atomic temp save implementation

### Files NOT Modified:
- `lib/instructor_course_feedback_page.dart` (Instructor Course - different module)
- `lib/main.dart` (No changes needed)
- All other files in `lib/` (No changes needed)

---

## 🔒 Security & Data Integrity

### Firestore Rules:
Ensure rules allow instructors to write to their own temporary feedbacks:
```javascript
match /feedbacks/{feedbackId} {
  allow create, update: if request.auth != null 
    && request.auth.uid == request.resource.data.instructorId
    && request.resource.data.isTemporary == true;
}
```

### Data Validation:
- Server-side timestamp prevents client clock manipulation
- `instructorId` verified against `request.auth.uid`
- `isTemporary` flag prevents accidental permanent saves

---

## 📝 Next Steps

1. **Deploy to Production**:
   - Run full Flutter build
   - Deploy to Firebase Hosting/App Distribution
   - Monitor Firestore for validation errors in logs

2. **User Training**:
   - Update user documentation
   - Explain new two-button workflow
   - Clarify difference between Temporary and Finalize saves

3. **Future Enhancements**:
   - Consider adding progress indicator during read-back verification
   - Add retry logic for network failures
   - Implement controller lists for direct serialization (major refactor)

---

## 📞 Support

**Issues**: If validation errors occur frequently, check:
1. Are users filling in trainee names AND values?
2. Is Firestore write succeeding? (Check Firebase Console logs)
3. Are network conditions stable? (Read-back verification requires internet)

**Logs**: Search console for:
- `TEMP_SAVE_OK` - Successful saves
- `VALIDATION FAILED` - Pre-write validation errors
- `VERIFY_FAIL` - Post-write verification errors
- `TEMP_SAVE_FAIL` - Critical failures (no user ID, network, etc.)

---

**Implementation Complete** ✅  
**Tested**: Compilation ✅ | Manual Testing Required ⏳  
**Documented**: 2025-01-XX
