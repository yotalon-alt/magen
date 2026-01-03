# Instructor Course Autosave Implementation Summary

## ✅ Changes Implemented (ONLY instructor course module)

### 1. **Autosave to Draft** (Replaces Temporary Save)
- **File**: `lib/instructor_course_feedback_page.dart`
- **Debounce Timer**: 700ms delay after last edit
- **Trigger Points**:
  - Score changes (all 5 categories)
  - Text field changes (hits, time, personal details)
  - Level test rating updates
- **Draft Document**:
  - Collection: `instructor_course_feedbacks`
  - Fields: `status: "draft"`, `isTemporary: true`
  - Stable ID: `draft_{uid}_{timestamp}` (created once per session)
  - Idempotent: Overwrites same draft, never creates duplicates

### 2. **UI Changes** (instructor_course_feedback_page.dart)
- ❌ **Removed**: "שמור משוב" button
- ✅ **Added**: Autosave status indicator
  - Shows "שומר אוטומטית..." while saving
  - Shows "השינויים נשמרו" when clean
- ✅ **Kept**: "סיים משוב" button (finalize action)

### 3. **Finalize Flow** (Single Collection)
- **Before**: Moved document from `instructor_course_drafts` → `instructor_course_feedbacks`
- **After**: Updates same document in `instructor_course_feedbacks`
  - Changes `status: "draft"` → `status: "finalized"`
  - Sets `isTemporary: false`
  - Sets `isSuitable: true/false` (based on score ≥ 3.6)
  - Adds `finalizedAt` timestamp
- **No data loss**: All fields preserved during finalize

### 4. **List Views** (instructor_course_selection_feedbacks_page.dart)
- ✅ **Added**: "משובים בתהליך" button (blue)
  - Query: `where('status', '==', 'draft')`
  - Shows all draft feedbacks (auto-saved but not finalized)
- ✅ **Existing**: "מתאימים" button (green)
  - Query: `where('status', '==', 'finalized') AND where('isSuitable', '==', true)`
- ✅ **Existing**: "לא מתאימים" button (red)
  - Query: `where('status', '==', 'finalized') AND where('isSuitable', '==', false)`

### 5. **Data Persistence**
- **All scores stored as numbers** (int/double, not strings)
- **Schema preserved**:
  ```dart
  fields: {
    'בוחן רמה': {
      value: 4,
      filledBy: 'uid',
      filledAt: timestamp,
      hits: 8,         // only for levelTest
      timeSeconds: 12  // only for levelTest
    },
    // ... other categories
  }
  ```
- **Mapping preserved**: Hebrew keys → English keys for UI display

## 🔒 Safety & Non-Regression

### What was NOT changed:
- ❌ Range reports (`range_training_page.dart`)
- ❌ Surprise drills (`surprise_drills_*.dart`)
- ❌ General feedback (`main.dart` feedbacks)
- ❌ Other collections (no renames, no deletions)
- ❌ Authentication or permissions

### Logging Added (instructor_course only):
- `AUTOSAVE START/END`: Draft save lifecycle
- `FINALIZE_START/FINALIZE_OK`: Finalize success
- `LIST_LOAD`: Query execution and results
- `AUTOSAVE_ERROR`: Save failures with stack trace

## 📋 Testing Checklist

### ✅ Draft Autosave
- [ ] Open instructor course form
- [ ] Fill in required details (Pikud, Brigade, Name, Number)
- [ ] Change any score → Wait 700ms → Check console for "AUTOSAVE START"
- [ ] Change another score → Wait → Should see "AUTOSAVE START" again
- [ ] Close browser tab → Reopen → Navigate to "משובים בתהליך"
- [ ] Expect: Draft appears in list with your scores

### ✅ Finalize Flow
- [ ] Open draft from "משובים בתהליך"
- [ ] Complete all 5 categories (scores > 0)
- [ ] Click "סיים משוב"
- [ ] Expect: Success message, navigate back
- [ ] Check "מתאימים" or "לא מתאימים" (based on score)
- [ ] Expect: Finalized item appears in correct list
- [ ] Check "משובים בתהליך"
- [ ] Expect: Draft NO LONGER appears (moved to finals)

