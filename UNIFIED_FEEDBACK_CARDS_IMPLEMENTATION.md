# Unified Feedback List Cards + Delete + Auto Blue-Tag Mapping

## Summary
Implemented a unified feedback card system across ALL feedback list pages (except instructor course) with:
1. Consistent UI matching "משוב זמני - מטווחים" design
2. Delete functionality with confirmation for all saved feedbacks
3. Automatic blue tag mapping from document data to Hebrew labels
4. Reusable widget to eliminate code duplication

## Changes Made

### 1. New Reusable Widget: `FeedbackListTileCard`
**File**: `lib/widgets/feedback_list_tile_card.dart` (NEW)

Features:
- LEFT: Red trash icon button (if permitted) or decorative icon
- CENTER: Title + metadata lines (instructor, participants, date)
- BLUE tag/chip with auto-mapped feedback type label
- RIGHT: Arrow icon button to open/edit
- RTL alignment throughout

### 2. Blue Tag Mapping Function
**Function**: `getBlueTagLabelFromDoc(Map<String, dynamic> data)`

Priority order for reading type:
1. `data['feedbackType']`
2. `data['rangeType']`  
3. `data['templateId']`
4. `data['folder']` / `data['category']`

Mappings (case-insensitive, supports synonyms):
- `short_range/short/קצרים` → "טווח קצר"
- `long_range/long/ארוכים` → "טווח רחוק"
- `surprise/הפתעה` → "תרגיל הפתעה"
- `structure/במבנה` → "עבודה במבנה"
- `defense/474/הגנה` → "הגנה 474"
- `general/כללי` → "משוב כללי"
- Default → "משוב"

### 3. Updated Pages to Use Unified Card

#### A. Main Feedbacks Page (Saved Feedbacks)
**File**: `lib/main.dart`

Changes:
- Added import: `widgets/feedback_list_tile_card.dart`
- Added `_confirmDeleteFeedback()` method with confirmation dialog
- Added `_deleteFeedback()` method to delete from Firestore + local cache
- Updated `ListView.builder` to use `FeedbackListTileCard`
- Permission check: Admin OR feedback creator can delete
- Blue tag auto-mapped from feedback data fields

#### B. Range Temp Feedbacks Page
**File**: `lib/range_temp_feedbacks_page.dart`

Changes:
- Added import: `widgets/feedback_list_tile_card.dart`
- Removed old `Card` widget with manual ListTile construction
- Replaced with `FeedbackListTileCard`
- Removed unused `_getRangeTypeLabel()` function
- Blue tag auto-mapped from document data

#### C. Surprise Drills Temp Feedbacks Page
**File**: `lib/surprise_drills_temp_feedbacks_page.dart`

Changes:
- Added import: `widgets/feedback_list_tile_card.dart`
- Removed old `Card` widget with manual ListTile construction
- Replaced with `FeedbackListTileCard`
- Blue tag auto-mapped from document data
- Removed redundant Directionality wrapper (parent already RTL)

## UI Consistency

All feedback list cards now have identical layout:

```
┌────────────────────────────────────────────────────┐
│ 🗑️  Title Text                    [טווח קצר] →   │
│     מדריך: שם המדריך                              │
│     משתתפים: 15                                    │
│     תאריך: 07/01/2026 14:30                       │
└────────────────────────────────────────────────────┘
```

- LEFT icon changes based on permission:
  - If can delete: Red trash icon
  - If cannot delete: Colored icon matching feedback type
- BLUE tag always present with auto-mapped label
- RIGHT arrow always present for navigation

## Delete Functionality

### Permissions
- **Admin**: Can delete ANY feedback
- **Instructor**: Can delete ONLY their own feedbacks
- **Check**: `currentUser?.role == 'Admin' || f.instructorName == currentUser?.name`

### Flow
1. User taps trash icon
2. Confirmation dialog appears: "האם למחוק את המשוב [title]? פעולה זו בלתי הפיכה."
3. If confirmed:
   - Delete document from Firestore (`feedbacks` collection)
   - Remove from local cache (`feedbackStorage`)
   - Show success SnackBar
   - Refresh UI with `setState()`
4. If error: Show error SnackBar

### Exception
**Instructor Course feedbacks** ("מיונים לקורס מדריכים") were NOT modified - their UI remains unchanged per requirements.

## Testing Checklist

### Visual Consistency
- [ ] All feedback lists match "משוב זמני - מטווחים" design
- [ ] Blue tags display correct Hebrew labels
- [ ] Cards have proper RTL alignment
- [ ] Trash icon shows only when permitted
- [ ] Arrow icon always visible

### Delete Functionality
- [ ] Admin can delete any feedback
- [ ] Instructor can delete only their own feedbacks
- [ ] Confirmation dialog appears before delete
- [ ] Success message after delete
- [ ] List refreshes immediately after delete
- [ ] Error message on Firestore failure

### Pages to Test
1. **Feedbacks → משובים – כללי** (saved feedbacks)
2. **Feedbacks → מטווחי ירי** (saved range feedbacks)
3. **Feedbacks → מחלקות ההגנה – חטיבה 474**
4. **Feedbacks → משוב תרגילי הפתעה**
5. **Exercises → מטווחים → משוב זמני** (temp range drafts)
6. **Exercises → תרגילי הפתעה → משובים זמניים** (temp surprise drafts)

### Blue Tag Accuracy
Test that labels match feedback type:
- [ ] Range short → "טווח קצר"
- [ ] Range long → "טווח רחוק"
- [ ] Surprise drill → "תרגיל הפתעה"
- [ ] General → "משוב כללי"
- [ ] Defense 474 → "הגנה 474"
- [ ] Structure → "עבודה במבנה"

## Files Modified
1. `lib/widgets/feedback_list_tile_card.dart` (NEW)
2. `lib/main.dart` (FeedbacksPage)
3. `lib/range_temp_feedbacks_page.dart`
4. `lib/surprise_drills_temp_feedbacks_page.dart`

## Files NOT Modified
- `lib/instructor_course_feedback_page.dart` (excluded per requirements)
- `lib/pages/screenings_menu_page.dart` (excluded per requirements)
- Any instructor course related files

## Flutter Analyze
✅ **No issues found!**

---
**Commit**: Unify feedback list cards + delete + auto blue-tag mapping (exclude instructor course)
