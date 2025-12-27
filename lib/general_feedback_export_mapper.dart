/// GeneralFeedbackExportMapper provides a mapping for general feedback fields.
class GeneralFeedbackExportMapper {
  /// Returns a mapping of feedback fields to their exportable headers.
  static Map<String, String> getMapping() {
    return {
      'id': 'ID',
      'role': 'תפקיד',
      'name': 'שם',
      'exercise': 'תרגיל',
      'scores': 'ציונים',
      'notes': 'הערות',
      'criteriaList': 'קריטריונים',
      'createdAt': 'תאריך יצירה',
      'instructorName': 'מדריך',
      'instructorRole': 'תפקיד מדריך',
      'folder': 'תיקייה',
      'scenario': 'תרחיש',
      'settlement': 'יישוב',
      'attendeesCount': 'מספר נוכחים',
    };
  }
}
