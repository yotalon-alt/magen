# DUPLICATE FEEDBACK DIAGNOSTIC LOGGING

## Bug Description
Saving final causes the same feedback to appear in BOTH temp list and normal list.

## Diagnostic Changes Made
Added comprehensive logging to track docIds and field values in all save and query operations.

### 1. FINAL_SAVE Function (range_training_page.dart)
**Location**: Lines ~2045-2090

**Logged BEFORE write**:
```
========== FINAL_SAVE DIAGNOSTIC ==========
FINAL_SAVE: Tag=FINAL_SAVE
FINAL_SAVE: docId=<firestore_doc_id>
FINAL_SAVE: _feedbackId=<widget.feedbackId>
FINAL_SAVE: isTemporary=<value>
FINAL_SAVE: status=<value>
FINAL_SAVE: isDraft=<value>
FINAL_SAVE: finalizedAt=<value>
FINAL_SAVE: folder=<value>
FINAL_SAVE: folderKey=<value>
```

**Logged AFTER write**:
```
========== FINAL_SAVE VERIFY ==========
FINAL_SAVE_VERIFY: docId=<firestore_doc_id> written
```

### 2. TEMP_SAVE Function (range_training_page.dart)
**Location**: Lines ~2440-2510

**Logged BEFORE write**:
```
========== TEMP_SAVE DIAGNOSTIC ==========
TEMP_SAVE: Tag=TEMP_SAVE
TEMP_SAVE: docId=<draft_id>
TEMP_SAVE: _feedbackId=<widget.feedbackId>
TEMP_SAVE: isTemporary=<value>
TEMP_SAVE: status=<value>
TEMP_SAVE: isDraft=<value>
TEMP_SAVE: finalizedAt=<value>
TEMP_SAVE: folder=<value>
TEMP_SAVE: folderKey=<value>
```

**Logged AFTER write**:
```
========== TEMP_SAVE VERIFY ==========
TEMP_SAVE_VERIFY: docId=<draft_id> written
```

### 3. TEMP_LIST_QUERY (range_temp_feedbacks_page.dart)
**Location**: Lines ~57-70

**Logged query filters**:
```
========== TEMP_LIST_QUERY DIAGNOSTIC ==========
TEMP_LIST_QUERY: collection=feedbacks
TEMP_LIST_QUERY: where module == shooting_ranges
TEMP_LIST_QUERY: where isTemporary == true
TEMP_LIST_QUERY: where instructorId == <uid> (if not admin)
TEMP_LIST_QUERY: orderBy createdAt DESC
```

### 4. NORMAL_LIST_FILTER (main.dart FeedbacksPage)
**Location**: Lines ~3703-3720

**Logged filter logic**:
```
========== NORMAL_LIST_FILTER DIAGNOSTIC ==========
NORMAL_LIST_FILTER: folder=מטווחי ירי
NORMAL_LIST_FILTER: Filter logic:
  1. Exclude where isTemporary == true
  2. Include where folderKey == shooting_ranges
  3. OR where module == shooting_ranges
  4. OR where folder == מטווחי ירי
```

## Test Scenario

### Setup
1. Start the app
2. Sign in as instructor/admin
3. Navigate to: תרגילים → מטווחים → טווח קצר

### Test Steps
1. Create a NEW range feedback:
   - Select settlement
   - Add 1 stage
   - Add 1 trainee name
   - Enter some hits
   
2. Press "שמור סופי" (Final Save) ONCE

3. Check the terminal output

### What to Look For

#### Expected Behavior (CORRECT)
```
TEMP_SAVE: docId=ABC123
TEMP_SAVE: isTemporary=true
TEMP_SAVE: status=temporary
...
FINAL_SAVE: docId=ABC123  <-- SAME ID
FINAL_SAVE: isTemporary=false
FINAL_SAVE: status=final
```
**Result**: Only ONE document with changing flags (temp → final)

#### Bug Behavior (INCORRECT)
```
TEMP_SAVE: docId=ABC123
TEMP_SAVE: isTemporary=true
TEMP_SAVE: status=temporary
...
FINAL_SAVE: docId=XYZ789  <-- DIFFERENT ID
FINAL_SAVE: isTemporary=false
FINAL_SAVE: status=final
```
**Result**: TWO separate documents (one temp, one final)

## Key Questions to Answer

1. **Same docId?**: Does TEMP_SAVE and FINAL_SAVE use the SAME docId?
   - If YES → flags should change correctly (temp → final)
   - If NO → creates duplicate (temp doc + final doc)

2. **isTemporary flag**: Does FINAL_SAVE write `isTemporary=false`?
   - If YES → should appear in normal list only
   - If NO → will appear in temp list

3. **_feedbackId value**: What is widget.feedbackId during FINAL_SAVE?
   - Should be the temp draft ID (from create flow)
   - If null/empty → creates NEW document instead of updating

4. **Query filters match saved data?**:
   - TEMP_LIST: `isTemporary == true` → should match temp docs
   - NORMAL_LIST: `isTemporary == false` → should match final docs

## Next Steps

After reviewing logs:
- If same docId but still appears in both lists → check loadFeedbacksForCurrentUser()
- If different docIds → fix FINAL_SAVE to use widget.feedbackId correctly
- If wrong isTemporary value → fix field assignment in FINAL_SAVE

## Files Modified

1. `lib/range_training_page.dart` - Added TEMP_SAVE and FINAL_SAVE diagnostics
2. `lib/range_temp_feedbacks_page.dart` - Added TEMP_LIST_QUERY diagnostics
3. `lib/main.dart` - Added NORMAL_LIST_FILTER diagnostics

## Diagnostic Output Location

All logs prefixed with:
- `TEMP_SAVE:` - Temporary save operation
- `FINAL_SAVE:` - Final save operation
- `TEMP_LIST_QUERY:` - Temp list query filters
- `NORMAL_LIST_FILTER:` - Normal list filter logic

Look for these tags in the terminal/console output during the test.
