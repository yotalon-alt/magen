import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Model לאירוע אימון בתוכנית 474
class TrainingEvent {
  final String? id;
  final DateTime date;
  final String settlement;
  final String trainingType;
  final List<String> instructors;
  final String location;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  const TrainingEvent({
    this.id,
    required this.date,
    required this.settlement,
    required this.trainingType,
    required this.instructors,
    required this.location,
    required this.createdBy,
    required this.createdAt,
    this.lastModified,
    this.lastModifiedBy,
  });

  /// Create from Firestore document
  factory TrainingEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TrainingEvent(
      id: doc.id,
      date: (data['date'] as Timestamp).toDate(),
      settlement: data['settlement'] as String? ?? '',
      trainingType: data['trainingType'] as String? ?? '',
      instructors: List<String>.from(data['instructors'] as List? ?? []),
      location: data['location'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastModified: (data['lastModified'] as Timestamp?)?.toDate(),
      lastModifiedBy: data['lastModifiedBy'] as String?,
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'date': Timestamp.fromDate(date),
      'settlement': settlement,
      'trainingType': trainingType,
      'instructors': instructors,
      'location': location,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastModified': lastModified != null
          ? Timestamp.fromDate(lastModified!)
          : FieldValue.serverTimestamp(),
      'lastModifiedBy': lastModifiedBy ?? createdBy,
    };
  }

  /// Copy with new values
  TrainingEvent copyWith({
    String? id,
    DateTime? date,
    String? settlement,
    String? trainingType,
    List<String>? instructors,
    String? location,
    String? createdBy,
    DateTime? createdAt,
    DateTime? lastModified,
    String? lastModifiedBy,
  }) {
    return TrainingEvent(
      id: id ?? this.id,
      date: date ?? this.date,
      settlement: settlement ?? this.settlement,
      trainingType: trainingType ?? this.trainingType,
      instructors: instructors ?? this.instructors,
      location: location ?? this.location,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    );
  }
}

/// Service לניהול תוכנית אימונים 474 ב-Firestore
class TrainingProgram474Service {
  static const String _collection = 'training_programs_474';

  /// Get Firestore collection reference
  static CollectionReference get _collectionRef =>
      FirebaseFirestore.instance.collection(_collection);

  /// Fetch all training events (sorted by date, newest first)
  static Stream<List<TrainingEvent>> getTrainingEventsStream() {
    return _collectionRef.orderBy('date', descending: false).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => TrainingEvent.fromFirestore(doc))
          .toList();
    });
  }

  /// Fetch single training event by ID
  static Future<TrainingEvent?> getTrainingEventById(String id) async {
    try {
      final doc = await _collectionRef.doc(id).get();
      if (!doc.exists) return null;
      return TrainingEvent.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ Error fetching training event: $e');
      return null;
    }
  }

  /// Add new training event
  static Future<String?> addTrainingEvent(TrainingEvent event) async {
    try {
      final docRef = await _collectionRef.add(event.toFirestore());
      debugPrint('✅ Training event added: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Error adding training event: $e');
      return null;
    }
  }

  /// Update existing training event
  static Future<bool> updateTrainingEvent(TrainingEvent event) async {
    if (event.id == null) {
      debugPrint('❌ Cannot update event without ID');
      return false;
    }

    try {
      await _collectionRef.doc(event.id).update(event.toFirestore());
      debugPrint('✅ Training event updated: ${event.id}');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating training event: $e');
      return false;
    }
  }

  /// Delete training event (Admin only)
  static Future<bool> deleteTrainingEvent(String id) async {
    try {
      await _collectionRef.doc(id).delete();
      debugPrint('✅ Training event deleted: $id');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting training event: $e');
      return false;
    }
  }

  /// Filter events by multiple criteria
  static List<TrainingEvent> filterEvents(
    List<TrainingEvent> events, {
    String? settlementFilter,
    String? trainingTypeFilter,
    String? instructorFilter,
    String? locationFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return events.where((event) {
      // Settlement filter
      if (settlementFilter != null &&
          settlementFilter.isNotEmpty &&
          settlementFilter != 'הכל') {
        if (event.settlement != settlementFilter) return false;
      }

      // Training type filter
      if (trainingTypeFilter != null &&
          trainingTypeFilter.isNotEmpty &&
          trainingTypeFilter != 'הכל') {
        if (event.trainingType != trainingTypeFilter) return false;
      }

      // Instructor filter
      if (instructorFilter != null &&
          instructorFilter.isNotEmpty &&
          instructorFilter != 'הכל') {
        if (!event.instructors.contains(instructorFilter)) return false;
      }

      // Location filter (partial match)
      if (locationFilter != null && locationFilter.isNotEmpty) {
        if (!event.location.contains(locationFilter)) return false;
      }

      // Date range filter
      if (startDate != null) {
        if (event.date.isBefore(startDate)) return false;
      }
      if (endDate != null) {
        // Include the entire end date (until 23:59:59)
        final endOfDay = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
        );
        if (event.date.isAfter(endOfDay)) return false;
      }

      return true;
    }).toList();
  }

  /// Get unique settlements from events (for filter dropdown)
  static List<String> getUniqueSettlements(List<TrainingEvent> events) {
    final settlements = events.map((e) => e.settlement).toSet().toList();
    settlements.sort();
    return settlements;
  }

  /// Get unique training types from events (for filter dropdown)
  static List<String> getUniqueTrainingTypes(List<TrainingEvent> events) {
    final types = events.map((e) => e.trainingType).toSet().toList();
    types.sort();
    return types;
  }

  /// Get unique instructors from events (for filter dropdown)
  static List<String> getUniqueInstructors(List<TrainingEvent> events) {
    final instructorsSet = <String>{};
    for (final event in events) {
      instructorsSet.addAll(event.instructors);
    }
    final instructors = instructorsSet.toList();
    instructors.sort();
    return instructors;
  }
}
