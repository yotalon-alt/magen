# Temp-Save Diagnostics Implementation

## Issue
Desktop/web temp-save does not persist trainee names or values, while mobile partially works.

## Root Cause Analysis
The issue is likely due to:
1. Missing async/await in button click handler
2. Insufficient error logging to detect Firestore write failures
3. No verification that data was actually saved
4. Platform-specific differences in Firestore behavior

## Changes Implemented

### 1. Enhanced Button OnPressed (range_training_page.dart:1154-1177)
**Before:**
```dart
onPressed: _canSaveTemporarily ? _saveTemporarily : null,
```

**After:**
```dart
onPressed: _canSaveTemporarily
    ? () async {
        final module = widget.mode == 'surprise' ? 'surprise' : 'range';
        final key = _rangeType;
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final email = FirebaseAuth.instance.currentUser?.email;
        debugPrint('TEMP_SAVE_CLICK module=$module key=$key user=$uid email=$email');
        debugPrint('TEMP_SAVE_CLICK platform=${kIsWeb ? "web" : "mobile"}');
        debugPrint('TEMP_SAVE_CLICK trainees=${trainees.length} stations=${stations.length}');
        await _saveTemporarily();
      }
    : null,
```

**Changes:**
- Made onPressed handler async
- Added TEMP_SAVE_CLICK diagnostics before save
- Properly awaits _saveTemporarily() call
- Logs module, key, user ID, email, platform, and data counts

### 2. Enhanced _saveTemporarily() Error Handling (range_training_page.dart:609-690)
**Added:**
- `TEMP_SAVE_START path=${docRef.path}` - logs full Firestore path
- Wrapped Firestore write in try-catch with explicit error logging:
  ```dart
  try {
    await docRef.set(saveData, SetOptions(merge: true));
    debugPrint('TEMP_SAVE_OK');
  } catch (e, st) {
    debugPrint('TEMP_SAVE_FAIL $e');
    debugPrint('$st');
    rethrow; // Show error to user
  }
  ```
- Immediate readback verification after save
- `TEMP_SAVE_READBACK exists=... keys=...` - verifies document exists
- Detailed verification of saved data:
  - Trainee count
  - Station count
  - Settlement
  - Attendees count
  - First trainee details (including name check)
- Mismatch detection and logging

### 3. Enhanced _loadExistingTemporaryFeedback() Diagnostics (range_training_page.dart:700-742)
**Added:**
- User ID and email logging
- Full document path logging
- Module and rangeType context
- Data keys listing
- Raw data inspection for trainees, stations, settlement, attendeesCount
- Detailed parsing logs for first 3 trainees

### 4. Added kIsWeb Import
```dart
import 'package:flutter/foundation.dart' show kIsWeb;
```

## Diagnostic Log Flow

### On Temp-Save Button Click (Desktop/Web):
```
TEMP_SAVE_CLICK module=range key=קצרים user=abc123 email=user@example.com
TEMP_SAVE_CLICK platform=web
TEMP_SAVE_CLICK trainees=5 stations=3

========== TEMP_SAVE START ==========
TEMP_SAVE: module=range path=feedbacks/abc123_range_קצרים
TEMP_SAVE: rangeType=קצרים
TEMP_SAVE: traineesCount=5
TEMP_SAVE: stationsCount=3
TEMP_SAVE: firstTrainee={name: חניך 1, hits: {station_0: 8}}
TEMP_SAVE: hasNames=true, hasScores=true
TEMP_SAVE: traineesPayload.length=5
TEMP_SAVE: traineesPayload[0]={name: חניך 1, hits: {station_0: 8}, totalHits: 8, number: 1}
TEMP_SAVE_START path=feedbacks/abc123_range_קצרים
TEMP_SAVE: Writing to Firestore...
TEMP_SAVE_OK
TEMP_SAVE: Verifying write with immediate readback...
TEMP_SAVE_READBACK exists=true keys=[exercise, folder, status, type, ...]
TEMP_SAVE_VERIFY: traineesLen=5
TEMP_SAVE_VERIFY: stationsLen=3
TEMP_SAVE_VERIFY: settlement=קצרין
TEMP_SAVE_VERIFY: attendeesCount=5
TEMP_SAVE_VERIFY: firstTrainee={name: חניך 1, hits: {station_0: 8}, ...}
✅ VERIFIED: Trainee count matches
✅ VERIFIED: Station count matches
========== TEMP_SAVE END ==========
```

### On Error:
```
❌ ========== TEMP_SAVE ERROR ==========
Error: [firebase_auth/permission-denied] Insufficient permissions
StackTrace: ...
========================================
```

### On Load:
```
========== TEMP_LOAD START ==========
TEMP_LOAD: user=abc123 email=user@example.com
TEMP_LOAD: path=feedbacks/abc123_range_קצרים
TEMP_LOAD: module=range rangeType=קצרים
TEMP_LOAD: using direct docRef.get() (no query)
TEMP_LOAD: fullPath=feedbacks/abc123_range_קצרים
TEMP_LOAD: got document, exists=true
TEMP_LOAD: doc.id=abc123_range_קצרים
TEMP_LOAD: dataKeys=[exercise, folder, status, trainees, stations, ...]
TEMP_LOAD: rawTrainees.length=5
TEMP_LOAD: rawStations.length=3
TEMP_LOAD: settlement=קצרין
TEMP_LOAD: attendeesCount=5
TEMP_LOAD: firstTraineeRaw={name: חניך 1, hits: {station_0: 8}, ...}
TEMP_LOAD: Parsing data...
TEMP_LOAD: Parsed 5 trainees into model
TEMP_LOAD:   Trainee 0: name="חניך 1", hits={0: 8}
TEMP_LOAD:   Trainee 1: name="חניך 2", hits={0: 5, 1: 7}
TEMP_LOAD:   Trainee 2: name="חניך 3", hits={1: 9}
TEMP_LOAD: ✅ Load complete
TEMP_LOAD:   attendeesCount=5
TEMP_LOAD:   trainees.length=5
TEMP_LOAD:   stations.length=3
========== TEMP_LOAD END (SUCCESS) ==========
```

