# Instructor Course Screening - Firestore Permission Fix

## 🎯 Problem Fixed

**Symptom**: When pressing "סיים משוב" on Instructor Course Screening:
- Error: `[cloud_firestore/permission-denied] Missing or insufficient permissions`
- Feedback stayed in "משובים בתהליך" (drafts)
- Did NOT move to finals (מתאימים / לא מתאימים)

**Root Cause**: Firestore security rules were missing for the collections used by Instructor Course Screening.

## ✅ Solution Implemented

### Collections Added to Firestore Rules

#### 1. **instructor_course_drafts** (Drafts/In-Progress)
```javascript
match /instructor_course_drafts/{draftId} {
  // Create: Any signed-in user
  allow create: if request.auth != null;
  
  // Read: Owner or admin
  allow read: if isOwner() || isAdmin();
  
  // Update: Owner or admin (when status is draft)
  allow update: if (isOwner() || isAdmin()) && 
    (resource.data.status == 'draft' || resource.data.status == 'in_progress');
  
  // Delete: Owner or admin (needed for finalize operation)
  allow delete: if isOwner() || isAdmin();
}
```

#### 2. **instructor_course_feedbacks** (Finals)
```javascript
match /instructor_course_feedbacks/{feedbackId} {
  // Create: Any signed-in user
  allow create: if request.auth != null;
  
  // Read: Any authenticated user
  allow read: if request.auth != null;
  
  // Update: Owner or admin only
  allow update: if isOwner() || isAdmin();
  
  // Delete: Admin only
  allow delete: if isAdmin();
}
```

### Finalize Operation Flow (Now Allowed)

The finalize operation uses **WriteBatch** for atomic execution:

1. **CREATE** new document in `instructor_course_feedbacks` ✅ Allowed
2. **DELETE** draft document from `instructor_course_drafts` ✅ Allowed

Both operations succeed atomically, so the feedback moves from drafts to finals cleanly.

## 🧪 Testing

### Test Steps

1. Open Instructor Course Screening form
2. Fill required fields (name, unit, rubrics)
3. Press **"סיים משוב"** button
4. Check console logs

### ✅ Expected Results

**Console Output**:
```
========== FINALIZE: INSTRUCTOR COURSE ==========
FINALIZE_START draftId=<draftId>
FINALIZE: Creating WriteBatch for atomic operation
BATCH: SET final doc in instructor_course_feedbacks
BATCH: DELETE temp doc from instructor_course_drafts
BATCH: Committing batch (atomic operation)...
FINALIZE_OK finalId=<finalId> draftDeleted=true result=suitable
✅ FINALIZE: Commit successful!
=================================================
```

**NO permission-denied error** ❌ → ✅

**UI Behavior**:
- ✅ No "יציאה ללא שמירה" dialog on exit
- ✅ Draft disappears from "משובים בתהליך"
- ✅ Final appears in "מתאימים לקורס מדריכים" or "לא מתאימים"

## 📋 Files Modified

### firestore.rules
- **Removed**: Old `instructor_course_screenings` collection rules
- **Added**: `instructor_course_drafts` collection rules
- **Added**: `instructor_course_feedbacks` collection rules

### Deployment
```bash
firebase deploy --only firestore:rules
```

**Result**: ✅ Rules deployed successfully

## 🔒 Security Model

### Ownership Rules
- **Drafts**: Owner can create, read, update, delete
- **Finals**: Owner can create, read, update (but NOT delete)
- **Admin**: Full access to both collections

### Atomic Batch Protection
Both operations in the finalize batch are now allowed:
1. ✅ CREATE in finals (any authenticated user)
2. ✅ DELETE from drafts (owner or admin)

If either operation fails permissions check, the entire batch is rejected (atomic safety).

## 🚀 Next Steps

### Optional Enhancements

1. **Stricter Create Validation**
   - Require `createdBy == request.auth.uid` on create
   - Validate required fields (candidateName, unit, etc.)

2. **Read-Only Finals**
   - After finalization, prevent updates to final feedbacks
   - Add `finalizedAt` timestamp check

3. **Audit Trail**
   - Log all finalize operations
   - Track who finalized each feedback

### Migration Note

If you have existing documents in the **old collection** (`instructor_course_screenings`):
- The old rules are **removed** (collection is deprecated)
- Migrate data to `instructor_course_drafts` if needed
- Or keep old rules temporarily for backwards compatibility

---

**Status**: ✅ Complete - Firestore rules deployed and tested
**Last Updated**: 2025-01-03
