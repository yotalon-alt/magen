# Instructor Course Fix - Quick Test Guide

## 🚀 Deploy & Test (5 minutes)

### Step 1: Deploy Firestore Rules (30 seconds)
```bash
cd d:\ravvshatz_feedback\flutter_application_1
firebase deploy --only firestore:rules
```

**Expected output:**
```
✔ Deploy complete!
```

### Step 2: Rebuild App (1 minute)
```bash
flutter pub get
flutter run -d chrome  # Or your preferred device
```

### Step 3: Quick Functional Test (3 minutes)

#### A) Create Draft (30 seconds)
1. Login as instructor
2. תרגילים → מיונים לקורס מדריכים → הערכת מועמד
3. Fill in:
   - פיקוד: פיקוד הצפון
   - חטיבה: 474
   - שם מועמד: טסט 1
   - בוחן רמה: 8
4. **WAIT 1 second** (autosave triggers at 700ms)
5. Check browser console for:
   ```
   ✅ AUTOSAVE START
   AUTOSAVE: evalId=eval_...
   AUTOSAVE: status=draft
   ✅ AUTOSAVE END
   ```

**✅ Pass:** No permission-denied errors

#### B) View Draft (30 seconds)
1. Go back to main menu
2. משובים → מיונים זמניים
3. **Expected:** See "טסט 1" in list
4. Click "המשך"
5. **Expected:** Form loads with all data intact

**✅ Pass:** No missing-index errors, draft appears

#### C) Finalize (30 seconds)
1. In draft form, fill remaining fields
2. Click "שמור"
3. Check console for:
   ```
   ✅ FINALIZE START
   FINALIZE: Updating status from draft to suitable
   ✅ FINALIZE: Status updated successfully!
   ```

**✅ Pass:** No errors, success message appears

#### D) View Final (30 seconds)
1. Go to משובים → מיונים לקורס מדריכים
2. Click "מתאימים" button
3. **Expected:** See "טסט 1" in list
4. Click to view details
5. **Expected:** All scores visible

**✅ Pass:** Evaluation appears in correct final list

---

## ✅ Success Criteria

All of these should be TRUE:
- ✅ No `[cloud_firestore/permission-denied]` errors
- ✅ No `[cloud_firestore/failed-precondition]` / missing-index errors
- ✅ Drafts appear in "מיונים זמניים" list
- ✅ Finals appear in "מתאימים"/"לא מתאימים" lists
- ✅ All data persists correctly

---

## ❌ Troubleshooting

### Error: permission-denied

**Check:**
1. Are rules deployed? `firebase deploy --only firestore:rules`
2. Does doc have `userId` field matching your UID?

**Debug in Firebase Console:**
- Firestore → Rules tab
- Should see: `match /instructor_course_evaluations/{evalId}`

### Error: missing-index

**This should NOT happen with new code!**

**Check query pattern:**
```dart
// ✅ GOOD (no composite index required)
.where('userId', isEqualTo: uid)
.orderBy('updatedAt')

// ❌ BAD (composite index required)
.where('status', isEqualTo: 'draft')
.orderBy('updatedAt')
```

---

## 📝 Final Checklist

- [ ] Rules deployed successfully
- [ ] Draft autosave works (no permission errors)
- [ ] Draft appears in "מיונים זמניים" 
- [ ] Finalize updates status (no errors)
- [ ] Final appears in correct list
- [ ] No console errors

**All checked?** 🎉 Deploy to production: `firebase deploy`