## Testing Instructions

### Desktop/Web Test:
1. Open app on desktop/web (Chrome, Edge, etc.)
2. Open terminal/console to see debug logs
3. Navigate to: תרגילים → מטווחים → טווח קצר
4. Fill in:
   - יישוב: Select a settlement
   - כמות נוכחים: Enter 3
   - Add at least one station with a name and bullets
   - Enter names for all 3 trainees
   - Enter hit values for at least one trainee
5. Click "שמור זמנית"
6. **Check logs** for:
   - `TEMP_SAVE_CLICK` - verify platform=web, correct trainee/station counts
   - `TEMP_SAVE_START` - verify path includes user ID
   - `TEMP_SAVE_OK` - write succeeded
   - `TEMP_SAVE_READBACK exists=true` - verification passed
   - `✅ VERIFIED` messages - data matches
   - NO `TEMP_SAVE_FAIL` or error messages
7. Navigate back to: תרגילים → מטווחים → טווח קצר
8. **Check logs** for:
   - `TEMP_LOAD` - verify same path as save
   - `exists=true` - document found
   - `rawTrainees.length=3` - correct count
   - `✅ Load complete` - parse succeeded
9. **Verify UI**:
   - Settlement field shows correct value
   - כמות נוכחים shows 3
   - All trainee names are filled in
   - All hit values are restored
   - Station names and bullets are correct

### Mobile Test (for comparison):
Same steps on mobile device/emulator

### Failure Scenarios to Check:

#### Scenario 1: Permission Denied
**Expected logs:**
```
TEMP_SAVE_FAIL [firebase_auth/permission-denied] ...
```
**Action:** Check Firestore rules, ensure user is authenticated

#### Scenario 2: Path Mismatch
**Expected logs:**
```
TEMP_SAVE_START path=feedbacks/userA_range_קצרים
TEMP_LOAD: path=feedbacks/userB_range_קצרים
⚠️ TEMP_LOAD: Document does not exist
```
**Action:** Verify user ID is consistent across save/load

#### Scenario 3: Empty Data After Save
**Expected logs:**
```
TEMP_SAVE_READBACK exists=true
TEMP_SAVE_VERIFY: traineesLen=0
❌ MISMATCH: Saved 0 but expected 3
```
**Action:** Check data serialization, ensure traineesPayload is not empty

#### Scenario 4: Web-Specific Firestore Issue
**Expected logs:**
```
TEMP_SAVE_CLICK platform=web
TEMP_SAVE_FAIL Error: ... (platform-specific)
```
**Action:** Check browser console for additional errors, verify Firestore web SDK

## Firestore Document Structure

Path: `feedbacks/{userId}_{moduleType}_{rangeType}`

Example: `feedbacks/abc123_range_קצרים`

```json
{
  "exercise": "מטווחים",
  "folder": "מטווחים - משוב זמני",
  "status": "temporary",
  "type": "range_training",
  "instructorName": "שם המדריך",
  "instructorId": "abc123",
  "rangeType": "קצרים",
  "settlement": "קצרין",
  "attendeesCount": 3,
  "stations": [
    {
      "name": "הרמות",
      "bulletsCount": 10,
      "timeSeconds": null,
      "hits": null,
      "isManual": false,
      "isLevelTester": false,
      "selectedRubrics": ["זמן", "פגיעות"]
    }
  ],
  "trainees": [
    {
      "name": "חניך 1",
      "hits": {"station_0": 8},
      "totalHits": 8,
      "number": 1
    },
    {
      "name": "חניך 2",
      "hits": {"station_0": 5},
      "totalHits": 5,
      "number": 2
    }
  ],
  "name": "קצרין",
  "role": "מטווח",
  "scores": {},
  "notes": {"temporary": "שמירה זמנית"},
  "criteriaList": [],
  "createdAt": <Timestamp>
}
```

## Next Steps if Issue Persists

1. **Check Browser Console:** Web-specific Firestore errors may appear there
2. **Verify Firestore Rules:** Ensure `/feedbacks/{feedbackId}` allows write for authenticated users
3. **Check Network Tab:** Look for failed Firestore requests
4. **Test with Simple Data:** Try saving with just 1 trainee, 1 station to isolate issue
5. **Compare Mobile vs Web Logs:** Look for differences in TEMP_SAVE flow
6. **Check Firestore Console:** Manually verify document was created with correct data
7. **Test on Different Browsers:** Chrome, Firefox, Safari behavior may differ
8. **Enable Firestore Debug Logging:** Add `firebase.firestore.setLogLevel('debug')` in web initialization

## Files Modified
- `lib/range_training_page.dart`
  - Enhanced button onPressed (line ~1154)
  - Added comprehensive save diagnostics (line ~609)
  - Added comprehensive load diagnostics (line ~700)
  - Added kIsWeb import (line 4)
