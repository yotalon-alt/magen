# StandardBackButton - Developer Guide

## Quick Start

### Basic Usage (Most Common)
```dart
AppBar(
  title: const Text('Page Title'),
  leading: const StandardBackButton(),
)
```

### With Custom Handler
```dart
AppBar(
  title: const Text('Page Title'),
  leading: StandardBackButton(
    onPressed: () async {
      // Your custom logic here
      if (await confirmExit()) {
        Navigator.pop(context);
      }
    },
  ),
)
```

### With Custom Color (for dark backgrounds)
```dart
StandardBackButton(
  onPressed: () => customAction(),
  color: Colors.white,
)
```

## Features

- ✅ **Always Visible**: Never hides, even on root screens or direct URL access
- ✅ **Smart Navigation**: Goes back if possible, otherwise navigates to Main screen
- ✅ **Consistent**: Same size, padding, and tooltip across entire app
- ✅ **RTL-Aware**: Uses correct arrow direction for Hebrew RTL layout
- ✅ **Customizable**: Optional custom handler, color, and tooltip
- ✅ **Deep Link Safe**: Handles direct access gracefully (no dead ends)

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `onPressed` | `VoidCallback?` | Smart navigation* | Custom back button action |
| `color` | `Color?` | `null` | Icon color (inherits theme color by default) |
| `tooltip` | `String?` | `'חזרה'` | Tooltip text shown on hover |

*SmNavigation Behavior

### Default Behavior (No Custom Handler)

When user taps the back button, `StandardBackButton` performs **smart navigation**:

```dart
void _handleBackNavigation(BuildContext context) {
  final canPop = Navigator.of(context).canPop();
  
  if (canPop) {
    // Normal back navigation - history exists
    Navigator.pop(context);
  } else {
    // No history - navigate to safe default (Main screen)
    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }
}
```

**Why This Matters:**
- ✅ Handles direct URL access (web)
- ✅ Handles deep links (mobile)
- ✅ Prevents users from feeling "trapped"
- ✅ Always provides an escape route

**Safe Default Route:**
- Target: `/main` (MainScreen with BottomNavigationBar)
- Provides: Home, Exercises, Feedbacks, Statistics, Materials tabs
- Clears navigation stack to prevent loopstory exists, performs `Navigator.pop()`. Otherwise, navigates to Main screen (`/main`).

## Examples from Codebase

### Example 1: Standard AppBar
```dart
// File: lib/main.dart - FeedbackFormPage
AppBar(
  title: Text('משוב - ${selectedExercise ?? ''}'),
  leading: const StandardBackButton(),
)
```

### Example 2: Custom Handler with Draft Check
```dart
// File: lib/instructor_course_feedback_page.dart
AppBar(
  title: const Text('מיון לקורס מדריכים'),
  leading: StandardBackButton(
    onPressed: () async {
      if (hasDraft) {
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('יציאה ללא שמירה'),
            content: const Text('יש משוב בתהליך שלא נשמר. האם אתה בטוח שברצונך לצאת?'),
            actions: [
              TextButton(
   Examples froAlways Visible on All Pages
```dart
// File: lib/main.dart - ReadinessPage, AlertsPage, ExercisesPage, etc.
// Back button ALWAYS shows, even when accessed directly
AppBar(
  title: const Text('Page Title'),
  leading: const StandardBackButton(), // Never hides
)
```

### Example 5: m Codebaseor.pop(ctx, false),
                child: const Text('הישאר'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('צא בכל זאת'),
              ),
            ],
          ),
        );
        if (shouldLeave != true) return;
      }
      if (!context.mounted) return;
      Navigator.pop(context);
    },
  ),
)
```

### Example 3: Custom Action (No Route Pop)
```dart
// File: lib/instructor_course_selection_feedbacks_page.dart
StandardBackButton(
  onPressed: () => setState(() {
    _selectedCategory = null;
    _feedbacks = [];
  }),
  color: Colors.white,
)
```

### Example 4: Using the Helper Function
```dart
// Quick AppBar creation
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: buildStandardAppBar(
      title: 'Page Title',
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => openSettings(),
        ),
      ],
    ),
    body: Y // Button disappears - user gets stuck!
)
```

### ✅ Correct: Always Visible
```dart
AppBar(
  leading: const StandardBackButton(), // Always shows, smart navigation

- [ ] Remove old `IconButton` with `Icons.arrow_forward`
- [ ] Add `import 'widgets/standard_back_button.dart';` (or `import '../widgets/standard_back_button.dart';` for pages in subdirectories)
- [ ] Replace with `leading: const StandardBackButton()`
- [ ] If custom behavior needed, use `leading: StandardBackButton(onPressed: ...)`
- [ ] Run `flutter analyze` to verify no errors

## Common Pitfalls

### ❌ Wrong: Manual IconButton
```dart
AppBar(
  title: const Text('Title'),
  leading: IconButton(
    icon: const Icon(Icons.arrow_forward),
    oNormal Navigation**: Navigate via menu, verify back button returns to previous screen
3. **Direct Access Test**: Open page via direct URL (web) and verify back button navigates to Main screen
4. **Deep Link Test**: Access page via deep link and verify safe fallback
5. **Always Visible Test**: Verify button NEVER disappears on any screen
6. **Custom Handler Test**: If using custom handler, test all code paths
7``

### ✅ Correct: StandardBackButton
```dart
AppBar(
  title: const Text('Title'),
  leading: const StandardBackButton(),
)
```

### ❌ Wrong: Manual canPop Check
```dart
AppBar(
  leading: Navigator.canPop(context) 
    ? IconButton(...)
    : null,
)
```

### ✅ Correct: Auto-Hide Built-In
```dart
AppBar(
  leading: const StandardBackButton(), // Automatically hides when can't pop
)
```

## RTL (Right-to-Left) Notes

- Uses `Icons.arrow_forward` which points **right** in RTL layout
- The `leading` property positions the button on the **right** side in RTL
- This matches Hebrew user expectations for back navigation
- Never use `Icons.arrow_back` in this app (it points left in RTL)

## Testing

To verify your back button implementation:

1. **Visual Test**: Navigate to your page and verify button appears in top-right
2. **Root Screen Test**: Navigate to app root and verify button hides
3. **Functionality Test**: Tap button and verify it navigates back correctly
4. **Custom Handler Test**: If using custom handler, test all code paths
5. **Flutter Analyze**: Run `flutter analyze` to ensure no compilation errors

## Support

If you encounter issues with `StandardBackButton`:

1. Check import statement is correct
2. Verify `Navigator.canPop()` works as expected in your context
3. For custom handlers, ensure context is valid when accessing Navigator
4. Review examples in this guide or existing pages in codebase

---
**Location:** `lib/widgets/standard_back_button.dart`  
**Documentation:** This file  
**Examples:** See any page in `lib/main.dart`, `lib/instructor_course_*.dart`, etc.
