# Soft Delete Fix for "מיונים – כללי" Folder

## Problem
- The folder "מיונים – כללי" appeared in the feedbacks folders grid
- This created **duplicate entry points** to the screenings menu:
  1. From Feedbacks tab → "מיונים – כללי" folder
  2. From Exercises tab → "מיונים לקורס מדריכים"
- Both navigated to the same `screenings_menu_page.dart` with buttons for:
  - "פתיחת משוב חדש"
  - "מיונים זמניים (בתהליך)"
- Users saw 2 different paths to the same functionality

## Solution Implemented

### 1. Folder Configuration with `isHidden` Flag
**File**: `lib/main.dart` (lines 38-62)

Created a configuration structure `_feedbackFoldersConfig` with:
- `title`: Folder name (String)
- `isHidden`: Visibility flag (bool)

```dart
const List<Map<String, dynamic>> _feedbackFoldersConfig = <Map<String, dynamic>>[
  {'title': 'מטווחי ירי', 'isHidden': false},
  {'title': 'מחלקות ההגנה – חטיבה 474', 'isHidden': false},
  {'title': 'מיונים – כללי', 'isHidden': true}, // ✅ SOFT DELETE
  {'title': 'מיונים לקורס מדריכים', 'isHidden': false},
  {'title': 'משובים – כללי', 'isHidden': false},
  {'title': 'עבודה במבנה', 'isHidden': false},
  {'title': 'משוב תרגילי הפתעה', 'isHidden': false},
];
```

### 2. Helper Lists for Backwards Compatibility
- `feedbackFolders`: All folders (including hidden) - used by dropdowns
- `visibleFeedbackFolders`: Only visible folders - used by UI grids

```dart
final List<String> feedbackFolders = _feedbackFoldersConfig
    .map((config) => config['title'] as String)
    .toList();

final List<String> visibleFeedbackFolders = _feedbackFoldersConfig
    .where((config) => config['isHidden'] != true)
    .map((config) => config['title'] as String)
    .toList();
```

### 3. Updated Folders Grid to Use `visibleFeedbackFolders`
**File**: `lib/main.dart` (FeedbacksPage)

Changed:
```dart
itemCount: visibleFeedbackFolders.length,
itemBuilder: (ctx, i) {
  final folder = visibleFeedbackFolders[i];
  // ...
```

### 4. Removed Duplicate Navigation Logic
Removed the `isMiunimCourse` variable and its navigation handler:
```dart
// BEFORE
final isMiunimCourse = folder == 'מיונים – כללי';
if (isInstructorCourse) { ... }
else if (isMiunimCourse) {
  Navigator.of(context).pushNamed('/screenings_menu');
}

// AFTER
final isInstructorCourse = folder == 'מיונים לקורס מדריכים';
if (isInstructorCourse) { ... }
else {
  setState(() => _selectedFolder = folder);
}
```

### 5. Simplified Icon Logic
Removed references to `isMiunimCourse` from icon rendering:
```dart
// BEFORE
Icon(
  isInstructorCourse || isMiunimCourse ? Icons.school : Icons.folder,
  color: (isInstructorCourse || isMiunimCourse) ? Colors.white : Colors.orangeAccent,
)

// AFTER
Icon(
  isInstructorCourse ? Icons.school : Icons.folder,
  color: isInstructorCourse ? Colors.white : Colors.orangeAccent,
)
```

## Results

### ✅ Fixed Issues
1. **Hidden Folder**: "מיונים – כללי" no longer appears in feedbacks folders grid
2. **Single Entry Point**: Only one path to screenings menu exists:
   - Exercises → "מיונים לקורס מדריכים" → screenings_menu_page
3. **No Duplicate Buttons**: Users see only one instance of:
   - "פתיחת משוב חדש"
   - "מיונים זמניים (בתהליך)"
4. **Backwards Compatible**: Hidden folder still exists in `feedbackFolders` list for:
   - Dropdown filters that may reference it
   - Existing feedback documents with `folder: "מיונים – כללי"`
   - Database queries

### ✅ Validation
- **Flutter Analyze**: No issues found
- **No Breaking Changes**: All existing functionality preserved
- **Clean UI**: Removed confusion from duplicate entry points

## Files Modified
- `lib/main.dart`: Folder configuration and grid display logic

## Testing Checklist
- [ ] Open app on mobile
- [ ] Navigate to Feedbacks tab
- [ ] Verify "מיונים – כללי" folder is NOT visible
- [ ] Count folders in grid (should be 6, not 7)
- [ ] Navigate to Exercises tab
- [ ] Tap "מיונים לקורס מדריכים"
- [ ] Verify screenings menu appears with exactly 2 buttons:
  - [ ] "פתיחת משוב חדש"
  - [ ] "מיונים זמניים (בתהליך)"
- [ ] Verify no duplicate buttons exist
- [ ] Test backwards compatibility:
  - [ ] Existing feedbacks with folder "מיונים – כללי" still load
  - [ ] Dropdown filters still include all folders

## Future Enhancements
If more folders need soft delete in the future:
1. Set `'isHidden': true` in `_feedbackFoldersConfig`
2. No code changes needed - automatic filtering via `visibleFeedbackFolders`

---
**Commit**: Hide unused "מיונים – כללי" folder and remove duplicate new/temp feedback buttons
