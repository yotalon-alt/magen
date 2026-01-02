import 'package:flutter/material.dart';

/// Standard back button for RTL Hebrew interface
/// ALWAYS visible - positioned consistently in top-right corner (leading position in RTL AppBar)
/// When no navigation history exists, navigates to safe default (Main screen)
///
/// Usage in AppBar:
/// ```dart
/// AppBar(
///   title: Text('Page Title'),
///   leading: StandardBackButton(),
/// )
/// ```
class StandardBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? color;
  final String? tooltip;

  const StandardBackButton({
    super.key,
    this.onPressed,
    this.color,
    this.tooltip,
  });

  /// Navigate back or to safe default (Main screen)
  void _handleBackNavigation(BuildContext context) {
    // Check if we can navigate back in current navigator
    final canPop = Navigator.of(context).canPop();

    if (canPop) {
      // Normal back navigation
      Navigator.pop(context);
    } else {
      // No history - navigate to safe default (Main screen)
      // This handles direct URL access or deep links
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ALWAYS show back button (never hide)
    return IconButton(
      icon: const Icon(
        Icons.arrow_forward,
      ), // arrow_forward points right in RTL
      color: color,
      onPressed: onPressed ?? () => _handleBackNavigation(context),
      tooltip: tooltip ?? 'חזרה',
      iconSize: 24,
      padding: const EdgeInsets.all(8),
    );
  }
}

/// Standard AppBar factory with consistent back button
/// Automatically includes back button when navigation stack allows
AppBar buildStandardAppBar({
  required String title,
  List<Widget>? actions,
  VoidCallback? onBackPressed,
  PreferredSizeWidget? bottom,
  Color? backgroundColor,
  Color? foregroundColor,
}) {
  return AppBar(
    title: Text(title),
    leading: StandardBackButton(onPressed: onBackPressed),
    actions: actions,
    bottom: bottom,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
  );
}
