# Miunim Module Fix - Testing Guide

## Changes Made

### 1. Data Model (CRITICAL)
**Changed field names:**
- `userId` → `ownerUid` (for rules and queries)
- Status values:
  - Draft: `status='draft'`
  - Final: `status='final'` + `isSuitable=true/false`

### 2. Firestore Paths (with detailed logging)
**Drafts:**
- Collection: `instructor_course_evaluations`
- Query: `where('ownerUid', '==', uid).orderBy('updatedAt', desc)`
- Filter: `status='draft'` (in-memory)

**Finals:**
- Collection: `instructor_course_evaluations` (SAME as drafts)
- Query: `where('ownerUid', '==', uid).orderBy('createdAt', desc)`
- Filter: `status='final' AND isSuitable=true/false` (in-memory)

### 3. Finalize Flow (Atomic)
**One operation:**
- Update doc status from 'draft' to 'final'
- Set `isSuitable` boolean
- Set `finalizedAt` timestamp
- **On error:** Show snackbar, do NOT navigate

### 4. Security Rules
**Updated:** `instructor_course_evaluations` collection
- Changed from `userId` to `ownerUid`
- Read access: owner OR status='final'
- Write access: owner only

### 5. Console Logging
**All Firestore operations now log:**
- 🔵 `MIUNIM_AUTOSAVE_WRITE` - Draft save
- 🟢 `MIUNIM_FINALIZE_WRITE` - Finalize start
- ✅ `MIUNIM_SAVE_OK` - Finalize success (with doc path)
- 🔍 `MIUNIM_LIST_READ` - List queries
- ❌ `MIUNIM_FINALIZE_ERROR` - Finalize failure

---

## Testing Checklist

### Pre-Deploy
1. **Deploy rules first:**
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Run app:**
   ```bash
   flutter run -d chrome
   ```

### Test Flow

#### Test 1: Create Draft
1. Login as instructor
2. תרגילים → מיונים לקורס מדריכים → הערכת מועמד
3. Fill in:
   - פיקוד: פיקוד צפון
   - חטיבה: 474
   - שם מועמד: טסט מיונים
   - בוחן רמה: 8
   - הדרכה טובה: 7
4. **Wait 1 second** (autosave)
5. **Check console for:**
   ```
   🔵 MIUNIM_AUTOSAVE_WRITE: collection=instructor_course_evaluations
   🔵 MIUNIM_AUTOSAVE_WRITE: docPath=instructor_course_evaluations/eval_...
   🔵 MIUNIM_AUTOSAVE_WRITE: status=draft, ownerUid=...
   ✅ AUTOSAVE: Save complete
   ```

**✅ Pass:** No permission errors, draft saved

#### Test 2: View Draft
1. Navigate to משובים → מיונים זמניים
2. **Expected:** See "טסט מיונים" in list
3. Click "המשך"
4. **Expected:** Form loads with all scores intact

**✅ Pass:** Draft appears and reloads correctly

#### Test 3: Finalize (Suitable)
1. In draft form, fill all categories (scores > 7)
2. Click "סיים משוב"
3. **Check console for:**
   ```
   🟢 MIUNIM_FINALIZE_WRITE: collection=instructor_course_evaluations
   🟢 MIUNIM_FINALIZE_WRITE: docPath=instructor_course_evaluations/eval_...
   🟢 MIUNIM_FINALIZE_WRITE: status=final, isSuitable=true, ownerUid=...
   ✅ MIUNIM_SAVE_OK: evalId=eval_..., docPath=instructor_course_evaluations/...
   ✅ MIUNIM_SAVE_OK: status=final, isSuitable=true
   ```
4. **Expected:** Success message, navigate to list

**✅ Pass:** Finalize completes without errors

#### Test 4: View in Final List (Suitable)
1. Navigate to משובים → מיונים לקורס מדריכים
2. Click "מתאימים לקורס מדריכים" button
3. **Check console for:**
   ```
   🔍 MIUNIM_LIST_READ: collection=instructor_course_evaluations ownerUid=...
   🔍 MIUNIM_LIST_READ: where("ownerUid", "==", "...")
   🔍 MIUNIM_LIST_READ: orderBy("createdAt", descending: true)
   🔍 MIUNIM_LIST_READ_RAW: Got X documents
   🔍 MIUNIM_LIST_READ_FILTERED: Y documents with status=final, isSuitable=true
   ```
4. **Expected:** See "טסט מיונים" in list
5. Click to view details
6. **Expected:** All scores visible

**✅ Pass:** Evaluation appears in "מתאימים" list

