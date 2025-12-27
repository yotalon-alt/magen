/// RangeExportMapper provides a mapping for range feedback fields.
class RangeExportMapper {
  /// Returns a mapping of range feedback fields to their exportable headers.
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
      'rangeType': 'סוג מטווח',
      'stationDetails': 'פרטי תחנות',
    };
  }
}
