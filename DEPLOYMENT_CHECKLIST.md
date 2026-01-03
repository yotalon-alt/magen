# Deployment Checklist - Instructor Course Fix

## Pre-Deployment Validation ✅

### 1. Code Review
- [x] firestore.rules updated with instructor_course_evaluations
- [x] instructor_course_feedback_page.dart refactored (autosave/finalize)
- [x] screenings_in_progress_page.dart updated (draft query)
- [x] instructor_course_selection_feedbacks_page.dart updated (final query)
- [x] shared_preferences import removed
- [x] All queries use userId-only (no composite index)
- [x] All status updates atomic (no write+delete)

### 2. Static Analysis
```bash
flutter analyze
```
**Expected:** No issues found!

### 3. Compilation Check
```bash
flutter pub get
```
**Expected:** No errors

---

## Deployment Steps

### Step 1: Deploy Firestore Rules
```bash
firebase deploy --only firestore:rules
```

**Verify:**
- ✅ Shows "Deploy complete!"
- ✅ No errors
- ✅ Rules include instructor_course_evaluations

### Step 2: Test on Dev Environment
```bash
flutter run -d chrome --debug
```

**Test Flow:**
1. Create draft → autosave → check console (no permission errors)
2. View in "מיונים זמניים" (no missing-index errors)
3. Reopen draft → verify data intact
4. Finalize → check status update
5. View in "מתאימים"/"לא מתאימים"

**Expected:** All tests pass ✅

### Step 3: Deploy to Production
```bash
firebase deploy
```

**Verify:**
- ✅ Rules deployed
- ✅ Hosting deployed (if applicable)
- ✅ Functions deployed (if applicable)

---

## Post-Deployment Verification

### 1. Smoke Test (2 minutes)
1. Login as instructor
2. Create new evaluation
3. Fill fields, wait 1 second (autosave)
4. Check browser console: No errors
5. Navigate away, come back
6. Check "מיונים זמניים": Draft appears
7. Open draft: Data intact
8. Finalize evaluation
9. Check final list: Appears correctly

### 2. Firebase Console Check
1. Open Firestore Database
2. Navigate to `instructor_course_evaluations`
3. Find test document
4. Verify structure:
   - ✅ userId field present
   - ✅ status field correct ("draft"/"suitable"/"notSuitable")
   - ✅ fields map populated
   - ✅ timestamps present

### 3. Error Monitoring
**Check for 24 hours:**
- Firebase Console → Functions → Logs
- Browser console in production
- User reports

**Expected:** Zero permission-denied or missing-index errors

---

## Rollback Plan (If Needed)

### Quick Rollback
```bash
# Revert code and rules
git checkout HEAD~1 firestore.rules lib/
firebase deploy --only firestore:rules
flutter pub get
firebase deploy
```

### Gradual Rollback
1. Keep new rules (no harm)
2. Revert code only
3. Monitor for 1 hour
4. Full rollback if needed

---

## Success Metrics

### Day 1 (Immediate)
- [ ] Zero permission-denied errors
- [ ] Zero missing-index errors
- [ ] All drafts save successfully
- [ ] All finals appear correctly

### Week 1 (Ongoing)
- [ ] No user-reported issues
- [ ] Firestore read costs reduced ~50%
- [ ] Firestore write costs reduced ~50%
- [ ] Response times improved

---

## Emergency Contacts

**If issues arise:**
1. Check Firebase Console → Firestore → Usage
2. Check Firebase Console → Functions → Logs
3. Review error logs in browser console
4. Rollback if critical issue found

---

## Completion Sign-Off

**Date:** __________

**Deployed by:** __________

**Tests Passed:** [ ] Yes  [ ] No

**Production Verified:** [ ] Yes  [ ] No

**Issues Found:** ______________________________

**Status:** [ ] Success  [ ] Rollback Required

---

## Next Steps

1. Monitor for 24 hours
2. Gather user feedback
3. Review Firestore usage stats
4. Document lessons learned
5. Plan next improvement

**🎉 Deployment Complete!**
