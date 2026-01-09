import 'package:flutter/material.dart';

/// Automatic blue tag mapping from feedback document data
/// Used by all feedback list cards for consistent labeling
String getBlueTagLabelFromDoc(Map<String, dynamic> data) {
  // Priority order: feedbackType > rangeType > templateId > folder/category

  // 1. Check feedbackType field
  final feedbackType = (data['feedbackType'] ?? '').toString().toLowerCase();
  if (feedbackType.isNotEmpty) {
    return _mapToHebrewLabel(feedbackType);
  }

  // 2. Check rangeType field
  final rangeType = (data['rangeType'] ?? '').toString().toLowerCase();
  if (rangeType.isNotEmpty) {
    return _mapToHebrewLabel(rangeType);
  }

  // 3. Check templateId field
  final templateId = (data['templateId'] ?? '').toString().toLowerCase();
  if (templateId.isNotEmpty) {
    return _mapToHebrewLabel(templateId);
  }

  // 4. Check folder/category field
  final folder = (data['folder'] ?? data['category'] ?? '').toString();
  if (folder.isNotEmpty) {
    return _mapToHebrewLabel(folder);
  }

  // Default fallback
  return 'משוב';
}

/// Map English/Hebrew variants to consistent Hebrew labels
String _mapToHebrewLabel(String input) {
  final normalized = input.toLowerCase().trim();

  // Short range variants
  if (normalized.contains('short') ||
      normalized.contains('קצר') ||
      normalized == 'קצרים') {
    return 'טווח קצר';
  }

  // Long range variants
  if (normalized.contains('long') ||
      normalized.contains('רחוק') ||
      normalized.contains('ארוך') ||
      normalized == 'ארוכים') {
    return 'טווח רחוק';
  }

  // Surprise drill variants
  if (normalized.contains('surprise') || normalized.contains('הפתעה')) {
    return 'תרגיל הפתעה';
  }

  // Structure/building variants
  if (normalized.contains('structure') ||
      normalized.contains('building') ||
      normalized.contains('במבנה')) {
    return 'עבודה במבנה';
  }

  // Defense 474 variants
  if (normalized.contains('defense') ||
      normalized.contains('474') ||
      normalized.contains('הגנה')) {
    return 'הגנה 474';
  }

  // 474 Ranges folder (new dedicated folder)
  if (normalized == '474 ranges') {
    return '474 Ranges';
  }

  // Shooting Ranges folder
  if (normalized.contains('shooting') ||
      normalized.contains('מטווח') ||
      normalized.contains('ירי')) {
    return 'מטווחי ירי';
  }

  // General feedback variants
  if (normalized.contains('general') || normalized.contains('כללי')) {
    return 'משוב כללי';
  }

  // If contains Hebrew, return as-is (already Hebrew label)
  if (RegExp(r'[\u0590-\u05FF]').hasMatch(input)) {
    return input;
  }

  // Default fallback
  return 'משוב';
}

/// Unified feedback list card widget matching "משוב זמני - מטווחים" design
/// Features:
/// - LEFT: Red trash icon button (delete)
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
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // LEFT: Delete button (if permitted) or empty space
        leading: canDelete && onDelete != null
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
              ),
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
