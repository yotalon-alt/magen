import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Service להשלמה אוטומטית של שמות חניכים לפי יישוב
/// משמש רק לטפסי הגמר חטיבה 474 (מטווחים, תרגילי הפתעה, סיכום אימון)
/// טוען חניכים מאוסף settlement_trainees
class TraineeAutocompleteService {
  // Cache - מפת יישוב -> רשימת חניכים
  static final Map<String, List<String>> _cache = {};

  // מפת יישוב -> זמן טעינה אחרון (לרענון אחרי 5 דקות)
  static final Map<String, DateTime> _cacheTime = {};

  // משך זמן תוקף ה-cache (5 דקות)
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// טעינת רשימת חניכים ליישוב מסוים מאוסף settlement_trainees
  /// מחזיר רשימה ריקה אם לא נמצאו חניכים
  static Future<List<String>> getTraineesForSettlement(
    String settlement,
  ) async {
    if (settlement.isEmpty) return [];

    final normalizedSettlement = settlement.trim();

    // בדיקה אם יש ב-cache ועדיין בתוקף
    if (_cache.containsKey(normalizedSettlement)) {
      final cacheTime = _cacheTime[normalizedSettlement];
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheDuration) {
        debugPrint(
          '📋 TraineeAutocomplete: Using cached data for $normalizedSettlement (${_cache[normalizedSettlement]!.length} trainees)',
        );
        return _cache[normalizedSettlement]!;
      }
    }

    try {
      debugPrint(
        '🔍 TraineeAutocomplete: Loading trainees for "$normalizedSettlement" from settlement_trainees collection...',
      );
      debugPrint('🔍 Document path: settlement_trainees/$normalizedSettlement');

      final doc = await FirebaseFirestore.instance
          .collection('settlement_trainees')
          .doc(normalizedSettlement)
          .get()
          .timeout(const Duration(seconds: 15));

      debugPrint('🔍 Document exists: ${doc.exists}');

      if (!doc.exists || doc.data() == null) {
        debugPrint(
          '⚠️ TraineeAutocomplete: No data found for "$normalizedSettlement" in settlement_trainees',
        );

        // נסה לחפש בכל האוסף ולהציג את שמות המסמכים
        debugPrint('🔍 Listing all documents in settlement_trainees...');
        final allDocs = await FirebaseFirestore.instance
            .collection('settlement_trainees')
            .limit(5)
            .get()
            .timeout(const Duration(seconds: 10));
        for (final d in allDocs.docs) {
          debugPrint('   Found doc: "${d.id}"');
        }

        _cache[normalizedSettlement] = [];
        _cacheTime[normalizedSettlement] = DateTime.now();
        return [];
      }

      final data = doc.data()!;
      final trainees = (data['trainees'] as List?)?.cast<String>() ?? [];
      trainees.sort(); // מיון לפי א"ב

      // שמירה ב-cache
      _cache[normalizedSettlement] = trainees;
      _cacheTime[normalizedSettlement] = DateTime.now();

      debugPrint(
        '✅ TraineeAutocomplete: Loaded ${trainees.length} trainees for $normalizedSettlement',
      );

      if (trainees.isNotEmpty) {
        debugPrint('   First 5 trainees: ${trainees.take(5).join(", ")}');
      }

      return trainees;
    } catch (e) {
      debugPrint(
        '❌ TraineeAutocomplete: Error loading trainees for $normalizedSettlement: $e',
      );
      return _cache[normalizedSettlement] ?? [];
    }
  }

  /// סינון רשימת חניכים לפי טקסט חיפוש
  /// מחזיר עד maxResults תוצאות
  static List<String> filterTrainees(
    List<String> trainees,
    String query, {
    int maxResults = 10,
  }) {
    if (query.isEmpty) return trainees.take(maxResults).toList();

    final normalizedQuery = query.trim().toLowerCase();

    return trainees
        .where((name) => name.toLowerCase().contains(normalizedQuery))
        .take(maxResults)
        .toList();
  }

  /// ניקוי ה-cache (לשימוש בעת התנתקות או רענון)
  static void clearCache() {
    _cache.clear();
    _cacheTime.clear();
    debugPrint('🗑️ TraineeAutocomplete: Cache cleared');
  }

  /// ניקוי cache ליישוב ספציפי
  static void clearCacheForSettlement(String settlement) {
    final normalized = settlement.trim();
    _cache.remove(normalized);
    _cacheTime.remove(normalized);
    debugPrint('🗑️ TraineeAutocomplete: Cache cleared for $normalized');
  }

  /// בדיקה אם יש חניכים ביישוב (ללא טעינה מלאה)
  static bool hasTraineesInCache(String settlement) {
    final normalized = settlement.trim();
    final cached = _cache[normalized];
    return cached != null && cached.isNotEmpty;
  }

  /// מספר החניכים ב-cache ליישוב
  static int getTraineeCountInCache(String settlement) {
    return _cache[settlement.trim()]?.length ?? 0;
  }
}
