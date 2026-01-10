import 'package:flutter/material.dart';

/// Automatic blue tag mapping from feedback document data
/// Used by all feedback list cards for consistent labeling
/// Returns the FEEDBACK TYPE label only (not folder, not location)
String getBlueTagLabelFromDoc(Map<String, dynamic> data) {
  // ====== FEEDBACK TYPE DETECTION ======
  // Priority: exercise > module+rangeType > feedbackType > legacy inference

  final exercise = (data['exercise'] ?? '').toString();
  final module = (data['module'] ?? '').toString().toLowerCase();
  final rangeType = (data['rangeType'] ?? '').toString();
  final feedbackType = (data['feedbackType'] ?? '').toString().toLowerCase();

  // 1. Check exercise field for specific exercise types
  if (exercise == 'מעגל פתוח') return 'מעגל פתוח';
  if (exercise == 'מעגל פרוץ') return 'מעגל פרוץ';
  if (exercise == 'סריקות רחוב') return 'סריקות רחוב';

  // 2. Check module for surprise drills
  if (module == 'surprise_drill' || exercise == 'תרגילי הפתעה') {
    return 'תרגילי הפתעה';
  }

  // 3. Check for range types (Short/Long Range)
  if (module == 'shooting_ranges' || exercise == 'מטווחים') {
    if (rangeType == 'קצרים') return 'טווח קצר';
    if (rangeType == 'ארוכים') return 'טווח רחוק';
    // Infer from feedbackType if rangeType is missing
    if (feedbackType.contains('short') || feedbackType.contains('קצר')) {
      return 'טווח קצר';
    }
    if (feedbackType.contains('long') ||
        feedbackType.contains('רחוק') ||
        feedbackType.contains('ארוך')) {
      return 'טווח רחוק';
    }
    // Default for ranges without specific type
    return 'מטווח';
  }

  // 4. Legacy inference from feedbackType field
  if (feedbackType.isNotEmpty) {
    if (feedbackType.contains('short') || feedbackType == 'range_short') {
      return 'טווח קצר';
    }
    if (feedbackType.contains('long') || feedbackType == 'range_long') {
      return 'טווח רחוק';
    }
    if (feedbackType.contains('surprise')) {
      return 'תרגילי הפתעה';
    }
  }

  // 5. Legacy inference from rangeType field directly
  if (rangeType == 'קצרים') return 'טווח קצר';
  if (rangeType == 'ארוכים') return 'טווח רחוק';

  // 6. Check for open/breached circle patterns in various fields
  final folder = (data['folder'] ?? '').toString();
  if (folder.contains('מעגל פתוח') || exercise.contains('פתוח')) {
    return 'מעגל פתוח';
  }
  if (folder.contains('מעגל פרוץ') || exercise.contains('פרוץ')) {
    return 'מעגל פרוץ';
  }
  if (folder.contains('סריקות') || exercise.contains('סריקות')) {
    return 'סריקות רחוב';
  }

  // Default fallback
  return 'משוב';
}

/// Unified feedback list card widget matching "משוב זמני - מטווחים" design
/// Features:
/// - LEFT: Red trash icon button (delete) OR checkbox (selection mode)
/// - BLUE tag/chip with auto-mapped feedback type
/// - RIGHT: Edit/open icon button
/// - Title + metadata (instructor, participants, date) with RTL alignment
class FeedbackListTileCard extends StatelessWidget {
  final String title;
  final List<String> metadataLines;
  final String blueTagLabel;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final bool canDelete;
  final IconData leadingIcon;
  final Color iconColor;
  final Color iconBackgroundColor;
  // Selection mode support
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const FeedbackListTileCard({
    super.key,
    required this.title,
    required this.metadataLines,
    required this.blueTagLabel,
    required this.onOpen,
    this.onDelete,
    this.canDelete = false,
    this.leadingIcon = Icons.description,
    this.iconColor = Colors.blue,
    this.iconBackgroundColor = const Color(0x33_2196F3), // blue with 20% alpha
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // LEFT: Checkbox (selection mode) OR Delete button OR icon
        leading: selectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: onSelectionToggle != null
                    ? (_) => onSelectionToggle!()
                    : null,
              )
            : (canDelete && onDelete != null
                  ? IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: onDelete,
                      tooltip: 'מחק משוב',
                    )
                  : SizedBox(
                      width: 48,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: iconBackgroundColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(leadingIcon, color: iconColor, size: 28),
                      ),
                    )),
        // TITLE + BLUE TAG
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                blueTagLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        // METADATA LINES
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            ...metadataLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: line.startsWith('נשמר:') || line.startsWith('תאריך:')
                      ? const TextStyle(fontSize: 12, color: Colors.grey)
                      : null,
                ),
              ),
            ),
          ],
        ),
        // RIGHT: Open/Edit button
        trailing: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: onOpen,
          tooltip: 'פתח משוב',
        ),
        onTap: onOpen,
      ),
    );
  }
}
