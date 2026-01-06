# Auto-Save Focus Fix - Range Training Tables

## Problem

Typing multi-digit numbers (e.g., "10") in the range training trainees table got interrupted after the first digit. User had to click the field again to continue typing.

**Root Cause:**
- TextField `onChanged` called `setState()` + `_scheduleAutoSave()`
- `setState()` triggered rebuild of the entire table widget
- New TextEditingController instances were created on each rebuild
- TextField lost focus when its controller was recreated

## Solution

Implemented debounced auto-save with stable controllers and focus nodes to prevent typing interruption.

### Key Changes

#### 1. Stable Controllers & Focus Nodes (Lines 92-96)
```dart
// ✅ STABLE CONTROLLERS: Prevent focus loss on rebuild
// Key format: "trainee_{idx}" for name fields, "trainee_{idx}_station_{stationIdx}" for numeric fields
final Map<String, TextEditingController> _textControllers = {};
final Map<String, FocusNode> _focusNodes = {};
```

**Purpose:** Store controllers/focus nodes in Maps keyed by trainee/station index so they persist across rebuilds.

#### 2. Controller/FocusNode Getters (Lines 110-135)
```dart
/// ✅ GET OR CREATE STABLE CONTROLLER: Returns existing or creates new controller
TextEditingController _getController(String key, String initialValue) {
  if (!_textControllers.containsKey(key)) {
    _textControllers[key] = TextEditingController(text: initialValue);
  } else {
    // Update text if it changed (e.g., loaded from Firestore)
    if (_textControllers[key]!.text != initialValue) {
      _textControllers[key]!.text = initialValue;
    }
  }
  return _textControllers[key]!;
}

/// ✅ GET OR CREATE STABLE FOCUS NODE: Returns existing or creates new focus node with blur listener
FocusNode _getFocusNode(String key) {
  if (!_focusNodes.containsKey(key)) {
    final node = FocusNode();
    node.addListener(() {
      if (!node.hasFocus) {
        // ✅ IMMEDIATE SAVE ON FOCUS LOSS: User finished editing this field
        debugPrint('🔵 FOCUS LOST: $key → triggering immediate save');
        _saveImmediately();
      }
    });
    _focusNodes[key] = node;
  }
  return _focusNodes[key]!;
}
```

**Purpose:** 
- Reuse existing controllers/nodes instead of creating new ones
- Auto-save immediately when user leaves a field (focus loss)
- Sync controller text when data changes externally (e.g., Firestore load)

#### 3. Debounced & Immediate Save (Lines 137-150)
```dart
/// ✅ DEBOUNCED AUTOSAVE: Schedule autosave after 700ms of inactivity
void _scheduleAutoSave() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = Timer(const Duration(milliseconds: 700), () {
    debugPrint('🔄 AUTOSAVE: Timer triggered (700ms debounce)');
    _saveTemporarily();
  });
}

/// ✅ IMMEDIATE SAVE: Triggered when user leaves a field (focus loss)
void _saveImmediately() {
  _autoSaveTimer?.cancel(); // Cancel pending debounced save
  debugPrint('⚡ IMMEDIATE SAVE: Saving now');
  _saveTemporarily();
}
```

**Purpose:**
- Debounced save: Wait 700ms after last keystroke (user still typing)
- Immediate save: Save instantly when user moves to next field (onSubmitted or blur)

#### 4. TextField onChanged - NO setState (Lines 1603-1615, 1725-1742, 2165-2178, 2225-2245)

**Mobile Name Field:**
```dart
onChanged: (v) {
  // ✅ ONLY UPDATE DATA: No setState, no save
  row.name = v;
  _scheduleAutoSave();
},
onSubmitted: (v) {
  // ✅ IMMEDIATE SAVE: User pressed Enter
  row.name = v;
  _saveImmediately();
},
```

**Mobile Numeric Fields:**
```dart
onChanged: (v) {
  final score = int.tryParse(v) ?? 0;
  // ... validation ...
  // ✅ ONLY UPDATE DATA: No setState, no save
  row.setValue(stationIndex, score);
  _scheduleAutoSave();
},
onSubmitted: (v) {
  // ✅ IMMEDIATE SAVE: User pressed Enter
  final score = int.tryParse(v) ?? 0;
  row.setValue(stationIndex, score);
  _saveImmediately();
},
```

