# Instructor Course Evaluations Permissions Fix

## What was fixed

Fixed `[cloud_firestore/permission-denied]` errors in Instructor Course Evaluations module.

## Changes made

### 1. Firestore Security Rules (firestore.rules)
Updated `instructor_course_evaluations` collection rules to enforce strict owner-only access:

```javascript
match /instructor_course_evaluations/{evalId} {
  // Create: ONLY if ownerUid == auth.uid
  allow create: if request.auth != null 
                && request.resource.data.ownerUid == request.auth.uid;

  // Read: Owner OR finalized documents
  allow read: if request.auth != null 
              && (resource.data.ownerUid == request.auth.uid
                  || resource.data.status == 'final');

  // Update: ONLY owner
  allow update: if request.auth != null 
                && resource.data.ownerUid == request.auth.uid;

  // Delete: Owner or admin
  allow delete: if request.auth != null 
                && (resource.data.ownerUid == request.auth.uid || isAdmin());
}
```

### 2. Code verification
Verified that Flutter code ALWAYS writes `ownerUid` field:
- ✅ Autosave: Sets `ownerUid: uid` (line 144)
- ✅ Finalize: Sets `ownerUid: uid` (line 402)

## Acceptance test

1. **Login** as instructor/admin
2. **Create** new instructor course evaluation
3. **Fill** some fields → wait for autosave (should see "✅ AUTOSAVE: Save complete")
4. **Exit** the form (go back)
5. **Navigate** to "מיונים זמניים" (in-progress screenings)
6. **Verify** your evaluation appears in the list
7. **Open** the evaluation again
8. **Verify** all data is preserved

**Expected**: No permission errors at any step.

## Console logs to verify

```
🔵 MIUNIM_AUTOSAVE_WRITE: collection=instructor_course_evaluations
🔵 MIUNIM_AUTOSAVE_WRITE: docPath=instructor_course_evaluations/<docId>
🔵 MIUNIM_AUTOSAVE_WRITE: evalId=<docId>
🔵 MIUNIM_AUTOSAVE_WRITE: status=draft, ownerUid=<your-uid>
✅ AUTOSAVE: Save complete
```

## What was NOT changed

- ❌ No changes to autosave behavior
- ❌ No changes to UI or buttons
- ❌ No changes to document structure (except enforcing ownerUid)
- ❌ No changes to other modules (ranges, surprise drills, etc.)

## Deployment status

✅ Rules deployed to Firebase: `firebase deploy --only firestore:rules`
✅ Static analysis passed: `flutter analyze`

## Rollback (if needed)

If issues occur, revert firestore.rules to previous version and redeploy:
```bash
git checkout HEAD~1 firestore.rules
firebase deploy --only firestore:rules
```
