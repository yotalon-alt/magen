# Instructor Course Screenings - Shared Visibility Fix

## 🎯 Problem
Instructors could only see their own submissions in "מיונים לקורס מדריכים". Each instructor's feedbacks were isolated.

## ✅ Solution
Changed to **shared visibility** - ALL instructors and admins now see ALL final submissions in both folders:
- **מתאימים לקורס מדריכים** (Suitable)
- **לא מתאימים לקורס מדריכים** (Not Suitable)

---

## 📋 Changes Applied

### 1. **Query Logic** (`instructor_course_selection_feedbacks_page.dart`)

**Before:**
```dart
// ❌ Filtered by ownerUid - only showed current user's submissions
.where('ownerUid', isEqualTo: uid)
```

**After:**
```dart
// ✅ Shared query - all instructors see all final submissions
.where('status', isEqualTo: 'final')
.where('isSuitable', isEqualTo: isSuitable)
.orderBy('createdAt', descending: true)
```

### 2. **Firestore Security Rules** (`firestore.rules`)

**Updated Rule:**
```javascript
match /instructor_course_evaluations/{evalId} {
  // ✅ All instructors/admins can read all final submissions
  allow read: if request.auth != null && (
    (isInstructor() || isAdmin()) && resource.data.status == 'final'
    || resource.data.ownerUid == request.auth.uid  // owners can read drafts
  );
  
  allow create: if request.auth != null && (isInstructor() || isAdmin());
  allow update: if request.auth != null && (
    resource.data.ownerUid == request.auth.uid || isAdmin()
  );
  allow delete: if isAdmin();
}
```

**Key Points:**
- ✅ **Read**: All instructors/admins can read `status == 'final'` docs
- ✅ **Read**: Owners can read their own drafts
- ✅ **Update**: Only owner or admin can update
- ✅ **Delete**: Only admin can delete

### 3. **Composite Index** (`firestore.indexes.json`)

Added index for efficient querying:
```json
{
  "collectionGroup": "instructor_course_evaluations",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "isSuitable", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

---

## 🚀 Deployment Steps

### Step 1: Deploy Firestore Rules
```bash
cd d:\ravvshatz_feedback\flutter_application_1
firebase deploy --only firestore:rules
```

### Step 2: Deploy Composite Index
```bash
firebase deploy --only firestore:indexes
```

**Note:** Index creation takes 1-5 minutes. Monitor progress:
```bash
firebase firestore:indexes
```

### Step 3: Deploy Flutter Web App
```bash
flutter build web
firebase deploy --only hosting
```

---

## ✅ Testing Checklist

### Test with 2 Instructor Accounts

**Instructor A:**
1. Navigate to: תרגילים → מיונים לקורס מדריכים
2. Create a "מתאימים" feedback (suitable)
3. Create a "לא מתאימים" feedback (not suitable)
4. Finalize both

**Instructor B (different account):**
1. Navigate to: משובים → מיונים לקורס מדריכים
2. Click "מתאימים לקורס מדריכים"
   - ✅ Should see Instructor A's suitable feedback
3. Go back, click "לא מתאימים לקורס מדריכים"
   - ✅ Should see Instructor A's not suitable feedback

**Admin:**
- ✅ Should see all feedbacks from both instructors in both folders

---

## 📊 Data Model

**Collection:** `instructor_course_evaluations`

**Fields:**
```javascript
{
  status: "draft" | "final",
  isSuitable: true | false,  // מתאים / לא מתאים
  candidateName: string,
  ownerUid: string,          // creator's UID
  ownerName: string,         // creator's name (optional)
  createdAt: Timestamp,
  updatedAt: Timestamp,
  fields: {
    "בוחן רמה": { value: 1-5 },
    "הדרכה טובה": { value: 1-5 },
    // ... other rubric fields
  }
}
```

---

## 🔒 Security Model

| Action | Drafts | Finals |
|--------|--------|--------|
| **Create** | ✅ Instructor/Admin | ✅ Instructor/Admin |
| **Read** | ✅ Owner only | ✅ **All** Instructors/Admins |
| **Update** | ✅ Owner/Admin | ✅ Owner/Admin |
| **Delete** | ✅ Admin only | ✅ Admin only |

---

## 🐛 Troubleshooting

### Issue: "Index required" error
**Solution:** Wait for index creation (check with `firebase firestore:indexes`)

### Issue: "Permission denied"
**Solution:** 
1. Verify user has `role: 'instructor'` or `role: 'admin'` in `/users/{uid}` document
2. Re-deploy rules: `firebase deploy --only firestore:rules`

### Issue: Instructors still only see their own
**Solution:**
1. Check Firestore console - verify `status: 'final'` on documents
2. Check browser console for query errors
3. Verify composite index is active (not building)

---

## 📝 Migration Notes

**No data migration needed!**

Existing documents in `instructor_course_evaluations` will work immediately:
- Documents with `status: 'final'` become visible to all instructors
- Documents with `status: 'draft'` remain private to owner

**Optional cleanup:**
If old data exists in legacy collections (`instructor_course_feedbacks`, `instructor_course_selection_suitable/not_suitable`), you can archive or delete them - they are no longer used.

---

## ✨ Summary

**Before:** Each instructor saw only their own submissions (isolated)  
**After:** All instructors see all final submissions (shared collaboration)

**Benefits:**
- ✅ Better collaboration between instructors
- ✅ Comprehensive view of all candidates
- ✅ Consistent evaluation standards
- ✅ No duplicate evaluations