**Desktop Table:** Same pattern applied to desktop table TextFields.

**Purpose:** Update data model directly without triggering rebuild, schedule debounced save.

#### 5. Save Without Rebuild (Lines 719-734, 862-865)

**Before:**
```dart
setState(() => _isSaving = true);
// ...
finally {
  if (mounted) {
    setState(() => _isSaving = false);
  }
}
```

**After:**
```dart
// ✅ Track saving state WITHOUT rebuilding (prevents focus loss)
_isSaving = true;
// ...
finally {
  // ✅ NO REBUILD: Reset flag WITHOUT setState to prevent focus loss
  _isSaving = false;
}
```

**Purpose:** Track saving state internally without triggering UI rebuild (prevents controller recreation).

#### 6. Dispose Controllers & Focus Nodes (Lines 152-165)
```dart
@override
void dispose() {
  _autoSaveTimer?.cancel();
  _attendeesCountController.dispose();
  // ✅ Dispose all controllers and focus nodes
  for (final controller in _textControllers.values) {
    controller.dispose();
  }
  for (final node in _focusNodes.values) {
    node.dispose();
  }
  _textControllers.clear();
  _focusNodes.clear();
  super.dispose();
}
```

**Purpose:** Properly clean up all resources to prevent memory leaks.

## Benefits

✅ **Smooth Typing Experience:** Users can type multi-digit numbers without interruption  
✅ **Auto-Save Still Works:** Data is saved automatically after 700ms of typing inactivity  
✅ **Immediate Save on Blur:** When user moves to next field, data is saved instantly  
✅ **No Focus Loss:** TextField stays focused during entire typing session  
✅ **No Performance Impact:** Debouncing prevents excessive Firestore writes  
✅ **Memory Safe:** All controllers and focus nodes are properly disposed  

## Testing Checklist

- [x] Type "10" in a numeric field → Both digits appear without focus loss
- [x] Type "123" in a numeric field → All three digits appear
- [x] Type in name field → Can type full name smoothly
- [x] Wait 700ms after typing → Auto-save triggers (check Firestore)
- [x] Press Enter after typing → Immediate save triggers
- [x] Tab to next field → Focus loss triggers immediate save
- [x] Switch between fields rapidly → No duplicate saves (debouncing works)
- [x] Resize window (mobile ↔ desktop) → Controllers persist
- [x] Code compiles: `flutter analyze` → No issues found!

## Files Modified

- `lib/range_training_page.dart`
  - Lines 92-165: State variables and initialization
  - Lines 1590-1615: Mobile name TextField
  - Lines 1710-1768: Mobile numeric TextFields
  - Lines 2150-2180: Desktop name TextField
  - Lines 2210-2260: Desktop numeric TextFields
  - Lines 719-734: _saveTemporarily() start
  - Lines 862-865: _saveTemporarily() finally block

## Technical Details

**Controller Key Format:**
- Mobile name: `trainee_{idx}`
- Mobile numeric: `trainee_{idx}_station_{stationIdx}`
- Desktop name: `desktop_trainee_{idx}`
- Desktop numeric: `desktop_trainee_{idx}_station_{stationIdx}`

**Save Triggers:**
1. **Debounced (700ms):** User stops typing → `_scheduleAutoSave()` → 700ms timer → `_saveTemporarily()`
2. **Immediate:** User presses Enter → `onSubmitted` → `_saveImmediately()` → instant save
3. **Immediate:** User tabs/clicks away → FocusNode listener → `_saveImmediately()` → instant save

**Why 700ms?**
- Previous: 600ms (too short for multi-digit typing)
- New: 700ms (allows smooth typing of 2-3 digit numbers)
- Balance: Long enough to prevent interruption, short enough to feel responsive

## Related Documentation

- [AUTOSAVE_REMOVAL_FIX.md](AUTOSAVE_REMOVAL_FIX.md) - Previous autosave improvements
- [SAVE_UX_IMPLEMENTATION_SUMMARY.md](SAVE_UX_IMPLEMENTATION_SUMMARY.md) - Save flow architecture
- [TRAINEE_TABLE_PERSISTENCE_FIX.md](TRAINEE_TABLE_PERSISTENCE_FIX.md) - Trainee data persistence

---
**Status:** ✅ COMPLETE  
**Tested:** 2024 - All functionality verified  
**Performance:** No regressions, improved UX
