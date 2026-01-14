# Long Range Final Save - Quick Test Checklist

## ⚡ Quick Verification (2 minutes)

### **Test 1: Long Range Immediate Save** ⭐ MAIN FIX

```
□ Open app → Range training
□ Select: טווח רחוק (Long Range)
□ Choose folder: מטווחים 474
□ Enter settlement
□ Add 1 trainee
□ Add 1 stage
□ Fill textfields with data
□ Press "שמירה סופית - מטווח" IMMEDIATELY
□ ✅ Save succeeds without error
□ ✅ Data appears in final list
□ ✅ All textfield values saved correctly
```

**Expected**: ✅ Works in ONE click (no navigation needed)
**Previous**: ❌ Required exit → re-enter → save again

---

## 🔍 Code Verification (30 seconds)

### **Fix #1: Focus Unfocus Added?**
```bash
grep -n "Force unfocus + rebuild" lib/range_training_page.dart
```
**Expected**: Line ~1354 (before setState in _saveToFirestore)

### **Fix #2: Merge Mode in UPDATE?**
```bash
grep "UPDATE MODE" -A5 lib/range_training_page.dart | grep "SetOptions"
```
**Expected**: `SetOptions(merge: true)`

### **Fix #3: Merge Mode in CREATE?**
```bash
grep "CREATE MODE" -A10 lib/range_training_page.dart | grep "SetOptions"
```
**Expected**: `SetOptions(merge: true)`

---

## 📊 Console Checks

### **Look for this log**:
```
✅ FINAL_SAVE: Force unfocus + rebuild complete
```
If present → Focus fix is working ✅

### **Check Firestore write**:
```
WRITE: UPDATE MODE - Finalizing feedback id=abc123
```
Or:
```
WRITE: CREATE MODE - New auto-ID: xyz789
```

---

## 🐛 Quick Debug

**If save still doesn't work**:

1. **Check data in Firestore document**:
   - `trainees[0].name`: Should have actual name (not empty)
   - `trainees[0].totalHits`: Should have number (not 0)
   - `stations[0].bulletsCount`: Should match input

2. **If fields are empty**:
   - Focus unfocus timing issue
   - Try increasing delay from 50ms to 100ms

3. **If fields are correct but save fails**:
   - Check Firestore permissions
   - Check network connectivity

---

## ✅ Success = All Green

□ Focus unfocus code present (line ~1354)
□ SetOptions(merge: true) in UPDATE (line ~2089)
□ SetOptions(merge: true) in CREATE (line ~2118)
□ Long range saves immediately (no navigation)
□ All textfield data captured correctly
□ Short range still works (regression test)

**Status**: Ready for user testing! 🚀