### ✅ Data Integrity
- [ ] Open finalized feedback from list
- [ ] Click to view details dialog
- [ ] Expect: All scores show actual values (NOT zeros)
- [ ] Verify average score matches individual scores
- [ ] Check console for `SCORE_MAP` logs (confirms mapping)

### ✅ Concurrent Autosaves
- [ ] Rapidly change multiple scores back-to-back
- [ ] Check console logs
- [ ] Expect: Only ONE autosave runs at a time (debounced)
- [ ] Expect: No "already saving" warnings

### ✅ Exit Without Save
- [ ] Make changes to draft
- [ ] Wait for autosave to complete ("השינויים נשמרו")
- [ ] Press back button
- [ ] Expect: NO unsaved changes warning
- [ ] Reopen draft
- [ ] Expect: Changes are present

## 🐛 Known Issues & Solutions

### Issue: "Missing Firestore index"
**Symptom**: Red error on "משובים בתהליך" screen  
**Cause**: Composite index required for `status + updatedAt`  
**Solution**:
1. Go to Firebase Console → Firestore → Indexes
2. Create index:
   - Collection: `instructor_course_feedbacks`
   - Field 1: `status` (Ascending)
   - Field 2: `updatedAt` (Descending)
3. Wait 1-5 minutes for index to build

### Issue: Scores show zeros
**Symptom**: Details dialog shows "—" or "0" for all scores  
**Cause**: Score mapping issue  
**Solution**: Check console for `SCORE_MAP` logs. If missing, verify:
- `fields[hebrewName].value` exists in Firestore
- Hebrew→English mapping is correct

### Issue: Draft not appearing in list
**Symptom**: Autosave succeeded but draft not in "משובים בתהליך"  
**Debug Steps**:
1. Check console for `AUTOSAVE: draftId=...`
2. Open Firestore Console → `instructor_course_feedbacks`
3. Find document with that ID
4. Verify `status: "draft"` field exists
5. If not, check for autosave errors in logs

## 📊 Console Logs Reference

### Successful Autosave:
```
🔄 AUTOSAVE: Timer triggered
========== ✅ AUTOSAVE START ==========
AUTOSAVE: Created stable draftId=draft_ABC123_1234567890
AUTOSAVE: Saving to instructor_course_feedbacks/draft_ABC123_1234567890
✅ AUTOSAVE: Save complete
✅ AUTOSAVE: Verification PASSED
AUTOSAVE: draftId=draft_ABC123_1234567890
========== ✅ AUTOSAVE END ==========
```

### Successful Finalize:
```
========== FINALIZE: INSTRUCTOR COURSE ==========
FINALIZE: Forcing immediate save of pending changes
FINALIZE_START draftId=draft_ABC123_1234567890
FINALIZE: Updating status from draft to finalized
FINALIZE_OK finalId=draft_ABC123_1234567890 result=suitable
✅ FINALIZE: Status updated successfully!
RESULT: status=finalized
RESULT: isSuitable=suitable
=================================================
```

### Successful List Load (In Process):
```
🔍 ===== LIST_LOAD: INSTRUCTOR COURSE FEEDBACKS =====
LIST_LOAD collection=instructor_course_feedbacks filters={status: draft}
QUERY: where("status", "==", "draft")
QUERY: orderBy("updatedAt", descending: true)
LIST_LOAD_RESULT: Got 3 draft documents
DRAFT: draft_ABC123_1234567890 - John Doe avg=4.2 scores=5
✅ Loaded 3 draft feedbacks
===================================================
```

## 🔄 Migration Notes

### Old Data Compatibility
- **Old collection**: `instructor_course_drafts` (deprecated)
- **New collection**: `instructor_course_feedbacks` (single collection for both drafts and finals)
- **Migration**: NOT required - old drafts can be manually finalized or left in old collection

### Future Cleanup (Optional)
If you want to clean up old drafts collection:
1. Backup data from `instructor_course_drafts`
2. Manually copy important drafts to `instructor_course_feedbacks` with `status: "draft"`
3. Delete old `instructor_course_drafts` collection

## 📞 Support

If issues persist:
1. Check Firebase Console → Firestore → Indexes (ensure all indexes are enabled)
2. Check browser console for error logs
3. Verify user permissions (instructor or admin)
4. Check network tab for failed Firestore requests
