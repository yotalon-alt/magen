# Firestore Security Rules for Instructor Course Autosave

## Required Rules Update

Add the following rules to `firestore.rules` to allow instructor course draft autosave:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // ... existing rules ...
    
    // ✅ NEW: Instructor Course Draft Subcollection
    // Users can only read/write/delete their own drafts
    match /users/{userId}/instructor_course_feedback_drafts/{draftId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null && request.auth.uid == userId;
      allow update: if request.auth != null && request.auth.uid == userId;
      allow delete: if request.auth != null && request.auth.uid == userId;
    }
    
    // Existing final feedbacks collection (no changes needed)
    match /instructor_course_feedbacks/{feedbackId} {
      // ... existing rules for final feedbacks ...
    }
  }
}
```

---

## Rule Explanation

### Path: `users/{userId}/instructor_course_feedback_drafts/{draftId}`

**Purpose:**
- Store instructor course feedback drafts per user
- Autosave writes here every 700ms
- Finalize deletes draft after creating final feedback

**Security:**
- ✅ User can ONLY access their own drafts (`request.auth.uid == userId`)
- ✅ No other users can see/modify drafts
- ✅ Drafts are isolated per user (subcollection pattern)

**Operations:**
1. **read**: Load existing draft when reopening form
2. **create**: First autosave creates draft document
3. **update**: Subsequent autosaves update existing draft
4. **delete**: Finalize deletes draft after writing final feedback

---

## Testing Rules Locally (Optional)

Use Firebase Emulator to test rules before deploying:

```bash
# Start emulators
firebase emulators:start

# Test rules in Emulator UI
# Navigate to: http://localhost:4000
# Go to Firestore → Rules Playground
# Test path: users/{your-uid}/instructor_course_feedback_drafts/draft_123
# Operation: read/write
# Auth: Set uid to match {your-uid}
```

---

## Deployment

### Option 1: Firebase Console (Web UI)
1. Go to: https://console.firebase.google.com/
2. Select your project
3. Navigate to: Firestore Database → Rules
4. Add the new `match` block for instructor_course_feedback_drafts
5. Click "Publish"

### Option 2: Firebase CLI
```bash
# Deploy rules only
firebase deploy --only firestore:rules

# Or deploy everything
firebase deploy
```

---

## Verification After Deployment

### Test 1: Draft Creation
1. Open instructor course feedback form
2. Fill in details and scores
3. Check browser console for: `AUTOSAVE: draftDocPath=users/{uid}/instructor_course_feedback_drafts/...`
4. Open Firestore Console → `users/{uid}/instructor_course_feedback_drafts`
5. Verify: Draft document exists

**If draft creation fails:**
- Check console for: `permission-denied` error
- Verify: Rules include the `instructor_course_feedback_drafts` match block
- Verify: `request.auth.uid == userId` matches your actual UID

---

### Test 2: Draft Reload
1. Refresh page or close/reopen browser
2. Navigate to: מיונים זמניים (בתהליך)
3. Click on draft
4. Verify: All data loads correctly

**If draft load fails:**
- Check console for: `permission-denied` on read operation
- Verify: `allow read` rule exists for draft subcollection

---

### Test 3: Draft Deletion (Finalize)
1. Complete all scores
2. Click "סיים משוב"
3. Check console for: `FINALIZE: Deleting draft from ...`
4. Open Firestore Console → `users/{uid}/instructor_course_feedback_drafts`
5. Verify: Draft document is deleted

**If draft deletion fails:**
- Check console for: `permission-denied` on delete operation
- Verify: `allow delete` rule exists for draft subcollection

---

## Complete Example (Full firestore.rules)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Allow users to read/write their own user document
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
      
      // ✅ INSTRUCTOR COURSE DRAFTS (per-user subcollection)
      match /instructor_course_feedback_drafts/{draftId} {
        allow read: if request.auth != null && request.auth.uid == userId;
        allow create: if request.auth != null && request.auth.uid == userId;
        allow update: if request.auth != null && request.auth.uid == userId;
        allow delete: if request.auth != null && request.auth.uid == userId;
      }
    }
    
    // Final instructor course feedbacks (shared collection)
    match /instructor_course_feedbacks/{feedbackId} {
      // Allow authenticated users to read all final feedbacks
      allow read: if request.auth != null;
      
      // Allow authenticated users to create final feedbacks
      allow create: if request.auth != null;
      
      // Allow creator to update their own feedbacks
      allow update: if request.auth != null && 
                      resource.data.createdBy == request.auth.uid;
      
      // Admins can delete (optional - adjust as needed)
      allow delete: if request.auth != null && 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin';
    }
    
    // Other collections (ranges, drills, etc.)
    // ... existing rules ...
  }
}
```

---

## Common Issues & Solutions

### Issue: "Missing or insufficient permissions"
**Cause:** Rules not deployed or incorrect match path

**Solution:**
1. Verify rules are deployed: `firebase deploy --only firestore:rules`
2. Check match path exactly matches: `users/{userId}/instructor_course_feedback_drafts/{draftId}`
3. Check `userId` variable matches in allow rules: `request.auth.uid == userId`

---

### Issue: "Cannot read property 'uid' of null"
**Cause:** User not authenticated

**Solution:**
1. Verify user is signed in: Check `FirebaseAuth.instance.currentUser`
2. Add auth check in rules: `allow read: if request.auth != null && ...`

---

### Issue: Drafts visible to other users
**Cause:** Missing userId check in rules

**Solution:**
- Ensure rule includes: `request.auth.uid == userId`
- This ensures users can ONLY access their own subcollection

---

## Testing Checklist

Before deployment:
- [ ] Rules syntax is valid (no errors in Firebase Console)
- [ ] `match /users/{userId}/instructor_course_feedback_drafts/{draftId}` exists
- [ ] All four operations allowed: read, create, update, delete
- [ ] Security check: `request.auth.uid == userId` present

After deployment:
- [ ] Test draft creation (autosave)
- [ ] Test draft reload (reopen form)
- [ ] Test draft update (change scores)
- [ ] Test draft deletion (finalize)
- [ ] Verify no permission-denied errors in console
- [ ] Verify drafts isolated per user (cannot see other users' drafts)

---

## Notes

- **No composite indexes required** for draft subcollection (simple orderBy on updatedAt)
- **Automatic cleanup**: Drafts deleted on finalize, no orphaned data
- **Privacy**: Each user's drafts are isolated in their own subcollection
- **Scalability**: Subcollection pattern scales better than flat collection with uid filter