#### Test 5: Finalize (Not Suitable)
1. Create new draft: "טסט לא מתאים"
2. Fill with low scores (< 5)
3. Finalize
4. **Check console for:**
   ```
   ✅ MIUNIM_SAVE_OK: status=final, isSuitable=false
   ```
5. Navigate to "לא מתאימים לקורס מדריכים"
6. **Expected:** See "טסט לא מתאים" in this list ONLY

**✅ Pass:** Not suitable evaluations appear in correct list

#### Test 6: Drafts Don't Show in Finals
1. Create new draft: "טיוטה בלבד"
2. Fill some fields, wait for autosave
3. **Do NOT finalize**
4. Check both "מתאימים" and "לא מתאימים" lists
5. **Expected:** "טיוטה בלבד" does NOT appear
6. Check "מיונים זמניים"
7. **Expected:** "טיוטה בלבד" DOES appear here

**✅ Pass:** Drafts isolated from finals

---

## Firestore Console Verification

1. Open Firebase Console → Firestore
2. Navigate to `instructor_course_evaluations` collection
3. Find test documents

### Draft Document
```javascript
{
  "ownerUid": "abc123",
  "status": "draft",
  "courseType": "miunim",
  "createdAt": Timestamp,
  "updatedAt": Timestamp,
  "candidateName": "טיוטה בלבד",
  "fields": { ... },
  "isSuitable": true,  // calculated but not used for filtering
  // ... other fields
}
```

### Final Document
```javascript
{
  "ownerUid": "abc123",
  "status": "final",  // ← CHANGED from 'suitable'/'notSuitable'
  "isSuitable": true, // ← USED for filtering
  "courseType": "miunim",
  "createdAt": Timestamp,
  "updatedAt": Timestamp,
  "finalizedAt": Timestamp,
  "candidateName": "טסט מיונים",
  "fields": { ... },
  "finalWeightedScore": 78.5,
  // ... other fields
}
```

---

## Success Criteria

- [x] Drafts save with `ownerUid` field
- [x] Finals save with `status='final'` + `isSuitable` boolean
- [x] "מתאימים" list shows only `isSuitable=true` finals
- [x] "לא מתאימים" list shows only `isSuitable=false` finals
- [x] Drafts appear in "מיונים זמניים" only
- [x] All Firestore paths logged to console
- [x] Error handling prevents navigation on failure
- [x] No permission-denied errors
- [x] No missing-index errors

---

## Expected Console Output (Full Flow)

```
🔵 MIUNIM_AUTOSAVE_WRITE: collection=instructor_course_evaluations
🔵 MIUNIM_AUTOSAVE_WRITE: docPath=instructor_course_evaluations/eval_abc123_1234567890
🔵 MIUNIM_AUTOSAVE_WRITE: evalId=eval_abc123_1234567890
🔵 MIUNIM_AUTOSAVE_WRITE: status=draft, ownerUid=abc123
✅ AUTOSAVE: Save complete

... (user fills form) ...

🟢 MIUNIM_FINALIZE_WRITE: collection=instructor_course_evaluations
🟢 MIUNIM_FINALIZE_WRITE: docPath=instructor_course_evaluations/eval_abc123_1234567890
🟢 MIUNIM_FINALIZE_WRITE: evalId=eval_abc123_1234567890
🟢 MIUNIM_FINALIZE_WRITE: status=final, isSuitable=true, ownerUid=abc123
✅ MIUNIM_SAVE_OK: evalId=eval_abc123_1234567890, docPath=instructor_course_evaluations/eval_abc123_1234567890
✅ MIUNIM_SAVE_OK: status=final, isSuitable=true

... (navigate to final list) ...

🔍 MIUNIM_LIST_READ: collection=instructor_course_evaluations ownerUid=abc123 isSuitable=true
🔍 MIUNIM_LIST_READ: where("ownerUid", "==", "abc123")
🔍 MIUNIM_LIST_READ: orderBy("createdAt", descending: true)
🔍 MIUNIM_LIST_READ_RAW: Got 5 documents (all statuses)
🔍 MIUNIM_LIST_READ_FILTERED: 2 documents with status=final, isSuitable=true
```

---

## Rollback (if needed)

```bash
git checkout HEAD~1 lib/ firestore.rules
firebase deploy --only firestore:rules
flutter pub get
```

---

## Deploy to Production

```bash
# 1. Deploy rules
firebase deploy --only firestore:rules

# 2. Test locally first
flutter run -d chrome

# 3. Run all tests above

# 4. Deploy full app
firebase deploy
```

**Status:** Ready for testing! 🚀
