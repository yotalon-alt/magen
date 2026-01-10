# Surprise Drills Location Selection Enhancement

## Summary
Successfully implemented dropdown location selection with manual text input option for Surprise Drills feedback, ensuring data is saved exclusively to the correct folder.

## Changes Applied

### 1. Added State Variables
**File:** `lib/range_training_page.dart`

Added two new state variables to track manual location selection:
- `bool isManualLocation` - Tracks if "Manual Location" is selected
- `String manualLocationText` - Stores the manually entered location text

### 2. Enhanced Settlement Selector
**File:** `lib/range_training_page.dart` - `_openSettlementSelectorSheet()`

Modified the settlement selector to:
- Include "Manual Location" option in dropdown for Surprise Drills mode only
- Show visual distinction (icon + orange color) for Manual Location option
- Set appropriate state when Manual Location is selected
- Clear manual location text when a predefined settlement is selected

### 3. Updated UI Layout
**File:** `lib/range_training_page.dart` - `build()` method

Restructured the settlement/location field section:
- **For Surprise Drills:**
  - Show dropdown with Golan settlements + "Manual Location" option
  - Display conditional text input field when "Manual Location" is selected
  - Use special icon and styling for manual location input
  
- **For Range Modes:**
  - Keep existing behavior (474 Ranges dropdown vs Shooting Ranges free text)

### 4. Updated Save Logic
**File:** `lib/range_training_page.dart`

#### Final Save (`_saveToFirestore`)
- Modified `baseData` to use the correct settlement value:
  - If `isManualLocation` is true, use `manualLocationText`
  - Otherwise, use `settlementName` or `selectedSettlement`
- Surprise Drills data now correctly stores location in both `name` and `settlement` fields

#### Temporary Save (`_saveTemporarily`)
- Updated payload to include:
  - `isManualLocation` boolean flag
  - `manualLocationText` string value
  - Correct `settlement` value based on manual/dropdown selection

### 5. Updated Load Logic
**File:** `lib/range_training_page.dart` - `_loadExistingTemporaryFeedback()`

Modified state restoration to:
- Load `isManualLocation` and `manualLocationText` from saved feedback
- Set `_settlementDisplayText` correctly:
  - "Manual Location" if manual mode
  - Otherwise show the actual settlement name

## Folder Assignment
All Surprise Drills feedbacks are now saved with:
```dart
'folder': 'משוב תרגילי הפתעה',
'module': 'surprise_drill',
'type': 'surprise_exercise',
```

This ensures they appear exclusively in the "Surprise Drills" folder in the Feedbacks list.

## Location Data Storage
The selected or manually entered location is stored in:
1. `settlement` field - Used for filtering and display
2. `name` field - Also contains the location (for Surprise Drills)
3. `isManualLocation` - Boolean flag for manual entry mode
4. `manualLocationText` - Raw manual text (preserved for editing)

## Export Support
The location data is available in:
- Standard feedback exports via `settlement` field
- Surprise Drills-specific exports
- All filtering operations in feedback list

## Testing Verification
✅ Code compiles without errors (`flutter analyze` passed)
✅ No impact on other feedback types or folders
✅ Backward compatible with existing Surprise Drills feedbacks

## User Workflow
1. Open Surprise Drills feedback form
2. Click on "מיקום" (Location) dropdown
3. Options shown:
   - All Golan settlements
   - "Manual Location" (with special icon)
4. If Manual Location selected:
   - Text input field appears below dropdown
   - User types custom location name
   - Value saved and appears in exports/filters
5. If predefined settlement selected:
   - Works as before
   - Manual location field hidden

## Technical Notes
- Manual Location is only available for Surprise Drills mode
- Range modes (474 Ranges, Shooting Ranges) unchanged
- All autosave functionality preserved
- Draft loading/saving fully compatible
