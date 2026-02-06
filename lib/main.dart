import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'instructor_course_selection_feedbacks_page.dart';
import 'pages/screenings_menu_page.dart';
import 'range_selection_page.dart';
import 'feedback_export_service.dart';
import 'export_selection_page.dart';
import 'universal_export_page.dart';
import 'surprise_drills_entry_page.dart';
import 'widgets/standard_back_button.dart';
import 'widgets/feedback_list_tile_card.dart';
import 'widgets/trainee_selection_dialog.dart';
import 'services/trainee_autocomplete_service.dart';

// ===== Minimal stubs and models (null-safe) =====
// Initialize default in-memory users (no-op stub to avoid undefined symbol)
void initDefaultUsers() {}

// Simple app user model used across the app
class AppUser {
  final String username;
  final String name;
  final String role; // 'Admin' or 'Instructor'
  final String uid;
  const AppUser({
    required this.username,
    required this.name,
    required this.role,
    required this.uid,
  });
}

// Currently signed-in user (nullable until auth completes)
AppUser? currentUser;

// Global folders used by FeedbacksPage and filters
// Each folder has: title (String) and isHidden (bool)
const List<Map<String, dynamic>>
_feedbackFoldersConfig = <Map<String, dynamic>>[
  {
    'title': 'הגמר חטיבה 474',
    'isHidden': false,
    'isSpecialCategory': true,
  }, // ✨ NEW: Parent folder for 4 sub-folders
  {'title': 'מיונים לקורס מדריכים', 'isHidden': false},
  {'title': 'מטווחי ירי', 'isHidden': false},
  {'title': 'משובים – כללי', 'isHidden': false},
  {
    'title': 'תרגילי הפתעה כללי',
    'isHidden': false,
  }, // ✨ NEW: General surprise drills
  {
    'title': 'סיכום אימון כללי',
    'isHidden': false,
  }, // ✨ NEW: General training summary
  // Hidden folders - accessible ONLY through 'הגמר חטיבה 474'
  {
    'title': 'מטווחים 474',
    'displayLabel': 'מטווחים 474',
    'internalValue': '474 Ranges',
    'isHidden': true, // ✅ MOVED: Now part of הגמר חטיבה 474
  },
  {
    'title': 'מחלקות ההגנה – חטיבה 474',
    'displayLabel': 'מחלקות הגנה 474',
    'isHidden': true,
  }, // ✅ MOVED: Now part of הגמר חטיבה 474
  {
    'title': 'משוב תרגילי הפתעה',
    'displayLabel': 'תרגילי הפתעה 474',
    'isHidden': true,
  }, // ✅ MOVED: Now part of הגמר חטיבה 474
  {
    'title': 'משוב סיכום אימון 474',
    'displayLabel': 'סיכום אימון 474',
    'isHidden': true,
  }, // ✅ MOVED: Now part of הגמר חטיבה 474
  {'title': 'מיונים – כללי', 'isHidden': true}, // ✅ SOFT DELETE: Hidden from UI
  {
    'title': 'עבודה במבנה',
    'isHidden': true,
  }, // ✅ SOFT DELETE: Unused folder removed from UI
];

// Helper: Get all folder titles (including hidden) for backwards compatibility
final List<String> feedbackFolders = _feedbackFoldersConfig
    .map((config) => config['title'] as String)
    .toList();

// Helper: Get only visible folder titles for UI display
final List<String> visibleFeedbackFolders = _feedbackFoldersConfig
    .where((config) => config['isHidden'] != true)
    .map((config) => config['title'] as String)
    .toList();

// Settlements list for dropdown (can be extended; empty list is valid)
const List<String> golanSettlements = <String>[
  'אורטל',
  'אבני איתן',
  'אודם',
  'אלוני הבשן',
  'אליעד',
  'אלרום',
  'אניעם',
  'אפיק',
  'בני יהודה',
  'גבעת יואב',
  'גשור',
  'חד נס',
  'חספין',
  'יונתן',
  'כפר חרוב',
  'כנף',
  'מבוא חמה',
  'מיצר',
  'מעלה גמלא',
  'מרום גולן',
  'מצוק עורבים',
  'נטור',
  'נאות גולן',
  'נוב',
  'נווה אטיב',
  'עין זיוון',
  'קלע אלון',
  'קשת',
  'קדמת צבי',
  'רמת מגשימים',
  'רמת טראמפ',
  'רמות',
  'שעל',
  'קצרין',
  'מסעדה',
  'בוקעתא',
  'מג\'דל שמס',
  'עין קינייה',
];

// רשימת מדריכים חטיבה 474
const List<String> brigade474Instructors = <String>[
  'יותם אלון',
  'לירון מוסרי',
  'דוד בן צבי',
  'חן לוי',
  'יוגב נגרקר',
  'דוד נוביק',
  'ניר בר',
  'וואסים דאבוס',
  'יגל שוורץ',
  'מהרטו ביאגדלין',
  'יוסי גן ואר',
  'יוסי זוסמן',
  'בועז בן חורין',
  'אורי כי טוב',
  'נתנאל אינדיג',
  'נתנאל עמיחי',
  'דותן יוסף',
  'מעוז אביב',
  'דוד גליקמן',
  'גל זבידאן',
  'איתן לוי',
  'חנן גלר',
  'תיירי לסקרט',
];

// Feedback model used throughout the app
class FeedbackModel {
  final String? id;
  final String role;
  final String name;
  final String exercise;
  final Map<String, int> scores;
  final Map<String, String> notes;
  final List<String> criteriaList;
  final DateTime createdAt;
  final String instructorName;
  final String instructorRole;
  final String commandText;
  final String commandStatus;
  final String folder;
  final String scenario;
  final String settlement;
  final int attendeesCount;
  // New fields for proper filtering
  final String module; // 'surprise_drill' or 'shooting_ranges'
  final String type; // 'surprise_exercise' or 'range_feedback'
  final bool isTemporary; // true for drafts, false for final
  final String
  folderKey; // canonical key: 'ranges_474' | 'shooting_ranges' | ''
  final String folderLabel; // Hebrew display label
  final String rangeSubType; // 'טווח קצר' or 'טווח רחוק' for display
  final String trainingType; // 'סוג אימון' for training summary
  final String summary; // סיכום משוב
  final List<String>
  instructors; // ✨ NEW: Additional instructors with access to this feedback

  const FeedbackModel({
    this.id,
    required this.role,
    required this.name,
    required this.exercise,

    required this.scores,
    required this.notes,
    required this.criteriaList,
    required this.createdAt,
    required this.instructorName,
    required this.instructorRole,
    required this.commandText,
    required this.commandStatus,
    required this.folder,
    required this.scenario,
    required this.settlement,
    required this.attendeesCount,
    this.module = '',
    this.type = '',
    this.isTemporary = false,
    this.folderKey = '',
    this.folderLabel = '',
    this.rangeSubType = '',
    this.trainingType = '',
    this.summary = '',
    this.instructors = const [], // ✨ NEW: Default empty list
  });

  static FeedbackModel? fromMap(Map<String, dynamic>? m, {String? id}) {
    if (m == null) return null;
    final Map<String, int> scores = {};
    final dynamic rawScores = m['scores'];
    if (rawScores != null) {
      if (rawScores is Map) {
        for (final e in rawScores.entries) {
          final k = e.key;
          final v = e.value;
          if (k is String && (v is int || v is num)) {
            scores[k] = (v as num).toInt();
          }
        }
      }
    }

    final Map<String, String> notes = {};
    final dynamic rawNotes = m['notes'];
    if (rawNotes != null) {
      if (rawNotes is Map) {
        for (final e in rawNotes.entries) {
          final k = e.key;
          final v = e.value;
          if (k is String && v is String) {
            notes[k] = v;
          }
        }
      }
    }
    final List<String> criteriaList = ((m['criteriaList'] as List?) ?? const [])
        .whereType<String>()
        .toList();

    // createdAt may be a Timestamp or ISO string; handle both safely
    DateTime createdAt = DateTime.now();
    final ca = m['createdAt'];
    if (ca is Timestamp) {
      createdAt = ca.toDate();
    } else if (ca is String) {
      createdAt = DateTime.tryParse(ca) ?? createdAt;
    }

    return FeedbackModel(
      id: id,
      role: (m['role'] ?? m['roleEvaluated'] ?? '').toString(),
      name: (m['name'] ?? m['evaluatedName'] ?? '').toString(),
      exercise: (m['exercise'] ?? m['exerciseName'] ?? '').toString(),
      scores: scores,
      notes: notes,
      criteriaList: criteriaList,
      createdAt: createdAt,
      instructorName: (m['instructorName'] ?? '').toString(),
      instructorRole: (m['instructorRole'] ?? '').toString(),
      commandText: (m['commandText'] ?? '').toString(),
      commandStatus: (m['commandStatus'] ?? 'פתוח').toString(),
      folder: (m['folder'] ?? '').toString(),
      scenario: (m['scenario'] ?? '').toString(),
      settlement: (m['settlement'] ?? '').toString(),
      attendeesCount: (m['attendeesCount'] as num?)?.toInt() ?? 0,
      module: (m['module'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      isTemporary:
          (m['isTemporary'] ?? m['status'] == 'temporary') as bool? ?? false,
      // Derive canonical folderKey and folderLabel for backward compatibility
      folderKey: (() {
        final rawKey = (m['folderKey'] as String?) ?? '';
        if (rawKey.isNotEmpty) return rawKey;
        final rawFolder = ((m['rangeFolder'] ?? m['folder']) as String?) ?? '';
        final low = rawFolder.toLowerCase();
        if (low.contains('474') ||
            low.contains('מטווחים 474') ||
            low.contains('474 ranges') ||
            low.contains('474ranges')) {
          return 'ranges_474';
        }
        if (low.contains('shoot') || low.contains('מטווח')) {
          return 'shooting_ranges';
        }
        return '';
      })(),
      folderLabel: (() {
        final rawLabel = (m['folderLabel'] as String?) ?? '';
        if (rawLabel.isNotEmpty) return rawLabel;
        final rawFolder = ((m['rangeFolder'] ?? m['folder']) as String?) ?? '';
        if (rawFolder.isNotEmpty) return rawFolder;
        return '';
      })(),
      rangeSubType: (m['rangeSubType'] ?? '').toString(),
      trainingType: (m['trainingType'] ?? '').toString(),
      summary: (m['summary'] ?? '').toString(),
      instructors: ((m['instructors'] as List?) ?? const [])
          .whereType<String>()
          .toList(), // ✨ NEW: Load instructors array
    );
  }

  FeedbackModel copyWith({
    String? role,
    String? name,
    String? exercise,
    Map<String, int>? scores,
    Map<String, String>? notes,
    DateTime? createdAt,
    String? instructorName,
    String? instructorRole,
    String? commandText,
    String? commandStatus,
    List<String>? criteriaList,
    String? folder,
    String? scenario,
    String? settlement,
    int? attendeesCount,
    String? id,
    String? module,
    String? type,
    bool? isTemporary,
    String? folderKey,
    String? folderLabel,
    String? rangeSubType,
    String? trainingType,
    String? summary,
    List<String>? instructors, // ✨ NEW
  }) {
    return FeedbackModel(
      id: id ?? this.id,
      role: role ?? this.role,
      name: name ?? this.name,
      exercise: exercise ?? this.exercise,
      scores: scores ?? this.scores,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      instructorName: instructorName ?? this.instructorName,
      instructorRole: instructorRole ?? this.instructorRole,
      commandText: commandText ?? this.commandText,
      commandStatus: commandStatus ?? this.commandStatus,
      criteriaList: criteriaList ?? this.criteriaList,
      folder: folder ?? this.folder,
      scenario: scenario ?? this.scenario,
      settlement: settlement ?? this.settlement,
      attendeesCount: attendeesCount ?? this.attendeesCount,
      module: module ?? this.module,
      type: type ?? this.type,
      isTemporary: isTemporary ?? this.isTemporary,
      folderKey: folderKey ?? this.folderKey,
      folderLabel: folderLabel ?? this.folderLabel,
      rangeSubType: rangeSubType ?? this.rangeSubType,
      trainingType: trainingType ?? this.trainingType,
      summary: summary ?? this.summary,
      instructors: instructors ?? this.instructors, // ✨ NEW
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'name': name,
      'exercise': exercise,
      'scores': scores,
      'notes': notes,
      'criteriaList': criteriaList,
      'createdAt': createdAt.toIso8601String(),
      'instructorName': instructorName,
      'instructorRole': instructorRole,
      'commandText': commandText,
      'commandStatus': commandStatus,
      'folder': folder,
      'scenario': scenario,
      'settlement': settlement,
      'attendeesCount': attendeesCount,
      'module': module,
      'type': type,
      'isTemporary': isTemporary,
      'folderKey': folderKey,
      'folderLabel': folderLabel,
      'rangeSubType': rangeSubType,
      'trainingType': trainingType,
      'summary': summary,
      'instructors': instructors, // ✨ NEW
    };
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize default in-memory users synchronously
  initDefaultUsers();

  // Initialize Firebase BEFORE starting the app to avoid race conditions
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
    // ignore: avoid_print
    print('Firebase initialized successfully in main()');
  } catch (e) {
    // Initialization failed or timed out — log but continue
    // ignore: avoid_print
    print('Firebase init failed in main(): $e');
  }

  runApp(const MyApp());
}

/// Global in-memory storage
final List<FeedbackModel> feedbackStorage = [];

/// Helper function to resolve user's Hebrew full name from Firestore
/// Returns the full Hebrew name, never an email or UID
Future<String> resolveUserHebrewName(String uid) async {
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 3));

    if (userDoc.exists) {
      final userData = userDoc.data();
      // Priority: displayName > fullName > name (never return email/username)
      final displayName = userData?['displayName'] as String?;
      final fullName = userData?['fullName'] as String?;
      final name = userData?['name'] as String?;

      if (displayName != null &&
          displayName.isNotEmpty &&
          !displayName.contains('@')) {
        return displayName;
      } else if (fullName != null &&
          fullName.isNotEmpty &&
          !fullName.contains('@')) {
        return fullName;
      } else if (name != null && name.isNotEmpty && !name.contains('@')) {
        return name;
      }
    }
  } catch (e) {
    debugPrint('⚠️ Failed to resolve Hebrew name for UID $uid: $e');
  }

  // Fallback: return a placeholder with truncated UID (never "לא ידוע")
  return 'מדריך ${uid.substring(0, min(8, uid.length))}...';
}

// Load feedbacks from Firestore according to current user permissions
// בדיקה זמנית - שאילתה פשוטה בלי where לוודא שהדאטה קיימת
Future<void> testSimpleFeedbackQuery() async {
  try {
    debugPrint('\n🧪 ===== TEST: Simple Query (no filters) =====');
    final snap = await FirebaseFirestore.instance
        .collection('feedbacks')
        .orderBy('createdAt', descending: true)
        .get()
        .timeout(const Duration(seconds: 10));

    debugPrint('✅ TEST SUCCESS: Got ${snap.docs.length} total documents');

    for (var i = 0; i < snap.docs.length && i < 3; i++) {
      final doc = snap.docs[i];
      final data = doc.data();
      debugPrint(
        '   Doc $i: id=${doc.id}, instructorId=${data['instructorId']}, createdAt=${data['createdAt']}',
      );
    }

    debugPrint('🧪 ===== TEST END =====\n');
  } catch (e) {
    debugPrint('❌ TEST FAILED: $e');
  }
}

Future<void> loadFeedbacksForCurrentUser({bool? isAdmin}) async {
  feedbackStorage.clear();
  final uid = FirebaseAuth.instance.currentUser?.uid;
  debugPrint('\n===== loadFeedbacksForCurrentUser START =====');
  debugPrint('ROLE: ${currentUser?.role}');
  debugPrint('UID: $uid');
  debugPrint('========================================\n');

  if (uid == null || uid.isEmpty) {
    debugPrint('⚠️ loadFeedbacksForCurrentUser: uid is null/empty, returning');
    return;
  }

  bool adminFlag = isAdmin ?? false;
  if (isAdmin == null) {
    // Fetch role once if not provided to decide query scope.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final data = doc.data();
      final role = (data?['role'] ?? '').toString().toLowerCase();
      adminFlag = role == 'admin';
      debugPrint(
        '🔍 loadFeedbacksForCurrentUser: fetched role=$role, adminFlag=$adminFlag',
      );
    } catch (e) {
      debugPrint('⚠️ loadFeedbacksForCurrentUser: role fetch error $e');
      adminFlag = false; // fallback to instructor scope on errors
    }
  } else {
    debugPrint(
      '🔍 loadFeedbacksForCurrentUser: isAdmin param provided=$isAdmin',
    );
    adminFlag = isAdmin;
  }

  final coll = FirebaseFirestore.instance.collection('feedbacks');
  Query q = coll;

  debugPrint('\n🔍 ===== QUERY CONSTRUCTION =====');
  debugPrint('   Current User UID: "$uid"');
  debugPrint('   Is Admin: $adminFlag');
  debugPrint('   Role: ${currentUser?.role}');

  // Admin sees all; instructor filtered by their UID
  if (!adminFlag) {
    debugPrint('   Building INSTRUCTOR query with filter:');
    debugPrint('   where("instructorId", "==", "$uid")');
    q = q.where('instructorId', isEqualTo: uid);
  } else {
    debugPrint('   Building ADMIN query (NO filter - all feedbacks)');
  }

  // Apply orderBy AFTER where clause (requires composite index for instructors)
  q = q.orderBy('createdAt', descending: true);
  debugPrint('   orderBy("createdAt", descending: true)');
  debugPrint('🔍 ===== QUERY READY =====\n');

  debugPrint('🚀 Executing Firestore query...');

  try {
    final snap = await q.get().timeout(const Duration(seconds: 15));
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.docs
        .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();

    debugPrint('\n✅ ===== QUERY RESULTS (MY FEEDBACKS) =====');
    debugPrint('   RESULT SIZE: ${docs.length}');
    debugPrint('   Query returned ${docs.length} document(s)');
    debugPrint('   User UID: "$uid"');
    debugPrint('   Is Admin: $adminFlag');

    if (docs.isEmpty) {
      debugPrint('\n⚠️⚠️⚠️ NO DOCUMENTS FOUND ⚠️⚠️⚠️');
      debugPrint('   Possible reasons:');
      debugPrint('   1. instructorId in Firestore does NOT match current UID');
      debugPrint('   2. No feedback documents exist for this instructor');
      debugPrint('   3. Composite index is still building');
      debugPrint('');
      debugPrint('   🔍 DEBUG STEPS:');
      debugPrint('   1. Open Firebase Console → Firestore');
      debugPrint('   2. Check a feedback document');
      debugPrint('   3. Compare instructorId field value to: "$uid"');
      debugPrint('   4. They must match EXACTLY (case-sensitive)');
      debugPrint('⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️\n');
    }

    for (final doc in docs) {
      final raw = doc.data();
      final docInstructorId = raw['instructorId'] ?? 'MISSING';
      debugPrint(
        '📄 Document ${doc.id}: instructorId="$docInstructorId", evaluatedName="${raw['name'] ?? raw['evaluatedName']}"',
      );
      final model = FeedbackModel.fromMap(raw, id: doc.id);
      if (model == null) {
        debugPrint('  ⚠️ Failed to parse document ${doc.id}');
        continue;
      }
      // Firestore query already filtered by instructorId for instructors
      feedbackStorage.add(model);
      debugPrint(
        '  ✅ Added feedback: ${model.name} by ${model.instructorName}',
      );
    }
    debugPrint(
      '📋 loadFeedbacksForCurrentUser: total ${feedbackStorage.length} feedbacks in storage (my feedbacks)',
    );

    // ✨ NEW: Load feedbacks where I'm an additional instructor (non-admins only)
    // This includes BOTH final AND temporary (drafts) feedbacks
    // ✅ HYBRID: Check BOTH UID and name for backward compatibility
    if (!adminFlag) {
      debugPrint('\n🔍 ===== LOADING SHARED FEEDBACKS (FINAL + DRAFTS) =====');
      debugPrint(
        '   Looking for feedbacks where I am in instructors array (UID or name)',
      );

      int finalCount = 0;
      int draftCount = 0;
      final Set<String> processedIds =
          {}; // Track processed to avoid duplicates

      try {
        // Query 1: Search by UID (new format)
        debugPrint('   🔍 Query 1: Searching by UID=$uid');
        final sharedQueryByUid = FirebaseFirestore.instance
            .collection('feedbacks')
            .where('instructors', arrayContains: uid);

        final sharedSnapByUid = await sharedQueryByUid.get().timeout(
          const Duration(seconds: 10),
        );
        debugPrint(
          '   Found ${sharedSnapByUid.docs.length} feedback(s) by UID',
        );

        for (final doc in sharedSnapByUid.docs) {
          final raw = doc.data();
          // Skip if already in storage or already processed
          if (feedbackStorage.any((f) => f.id == doc.id) ||
              processedIds.contains(doc.id)) {
            debugPrint('  ⏭️ Skipping ${doc.id} (already in storage)');
            continue;
          }

          final model = FeedbackModel.fromMap(raw, id: doc.id);
          if (model != null) {
            feedbackStorage.add(model);
            processedIds.add(doc.id);
            if (model.isTemporary) {
              draftCount++;
              debugPrint(
                '  ✅ Added shared DRAFT (by UID): ${model.name} by ${model.instructorName}',
              );
            } else {
              finalCount++;
              debugPrint(
                '  ✅ Added shared FINAL (by UID): ${model.name} by ${model.instructorName}',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Failed to load shared feedbacks by UID: $e');
      }

      // Query 2: Search by name (fallback for old data)
      try {
        final currentUserName = currentUser?.name ?? '';
        if (currentUserName.isNotEmpty) {
          debugPrint('   🔍 Query 2: Searching by name="$currentUserName"');
          final sharedQueryByName = FirebaseFirestore.instance
              .collection('feedbacks')
              .where('instructors', arrayContains: currentUserName);

          final sharedSnapByName = await sharedQueryByName.get().timeout(
            const Duration(seconds: 10),
          );
          debugPrint(
            '   Found ${sharedSnapByName.docs.length} feedback(s) by name',
          );

          for (final doc in sharedSnapByName.docs) {
            final raw = doc.data();
            // Skip if already in storage or already processed
            if (feedbackStorage.any((f) => f.id == doc.id) ||
                processedIds.contains(doc.id)) {
              debugPrint('  ⏭️ Skipping ${doc.id} (already processed)');
              continue;
            }

            final model = FeedbackModel.fromMap(raw, id: doc.id);
            if (model != null) {
              feedbackStorage.add(model);
              processedIds.add(doc.id);
              if (model.isTemporary) {
                draftCount++;
                debugPrint(
                  '  ✅ Added shared DRAFT (by name): ${model.name} by ${model.instructorName}',
                );
              } else {
                finalCount++;
                debugPrint(
                  '  ✅ Added shared FINAL (by name): ${model.name} by ${model.instructorName}',
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Failed to load shared feedbacks by name: $e');
      }

      debugPrint('📋 Total shared: $finalCount final + $draftCount drafts');
      debugPrint('📋 Total after shared: ${feedbackStorage.length} feedbacks');
      debugPrint('🔍 ===== END SHARED FEEDBACKS =====\n');
    }

    // Debug: Show training summaries found
    final trainingSummaries = feedbackStorage
        .where(
          (f) =>
              f.folder == 'משוב סיכום אימון 474' ||
              f.module == 'training_summary',
        )
        .toList();
    debugPrint('\n🎯 ===== TRAINING SUMMARIES FOUND =====');
    debugPrint('   Count: ${trainingSummaries.length}');
    for (final ts in trainingSummaries) {
      debugPrint(
        '   - ID: ${ts.id}, Name: ${ts.name}, Settlement: ${ts.settlement}',
      );
      debugPrint('     Folder: "${ts.folder}", Module: "${ts.module}"');
    }
    debugPrint('🎯 ===================================\n');

    // ✅ LOAD INSTRUCTOR COURSE EVALUATIONS (from separate collection)
    debugPrint('\n🔍 ===== LOADING INSTRUCTOR COURSE EVALUATIONS =====');
    try {
      Query evalQuery = FirebaseFirestore.instance
          .collection('instructor_course_evaluations')
          .where('status', isEqualTo: 'final');

      // Filter by instructor for non-admins
      if (!adminFlag) {
        evalQuery = evalQuery.where('instructorId', isEqualTo: uid);
      }

      final evalSnap = await evalQuery
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 10));

      debugPrint(
        '   Found ${evalSnap.docs.length} instructor course evaluations',
      );

      for (final doc in evalSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final isSuitable = data['isSuitable'] as bool? ?? false;

        // Convert to FeedbackModel format with appropriate folder name
        final folderName = isSuitable
            ? 'מתאימים לקורס מדריכים'
            : 'לא מתאימים לקורס מדריכים';

        final feedback = FeedbackModel(
          id: doc.id,
          role: data['role'] as String? ?? '',
          name: data['candidateName'] as String? ?? '',
          exercise: 'מיונים לקורס מדריכים',
          scores: (data['scores'] as Map?)?.cast<String, int>() ?? {},
          notes: (data['notes'] as Map?)?.cast<String, String>() ?? {},
          criteriaList: (data['criteriaList'] as List?)?.cast<String>() ?? [],
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          instructorName: data['instructorName'] as String? ?? '',
          instructorRole: data['instructorRole'] as String? ?? '',
          commandText: data['commandText'] as String? ?? '',
          commandStatus: data['commandStatus'] as String? ?? 'פתוח',
          folder: folderName,
          scenario: data['scenario'] as String? ?? '',
          settlement: data['settlement'] as String? ?? '',
          attendeesCount: 0,
        );

        feedbackStorage.add(feedback);
        debugPrint(
          '  ✅ Added course evaluation: ${feedback.name} → $folderName',
        );
      }

      debugPrint(
        '📋 Total after adding evaluations: ${feedbackStorage.length} feedbacks',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load instructor course evaluations: $e');
    }
    debugPrint('🔍 ===== END INSTRUCTOR COURSE EVALUATIONS =====\n');
  } on FirebaseException catch (e) {
    debugPrint('❌ FirebaseException: ${e.code}');
    debugPrint('   Message: ${e.message}');

    if (e.code == 'failed-precondition' ||
        e.message?.contains('index') == true) {
      debugPrint('\n🔥🔥🔥 COMPOSITE INDEX ERROR DETECTED! 🔥🔥🔥');
      debugPrint('');
      debugPrint('The query requires a composite index on:');
      debugPrint('  Collection: feedbacks');
      debugPrint('  Fields:');
      debugPrint('    1. instructorId (Ascending)');
      debugPrint('    2. createdAt (Descending)');
      debugPrint('');
      debugPrint('📋 To create the index:');
      debugPrint('   1. Go to: https://console.firebase.google.com/');
      debugPrint('   2. Select your project');
      debugPrint('   3. Go to: Firestore Database → Indexes');
      debugPrint('   4. Click "Create Index"');
      debugPrint('   5. Enter:');
      debugPrint('      - Collection ID: feedbacks');
      debugPrint('      - Field 1: instructorId | Ascending');
      debugPrint('      - Field 2: createdAt | Descending');
      debugPrint('   6. Click "Create"');
      debugPrint('   7. Wait for index to build (usually 1-5 minutes)');
      debugPrint('');
      debugPrint('Or use the Firebase CLI:');
      debugPrint('   firebase firestore:indexes');
      debugPrint('');
      debugPrint(
        '⚠️ Until the index is created, instructors will see empty feedback list.',
      );
      debugPrint('🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥\n');
    }

    // On error, leave feedbackStorage empty - UI will show empty state
    // This prevents the screen from freezing in loading state
  } on TimeoutException catch (e) {
    debugPrint('❌ Query timeout: $e');
    debugPrint('   Firestore query took too long to respond');
    // On error, leave feedbackStorage empty - UI will show empty state
  } catch (e) {
    debugPrint('❌ loadFeedbacksForCurrentUser: unexpected error $e');
    // On error, leave feedbackStorage empty - UI will show empty state
  }
}

/// Migration function to fix incorrectly saved feedback types
Future<void> migrateFeedbackRouting() async {
  debugPrint('\n🔧 ===== FEEDBACK ROUTING MIGRATION START =====');

  final targetExercises = ['מעגל פתוח', 'מעגל פרוץ', 'סריקות רחוב'];
  final allowedFolders = ['מחלקות ההגנה – חטיבה 474', 'משובים – כללי'];
  final incorrectFolders = ['מטווחים 474', '474 Ranges', 'מטווחי ירי'];

  int migratedCount = 0;
  int errorCount = 0;

  try {
    // Query all feedbacks of target exercise types
    final query = FirebaseFirestore.instance
        .collection('feedbacks')
        .where('exercise', whereIn: targetExercises);

    final snapshot = await query.get();
    debugPrint('Found ${snapshot.docs.length} feedbacks to check');

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final exercise = data['exercise'] as String? ?? '';
        final currentFolder = data['folder'] as String? ?? '';
        final settlement = data['settlement'] as String? ?? '';

        debugPrint('\n📝 Checking feedback: ${doc.id}');
        debugPrint('   Exercise: $exercise');
        debugPrint('   Current folder: $currentFolder');
        debugPrint('   Settlement: $settlement');

        // Check if feedback is in wrong folder
        if (incorrectFolders.contains(currentFolder) ||
            !allowedFolders.contains(currentFolder)) {
          // Determine correct folder
          String correctFolder;
          if (currentFolder == 'מחלקות ההגנה – חטיבה 474' ||
              settlement.isNotEmpty) {
            correctFolder = 'מחלקות ההגנה – חטיבה 474';
          } else {
            correctFolder = 'משובים – כללי';
          }

          debugPrint('   ❌ NEEDS MIGRATION');
          debugPrint('   Target folder: $correctFolder');

          // Update the feedback document
          await doc.reference.update({
            'folder': correctFolder,
            'migrated': true,
            'migratedAt': DateTime.now(),
            'originalFolder': currentFolder,
          });

          migratedCount++;
          debugPrint('   ✅ Migrated successfully');

          // Log migration for verification
          debugPrint(
            'MIGRATED: ${doc.id} from "$currentFolder" to "$correctFolder"',
          );
        } else {
          debugPrint('   ✅ Already in correct folder');
        }
      } catch (e) {
        errorCount++;
        debugPrint('   ❌ Error migrating ${doc.id}: $e');
      }
    }
  } catch (e) {
    debugPrint('❌ Migration failed: $e');
  }

  debugPrint('\n🔧 ===== MIGRATION SUMMARY =====');
  debugPrint('   Total migrated: $migratedCount');
  debugPrint('   Errors: $errorCount');
  debugPrint('🔧 ===== MIGRATION COMPLETE =====\n');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'מערכת משובים',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: Colors.blueGrey[900],
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blueGrey,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey, width: 1.0),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          alignLabelWithHint: true,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black87),
          bodyMedium: TextStyle(color: Colors.black87),
          bodySmall: TextStyle(color: Colors.black87),
          headlineLarge: TextStyle(color: Colors.black87),
          headlineMedium: TextStyle(color: Colors.black87),
          headlineSmall: TextStyle(color: Colors.black87),
        ),
      ),
      home: const AuthGate(),
      routes: {'/main': (_) => const MainScreen()},
      // readiness and alerts routes
      onGenerateRoute: (settings) {
        if (settings.name == '/commander') {
          return MaterialPageRoute(
            builder: (_) => const CommanderDashboardPage(),
          );
        }
        if (settings.name == '/alerts') {
          return MaterialPageRoute(builder: (_) => const AlertsPage());
        }
        if (settings.name == '/readiness') {
          return MaterialPageRoute(builder: (_) => const ReadinessPage());
        }
        return null;
      },
    );
  }
}

/* ================== AUTH GATE ================== */

/// AuthGate: continuously listens to auth state and validates profile.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        debugPrint('AuthGate: authStateChanges=${authSnap.data?.uid}');

        // Still waiting for initial auth state
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('טוען...'),
                ],
              ),
            ),
          );
        }

        // No user signed in
        final user = authSnap.data;
        if (user == null) {
          debugPrint('AuthGate: no user → login');
          return const LoginPage();
        }

        // User signed in; now validate profile
        debugPrint('AuthGate: user=${user.uid}, loading profile...');
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 10)),
          builder: (context, docSnap) {
            // Still loading profile
            if (docSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('טוען פרופיל...'),
                    ],
                  ),
                ),
              );
            }

            // Error or timeout
            if (docSnap.hasError) {
              debugPrint('AuthGate: profile error ${docSnap.error}');
              return _buildMessage('שגיאה בטעינת פרופיל: ${docSnap.error}');
            }

            // Profile missing
            if (!docSnap.hasData || !docSnap.data!.exists) {
              debugPrint('AuthGate: profile missing');
              return _buildMessage('משתמש לא קיים במערכת.\nפנה למנהל המערכת.');
            }

            final data = docSnap.data!.data() as Map<String, dynamic>?;
            final role = (data?['role'] ?? '').toString().toLowerCase();
            debugPrint('AuthGate: role=$role');

            if (role != 'instructor' && role != 'admin') {
              return _buildMessage(
                'אין הרשאה - נדרש תפקיד מדריך או מנהל.\nהתפקיד שלך: $role',
              );
            }

            currentUser = AppUser(
              username: user.email ?? user.uid,
              name: (data?['name'] ?? user.email ?? ''),
              role: role == 'admin' ? 'Admin' : 'Instructor',
              uid: user.uid,
            );
            // Note: MainScreen.initState will load feedbacks
            // Removed duplicate preload here to prevent race condition

            debugPrint('AuthGate: authorized → MainScreen');
            return const MainScreen();
          },
        );
      },
    );
  }

  Widget _buildMessage(String message) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אין הרשאה'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                style: const TextStyle(fontSize: 18, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              icon: const Icon(Icons.logout),
              label: const Text('התנתק'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ================== READINESS / ALERTS SERVICES & PAGES ================== */

class ReadinessSnapshot {
  final DateTime at;
  final Map<String, double> personScores; // name -> 0-100
  ReadinessSnapshot({required this.at, required this.personScores});
  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'personScores': personScores,
  };
  static ReadinessSnapshot fromJson(Map<String, dynamic> j) =>
      ReadinessSnapshot(
        at: DateTime.parse(j['at']),
        personScores: Map<String, double>.from(j['personScores'] ?? {}),
      );
}

class ReadinessService {
  // Weights aligned with current evaluation criteria (equal weight by default)
  static const Map<String, double> weights = {
    'פוש': 0.1111111111111111,
    'הכרזה': 0.1111111111111111,
    'הפצה': 0.1111111111111111,
    'מיקום המפקד': 0.1111111111111111,
    'מיקום הכוח': 0.1111111111111111,
    'חיילות פרט': 0.1111111111111111,
    'מקצועיות המחלקה': 0.1111111111111111,
    'הבנת האירוע': 0.1111111111111111,
    'תפקוד באירוע': 0.1111111111111111,
  };

  // compute readiness for a person across feedbacks
  static double computeReadinessForPerson(
    String person,
    List<FeedbackModel> data,
  ) {
    // average per category for the person
    final Map<String, List<int>> vals = {for (final k in weights.keys) k: []};
    for (final f in data.where((x) => x.name == person)) {
      for (final k in weights.keys) {
        final v = f.scores[k];
        if (v != null && v != 0) {
          final list = vals[k];
          if (list == null) {
            vals[k] = [v];
          } else {
            list.add(v);
          }
        }
      }
    }
    if (vals.values.every((l) => l.isEmpty)) return 0.0;
    double weighted = 0.0;
    for (final k in weights.keys) {
      final list = vals[k];
      if (list == null || list.isEmpty) continue;
      final avg = list.reduce((a, b) => a + b) / list.length; // 1..5
      weighted += (avg / 5.0) * (weights[k] ?? 0.0);
    }
    return (weighted * 100.0);
  }

  // compute readiness per exercise
  static double computeReadinessForExercise(
    String exercise,
    List<FeedbackModel> data,
  ) {
    final Map<String, List<int>> vals = {for (final k in weights.keys) k: []};
    for (final f in data.where((x) => x.exercise == exercise)) {
      for (final k in weights.keys) {
        final v = f.scores[k];
        if (v != null && v != 0) {
          final list = vals[k];
          if (list == null) {
            vals[k] = [v];
          } else {
            list.add(v);
          }
        }
      }
    }
    if (vals.values.every((l) => l.isEmpty)) return 0.0;
    double weighted = 0.0;
    for (final k in weights.keys) {
      final list = vals[k];
      if (list == null || list.isEmpty) continue;
      final avg = list.reduce((a, b) => a + b) / list.length;
      weighted += (avg / 5.0) * (weights[k] ?? 0.0);
    }
    return (weighted * 100.0);
  }

  // persist snapshot
  static Future<void> saveSnapshot(ReadinessSnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('readiness_history') ?? '[]';
    final List<dynamic> arr = json.decode(raw);
    arr.add(snap.toJson());
    await prefs.setString('readiness_history', json.encode(arr));
  }

  static Future<List<ReadinessSnapshot>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('readiness_history') ?? '[]';
    final List<dynamic> arr = json.decode(raw);
    return arr
        .map((e) => ReadinessSnapshot.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // generate alerts: returns list of maps describing alerts
  static List<Map<String, dynamic>> generateAlerts(List<FeedbackModel> data) {
    final List<Map<String, dynamic>> alerts = [];
    // per person, compare exercises ordered by date (simple: by createdAt)
    final persons = data.map((f) => f.name).toSet();
    for (final p in persons) {
      final perPerson = data.where((f) => f.name == p).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (perPerson.length < 2) continue;
      // compute readiness per exercise occurrence
      final List<double> vals = [];
      final List<String> exNames = [];
      for (final f in perPerson) {
        final r = computeReadinessForPerson(p, [f]);
        vals.add(r);
        exNames.add(f.exercise);
      }
      for (var i = 1; i < vals.length; i++) {
        if (vals[i - 1] - vals[i] > 10.0) {
          alerts.add({
            'who': p,
            'from': exNames[i - 1],
            'to': exNames[i],
            'drop': (vals[i - 1] - vals[i]).toStringAsFixed(1),
          });
        }
      }
    }
    // category average <=3 (on 1..5) -> alert
    final Map<String, List<int>> catVals = {
      for (final k in weights.keys) k: [],
    };
    for (final f in data) {
      for (final k in weights.keys) {
        final v = f.scores[k];
        if (v != null && v != 0) {
          final list = catVals[k];
          if (list == null) {
            catVals[k] = [v];
          } else {
            list.add(v);
          }
        }
      }
    }
    for (final k in catVals.keys) {
      final list = catVals[k];
      if (list == null || list.isEmpty) continue;
      final avg = list.reduce((a, b) => a + b) / list.length;
      if (avg <= 3.0) {
        alerts.add({'category': k, 'avg': avg.toStringAsFixed(2)});
      }
    }
    return alerts;
  }
}

class ReadinessPage extends StatefulWidget {
  const ReadinessPage({super.key});
  @override
  State<ReadinessPage> createState() => _ReadinessPageState();
}

class _ReadinessPageState extends State<ReadinessPage> {
  DateTime? from;
  DateTime? to;

  Future<void> snapshotNow() async {
    // compute readiness per person
    final persons = feedbackStorage.map((f) => f.name).toSet();
    final Map<String, double> map = {};
    for (final p in persons) {
      map[p] = ReadinessService.computeReadinessForPerson(p, feedbackStorage);
    }
    final snap = ReadinessSnapshot(at: DateTime.now(), personScores: map);
    await ReadinessService.saveSnapshot(snap);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('נשמר מדד כשירות')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';
    final persons = feedbackStorage.map((f) => f.name).toSet().toList();
    persons.sort();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מדד כשירות'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  ElevatedButton(
                    onPressed: isAdmin ? snapshotNow : null,
                    child: const Text('שמור מדידה'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/alerts'),
                    child: const Text('התראות'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: persons.map((p) {
                    final score = ReadinessService.computeReadinessForPerson(
                      p,
                      feedbackStorage,
                    ).round();
                    final color = score >= 80
                        ? Colors.green
                        : (score >= 60 ? Colors.yellow : Colors.red);
                    return ListTile(
                      title: Text(
                        p,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: CircleAvatar(
                        backgroundColor: color,
                        child: Text('$score'),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});
  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  bool _isMigrating = false;

  Future<void> _runMigration() async {
    setState(() => _isMigrating = true);

    try {
      await migrateFeedbackRouting();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Migration completed successfully! Check console for details.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh feedback storage after migration
        await loadFeedbacksForCurrentUser(isAdmin: true);
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Migration failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMigrating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';
    if (!isAdmin) return const Scaffold(body: Center(child: Text('אין הרשאה')));
    final alerts = ReadinessService.generateAlerts(feedbackStorage);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('התראות מבצעיות'),
          leading: const StandardBackButton(),
          actions: [
            // Migration button for admins
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ElevatedButton.icon(
                onPressed: _isMigrating ? null : _runMigration,
                icon: _isMigrating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.build_circle, size: 18),
                label: Text(_isMigrating ? 'Migrating...' : 'Migrate Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Migration info card
            Card(
              color: Colors.blue.shade50,
              margin: const EdgeInsets.all(12.0),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Data Migration Tool',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Fixes incorrectly saved feedback types (מעגל פתוח, מעגל פרוץ, סריקות רחוב) '
                      'that were saved to wrong folders. Moves them to correct folders only.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            // Alerts list
            Expanded(
              child: ListView(
                children: alerts.map((a) {
                  if (a.containsKey('who')) {
                    return ListTile(
                      title: Text('נפילה מעל 10%: ${a['who']}'),
                      subtitle: Text(
                        'מ ${a['from']} ל ${a['to']} — ${a['drop']}',
                      ),
                    );
                  }
                  return ListTile(
                    title: Text('קטגוריה חלשה: ${a['category']}'),
                    subtitle: Text('ממוצע ${a['avg']}'),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommanderDashboardPage extends StatelessWidget {
  const CommanderDashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';
    if (!isAdmin) return const Scaffold(body: Center(child: Text('אין הרשאה')));
    final persons = feedbackStorage.map((f) => f.name).toSet().toList();
    final List<MapEntry<String, double>> scores = persons
        .map(
          (p) => MapEntry(
            p,
            ReadinessService.computeReadinessForPerson(p, feedbackStorage),
          ),
        )
        .toList();
    scores.sort((a, b) => b.value.compareTo(a.value));
    final top5 = scores.take(5).toList();
    final bottom5 = scores.reversed.take(5).toList();
    final alerts = ReadinessService.generateAlerts(feedbackStorage);
    final overall = scores.isEmpty
        ? 0.0
        : scores.map((e) => e.value).reduce((a, b) => a + b) / scores.length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('לוח מבצע'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView(
            children: [
              ListTile(
                title: const Text('ממוצע כולל'),
                trailing: Text(overall.toStringAsFixed(1)),
              ),
              const Divider(),
              const Text(
                'Top 5',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...top5.map(
                (e) => ListTile(
                  title: Text(e.key),
                  trailing: Text(e.value.toStringAsFixed(1)),
                ),
              ),
              const Divider(),
              const Text(
                'Bottom 5',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...bottom5.map(
                (e) => ListTile(
                  title: Text(e.key),
                  trailing: Text(e.value.toStringAsFixed(1)),
                ),
              ),
              const Divider(),
              const Text(
                'התראות אחרונות',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...alerts
                  .take(10)
                  .map(
                    (a) => ListTile(
                      title: Text(
                        a.containsKey('who')
                            ? 'נפילה: ${a['who']}'
                            : 'קטגוריה: ${a['category']}',
                      ),
                      subtitle: Text(
                        a.containsKey('drop') ? '${a['drop']}' : '${a['avg']}',
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  late final List<Navigator> _pages;
  bool _loadingData = true;

  // GlobalKey for StatisticsPage to access its state
  final GlobalKey<_StatisticsPageState> _statisticsKey =
      GlobalKey<_StatisticsPageState>();

  // GlobalKeys for nested navigators
  final GlobalKey<NavigatorState> _homeNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _exercisesNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _feedbacksNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _statisticsNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _materialsNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _pages = [
      Navigator(
        key: _homeNavigatorKey,
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) => const HomePage(),
            settings: settings,
          );
        },
      ),
      Navigator(
        key: _exercisesNavigatorKey,
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/screenings_menu':
              return MaterialPageRoute(
                builder: (_) => const ScreeningsMenuPage(courseType: 'miunim'),
                settings: settings,
              );
            case '/range_selection':
              return MaterialPageRoute(
                builder: (_) => const RangeSelectionPage(),
                settings: settings,
              );
            case '/surprise_drills':
              return MaterialPageRoute(
                builder: (_) => const SurpriseDrillsEntryPage(),
                settings: settings,
              );
            case '/training_summary':
              return MaterialPageRoute(
                builder: (_) => const TrainingSummaryFormPage(),
                settings: settings,
              );
            case '/feedback_form':
              final exercise = settings.arguments as String?;
              return MaterialPageRoute(
                builder: (_) => FeedbackFormPage(exercise: exercise),
                settings: settings,
              );
            default:
              return MaterialPageRoute(
                builder: (_) => const ExercisesPage(),
                settings: settings,
              );
          }
        },
      ),
      Navigator(
        key: _feedbacksNavigatorKey,
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/universal_export':
              return MaterialPageRoute(
                builder: (_) => const UniversalExportPage(),
                settings: settings,
              );
            case '/instructor_course_selection_feedbacks':
              return MaterialPageRoute(
                builder: (_) => const InstructorCourseSelectionFeedbacksPage(),
                settings: settings,
              );
            case '/screenings_menu':
              return MaterialPageRoute(
                builder: (_) => const ScreeningsMenuPage(courseType: 'miunim'),
                settings: settings,
              );
            case '/export_selection':
              return MaterialPageRoute(
                builder: (_) => const ExportSelectionPage(),
                settings: settings,
              );
            case '/feedback_details':
              final feedback = settings.arguments as FeedbackModel;
              return MaterialPageRoute(
                builder: (_) => FeedbackDetailsPage(feedback: feedback),
                settings: settings,
              );
            default:
              return MaterialPageRoute(
                builder: (_) => const FeedbacksPage(),
                settings: settings,
              );
          }
        },
      ),
      Navigator(
        key: _statisticsNavigatorKey,
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/general_statistics':
              return MaterialPageRoute(
                builder: (_) => const GeneralStatisticsPage(),
                settings: settings,
              );
            case '/range_statistics':
              return MaterialPageRoute(
                builder: (_) => const RangeStatisticsPage(),
                settings: settings,
              );
            case '/surprise_drills_statistics':
              return MaterialPageRoute(
                builder: (_) => const SurpriseDrillsStatisticsPage(),
                settings: settings,
              );
            case '/brigade_474_statistics':
              return MaterialPageRoute(
                builder: (_) => const Brigade474StatisticsPage(),
                settings: settings,
              );
            default:
              return MaterialPageRoute(
                builder: (_) => StatisticsPage(key: _statisticsKey),
                settings: settings,
              );
          }
        },
      ),
      Navigator(
        key: _materialsNavigatorKey,
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/maagal_patuach':
              return MaterialPageRoute(
                builder: (_) => const MaagalPatuachPage(),
                settings: settings,
              );
            case '/sheva':
              return MaterialPageRoute(
                builder: (_) => const ShevaPrinciplesPage(),
                settings: settings,
              );
            case '/saabal':
              return MaterialPageRoute(
                builder: (_) => const SaabalPage(),
                settings: settings,
              );
            case '/poruz':
              return MaterialPageRoute(
                builder: (_) => const MaagalPoruzPage(),
                settings: settings,
              );
            case '/sarikot':
              return MaterialPageRoute(
                builder: (_) => const SarikotFixedPage(),
                settings: settings,
              );
            case '/about':
              return MaterialPageRoute(
                builder: (_) => const AboutPage(),
                settings: settings,
              );
            default:
              return MaterialPageRoute(
                builder: (_) => const MaterialsPage(),
                settings: settings,
              );
          }
        },
      ),
    ];
    // Initial data load from Firestore to populate feedbackStorage
    Future.microtask(() async {
      try {
        // בדיקה זמנית - מריצים שאילתה פשוטה קודם
        await testSimpleFeedbackQuery();

        final isAdmin = currentUser?.role == 'Admin';
        debugPrint('\n🔍 ===== DIAGNOSTIC INFO =====');
        debugPrint('   currentUser.name: ${currentUser?.name}');
        debugPrint('   currentUser.role: ${currentUser?.role}');
        debugPrint('   currentUser.uid: ${currentUser?.uid}');
        debugPrint(
          '   auth.currentUser.uid: ${FirebaseAuth.instance.currentUser?.uid}',
        );
        debugPrint('   isAdmin: $isAdmin');
        debugPrint(
          '   feedbackStorage.length BEFORE load: ${feedbackStorage.length}',
        );
        debugPrint('🔍 ===========================\n');
        debugPrint(
          '📥 Loading feedbacks for role: ${currentUser?.role} (isAdmin: $isAdmin)',
        );
        await loadFeedbacksForCurrentUser(isAdmin: isAdmin).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('MainScreen: feedback load timeout');
            // Don't throw; just continue with empty feedbackStorage
          },
        );

        // ✅ קריטי: קורא ל-setState אחרי שה-feedbackStorage התעדכן
        if (mounted) {
          setState(() {
            debugPrint('\n✅ ===== UI UPDATE =====');
            debugPrint(
              '   feedbackStorage.length AFTER load: ${feedbackStorage.length}',
            );
            debugPrint('   Triggering rebuild...');
            debugPrint('✅ ====================\n');
          });
        }
      } catch (e) {
        debugPrint('MainScreen: feedback load error $e');
        // Continue; let UI show empty state
      } finally {
        // Always clear loading state, regardless of success/timeout/error
        if (mounted) {
          setState(() {
            _loadingData = false;
            debugPrint('MainScreen: _loadingData cleared for instructor/admin');
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: _loadingData
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('טוען נתונים...'),
                        ],
                      ),
                    )
                  : IndexedStack(index: selectedIndex, children: _pages),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (i) => setState(() => selectedIndex = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.blueGrey.shade900,
          selectedItemColor: Colors.orangeAccent,
          unselectedItemColor: Colors.white,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'בית'),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment),
              label: 'תרגילים',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.feedback),
              label: 'משובים',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: 'סטטיסטיקה',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book),
              label: 'חומר עיוני',
            ),
          ],
        ),
      ),
    );
  }
}

/* ================== LOGIN ================== */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryLogin() async {
    final email = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('אנא מלא אימייל וסיסמה')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ignore: avoid_print
      print('🔵 התחלת תהליך התחברות: $email');

      // Step 1: Sign in with Firebase Auth
      // ignore: avoid_print
      print('🔐 שלב 1: אימות Firebase Auth');
      final UserCredential cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass);

      // ignore: avoid_print
      print('✅ אימות הצליח! UID: ${cred.user?.uid}');

      // Step 2: Verify currentUser is not null
      if (cred.user == null || cred.user!.uid.isEmpty) {
        // ignore: avoid_print
        print('❌ שגיאה: currentUser הוא null למרות התחברות מוצלחת');
        if (mounted) setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאת אימות - לא הצלחנו לאמת את המשתמש'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final String uid = cred.user!.uid;

      // Step 3: Read user document from Firestore with timeout
      // ignore: avoid_print
      print('📋 שלב 2: קריאת מסמך משתמש מ-Firestore (users/$uid)');
      String? userRole;
      bool docExists = false;

      try {
        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 5));

        docExists = profileDoc.exists;

        if (profileDoc.exists) {
          final data = profileDoc.data();
          userRole = data?['role'] as String?;
          // ignore: avoid_print
          print('✅ מסמך משתמש נמצא. Role: $userRole');
        } else {
          // ignore: avoid_print
          print('⚠️ מסמך משתמש לא קיים ב-Firestore');
        }
      } on TimeoutException {
        // ignore: avoid_print
        print('⏱️ Timeout בקריאה מ-Firestore (5 שניות)');
      } on FirebaseException catch (fe) {
        // ignore: avoid_print
        print('⚠️ שגיאת Firestore: ${fe.code} - ${fe.message}');
      } catch (e) {
        // ignore: avoid_print
        print('⚠️ שגיאה לא צפויה בקריאת Firestore: $e');
      }

      // If document doesn't exist, show error and stop
      if (!docExists) {
        if (mounted) setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('משתמש לא קיים במערכת - פנה למנהל'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Normalize role
      userRole = (userRole?.toLowerCase() ?? '').trim();
      final bool isAdmin = userRole == 'admin';

      debugPrint('✅ התחברות הושלמה בהצלחה!');
      debugPrint('   Email: $email');
      debugPrint('   UID: $uid');
      debugPrint('   Role: ${isAdmin ? 'admin' : 'user'}');

      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;

      // AuthGate will automatically navigate based on authStateChanges
      debugPrint('🚀 AuthGate יטפל בניווט אוטומטית');
    } on FirebaseAuthException catch (fae) {
      debugPrint('❌ FirebaseAuthException: ${fae.code}');
      debugPrint('   Message: ${fae.message}');

      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;

      String errorMsg;
      switch (fae.code) {
        case 'user-not-found':
          errorMsg = 'המשתמש לא קיים במערכת';
          break;
        case 'wrong-password':
          errorMsg = 'סיסמה שגויה';
          break;
        case 'invalid-email':
          errorMsg = 'כתובת אימייל לא תקינה';
          break;
        case 'too-many-requests':
          errorMsg = 'יותר מדי ניסיונות התחברות - נסה שוב מאוחר יותר';
          break;
        case 'unknown':
          errorMsg = 'שגיאה לא ידועה - בדוק את ההגדרות של Firebase';
          break;
        default:
          errorMsg = 'שגיאת אימות: ${fae.code}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } catch (e) {
      // ignore: avoid_print
      print('❌ שגיאה כללית: $e');

      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה לא צפויה: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('כניסה')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(labelText: 'אימייל'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: 'סיסמה'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _tryLogin,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('התחבר'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple role-based home pages
class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Home')),
      body: const Center(child: Text('Welcome, Admin')),
    );
  }
}

class UserHomePage extends StatelessWidget {
  const UserHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Home')),
      body: const Center(child: Text('Welcome, User')),
    );
  }
}

/* ================== HOME ================== */

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  static bool _hasPlayed = false; // play only once per app session

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _offset;

  // ✨ NEW: Version tracking for update alert
  String _currentVersion = '';
  String _savedVersion = '';
  bool _showUpdateAlert = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.90,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (_hasPlayed) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
      _hasPlayed = true;
    }

    // ✨ Check for app version changes
    _checkVersionUpdate();
  }

  /// Check if app version has changed - show update alert if needed
  Future<void> _checkVersionUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final prefs = await SharedPreferences.getInstance();

      final currentVersion =
          '${packageInfo.version}+${packageInfo.buildNumber}';
      final savedVersion = prefs.getString('app_version') ?? '';

      if (mounted) {
        setState(() {
          _currentVersion = currentVersion;
          _savedVersion = savedVersion;
          // Show alert if version changed AND we had a previous version
          _showUpdateAlert =
              savedVersion.isNotEmpty && currentVersion != savedVersion;
        });

        debugPrint(
          '🔔 Version check: current=$currentVersion, saved=$savedVersion, showAlert=$_showUpdateAlert',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Version check error: $e');
    }
  }

  /// User acknowledged the update - save new version and hide alert
  Future<void> _dismissUpdateAlert() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_version', _currentVersion);

      if (mounted) {
        setState(() {
          _savedVersion = _currentVersion;
          _showUpdateAlert = false;
        });
      }

      debugPrint('✅ Version saved: $_currentVersion');
    } catch (e) {
      debugPrint('⚠️ Save version error: $e');
    }
  }

  /// Show update instructions dialog
  void _showUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.update, color: Colors.orangeAccent, size: 32),
              SizedBox(width: 12),
              Text('עדכון אפליקציה'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'האפליקציה עודכנה לגרסה חדשה!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'כדי להבטיח שכל העדכונים ייטענו כראוי:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '1️⃣ סגור את האפליקציה',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '2️⃣ פתח את האפליקציה מחדש',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_savedVersion.isNotEmpty)
                Text(
                  'גרסה קודמת: $_savedVersion',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              if (_savedVersion.isNotEmpty) const SizedBox(height: 4),
              Text(
                'גרסה חדשה: $_currentVersion',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _dismissUpdateAlert();
              },
              child: const Text('הבנתי'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: FadeTransition(
              opacity: _opacity,
              child: SlideTransition(
                position: _offset,
                child: ScaleTransition(
                  scale: _scale,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // MAIN HEADING
                        const Text(
                          'מגנים על הבית!!!',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            color: Colors.orangeAccent,
                            letterSpacing: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        // MAIN CARD
                        Card(
                          elevation: 8,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 280,
                              maxWidth: 520,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 28.0,
                                horizontal: 24.0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: const [
                                  Text(
                                    'מגן אנושי',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'משוב בית הספר להגנת היישוב',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'חטיבה 474',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ✨ Update alert button (top center, below header)
          if (_showUpdateAlert)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    child: ElevatedButton.icon(
                      onPressed: _showUpdateDialog,
                      icon: const Icon(Icons.update, size: 24),
                      label: const Text(
                        'עדכון זמין - סגור ופתח את האפליקציה',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        elevation: 12,
                        shadowColor: Colors.orangeAccent.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Logout button in top left corner
          Positioned(
            top: 16,
            left: 16,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      // AuthGate will automatically handle navigation
                    },
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('יציאה'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 14),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Footer
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'משוב מבצר • נוצר על-ידי יותם אלון',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ================== EXERCISES ================== */

class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final exercises = [
      'מטווחים',
      'תרגילי הפתעה',
      'מעגל פתוח',
      'סריקות רחוב',
      'מעגל פרוץ',
      'סיכום אימון',
      'מיונים לקורס מדריכים',
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('תרגילים'),
          leading: const StandardBackButton(),
        ),
        body: ListView.builder(
          itemCount: exercises.length,
          itemBuilder: (ctx, i) {
            final ex = exercises[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 2,
              child: InkWell(
                onTap: () {
                  debugPrint('⚡ פתח משוב עבור "$ex"');
                  // Allow Instructors and Admins to open feedback
                  if (currentUser == null ||
                      (currentUser?.role != 'Instructor' &&
                          currentUser?.role != 'Admin')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('רק מדריכים או מנהל יכולים לפתוח משוב'),
                      ),
                    );
                    return;
                  }

                  // מיונים לקורס מדריכים: זרימה חדשה למסך ניהול מיונים
                  if (ex == 'מיונים לקורס מדריכים') {
                    // Navigate to screenings menu (two-buttons screen)
                    Navigator.of(context).pushNamed('/screenings_menu');
                  } else if (ex == 'מטווחים') {
                    Navigator.of(context).pushNamed('/range_selection');
                  } else if (ex == 'תרגילי הפתעה') {
                    Navigator.of(context).pushNamed('/surprise_drills');
                  } else if (ex == 'סיכום אימון') {
                    Navigator.of(context).pushNamed('/training_summary');
                  } else {
                    Navigator.of(
                      context,
                    ).pushNamed('/feedback_form', arguments: ex);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment,
                        size: 32,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          ex,
                          textAlign: ex == 'תרגילי הפתעה'
                              ? TextAlign.right
                              : TextAlign.start,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/* ================== FEEDBACK FORM ================== */

class FeedbackFormPage extends StatefulWidget {
  final String? exercise;
  const FeedbackFormPage({super.key, this.exercise});

  @override
  State<FeedbackFormPage> createState() => _FeedbackFormPageState();
}

class _FeedbackFormPageState extends State<FeedbackFormPage> {
  final List<String> roles = [
    'רבש"ץ',
    'סגן רבש"ץ',
    'מפקד מחלקה',
    'סגן מפקד מחלקה',
    'לוחם',
  ];
  String? selectedRole;
  String name = '';
  String generalNote = '';
  // instructor is the logged in user
  String instructorNameDisplay = '';
  String instructorRoleDisplay = '';

  final List<String> exercises = ['מעגל פתוח', 'מעגל פרוץ', 'סריקות רחוב'];
  String? selectedExercise;
  String evaluatedName = '';
  String? selectedFolder; // תיקייה נבחרת (חובה)
  String scenario = ''; // תרחיש
  String settlement = ''; // יישוב

  // Custom settlements for manual entry folders
  List<String> customSettlements = [];
  final TextEditingController settlementController = TextEditingController();
  bool isLoadingCustomSettlements = false;

  // Base criteria for מעגל פתוח and מעגל פרוץ (original)
  static const List<String> _baseCriteria = [
    'פוש',
    'הכרזה',
    'הפצה',
    'מיקום המפקד',
    'מיקום הכוח',
    'חיילות פרט',
    'מקצועיות המחלקה',
    'הבנת האירוע',
    'תפקוד באירוע',
  ];

  // Additional criteria for סריקות רחוב only
  static const List<String> _streetScanCriteria = [
    'אבטחה היקפית',
    'שמירה על קשר בתוך הכוח הסורק',
    'שליטה בכוח',
    'יצירת גירוי והאזנה לשטח',
    'עבודה ממרכז הרחוב והחוצה',
  ];

  // Get criteria based on selected exercise
  List<String> get availableCriteria {
    if (selectedExercise == 'סריקות רחוב') {
      return [..._baseCriteria, ..._streetScanCriteria];
    }
    return _baseCriteria;
  }

  // which criteria are active (checkboxes at top)
  final Map<String, bool> activeCriteria = {};

  final Map<String, int> scores = {};
  final Map<String, String> notes = {};
  // Feedback summary field (replaces admin command)
  String feedbackSummary = '';

  // Prevent double-submission
  bool _isSaving = false;

  // Initialize criteria maps for current exercise
  void _initializeCriteriaForExercise() {
    // Clear existing maps
    scores.clear();
    notes.clear();
    activeCriteria.clear();

    // Populate maps for current exercise's criteria
    for (final c in availableCriteria) {
      scores[c] = 0;
      notes[c] = '';
      activeCriteria[c] = false; // do NOT display by default
    }
  }

  @override
  void initState() {
    super.initState();
    selectedExercise =
        (widget.exercise != null && exercises.contains(widget.exercise))
        ? widget.exercise
        : null;
    if (currentUser != null) {
      instructorNameDisplay = currentUser?.name ?? '';
      instructorRoleDisplay = currentUser?.role ?? '';
    }
    _initializeCriteriaForExercise();
    _loadCustomSettlements();
  }

  @override
  void dispose() {
    settlementController.dispose();
    super.dispose();
  }

  // Load custom settlements from Firestore
  Future<void> _loadCustomSettlements() async {
    setState(() => isLoadingCustomSettlements = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('custom_settlements')
          .orderBy('name')
          .get()
          .timeout(const Duration(seconds: 5));

      final List<String> loaded = [];
      for (final doc in snapshot.docs) {
        final name = (doc.data()['name'] ?? '').toString();
        if (name.isNotEmpty) {
          loaded.add(name);
        }
      }

      if (mounted) {
        setState(() {
          customSettlements = loaded;
          isLoadingCustomSettlements = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load custom settlements: $e');
      if (mounted) {
        setState(() => isLoadingCustomSettlements = false);
      }
    }
  }

  // Normalize settlement name for deduplication
  String _normalizeSettlement(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  // Add custom settlement to Firestore
  Future<void> _addCustomSettlement(String name) async {
    final normalized = _normalizeSettlement(name);

    // Check if already exists (case-insensitive)
    final exists = customSettlements.any(
      (s) => _normalizeSettlement(s) == normalized,
    );

    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('היישוב כבר קיים ברשימה')));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('custom_settlements').add({
        'name': name.trim(),
        'createdAt': DateTime.now(),
      });

      setState(() {
        customSettlements.add(name.trim());
        customSettlements.sort();
      });
    } catch (e) {
      debugPrint('Failed to add custom settlement: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה בהוספת יישוב: $e')));
    }
  }

  Future<void> _save() async {
    // Prevent double-submission
    if (_isSaving) {
      debugPrint('⚠️ _save() already in progress, ignoring duplicate call');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    debugPrint('🔵 _save() called, currentUser=${currentUser?.name}');
    // ensure instructor is logged in and is Instructor or Admin
    if (currentUser == null ||
        (currentUser?.role != 'Instructor' && currentUser?.role != 'Admin')) {
      debugPrint('❌ role check failed: ${currentUser?.role}');
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('רק מדריכים או מנהל יכולים לשמור משוב')),
      );
      return;
    }

    if (evaluatedName.trim().isEmpty) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('אנא מלא שם הנבדק')));
      return;
    }

    if (selectedRole == null) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא בחר תפקיד')));
      return;
    }

    if (selectedFolder == null || selectedFolder!.isEmpty) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא בחר תיקייה')));
      return;
    }

    // Validate settlement when folder is selected
    if (selectedFolder != null && settlement.trim().isEmpty) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא בחר/הזן יישוב')));
      return;
    }

    // Build final scores and notes only for active criteria
    final Map<String, int> finalScores = {};
    final Map<String, String> finalNotes = {};
    final List<String> criteriaList = [];
    for (final c in availableCriteria) {
      if (activeCriteria[c] == true) {
        criteriaList.add(c);
        finalScores[c] = scores[c] ?? 0;
        finalNotes[c] = notes[c] ?? '';
      }
    }

    try {
      final now = DateTime.now();
      final uid = currentUser?.uid ?? '';

      // ✅ CRITICAL: Validate folder routing for specific feedback types
      final targetExercises = ['מעגל פתוח', 'מעגל פרוץ', 'סריקות רחוב'];
      final allowedFolders = ['מחלקות ההגנה – חטיבה 474', 'משובים – כללי'];

      if (targetExercises.contains(selectedExercise)) {
        if (!allowedFolders.contains(selectedFolder)) {
          setState(() {
            _isSaving = false;
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'שגיאה: תרגיל "$selectedExercise" יכול להישמר רק תחת "${allowedFolders.join('" או "')}"',
              ),
            ),
          );
          return;
        }
      }

      // Resolve instructor's Hebrew full name from Firestore
      String resolvedInstructorName = instructorNameDisplay;
      if (uid.isNotEmpty) {
        resolvedInstructorName = await resolveUserHebrewName(uid);
      }

      // Map selected folder to canonical fields for these specific feedback types
      String folderKey = '';
      String folderLabel = selectedFolder ?? '';

      if (targetExercises.contains(selectedExercise)) {
        switch (selectedFolder) {
          case 'מחלקות ההגנה – חטיבה 474':
            folderKey = 'defense_474';
            folderLabel = 'מחלקות ההגנה 474';
            break;
          case 'משובים – כללי':
            folderKey = 'general_feedback';
            folderLabel = 'משובים כללי';
            break;
          default:
            // Should never reach here due to validation above
            throw Exception('Invalid folder selection: $selectedFolder');
        }
      }

      final Map<String, dynamic> doc = {
        'role': selectedRole,
        'name': evaluatedName.trim(),
        'exercise': selectedExercise ?? '',
        'scores': finalScores,
        'notes': finalNotes,
        'criteriaList': criteriaList,
        'createdAt': now,
        'createdByName': resolvedInstructorName,
        'createdByUid': uid,
        'instructorName': resolvedInstructorName,
        'instructorRole': instructorRoleDisplay,
        'commandText': '',
        'commandStatus': 'פתוח',
        'summary': feedbackSummary,
        'folder': selectedFolder ?? '',
        'folderKey': folderKey,
        'folderLabel': folderLabel,
        'scenario': scenario,
        'settlement': settlement,
        'attendeesCount': 0,
        'instructorId': uid,
      };

      // Debug logging for folder routing
      if (targetExercises.contains(selectedExercise)) {
        debugPrint('\n========== FEEDBACK SAVE: SPECIFIC TYPE ==========');
        debugPrint('SAVE: exercise=$selectedExercise');
        debugPrint('SAVE: selectedFolder=$selectedFolder');
        debugPrint('SAVE: folderKey=$folderKey');
        debugPrint('SAVE: folderLabel=$folderLabel');
        debugPrint('SAVE: Will appear under משובים → $selectedFolder');
        debugPrint('SAVE: Single destination only - no duplicates');
        debugPrint('===============================================\n');
      }

      final ref = await FirebaseFirestore.instance
          .collection('feedbacks')
          .add(doc);

      // Update local cache (optional but useful for immediate UI refresh)
      final model = FeedbackModel.fromMap(doc, id: ref.id);
      if (model != null) {
        feedbackStorage.insert(0, model);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('המשוב נשמר בהצלחה')));
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ save feedback error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('שגיאה בשמירה: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('משוב - ${selectedExercise ?? ''}'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView(
            children: [
              // Instructor (required)
              const Text('מדריך ממשב'),
              const SizedBox(height: 8),
              Text(
                instructorNameDisplay.isNotEmpty
                    ? instructorNameDisplay
                    : 'לא מחובר',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'תפקיד: ${instructorRoleDisplay.isNotEmpty ? instructorRoleDisplay : 'לא מוגדר'}',
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),

              // 1. תיקייה (ראשונה)
              const Text(
                'תיקייה',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (ctx) {
                  // Determine allowed folders based on selected exercise
                  List<String> allowedFolders;

                  // For specific exercises, allow all 3 folders
                  if (selectedExercise == 'מעגל פתוח' ||
                      selectedExercise == 'מעגל פרוץ' ||
                      selectedExercise == 'סריקות רחוב') {
                    allowedFolders = [
                      'מחלקות ההגנה – חטיבה 474',
                      'משובים – כללי',
                    ];
                  } else {
                    // For other exercises, keep the original 2 folders
                    allowedFolders = [
                      'מחלקות ההגנה – חטיבה 474',
                      'משובים – כללי',
                    ];
                  }

                  // Display name mapping (internal value -> display label)
                  String getDisplayName(String internalValue) {
                    switch (internalValue) {
                      case 'מחלקות ההגנה – חטיבה 474':
                        return 'מחלקות הגנה 474';
                      default:
                        return internalValue;
                    }
                  }

                  return DropdownButtonFormField<String>(
                    initialValue: selectedFolder,
                    hint: const Text('בחר תיקייה (חובה)'),
                    decoration: const InputDecoration(
                      labelText: 'בחירת תיקייה',
                      border: OutlineInputBorder(),
                    ),
                    items: allowedFolders
                        .map(
                          (folder) => DropdownMenuItem(
                            value: folder,
                            child: Text(getDisplayName(folder)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      selectedFolder = v;
                      // Clear settlement when folder changes
                      settlement = '';
                      settlementController.clear();
                    }),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 2. יישוב (directly under folder, conditional behavior)
              if (selectedFolder == 'מחלקות ההגנה – חטיבה 474') ...[
                // Folder 474: Dropdown from Golan settlements
                const Text(
                  'יישוב',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue:
                      settlement.isNotEmpty &&
                          golanSettlements.contains(settlement)
                      ? settlement
                      : null,
                  hint: const Text('בחר יישוב'),
                  decoration: const InputDecoration(
                    labelText: 'בחר יישוב',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(color: Colors.black87, fontSize: 16),
                  dropdownColor: Colors.white,
                  items: golanSettlements
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => settlement = v ?? ''),
                ),
                const SizedBox(height: 12),
              ] else if (selectedFolder == 'משובים – כללי') ...[
                // Other folders: Manual text field with autocomplete
                const Text(
                  'יישוב',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    final normalized = _normalizeSettlement(
                      textEditingValue.text,
                    );
                    return customSettlements.where((String option) {
                      return _normalizeSettlement(option).contains(normalized);
                    });
                  },
                  onSelected: (String selection) {
                    setState(() {
                      settlement = selection;
                      settlementController.text = selection;
                    });
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                        // Sync with our controller
                        if (controller.text.isEmpty && settlement.isNotEmpty) {
                          controller.text = settlement;
                        }
                        settlementController.text = controller.text;

                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'יישוב',
                            border: const OutlineInputBorder(),
                            hintText: 'הקלד שם יישוב',
                            suffixIcon: controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.add_circle),
                                    tooltip: 'הוסף לרשימה',
                                    onPressed: () async {
                                      final text = controller.text.trim();
                                      if (text.isNotEmpty) {
                                        await _addCustomSettlement(text);
                                      }
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (v) =>
                              setState(() => settlement = v.trim()),
                        );
                      },
                ),
                if (customSettlements.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: customSettlements.take(10).map((s) {
                      return ActionChip(
                        label: Text(s),
                        onPressed: () {
                          setState(() {
                            settlement = s;
                            settlementController.text = s;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),
              ],

              // 3. תפקיד
              const Text(
                'תפקיד',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (ctx) {
                  final items = roles.toSet().toList();
                  final value = items.contains(selectedRole)
                      ? selectedRole
                      : null;
                  return DropdownButtonFormField<String>(
                    initialValue: value,
                    hint: const Text('בחר תפקיד'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: items
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => selectedRole = v),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 4. שם הנבדק
              TextField(
                decoration: const InputDecoration(
                  labelText: 'שם הנבדק',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => evaluatedName = v,
              ),
              const SizedBox(height: 12),

              // 5. תרחיש
              TextField(
                decoration: const InputDecoration(
                  labelText: 'תרחיש',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (v) => setState(() => scenario = v),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              // Criteria selector (checkboxes)
              const Text(
                'בחר קריטריונים להערכתם',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: availableCriteria.map((c) {
                  return FilterChip(
                    label: Text(c),
                    selected: activeCriteria[c] ?? false,
                    onSelected: (sel) =>
                        setState(() => activeCriteria[c] = sel),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Active criteria inputs
              ...availableCriteria.where((c) => activeCriteria[c] == true).map((
                c,
              ) {
                final val = scores[c] ?? 0;
                // Use 1-5 scale for "תפקוד באירוע", 1,3,5 for others
                final scoreOptions = c == 'תפקוד באירוע'
                    ? [1, 2, 3, 4, 5]
                    : [1, 3, 5];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceEvenly,
                        children: scoreOptions.map((v) {
                          final selected = val == v;
                          final isEdgeValue = v == 1 || v == 5;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: selected
                                      ? Colors.blueAccent
                                      : Colors.grey.shade300,
                                  foregroundColor: selected
                                      ? Colors.white
                                      : Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: selected ? 4 : 1,
                                ),
                                onPressed: () => setState(() => scores[c] = v),
                                child: Text(
                                  v.toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isEdgeValue) ...[
                                const SizedBox(height: 4),
                                Text(
                                  v == 1 ? 'נמוך מאוד' : 'גבוה מאוד',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(labelText: 'הערות'),
                        maxLines: 2,
                        onChanged: (t) => notes[c] = t,
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              // Feedback summary section (for all users)
              const Text(
                'סיכום משוב',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'סיכום',
                  hintText: 'הזן סיכום כללי של המשוב...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                onChanged: (v) => setState(() => feedbackSummary = v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('שמור משוב'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// helper removed: statuses are not editable in UI (read-only for admin)

/* ================== TRAINING SUMMARY FORM PAGE ================== */

class TrainingSummaryFormPage extends StatefulWidget {
  const TrainingSummaryFormPage({super.key});

  @override
  State<TrainingSummaryFormPage> createState() =>
      _TrainingSummaryFormPageState();
}

class _TrainingSummaryFormPageState extends State<TrainingSummaryFormPage> {
  String instructorNameDisplay = '';
  String instructorRoleDisplay = '';
  String? trainingSummaryFolder; // No default - user must select
  String selectedSettlement = '';
  String trainingType = '';
  String summary = '';
  int attendeesCount = 0;
  int instructorsCount = 0; // מספר מדריכים
  late TextEditingController _attendeesCountController;
  late TextEditingController _instructorsCountController; // בקר מספר מדריכים
  final Map<String, TextEditingController> _attendeeNameControllers = {};
  final Map<String, TextEditingController> _instructorNameControllers =
      {}; // בקרים לשמות מדריכים
  bool _isSaving = false;

  // ✨ NEW: Linked feedbacks feature
  List<FeedbackModel> _availableFeedbacks = []; // Feedbacks available to link
  final Set<String> _selectedFeedbackIds = {}; // Selected feedback IDs to link
  bool _isLoadingFeedbacks = false;
  String _feedbackFilterRole = 'הכל'; // Filter by role
  String _feedbackFilterName = ''; // Filter by name

  // ✅ Autocomplete trainees for 474 folder
  List<String> _autocompleteTrainees = [];

  @override
  void initState() {
    super.initState();
    if (currentUser != null) {
      instructorNameDisplay = currentUser?.name ?? '';
      instructorRoleDisplay = currentUser?.role ?? '';
    }
    _attendeesCountController = TextEditingController(
      text: attendeesCount.toString(),
    );
    _instructorsCountController = TextEditingController(
      text: instructorsCount.toString(),
    );
    // ✅ CRITICAL: Load trainees on init if settlement already selected (from draft)
    Future.microtask(() {
      if (trainingSummaryFolder == 'משוב סיכום אימון 474' &&
          selectedSettlement.isNotEmpty) {
        _loadTraineesForAutocomplete(selectedSettlement);
      }
    });
  }

  @override
  void dispose() {
    _attendeesCountController.dispose();
    _instructorsCountController.dispose();
    for (final controller in _attendeeNameControllers.values) {
      controller.dispose();
    }
    for (final controller in _instructorNameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _getAttendeeController(
    String key,
    String initialValue,
  ) {
    if (!_attendeeNameControllers.containsKey(key)) {
      _attendeeNameControllers[key] = TextEditingController(text: initialValue);
    }
    return _attendeeNameControllers[key]!;
  }

  TextEditingController _getInstructorController(
    String key,
    String initialValue,
  ) {
    if (!_instructorNameControllers.containsKey(key)) {
      _instructorNameControllers[key] = TextEditingController(
        text: initialValue,
      );
    }
    return _instructorNameControllers[key]!;
  }

  /// ✅ Load trainees for autocomplete from previous training summaries
  Future<void> _loadTraineesForAutocomplete(String settlement) async {
    if (settlement.isEmpty || trainingSummaryFolder != 'משוב סיכום אימון 474') {
      setState(() => _autocompleteTrainees = []);
      return;
    }

    try {
      final trainees =
          await TraineeAutocompleteService.getTraineesForSettlement(settlement);
      if (mounted) {
        setState(() {
          _autocompleteTrainees = trainees;
        });
        debugPrint(
          '✅ Loaded ${trainees.length} trainees for autocomplete in Training Summary',
        );
      }
    } catch (e) {
      debugPrint('❌ Error loading trainees for autocomplete: $e');
      if (mounted) {
        setState(() => _autocompleteTrainees = []);
      }
    }
  }

  /// ✨ NEW: Open trainee selection dialog and auto-fill table
  Future<void> _openTraineeSelectionDialog() async {
    if (_autocompleteTrainees.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('טוען רשימת חניכים...')));
      return;
    }

    // ✅ שלח את החניכים הנוכחיים כ-preSelected כדי לאפשר עריכה
    final currentTrainees = <String>[];
    for (int i = 0; i < attendeesCount; i++) {
      final controller = _attendeeNameControllers['attendee_$i'];
      final name = controller?.text.trim() ?? '';
      if (name.isNotEmpty) {
        currentTrainees.add(name);
      }
    }

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => TraineeSelectionDialog(
        settlementName: selectedSettlement,
        availableTrainees: _autocompleteTrainees,
        preSelectedTrainees:
            currentTrainees, // ✅ החניכים הנוכחיים יופיעו מסומנים
      ),
    );

    // ✅ אפשר לקבל גם רשימה ריקה אם המשתמש ניקה את כולם
    if (result != null) {
      setState(() {
        // Update attendees count
        attendeesCount = result.length;
        _attendeesCountController.text = attendeesCount.toString();

        // Clear existing controllers
        _attendeeNameControllers.clear();

        // Fill in selected trainees
        for (int i = 0; i < result.length; i++) {
          final controller = TextEditingController(text: result[i]);
          _attendeeNameControllers['attendee_$i'] = controller;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isEmpty ? 'הרשימה נוקתה' : 'נבחרו ${result.length} חניכים',
          ),
        ),
      );
    }
  }

  void _updateAttendeesCount(int count) {
    setState(() {
      attendeesCount = count;
    });
  }

  /// ✨ Load available personal feedbacks from same settlement and same day
  Future<void> _loadAvailableFeedbacks() async {
    if (selectedSettlement.isEmpty) {
      setState(() {
        _availableFeedbacks = [];
        _selectedFeedbackIds.clear();
      });
      return;
    }

    setState(() => _isLoadingFeedbacks = true);

    try {
      // Get today's date range (start and end of day)
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      debugPrint(
        '🔍 Loading feedbacks for settlement: $selectedSettlement, date: ${startOfDay.toIso8601String()}',
      );

      // Simple query by settlement only - filter dates client-side to avoid composite index requirement
      final query = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('settlement', isEqualTo: selectedSettlement);

      debugPrint(
        '🔍 Executing simple query for settlement: $selectedSettlement',
      );

      final snapshot = await query.get().timeout(const Duration(seconds: 15));

      debugPrint('🔍 Query returned ${snapshot.docs.length} documents');

      final List<FeedbackModel> feedbacks = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Filter by date (today only) - client-side
        DateTime? createdAt;
        final ca = data['createdAt'];
        if (ca is Timestamp) {
          createdAt = ca.toDate();
        } else if (ca is String) {
          createdAt = DateTime.tryParse(ca);
        }

        if (createdAt == null) {
          debugPrint('  ⚠️ Doc ${doc.id} has no valid createdAt');
          continue;
        }

        // Check if today
        final isToday =
            createdAt.year == now.year &&
            createdAt.month == now.month &&
            createdAt.day == now.day;

        if (!isToday) {
          continue;
        }

        // Only include personal feedbacks (מעגל פתוח, מעגל פרוץ, סריקות רחוב)
        final exercise = (data['exercise'] as String?) ?? '';
        final folder = (data['folder'] as String?) ?? '';
        final isPersonalFeedback =
            (exercise == 'מעגל פתוח' ||
                exercise == 'מעגל פרוץ' ||
                exercise == 'סריקות רחוב') &&
            (folder == 'מחלקות ההגנה – חטיבה 474' || folder == 'משובים – כללי');

        if (!isPersonalFeedback) {
          debugPrint(
            '  ⚠️ Doc ${doc.id} not personal feedback: exercise=$exercise, folder=$folder',
          );
          continue;
        }

        // Skip temporary/draft feedbacks
        final isTemporary = (data['isTemporary'] as bool?) ?? false;
        if (isTemporary) {
          debugPrint('  ⚠️ Doc ${doc.id} is temporary, skipping');
          continue;
        }

        final model = FeedbackModel.fromMap(data, id: doc.id);
        if (model != null) {
          feedbacks.add(model);
          debugPrint('  ✅ Added feedback: ${model.name} (${model.exercise})');
        }
      }

      debugPrint('✅ Found ${feedbacks.length} personal feedbacks to link');

      if (mounted) {
        setState(() {
          _availableFeedbacks = feedbacks;
          _isLoadingFeedbacks = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading feedbacks for linking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בטעינת משובים: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _availableFeedbacks = [];
          _isLoadingFeedbacks = false;
        });
      }
    }
  }

  /// ✨ Get filtered feedbacks based on role and name filters
  List<FeedbackModel> get _filteredAvailableFeedbacks {
    return _availableFeedbacks.where((f) {
      // Filter by role
      if (_feedbackFilterRole != 'הכל' && f.role != _feedbackFilterRole) {
        return false;
      }
      // Filter by name
      if (_feedbackFilterName.isNotEmpty &&
          !f.name.contains(_feedbackFilterName)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// ✨ Check if a feedback is already linked to another training summary
  Future<String?> _checkIfFeedbackAlreadyLinked(String feedbackId) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'training_summary')
          .where('linkedFeedbackIds', arrayContains: feedbackId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        final settlement = (data['settlement'] as String?) ?? '';
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final dateStr = createdAt != null
            ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
            : '';
        return 'סיכום אימון $settlement ($dateStr)';
      }
    } catch (e) {
      debugPrint('Error checking linked status: $e');
    }
    return null;
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    // Validation
    if (currentUser == null ||
        (currentUser?.role != 'Instructor' && currentUser?.role != 'Admin')) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('רק מדריכים או מנהל יכולים לשמור משוב')),
      );
      return;
    }

    if (trainingSummaryFolder == null || trainingSummaryFolder!.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא בחר תיקייה')));
      return;
    }

    if (selectedSettlement.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא בחר יישוב')));
      return;
    }

    if (trainingType.trim().isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן סוג אימון')));
      return;
    }

    // Validate attendees count
    if (attendeesCount == 0) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן כמות נוכחים')));
      return;
    }

    // Filter out empty attendees and collect names
    final List<String> validAttendees = [];
    for (int i = 0; i < attendeesCount; i++) {
      final controller = _attendeeNameControllers['attendee_$i'];
      final name = controller?.text.trim() ?? '';
      if (name.isNotEmpty) {
        validAttendees.add(name);
      }
    }

    // Validate at least one attendee has a name
    if (validAttendees.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן לפחות נוכח אחד')));
      return;
    }

    try {
      final now = DateTime.now();
      final uid = currentUser?.uid ?? '';

      // Resolve instructor's Hebrew full name from Firestore
      String resolvedInstructorName = instructorNameDisplay;
      if (uid.isNotEmpty) {
        resolvedInstructorName = await resolveUserHebrewName(uid);
      }

      // Filter out empty instructors and collect names
      final List<String> validInstructors = [];
      for (int i = 0; i < instructorsCount; i++) {
        final controller = _instructorNameControllers['instructor_$i'];
        final name = controller?.text.trim() ?? '';
        if (name.isNotEmpty) {
          validInstructors.add(name);
        }
      }

      // ✅ Map folder selection to canonical keys for filtering
      String folderKey;
      String folderLabel = trainingSummaryFolder ?? '';

      if (trainingSummaryFolder == 'סיכום אימון כללי') {
        folderKey = 'training_summary_general';
      } else {
        folderKey = 'training_summary_474';
      }

      final Map<String, dynamic> doc = {
        'folder': trainingSummaryFolder,
        'folderKey': folderKey, // ✅ Add canonical key for filtering
        'folderLabel': folderLabel, // ✅ Add label for display
        'settlement': selectedSettlement,
        'trainingType': trainingType,
        'attendees': validAttendees,
        'attendeesCount': validAttendees.length,
        'instructorsCount': validInstructors.length,
        'instructors': validInstructors,
        'summary': summary,
        'instructorName': resolvedInstructorName,
        'instructorRole': instructorRoleDisplay,
        'instructorId': uid,
        'createdAt': now,
        'createdByName': resolvedInstructorName,
        'createdByUid': uid,
        // For compatibility with existing feedback system
        'role': '',
        'name': selectedSettlement,
        'exercise': 'סיכום אימון',
        'scores': {},
        'notes': {},
        'criteriaList': [],
        'commandText': '',
        'commandStatus': 'פתוח',
        'scenario': '',
        'module': 'training_summary',
        'type': 'training_summary',
        'isTemporary': false,
        // ✨ NEW: Linked feedbacks
        'linkedFeedbackIds': _selectedFeedbackIds.toList(),
      };

      final ref = await FirebaseFirestore.instance
          .collection('feedbacks')
          .add(doc);

      // Update local cache
      final model = FeedbackModel.fromMap(doc, id: ref.id);
      if (model != null) {
        feedbackStorage.insert(0, model);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('הסיכום נשמר בהצלחה')));
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ save training summary error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('שגיאה בשמירה: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סיכום אימון 474'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView(
            children: [
              // 1. Instructor (read-only)
              const Text(
                'מדריך ממשב',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                instructorNameDisplay.isNotEmpty
                    ? instructorNameDisplay
                    : 'לא מחובר',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'תפקיד: ${instructorRoleDisplay.isNotEmpty ? instructorRoleDisplay : 'לא מוגדר'}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),

              // 2. Folder selection (dropdown)
              const Text(
                'תיקייה',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('training_folder_$trainingSummaryFolder'),
                initialValue: trainingSummaryFolder,
                hint: const Text('בחר תיקייה'),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                    value: 'משוב סיכום אימון 474',
                    child: Text('סיכום אימון 474'),
                  ),
                  DropdownMenuItem(
                    value: 'סיכום אימון כללי',
                    child: Text('סיכום אימון כללי'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  trainingSummaryFolder = v;
                  // Reset settlement when folder changes
                  selectedSettlement = '';
                }),
              ),
              const SizedBox(height: 12),

              // 3. Settlement - conditional based on folder
              const Text(
                'יישוב',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (trainingSummaryFolder == 'סיכום אימון כללי') ...[
                // General folder: free text input
                TextField(
                  controller: TextEditingController(text: selectedSettlement)
                    ..selection = TextSelection.collapsed(
                      offset: selectedSettlement.length,
                    ),
                  decoration: const InputDecoration(
                    labelText: 'יישוב',
                    border: OutlineInputBorder(),
                    hintText: 'הזן שם יישוב',
                  ),
                  onChanged: (v) => setState(() => selectedSettlement = v),
                ),
              ] else ...[
                // 474 folder: dropdown from Golan settlements
                DropdownButtonFormField<String>(
                  initialValue: selectedSettlement.isNotEmpty
                      ? selectedSettlement
                      : null,
                  hint: const Text('בחר יישוב'),
                  decoration: const InputDecoration(
                    labelText: 'בחר יישוב',
                    border: OutlineInputBorder(),
                  ),
                  items: golanSettlements
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => selectedSettlement = v ?? '');
                    // ✅ Load trainees for autocomplete when settlement changes
                    if (v != null && v.isNotEmpty) {
                      _loadTraineesForAutocomplete(v);
                    }
                  },
                ),
              ],
              const SizedBox(height: 12),

              // 4. Training type (free text)
              const Text(
                'סוג אימון',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'סוג אימון',
                  hintText: 'לדוגמה: אימון ירי, אימון שטח, תרגיל לילה',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => trainingType = v),
              ),
              const SizedBox(height: 12),

              // 6. מספר מדריכים
              const Text(
                'מספר מדריכים באימון',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instructorsCountController,
                decoration: const InputDecoration(
                  labelText: 'מספר מדריכים',
                  hintText: 'הזן מספר מדריכים (אופציונלי)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final count = int.tryParse(v) ?? 0;
                  setState(() {
                    instructorsCount = count;
                  });
                },
              ),
              const SizedBox(height: 12),

              // 7. Instructors table (displayed when count > 0)
              if (instructorsCount > 0) ...[
                const Text(
                  'מדריכים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.blueGrey.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Table header
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: const [
                              SizedBox(
                                width: 60,
                                child: Text(
                                  'מספר',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'שם',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Instructors rows
                        ...List.generate(instructorsCount, (index) {
                          final controllerKey = 'instructor_$index';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                // Number column
                                Container(
                                  width: 60,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Name column - Autocomplete with suggestions
                                Expanded(
                                  child: Autocomplete<String>(
                                    optionsBuilder:
                                        (TextEditingValue textEditingValue) {
                                          if (textEditingValue.text.isEmpty) {
                                            return brigade474Instructors;
                                          }
                                          return brigade474Instructors.where((
                                            name,
                                          ) {
                                            return name.contains(
                                              textEditingValue.text,
                                            );
                                          });
                                        },
                                    onSelected: (String selection) {
                                      setState(() {
                                        _getInstructorController(
                                          controllerKey,
                                          '',
                                        ).text = selection;
                                      });
                                    },
                                    fieldViewBuilder:
                                        (
                                          context,
                                          controller,
                                          focusNode,
                                          onFieldSubmitted,
                                        ) {
                                          // Sync with instructor controller
                                          final instructorController =
                                              _getInstructorController(
                                                controllerKey,
                                                '',
                                              );
                                          if (controller.text.isEmpty &&
                                              instructorController
                                                  .text
                                                  .isNotEmpty) {
                                            controller.text =
                                                instructorController.text;
                                          }
                                          // Update instructor controller when autocomplete changes
                                          controller.addListener(() {
                                            instructorController.text =
                                                controller.text;
                                          });

                                          return TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            decoration: const InputDecoration(
                                              hintText: 'בחר או הקלד שם מדריך',
                                              labelText: 'שם מדריך',
                                              border: OutlineInputBorder(),
                                              filled: true,
                                              fillColor: Colors.white,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 14,
                                                  ),
                                              suffixIcon: Icon(
                                                Icons.arrow_drop_down,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 14,
                                            ),
                                          );
                                        },
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 8. בחירת חניכים - כפתור מרכזי (רק למטווחים 474)
              if (selectedSettlement.isNotEmpty &&
                  _autocompleteTrainees.isNotEmpty) ...[
                const Text(
                  'בחירת נוכחים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openTraineeSelectionDialog,
                    icon: const Icon(Icons.how_to_reg, size: 24),
                    label: const Text(
                      'בחר חניכים מרשימה',
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
              ],

              // 9. כמות נוכחים (ידני)
              const Text(
                'כמות נוכחים',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _attendeesCountController,
                decoration: const InputDecoration(
                  labelText: 'כמות נוכחים',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final count = int.tryParse(v) ?? 0;
                  _updateAttendeesCount(count);
                },
              ),
              const SizedBox(height: 12),

              // 9. Attendees table (displayed when count > 0)
              if (attendeesCount > 0) ...[
                const Text(
                  'נוכחים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.blueGrey.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Table header
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: const [
                              SizedBox(
                                width: 60,
                                child: Text(
                                  'מספר',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'שם',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Attendees rows
                        ...List.generate(attendeesCount, (index) {
                          final controllerKey = 'attendee_$index';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                // Number column
                                Container(
                                  width: 60,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.orangeAccent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Name column - Autocomplete for 474, TextField for general
                                Expanded(
                                  child:
                                      trainingSummaryFolder ==
                                              'משוב סיכום אימון 474' &&
                                          _autocompleteTrainees.isNotEmpty
                                      ? Autocomplete<String>(
                                          optionsBuilder:
                                              (
                                                TextEditingValue
                                                textEditingValue,
                                              ) {
                                                if (textEditingValue
                                                    .text
                                                    .isEmpty) {
                                                  return _autocompleteTrainees;
                                                }
                                                return _autocompleteTrainees
                                                    .where((name) {
                                                      return name.contains(
                                                        textEditingValue.text,
                                                      );
                                                    });
                                              },
                                          onSelected: (String selection) {
                                            setState(() {
                                              _getAttendeeController(
                                                controllerKey,
                                                '',
                                              ).text = selection;
                                            });
                                          },
                                          fieldViewBuilder:
                                              (
                                                context,
                                                controller,
                                                focusNode,
                                                onFieldSubmitted,
                                              ) {
                                                // Sync with attendee controller
                                                final attendeeController =
                                                    _getAttendeeController(
                                                      controllerKey,
                                                      '',
                                                    );
                                                if (controller.text.isEmpty &&
                                                    attendeeController
                                                        .text
                                                        .isNotEmpty) {
                                                  controller.text =
                                                      attendeeController.text;
                                                }
                                                // Update attendee controller when autocomplete changes
                                                controller.addListener(() {
                                                  attendeeController.text =
                                                      controller.text;
                                                });

                                                return TextField(
                                                  controller: controller,
                                                  focusNode: focusNode,
                                                  decoration:
                                                      const InputDecoration(
                                                        hintText:
                                                            'בחר או הקלד שם',
                                                        border:
                                                            OutlineInputBorder(),
                                                        filled: true,
                                                        fillColor: Colors.white,
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 14,
                                                            ),
                                                        suffixIcon: Icon(
                                                          Icons.arrow_drop_down,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontSize: 14,
                                                  ),
                                                );
                                              },
                                        )
                                      : TextField(
                                          controller: _getAttendeeController(
                                            controllerKey,
                                            '',
                                          ),
                                          decoration: const InputDecoration(
                                            hintText: 'שם',
                                            border: OutlineInputBorder(),
                                            filled: true,
                                            fillColor: Colors.white,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 14,
                                                ),
                                          ),
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 14,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 10. Summary (free text, multiline)
              const Text(
                'סיכום האימון',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'סיכום',
                  hintText: 'תאר את האימון, נקודות חשובות, הערות...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 6,
                onChanged: (v) => setState(() => summary = v),
              ),
              const SizedBox(height: 20),

              // ✨ 11. Link personal feedbacks section (only for 474 folder)
              if (trainingSummaryFolder == 'משוב סיכום אימון 474' &&
                  selectedSettlement.isNotEmpty) ...[
                const Divider(thickness: 2),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.link, color: Colors.orangeAccent),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'קישור משובים אישיים',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                    // Refresh button
                    IconButton(
                      icon: _isLoadingFeedbacks
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      onPressed: _isLoadingFeedbacks
                          ? null
                          : _loadAvailableFeedbacks,
                      tooltip: 'רענן רשימת משובים',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'משובים מיישוב $selectedSettlement מהיום בלבד',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),

                // Load feedbacks button if not loaded yet
                if (_availableFeedbacks.isEmpty && !_isLoadingFeedbacks)
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _loadAvailableFeedbacks,
                      icon: const Icon(Icons.search, color: Colors.white),
                      label: const Text(
                        'טען משובים זמינים',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade600,
                      ),
                    ),
                  ),

                // Filter controls
                if (_availableFeedbacks.isNotEmpty) ...[
                  Card(
                    color: Colors.blueGrey.shade800,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Filter row
                          Row(
                            children: [
                              // Role filter
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _feedbackFilterRole,
                                  decoration: const InputDecoration(
                                    labelText: 'תפקיד',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: 'הכל',
                                      child: Text('הכל'),
                                    ),
                                    ...{
                                      ..._availableFeedbacks
                                          .map((f) => f.role)
                                          .where((r) => r.isNotEmpty),
                                    }.map(
                                      (role) => DropdownMenuItem(
                                        value: role,
                                        child: Text(role),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) => setState(
                                    () => _feedbackFilterRole = v ?? 'הכל',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Name filter
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(
                                    labelText: 'שם',
                                    hintText: 'חפש לפי שם',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  onChanged: (v) =>
                                      setState(() => _feedbackFilterName = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Counter
                          Text(
                            'נבחרו: ${_selectedFeedbackIds.length} מתוך ${_filteredAvailableFeedbacks.length} משובים',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Feedbacks list
                  ..._filteredAvailableFeedbacks.map((feedback) {
                    final isSelected = _selectedFeedbackIds.contains(
                      feedback.id,
                    );
                    final date = feedback.createdAt;
                    final timeStr =
                        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

                    return Card(
                      color: isSelected
                          ? Colors.green.shade700
                          : Colors.blueGrey.shade700,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true && feedback.id != null) {
                              _selectedFeedbackIds.add(feedback.id!);
                            } else if (feedback.id != null) {
                              _selectedFeedbackIds.remove(feedback.id);
                            }
                          });
                        },
                        title: Text(
                          '${feedback.role} — ${feedback.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'תרגיל: ${feedback.exercise}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              'מדריך: ${feedback.instructorName} | $timeStr',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            // Show warning if already linked
                            FutureBuilder<String?>(
                              future: _checkIfFeedbackAlreadyLinked(
                                feedback.id ?? '',
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data != null) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber,
                                          color: Colors.amber,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'מקושר גם ל: ${snapshot.data}',
                                            style: const TextStyle(
                                              color: Colors.amber,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ),
                        activeColor: Colors.green,
                        checkColor: Colors.white,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    );
                  }),

                  if (_filteredAvailableFeedbacks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'לא נמצאו משובים אישיים התואמים לסינון',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                ],

                const SizedBox(height: 20),
              ],

              // 12. Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'שמור סיכום',
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ================== FEEDBACKS LIST + DETAILS ================== */

const List<String> rangeStations = [
  'כל המקצים',
  'רמות',
  'שלשות',
  'עפדיו',
  'חץ',
  'קשת',
  'חרב',
  'מגן',
];

class FeedbacksPage extends StatefulWidget {
  const FeedbacksPage({super.key});

  @override
  State<FeedbacksPage> createState() => _FeedbacksPageState();
}

class _FeedbacksPageState extends State<FeedbacksPage> {
  bool _isRefreshing = false;
  String?
  _selectedFolder; // null = show folders, non-null = show feedbacks from that folder
  String selectedSettlement = 'כל היישובים';

  // New filter state variables
  String _filterSettlement = 'הכל';
  String _filterExercise = 'הכל';
  String _filterRole = 'הכל';
  String _filterRangeType = 'הכל'; // Range type filter (short/long range)
  String _filterInstructor = 'הכל'; // Instructor filter for range folders
  DateTime? _filterDateFrom; // Date from filter for range folders
  DateTime? _filterDateTo; // Date to filter for range folders

  // Selection mode state (for 474 ranges multi-select export)
  bool _selectionMode = false;
  final Set<String> _selectedFeedbackIds = {};
  bool _isExporting = false;

  /// Helper: Get Hebrew display label for folder (handles internal values)
  String _getFolderDisplayLabel(String internalValue) {
    final config = _feedbackFoldersConfig.firstWhere(
      (c) => (c['internalValue'] ?? c['title']) == internalValue,
      orElse: () => {'title': internalValue},
    );
    return (config['displayLabel'] ?? config['title'] ?? internalValue)
        as String;
  }

  Future<void> _refreshFeedbacks() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      final isAdmin = currentUser?.role == 'Admin';
      debugPrint('🔄 Manual refresh triggered by user');
      await loadFeedbacksForCurrentUser(isAdmin: isAdmin);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('רשימת המשובים עודכנה')));
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה בטעינת משובים')));
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _showRecentRangeSaves() async {
    final isAdmin = currentUser?.role == 'Admin';
    if (!isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אין הרשאה - רק אדמין')));
      return;
    }

    try {
      final q = FirebaseFirestore.instance
          .collection('feedbacks')
          .orderBy('createdAt', descending: true)
          .limit(100);

      final snap = await q.get();
      final docs = snap.docs
          .where((d) {
            final data = d.data();
            final fk = (data['folderKey'] ?? '').toString();
            final mod = (data['module'] ?? '').toString();
            final folder = (data['folder'] ?? '').toString();
            // include known range docs by canonical key or legacy folder/module
            if (fk == 'ranges_474' || fk == 'shooting_ranges') {
              return true;
            }
            if (mod == 'shooting_ranges' || mod == 'surprise_drill') {
              return true;
            }
            final low = folder.toLowerCase();
            if (low.contains('474') || low.contains('מטווח')) {
              return true;
            }
            return false;
          })
          .take(20)
          .toList();
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Recent Range Saves (last 20)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (docs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Text('אין שמירות אחרונות'),
                    )
                  else
                    SizedBox(
                      height: 400,
                      child: ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (ctx, i) {
                          final d = docs[i];
                          final data = d.data();
                          final fk = (data['folderKey'] ?? '').toString();
                          final ft =
                              (data['feedbackType'] ?? data['type'] ?? '')
                                  .toString();
                          final instr = (data['instructorName'] ?? '')
                              .toString();
                          final sett =
                              (data['settlement'] ??
                                      data['settlementName'] ??
                                      '')
                                  .toString();
                          final ca = data['createdAt'];
                          String created = '';
                          if (ca is Timestamp) {
                            created = ca.toDate().toString();
                          } else if (ca is String) {
                            created = ca;
                          }

                          return ListTile(
                            title: Text(
                              '${d.id} • ${fk.isNotEmpty ? fk : '-'}',
                            ),
                            subtitle: Text(
                              'type: $ft • מדריך: $instr • יישוב: $sett',
                            ),
                            trailing: Text(created),
                            onTap: () => Navigator.of(context).pushNamed(
                              '/feedback_details',
                              arguments:
                                  FeedbackModel.fromMap(data, id: d.id) ??
                                  FeedbackModel(
                                    id: d.id,
                                    role: '',
                                    name: '',
                                    exercise: '',
                                    scores: {},
                                    notes: {},
                                    criteriaList: [],
                                    createdAt: DateTime.now(),
                                    instructorName: instr,
                                    instructorRole: '',
                                    commandText: '',
                                    commandStatus: '',
                                    folder: '',
                                    scenario: '',
                                    settlement: sett,
                                    attendeesCount: 0,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('סגור'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Error loading recent saves: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בטעינת שמירות אחרונות: $e')),
      );
    }
  }

  Future<void> _confirmDeleteFeedback(String feedbackId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משוב'),
          content: Text('האם למחוק את המשוב "$title"?\n\nפעולה זו בלתי הפיכה.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _deleteFeedback(feedbackId, title);
    }
  }

  Future<void> _deleteFeedback(String feedbackId, String title) async {
    try {
      await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(feedbackId)
          .delete();

      // Remove from local cache
      feedbackStorage.removeWhere((f) => f.id == feedbackId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('המשוב "$title" נמחק בהצלחה')));
      setState(() {}); // Refresh UI
    } catch (e) {
      debugPrint('❌ Delete feedback error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה במחיקת משוב: $e')));
    }
  }

  /// Export selected feedbacks (generic for all folders)
  Future<void> _exportSelectedFeedbacks() async {
    setState(() => _isExporting = true);

    try {
      final messenger = ScaffoldMessenger.of(context);

      if (_selectedFeedbackIds.isEmpty) {
        throw Exception('לא נבחרו משובים לייצוא');
      }

      // Fetch all selected feedback documents from Firestore
      final feedbacksData = await Future.wait(
        _selectedFeedbackIds.map((id) async {
          final doc = await FirebaseFirestore.instance
              .collection('feedbacks')
              .doc(id)
              .get()
              .timeout(const Duration(seconds: 10));

          if (doc.exists && doc.data() != null) {
            return doc.data()!;
          }
          return <String, dynamic>{};
        }),
      );

      // Filter out empty documents
      final validData = feedbacksData.where((data) => data.isNotEmpty).toList();

      if (validData.isEmpty) {
        throw Exception('לא נמצאו נתוני משוב תקינים');
      }

      // Determine export method based on folder type
      if (_selectedFolder == 'מטווחים 474' || _selectedFolder == '474 Ranges') {
        // Export 474 ranges
        await FeedbackExportService.export474RangesFeedbacks(
          feedbacksData: validData,
          fileNamePrefix: '474_ranges_selected',
        );
      } else if (_selectedFolder == 'מטווחי ירי') {
        // Export shooting ranges
        await FeedbackExportService.export474RangesFeedbacks(
          feedbacksData: validData,
          fileNamePrefix: 'shooting_ranges_selected',
        );
      } else if (_selectedFolder == 'משוב תרגילי הפתעה' ||
          _selectedFolder == 'תרגילי הפתעה כללי') {
        // Export surprise drills (both 474 and general)
        await FeedbackExportService.exportSurpriseDrillsToXlsx(
          feedbacksData: validData,
          fileNamePrefix: 'surprise_drills_selected',
        );
      } else {
        // Export general feedbacks (משובים כללי, מחלקות ההגנה)
        // Convert feedbacksData to FeedbackModel list
        final feedbackModels = validData
            .map(
              (data) => FeedbackModel.fromMap(data, id: data['id'] as String?),
            )
            .whereType<FeedbackModel>()
            .toList();

        final keys = [
          'id',
          'role',
          'name',
          'exercise',
          'scores',
          'notes',
          'criteriaList',
          'instructorName',
          'instructorRole',
          'commandText',
          'commandStatus',
          'folder',
          'scenario',
          'settlement',
          'attendeesCount',
        ];
        final headers = [
          'ID',
          'תפקיד',
          'שם',
          'תרגיל',
          'ציונים',
          'הערות',
          'קריטריונים',
          'מדריך',
          'תפקיד מדריך',
          'טקסט פקודה',
          'סטטוס פקודה',
          'תיקייה',
          'תרחיש',
          'יישוב',
          'מספר נוכחים',
        ];
        await FeedbackExportService.exportWithSchema(
          keys: keys,
          headers: headers,
          feedbacks: feedbackModels,
          fileNamePrefix: '${_selectedFolder}_selected',
        );
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('הקובץ נוצר בהצלחה!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Clear selection after successful export
      setState(() {
        _selectionMode = false;
        _selectedFeedbackIds.clear();
      });
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  /// Clear all filters
  void _clearFilters() {
    setState(() {
      _filterSettlement = 'הכל';
      _filterExercise = 'הכל';
      _filterRole = 'הכל';
      _filterRangeType = 'הכל';
      _filterInstructor = 'הכל';
      _filterDateFrom = null;
      _filterDateTo = null;
    });
  }

  /// Check if any filter is active
  bool get _hasActiveFilters =>
      _filterSettlement != 'הכל' ||
      _filterExercise != 'הכל' ||
      _filterRole != 'הכל' ||
      _filterRangeType != 'הכל' ||
      _filterInstructor != 'הכל' ||
      _filterDateFrom != null ||
      _filterDateTo != null;

  /// Get unique settlement options from a list of feedbacks
  List<String> _getSettlementOptions(List<FeedbackModel> feedbacks) {
    final settlements = feedbacks
        .map((f) => f.settlement)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    settlements.sort();
    return ['הכל', ...settlements];
  }

  /// Get unique exercise options from a list of feedbacks
  List<String> _getExerciseOptions(List<FeedbackModel> feedbacks) {
    // For training summary folders, use trainingType instead of exercise
    final isTrainingSummaryFolder =
        _selectedFolder == 'משוב סיכום אימון 474' ||
        _selectedFolder == 'סיכום אימון כללי';

    final exercises = feedbacks
        .map((f) {
          if (isTrainingSummaryFolder && f.trainingType.isNotEmpty) {
            return f.trainingType;
          }
          return f.exercise;
        })
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    exercises.sort();
    return ['הכל', ...exercises];
  }

  /// Get unique role options from a list of feedbacks
  List<String> _getRoleOptions(List<FeedbackModel> feedbacks) {
    final roles = feedbacks
        .map((f) => f.role)
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();
    roles.sort();
    return ['הכל', ...roles];
  }

  /// Get unique instructor options from a list of feedbacks
  List<String> _getInstructorOptions(List<FeedbackModel> feedbacks) {
    final instructors = feedbacks
        .map((f) => f.instructorName)
        .where((i) => i.isNotEmpty)
        .toSet()
        .toList();
    instructors.sort();
    return ['הכל', ...instructors];
  }

  /// Apply filters to a list of feedbacks (AND logic)
  List<FeedbackModel> _applyFilters(List<FeedbackModel> feedbacks) {
    // For training summary folders, filter by trainingType instead of exercise
    final isTrainingSummaryFolder =
        _selectedFolder == 'משוב סיכום אימון 474' ||
        _selectedFolder == 'סיכום אימון כללי';

    return feedbacks.where((f) {
      // Settlement filter
      if (_filterSettlement != 'הכל') {
        if (f.settlement.isEmpty || f.settlement != _filterSettlement) {
          return false;
        }
      }
      // Exercise filter
      if (_filterExercise != 'הכל') {
        // For training summary, compare against trainingType
        if (isTrainingSummaryFolder) {
          if (f.trainingType.isEmpty || f.trainingType != _filterExercise) {
            return false;
          }
        } else {
          if (f.exercise.isEmpty || f.exercise != _filterExercise) {
            return false;
          }
        }
      }
      // Role filter
      if (_filterRole != 'הכל') {
        if (f.role.isEmpty || f.role != _filterRole) {
          return false;
        }
      }
      // Range type filter (for shooting ranges)
      if (_filterRangeType != 'הכל') {
        if (f.rangeSubType.isEmpty || f.rangeSubType != _filterRangeType) {
          return false;
        }
      }
      // Instructor filter
      if (_filterInstructor != 'הכל') {
        if (f.instructorName.isEmpty || f.instructorName != _filterInstructor) {
          return false;
        }
      }
      // Date from filter
      if (_filterDateFrom != null) {
        final feedbackDate = DateTime(
          f.createdAt.year,
          f.createdAt.month,
          f.createdAt.day,
        );
        final fromDate = DateTime(
          _filterDateFrom!.year,
          _filterDateFrom!.month,
          _filterDateFrom!.day,
        );
        if (feedbackDate.isBefore(fromDate)) {
          return false;
        }
      }
      // Date to filter
      if (_filterDateTo != null) {
        final feedbackDate = DateTime(
          f.createdAt.year,
          f.createdAt.month,
          f.createdAt.day,
        );
        final toDate = DateTime(
          _filterDateTo!.year,
          _filterDateTo!.month,
          _filterDateTo!.day,
        );
        if (feedbackDate.isAfter(toDate)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';

    // Show folders view
    if (_selectedFolder == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('משובים - תיקיות'),
            actions: [
              IconButton(
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _isRefreshing ? null : _refreshFeedbacks,
                tooltip: 'רענן רשימה',
              ),
            ],
          ),
          body: ListView.builder(
            itemCount: visibleFeedbackFolders.length,
            itemBuilder: (ctx, i) {
              final folder = visibleFeedbackFolders[i];
              // Get internal value for filtering (if exists)
              final folderConfig = _feedbackFoldersConfig.firstWhere(
                (config) => config['title'] == folder,
                orElse: () => {'title': folder},
              );
              final internalValue =
                  folderConfig['internalValue'] as String? ?? folder;

              // Count feedbacks: regular + old feedbacks without folder (assigned to "משובים – כללי")
              int count;
              if (folder == 'משובים – כללי') {
                count = feedbackStorage
                    .where((f) => f.folder == folder || f.folder.isEmpty)
                    .length;
              } else if (folder == 'מיונים לקורס מדריכים') {
                // Direct Firestore count - bypasses feedbackStorage loading issues
                count = 0; // Will be loaded via FutureBuilder
              } else if (folder == 'הגמר חטיבה 474') {
                // Special category: count all feedbacks from 4 sub-folders
                count = feedbackStorage
                    .where(
                      (f) =>
                          f.folder == 'מטווחים 474' ||
                          f.folder == '474 Ranges' ||
                          f.folder == 'מחלקות ההגנה – חטיבה 474' ||
                          f.folder == 'משוב תרגילי הפתעה' ||
                          f.folder == 'משוב סיכום אימון 474',
                    )
                    .length;
              } else {
                // Use internal value for filtering to match Firestore data
                count = feedbackStorage
                    .where(
                      (f) => f.folder == folder || f.folder == internalValue,
                    )
                    .length;
              }
              final isInstructorCourse = folder == 'מיונים לקורס מדריכים';
              final isSpecialCategory =
                  folderConfig['isSpecialCategory'] == true;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 2,
                child: InkWell(
                  onTap: () {
                    if (isInstructorCourse) {
                      // Feedbacks view for instructor-course: only closed items via two category buttons
                      Navigator.of(
                        context,
                      ).pushNamed('/instructor_course_selection_feedbacks');
                    } else if (isSpecialCategory) {
                      // Special category (הגמר חטיבה 474): show intermediate screen with sub-folders
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Brigade474FinalFoldersPage(),
                        ),
                      );
                    } else {
                      // Use internal value for navigation/filtering
                      setState(() => _selectedFolder = internalValue);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          isSpecialCategory
                              ? Icons.shield
                              : (isInstructorCourse
                                    ? Icons.school
                                    : Icons.folder),
                          size: 32,
                          color: isSpecialCategory
                              ? Colors.deepOrange
                              : (isInstructorCourse
                                    ? Colors.purple
                                    : Colors.orangeAccent),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            folder,
                            textAlign: TextAlign.start,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        isInstructorCourse
                            ? FutureBuilder<int>(
                                future: FirebaseFirestore.instance
                                    .collection('instructor_course_evaluations')
                                    .where('status', isEqualTo: 'final')
                                    .count()
                                    .get()
                                    .timeout(const Duration(seconds: 5))
                                    .then((snapshot) => snapshot.count ?? 0)
                                    .catchError((e) {
                                      debugPrint(
                                        '⚠️ Failed to count instructor evaluations: $e',
                                      );
                                      return 0;
                                    }),
                                builder: (context, snapshot) {
                                  final displayCount = snapshot.data ?? count;
                                  return Text(
                                    '$displayCount משובים',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  );
                                },
                              )
                            : Text(
                                '$count משובים',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    // Show feedbacks for selected folder
    // BACKWARD-COMPATIBLE FILTERING: Support both legacy and new schema
    // Legacy docs: missing module/type fields, use folder only
    // New docs: have module/type/isTemporary fields
    List<FeedbackModel> filteredFeedbacks;

    if (_selectedFolder == 'משובים – כללי') {
      filteredFeedbacks = feedbackStorage
          .where(
            (f) =>
                (f.folder == _selectedFolder || f.folder.isEmpty) &&
                f.isTemporary == false,
          )
          .toList();
    } else if (_selectedFolder == 'משוב תרגילי הפתעה') {
      // SURPRISE DRILLS 474: Include BOTH new schema AND legacy docs
      filteredFeedbacks = feedbackStorage.where((f) {
        // Exclude temporary drafts
        if (f.isTemporary == true) return false;

        // Exclude general surprise drills
        if (f.folder == 'תרגילי הפתעה כללי' ||
            f.folderKey == 'surprise_drills_general') {
          return false;
        }

        // NEW SCHEMA: Has module field populated
        if (f.module.isNotEmpty) {
          return f.module == 'surprise_drill';
        }

        // LEGACY SCHEMA: No module field, use folder
        return f.folder == _selectedFolder;
      }).toList();
      debugPrint(
        '\n========== SURPRISE DRILLS 474 FILTER (BACKWARD-COMPATIBLE) ==========',
      );
      debugPrint('Total feedbacks in storage: ${feedbackStorage.length}');
      debugPrint('Filtered surprise drills 474: ${filteredFeedbacks.length}');
      final legacyCount = filteredFeedbacks
          .where((f) => f.module.isEmpty)
          .length;
      final newCount = filteredFeedbacks
          .where((f) => f.module.isNotEmpty)
          .length;
      debugPrint('  - Legacy docs (no module field): $legacyCount');
      debugPrint('  - New schema docs: $newCount');
      for (final f in filteredFeedbacks.take(3)) {
        debugPrint(
          '  - ${f.name}: module="${f.module}", type="${f.type}", folder="${f.folder}", isTemp=${f.isTemporary}',
        );
      }
      debugPrint(
        '================================================================\n',
      );
    } else if (_selectedFolder == 'סיכום אימון כללי') {
      // ✅ TRAINING SUMMARY GENERAL: Filter by folder name or folderKey
      filteredFeedbacks = feedbackStorage.where((f) {
        // Exclude temporary drafts
        if (f.isTemporary == true) return false;

        // Match by folder name or folderKey
        return f.folder == 'סיכום אימון כללי' ||
            f.folderKey == 'training_summary_general';
      }).toList();
      debugPrint('\n========== TRAINING SUMMARY GENERAL FILTER ==========');
      debugPrint('Total feedbacks in storage: ${feedbackStorage.length}');
      debugPrint(
        'Filtered training summaries general: ${filteredFeedbacks.length}',
      );
      debugPrint(
        '================================================================\n',
      );
    } else if (_selectedFolder == 'תרגילי הפתעה כללי') {
      // SURPRISE DRILLS GENERAL: Filter by folder name
      filteredFeedbacks = feedbackStorage.where((f) {
        // Exclude temporary drafts
        if (f.isTemporary == true) return false;

        // Match by folder name or folderKey
        return f.folder == 'תרגילי הפתעה כללי' ||
            f.folderKey == 'surprise_drills_general';
      }).toList();
      debugPrint('\n========== SURPRISE DRILLS GENERAL FILTER ==========');
      debugPrint('Total feedbacks in storage: ${feedbackStorage.length}');
      debugPrint(
        'Filtered surprise drills general: ${filteredFeedbacks.length}',
      );
      debugPrint(
        '================================================================\n',
      );
    } else if (_selectedFolder == 'מטווחי ירי') {
      // 🔍 DIAGNOSTIC: NORMAL_LIST_FILTER - Log filter logic
      debugPrint('\n========== NORMAL_LIST_FILTER DIAGNOSTIC ==========');
      debugPrint('NORMAL_LIST_FILTER: folder=מטווחי ירי');
      debugPrint('NORMAL_LIST_FILTER: Filter logic:');
      debugPrint('  1. Exclude where isTemporary == true');
      debugPrint('  2. Include where folderKey == shooting_ranges');
      debugPrint('  3. OR where module == shooting_ranges');
      debugPrint('  4. OR where folder == מטווחי ירי');
      debugPrint('====================================================\n');

      // SHOOTING RANGES: Prefer canonical folderKey, fallback to legacy fields
      filteredFeedbacks = feedbackStorage.where((f) {
        if (f.isTemporary == true) return false;

        // Prefer canonical folderKey when present
        if (f.folderKey.isNotEmpty) return f.folderKey == 'shooting_ranges';

        // New schema fallback: module
        if (f.module.isNotEmpty) return f.module == 'shooting_ranges';

        // Legacy fallback: folder label match
        return f.folder == _selectedFolder;
      }).toList();
      debugPrint(
        '\n========== SHOOTING RANGES FILTER (BACKWARD-COMPATIBLE) ==========',
      );
      debugPrint('Total feedbacks in storage: ${feedbackStorage.length}');
      debugPrint('Filtered shooting ranges: ${filteredFeedbacks.length}');
      final legacyCount = filteredFeedbacks
          .where((f) => f.module.isEmpty)
          .length;
      final newCount = filteredFeedbacks
          .where((f) => f.module.isNotEmpty)
          .length;
      debugPrint('  - Legacy docs (no module field): $legacyCount');
      debugPrint('  - New schema docs: $newCount');
      for (final f in filteredFeedbacks.take(3)) {
        debugPrint(
          '  - ${f.name}: module="${f.module}", type="${f.type}", folder="${f.folder}", isTemp=${f.isTemporary}',
        );
      }
      debugPrint(
        '================================================================\n',
      );
    } else if (_selectedFolder == '474 Ranges' ||
        _selectedFolder == 'מטווחים 474') {
      // ✅ FIX: 474 RANGES MUST EXCLUDE temporary docs AND training summary
      // Query logic: module==shooting_ranges AND folderKey==ranges_474 AND isTemporary==false
      filteredFeedbacks = feedbackStorage.where((f) {
        // ❌ CRITICAL: Exclude ALL temporary/draft feedbacks
        if (f.isTemporary == true) return false;

        // ❌ CRITICAL: Exclude training summary feedbacks
        if (f.module == 'training_summary' || f.type == 'training_summary') {
          return false;
        }
        if (f.folder == 'משוב סיכום אימון 474') {
          return false;
        }

        // ✅ Prefer canonical folderKey (most reliable)
        if (f.folderKey.isNotEmpty) return f.folderKey == 'ranges_474';

        // ✅ Fallback: module + folder label match (legacy compatibility)
        if (f.module.isNotEmpty && f.module == 'shooting_ranges') {
          final lowFolder = f.folder.toLowerCase();
          if (lowFolder.contains('474') ||
              lowFolder.contains('474 ranges') ||
              lowFolder.contains('מטווחים 474')) {
            return true;
          }
        }

        // ✅ Legacy fallback: folder label match only (very old docs)
        return f.folder == _selectedFolder || f.folder == 'מטווחים 474';
      }).toList();
      debugPrint('\n========== 474 RANGES FILTER ==========');
      debugPrint('Total feedbacks in storage: ${feedbackStorage.length}');
      debugPrint('Filtered 474 ranges: ${filteredFeedbacks.length}');
      debugPrint(
        '================================================================\n',
      );
    } else if (_selectedFolder == 'משוב סיכום אימון 474') {
      // ✅ TRAINING SUMMARY 474: Include ONLY 474 training summaries (exclude general)
      filteredFeedbacks = feedbackStorage.where((f) {
        // Exclude temporary drafts
        if (f.isTemporary == true) return false;

        // ❌ EXCLUDE general training summaries
        if (f.folder == 'סיכום אימון כללי' ||
            f.folderKey == 'training_summary_general') {
          return false;
        }

        // NEW SCHEMA: Has module field populated AND is 474
        if (f.module.isNotEmpty) {
          // Check folderKey for 474 specifically
          if (f.folderKey == 'training_summary_474') {
            return true;
          }
          // Fallback: module is training_summary AND folder is 474
          if (f.module == 'training_summary' &&
              f.folder == 'משוב סיכום אימון 474') {
            return true;
          }
          return false;
        }

        // Legacy schema: use folder match (only 474)
        return f.folder == _selectedFolder;
      }).toList();
      debugPrint('\n========== TRAINING SUMMARY FILTER ==========');
      debugPrint('Total feedbacks in storage: ${feedbackStorage.length}');
      debugPrint('Filtered training summaries: ${filteredFeedbacks.length}');
      for (final f in filteredFeedbacks.take(3)) {
        debugPrint(
          '  - ${f.name}: module="${f.module}", type="${f.type}", folder="${f.folder}"',
        );
      }
      debugPrint('================================================\n');
    } else {
      // Other folders: use standard folder filtering + exclude temporary
      filteredFeedbacks = feedbackStorage
          .where((f) => f.folder == _selectedFolder && f.isTemporary == false)
          .toList();
    }

    final isRangeFolder =
        _selectedFolder == 'מטווחי ירי' ||
        _selectedFolder == '474 Ranges' ||
        _selectedFolder == 'מטווחים 474';

    final isSurpriseDrillsFolder =
        _selectedFolder == 'משוב תרגילי הפתעה' ||
        _selectedFolder == 'תרגילי הפתעה כללי';

    final isTrainingSummaryFolder =
        _selectedFolder == 'משוב סיכום אימון 474' ||
        _selectedFolder == 'סיכום אימון כללי';

    // Apply settlement filter for range feedbacks (legacy behavior)
    List<FeedbackModel> preFilteredFeedbacks = filteredFeedbacks;
    if (isRangeFolder) {
      preFilteredFeedbacks = filteredFeedbacks
          .where(
            (f) =>
                selectedSettlement == 'כל היישובים' ||
                f.settlement == selectedSettlement,
          )
          .toList();
    }

    // Apply new generic filters (settlement, exercise, role) with AND logic
    final List<FeedbackModel> finalFilteredFeedbacks = _applyFilters(
      preFilteredFeedbacks,
    );

    // Get filter options from the folder's feedbacks (before user filters applied)
    final settlementOptions = _getSettlementOptions(filteredFeedbacks);
    final exerciseOptions = _getExerciseOptions(filteredFeedbacks);
    final roleOptions = _getRoleOptions(filteredFeedbacks);
    final instructorOptions = _getInstructorOptions(filteredFeedbacks);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getFolderDisplayLabel(_selectedFolder!)),
          leading: StandardBackButton(
            onPressed: () {
              // Clear filters when going back to folders
              _clearFilters();
              setState(() => _selectedFolder = null);
            },
            tooltip: 'חזרה לתיקיות',
          ),
          actions: [
            // Selection mode toggle for all export-enabled folders (Admin only)
            if ((_selectedFolder == 'מטווחים 474' ||
                    _selectedFolder == '474 Ranges' ||
                    _selectedFolder == 'מטווחי ירי' ||
                    _selectedFolder == 'מחלקות ההגנה – חטיבה 474' ||
                    _selectedFolder == 'משובים – כללי' ||
                    _selectedFolder == 'משוב תרגילי הפתעה' ||
                    _selectedFolder == 'תרגילי הפתעה כללי') &&
                isAdmin &&
                finalFilteredFeedbacks.isNotEmpty)
              IconButton(
                icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
                onPressed: () {
                  setState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) {
                      _selectedFeedbackIds.clear();
                    }
                  });
                },
                tooltip: _selectionMode ? 'בטל בחירה' : 'בחר לייצוא',
              ),
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isRefreshing ? null : _refreshFeedbacks,
              tooltip: 'רענן רשימה',
            ),
            // Admin-only recent range saves
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Recent range saves',
                onPressed: _showRecentRangeSaves,
              ),
          ],
        ),
        body: finalFilteredFeedbacks.isEmpty && !_hasActiveFilters
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('אין משובים בתיקייה זו'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        _clearFilters();
                        setState(() => _selectedFolder = null);
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('חזרה לתיקיות'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Selection mode action bar for all export-enabled folders
                  if (_selectionMode &&
                      (_selectedFolder == 'מטווחים 474' ||
                          _selectedFolder == '474 Ranges' ||
                          _selectedFolder == 'מטווחי ירי' ||
                          _selectedFolder == 'מחלקות ההגנה – חטיבה 474' ||
                          _selectedFolder == 'משובים – כללי' ||
                          _selectedFolder == 'משוב תרגילי הפתעה' ||
                          _selectedFolder == 'תרגילי הפתעה כללי'))
                    Container(
                      color: Colors.blueGrey.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'נבחרו: ${_selectedFeedbackIds.length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          if (_selectedFeedbackIds.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: _isExporting
                                  ? null
                                  : _exportSelectedFeedbacks,
                              icon: _isExporting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(Icons.download, size: 18),
                              label: const Text('ייצוא'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectionMode = false;
                                _selectedFeedbackIds.clear();
                              });
                            },
                            child: const Text('בטל'),
                          ),
                        ],
                      ),
                    ),
                  // Generic filters bar (for all folders except instructor course)
                  Card(
                    color: Colors.blueGrey.shade800,
                    margin: const EdgeInsets.all(8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Filter row
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.start,
                            children: [
                              // Settlement filter
                              if (settlementOptions.length > 1)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'יישוב',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    SizedBox(
                                      width: 200,
                                      child: DropdownButtonFormField<String>(
                                        initialValue:
                                            settlementOptions.contains(
                                              _filterSettlement,
                                            )
                                            ? _filterSettlement
                                            : 'הכל',
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 16,
                                          ),
                                        ),
                                        items: settlementOptions
                                            .map(
                                              (s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(
                                                  s,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                          () => _filterSettlement = v ?? 'הכל',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Exercise filter (only for non-range folders)
                              if (!isRangeFolder && exerciseOptions.length > 1)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isTrainingSummaryFolder
                                          ? 'סוג אימון'
                                          : 'תרגיל',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    SizedBox(
                                      width: 200,
                                      child: DropdownButtonFormField<String>(
                                        initialValue:
                                            exerciseOptions.contains(
                                              _filterExercise,
                                            )
                                            ? _filterExercise
                                            : 'הכל',
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 16,
                                          ),
                                        ),
                                        items: exerciseOptions
                                            .map(
                                              (e) => DropdownMenuItem(
                                                value: e,
                                                child: Text(
                                                  e,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                          () => _filterExercise = v ?? 'הכל',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Range type filter (only for range folders)
                              if (isRangeFolder)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'מטווח',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    SizedBox(
                                      width: 200,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _filterRangeType,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 16,
                                          ),
                                        ),
                                        items: ['הכל', 'טווח קצר', 'טווח רחוק']
                                            .map(
                                              (t) => DropdownMenuItem(
                                                value: t,
                                                child: Text(
                                                  t,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                          () => _filterRangeType = v ?? 'הכל',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Instructor filter (only for range folders)
                              if (isRangeFolder && instructorOptions.length > 1)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'מדריך',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    SizedBox(
                                      width: 200,
                                      child: DropdownButtonFormField<String>(
                                        initialValue:
                                            instructorOptions.contains(
                                              _filterInstructor,
                                            )
                                            ? _filterInstructor
                                            : 'הכל',
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 16,
                                          ),
                                        ),
                                        items: instructorOptions
                                            .map(
                                              (i) => DropdownMenuItem(
                                                value: i,
                                                child: Text(
                                                  i,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                          () => _filterInstructor = v ?? 'הכל',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Date filters (only for range folders)
                              if (isRangeFolder)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'תאריך',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 120,
                                          child: ElevatedButton(
                                            onPressed: () async {
                                              final now = DateTime.now();
                                              final picked =
                                                  await showDatePicker(
                                                    context: context,
                                                    initialDate:
                                                        _filterDateFrom ?? now,
                                                    firstDate: DateTime(2020),
                                                    lastDate: now,
                                                  );
                                              if (picked != null) {
                                                setState(
                                                  () =>
                                                      _filterDateFrom = picked,
                                                );
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 12,
                                                  ),
                                            ),
                                            child: Text(
                                              _filterDateFrom == null
                                                  ? 'מתאריך'
                                                  : '${_filterDateFrom!.day}/${_filterDateFrom!.month}/${_filterDateFrom!.year}',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 120,
                                          child: ElevatedButton(
                                            onPressed: () async {
                                              final now = DateTime.now();
                                              final picked =
                                                  await showDatePicker(
                                                    context: context,
                                                    initialDate:
                                                        _filterDateTo ?? now,
                                                    firstDate: DateTime(2020),
                                                    lastDate: now,
                                                  );
                                              if (picked != null) {
                                                setState(
                                                  () => _filterDateTo = picked,
                                                );
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 12,
                                                  ),
                                            ),
                                            child: Text(
                                              _filterDateTo == null
                                                  ? 'עד תאריך'
                                                  : '${_filterDateTo!.day}/${_filterDateTo!.month}/${_filterDateTo!.year}',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              // Role filter (only for non-range and non-surprise-drills folders)
                              if (!isRangeFolder &&
                                  !isSurpriseDrillsFolder &&
                                  roleOptions.length > 1)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'תפקיד',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    SizedBox(
                                      width: 200,
                                      child: DropdownButtonFormField<String>(
                                        initialValue:
                                            roleOptions.contains(_filterRole)
                                            ? _filterRole
                                            : 'הכל',
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 16,
                                          ),
                                        ),
                                        items: roleOptions
                                            .map(
                                              (r) => DropdownMenuItem(
                                                value: r,
                                                child: Text(
                                                  r,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                          () => _filterRole = v ?? 'הכל',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Clear filters button (only show when filters are active)
                              if (_hasActiveFilters)
                                TextButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(Icons.clear, size: 18),
                                  label: const Text('נקה פילטרים'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.orangeAccent,
                                  ),
                                ),
                            ],
                          ),
                          // Show filter status
                          if (_hasActiveFilters) ...[
                            const SizedBox(height: 8),
                            Text(
                              'מציג ${finalFilteredFeedbacks.length} מתוך ${filteredFeedbacks.length} משובים',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Settlement header for "מחלקות ההגנה – חטיבה 474" only
                  if (_selectedFolder == 'מחלקות ההגנה – חטיבה 474' &&
                      finalFilteredFeedbacks.isNotEmpty)
                    Builder(
                      builder: (context) {
                        // Show settlement name if filtered by settlement OR if all feedbacks are from same settlement
                        String? settlementToShow;

                        if (_filterSettlement != 'הכל') {
                          // User filtered by specific settlement
                          settlementToShow = _filterSettlement;
                        } else {
                          // Check if all feedbacks are from same settlement
                          final settlements = finalFilteredFeedbacks
                              .map((f) => f.settlement)
                              .where((s) => s.isNotEmpty)
                              .toSet();
                          if (settlements.length == 1) {
                            settlementToShow = settlements.first;
                          }
                        }

                        if (settlementToShow == null ||
                            settlementToShow.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orangeAccent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.orangeAccent,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'יישוב: $settlementToShow',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  // Empty state when filters return no results
                  if (finalFilteredFeedbacks.isEmpty && _hasActiveFilters)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            const Text('לא נמצאו משובים התואמים לסינון'),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.clear),
                              label: const Text('נקה פילטרים'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12.0),
                        itemCount: finalFilteredFeedbacks.length,
                        itemBuilder: (_, i) {
                          final f = finalFilteredFeedbacks[i];

                          // Build title from feedback data
                          final title =
                              (f.folderKey == 'shooting_ranges' ||
                                  f.module == 'shooting_ranges' ||
                                  f.folder == 'מטווחי ירי')
                              ? (f.settlement.isNotEmpty
                                    ? f.settlement
                                    : f.name)
                              : '${f.role} — ${f.name}';

                          // Parse date
                          final date = f.createdAt.toLocal();
                          final dateStr =
                              '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

                          // Build metadata lines
                          final metadataLines = <String>[];
                          if (_selectedFolder == 'מחלקות ההגנה – חטיבה 474') {
                            // Special order for Defense Companies folder only
                            if (f.settlement.isNotEmpty) {
                              metadataLines.add('יישוב: ${f.settlement}');
                            }
                            if (f.exercise.isNotEmpty) {
                              metadataLines.add('תרגיל: ${f.exercise}');
                            }
                            if (f.instructorName.isNotEmpty) {
                              metadataLines.add('מדריך: ${f.instructorName}');
                            }
                            metadataLines.add('תאריך: $dateStr');
                          } else {
                            // Original order for all other folders
                            if (f.exercise.isNotEmpty) {
                              metadataLines.add('תרגיל: ${f.exercise}');
                            }
                            // הוסף סוג אימון למשובי סיכום אימון 474
                            if ((f.folder == 'משוב סיכום אימון 474' ||
                                    f.module == 'training_summary') &&
                                f.trainingType.isNotEmpty) {
                              metadataLines.add('סוג אימון: ${f.trainingType}');
                            }
                            if (f.instructorName.isNotEmpty) {
                              metadataLines.add('מדריך: ${f.instructorName}');
                            }
                            if (f.attendeesCount > 0) {
                              metadataLines.add('משתתפים: ${f.attendeesCount}');
                            }
                            metadataLines.add('תאריך: $dateStr');
                          }

                          // Get blue tag label - build a map from FeedbackModel
                          // Pass exercise for type detection, not as rangeType
                          final feedbackData = <String, dynamic>{
                            'feedbackType': f.type,
                            'exercise': f.exercise,
                            'folder': f.folder,
                            'module': f.module,
                            'rangeType':
                                '', // Will be inferred from other fields
                            'rangeSubType': f
                                .rangeSubType, // ✅ Display label for short/long
                          };
                          final blueTagLabel = getBlueTagLabelFromDoc(
                            feedbackData,
                          );

                          // Check delete permissions - only admin for now (proper check requires async)
                          final canDelete = currentUser?.role == 'Admin';

                          // Check if folder supports selection mode
                          final supportsSelectionMode =
                              _selectedFolder == 'מטווחים 474' ||
                              _selectedFolder == '474 Ranges' ||
                              _selectedFolder == 'מטווחי ירי' ||
                              _selectedFolder == 'מחלקות ההגנה – חטיבה 474' ||
                              _selectedFolder == 'משובים – כללי' ||
                              _selectedFolder == 'משוב תרגילי הפתעה' ||
                              _selectedFolder == 'תרגילי הפתעה כללי';

                          return FeedbackListTileCard(
                            title: title,
                            metadataLines: metadataLines,
                            blueTagLabel: blueTagLabel,
                            canDelete: canDelete && !_selectionMode,
                            selectionMode:
                                _selectionMode && supportsSelectionMode,
                            isSelected: _selectedFeedbackIds.contains(f.id),
                            onSelectionToggle: f.id != null && f.id!.isNotEmpty
                                ? () {
                                    setState(() {
                                      if (_selectedFeedbackIds.contains(f.id)) {
                                        _selectedFeedbackIds.remove(f.id);
                                      } else {
                                        _selectedFeedbackIds.add(f.id!);
                                      }
                                    });
                                  }
                                : null,
                            onOpen: () {
                              if (_selectionMode && supportsSelectionMode) {
                                // In selection mode, clicking toggles selection
                                if (f.id != null && f.id!.isNotEmpty) {
                                  setState(() {
                                    if (_selectedFeedbackIds.contains(f.id)) {
                                      _selectedFeedbackIds.remove(f.id);
                                    } else {
                                      _selectedFeedbackIds.add(f.id!);
                                    }
                                  });
                                }
                              } else {
                                // Normal mode, open feedback details
                                Navigator.of(
                                  context,
                                ).pushNamed('/feedback_details', arguments: f);
                              }
                            },
                            onDelete:
                                f.id != null &&
                                    f.id!.isNotEmpty &&
                                    !_selectionMode
                                ? () => _confirmDeleteFeedback(f.id!, title)
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class FeedbackDetailsPage extends StatefulWidget {
  final FeedbackModel feedback;
  const FeedbackDetailsPage({super.key, required this.feedback});

  @override
  State<FeedbackDetailsPage> createState() => _FeedbackDetailsPageState();
}

class _FeedbackDetailsPageState extends State<FeedbackDetailsPage> {
  late FeedbackModel feedback;
  String? resolvedInstructorName; // Cached resolved name
  bool isResolvingName = false;

  @override
  void initState() {
    super.initState();
    feedback = widget.feedback;
    _resolveInstructorNameIfNeeded();
  }

  /// Resolve instructor name if it looks like email/UID
  Future<void> _resolveInstructorNameIfNeeded() async {
    final currentName = feedback.instructorName;

    // Check if name needs resolution (contains @, looks like UID, or is placeholder)
    final needsResolution =
        currentName.isEmpty ||
        currentName.contains('@') ||
        currentName.startsWith('מדריך ') ||
        currentName.length < 3;

    if (!needsResolution) {
      // Name looks good, use as-is
      setState(() {
        resolvedInstructorName = currentName;
      });
      return;
    }

    // Try to resolve from Firestore using feedback ID
    setState(() {
      isResolvingName = true;
    });

    try {
      if (feedback.id != null && feedback.id!.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('feedbacks')
            .doc(feedback.id)
            .get()
            .timeout(const Duration(seconds: 3));

        if (doc.exists) {
          final data = doc.data();
          final createdByUid = data?['createdByUid'] ?? data?['instructorId'];

          if (createdByUid != null && createdByUid.toString().isNotEmpty) {
            final resolvedName = await resolveUserHebrewName(
              createdByUid.toString(),
            );
            setState(() {
              resolvedInstructorName = resolvedName;
              isResolvingName = false;
            });

            // Optionally backfill the document with the resolved name
            await doc.reference.update({
              'instructorName': resolvedName,
              'createdByName': resolvedName,
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve instructor name: $e');
    }

    // Fallback: use original name
    setState(() {
      resolvedInstructorName = currentName.isNotEmpty ? currentName : 'לא ידוע';
      isResolvingName = false;
    });
  }

  bool _isExporting = false;

  void _showStationDetailsModal(
    BuildContext context,
    int stationIndex,
    String stationName,
    int bulletsPerTrainee,
    List<Map<String, dynamic>> trainees,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.blueGrey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'פרטי מקצה — $stationName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Colors.blueGrey.shade700,
                        ),
                        columns: const [
                          DataColumn(
                            label: Text(
                              'חניך',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'תוצאות',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        rows: trainees.map((t) {
                          final name = (t['name'] ?? '').toString();
                          final hitsMap =
                              (t['hits'] as Map?)?.cast<String, dynamic>() ??
                              {};
                          final hits =
                              (hitsMap['station_$stationIndex'] as num?)
                                  ?.toInt() ??
                              0;
                          final bullets = bulletsPerTrainee;
                          final pct = bullets > 0
                              ? ((hits / bullets) * 100).toStringAsFixed(1)
                              : '0.0';

                          // Get time value for בוחן רמה
                          final timeValuesMap =
                              (t['timeValues'] as Map?)
                                  ?.cast<String, dynamic>() ??
                              {};
                          final timeInSeconds =
                              (timeValuesMap['station_${stationIndex}_time']
                                      as num?)
                                  ?.toDouble() ??
                              0.0;
                          final timeDisplay = timeInSeconds > 0
                              ? '${timeInSeconds}s'
                              : '';

                          // Check if this is a בוחן רמה station by station name
                          final isLevelTester = stationName.contains(
                            'בוחן רמה',
                          );

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              DataCell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$hits מתוך $bullets • $pct%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    // Show time for בוחן רמה stations
                                    if (isLevelTester && timeDisplay.isNotEmpty)
                                      Text(
                                        'זמן: $timeDisplay',
                                        style: const TextStyle(
                                          color: Colors.lightBlueAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = feedback.createdAt.toLocal().toString().split('.').first;
    final isAdmin = currentUser?.role == 'Admin';
    final is474Ranges =
        feedback.folder == 'מטווחים 474' ||
        feedback.folder == '474 Ranges' ||
        feedback.folderKey == 'ranges_474';

    // Check if this is a special feedback type that should NOT show command box
    final isRangeFeedback =
        is474Ranges ||
        feedback.folder == 'מטווחי ירי' ||
        feedback.folderKey == 'shooting_ranges' ||
        feedback.module == 'shooting_ranges';
    final isSurpriseDrill =
        feedback.folder == 'משוב תרגילי הפתעה' ||
        feedback.module == 'surprise_drill';
    final isTrainingSummary =
        feedback.folder == 'משוב סיכום אימון 474' ||
        feedback.module == 'training_summary';
    final hideCommandBox =
        isRangeFeedback || isSurpriseDrill || isTrainingSummary;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('פרטי משוב'),
          leading: const StandardBackButton(),
          actions: [],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView(
            children: [
              // Show resolved instructor name (or loading indicator)
              isResolvingName
                  ? const Row(
                      children: [
                        Text('מדריך: '),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    )
                  : Text(
                      'מדריך: ${resolvedInstructorName ?? feedback.instructorName}',
                    ),
              const SizedBox(height: 8),
              // Additional instructors for range/training feedbacks
              if ((feedback.module == 'training_summary' ||
                      feedback.module == 'surprise_drill' ||
                      feedback.module == 'shooting_ranges' ||
                      feedback.folderKey == 'ranges_474' ||
                      feedback.folderKey == 'shooting_ranges') &&
                  feedback.id != null &&
                  feedback.id!.isNotEmpty)
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('feedbacks')
                      .doc(feedback.id)
                      .get()
                      .timeout(const Duration(seconds: 3)),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const SizedBox.shrink();
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data == null) return const SizedBox.shrink();

                    final additionalInstructors =
                        (data['instructors'] as List?)?.cast<String>() ?? [];

                    // Filter out main instructor from the list
                    final filteredInstructors = additionalInstructors
                        .where(
                          (name) =>
                              name.isNotEmpty &&
                              name != feedback.instructorName &&
                              name != resolvedInstructorName,
                        )
                        .toList();

                    if (filteredInstructors.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'מדריכים נוספים:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...filteredInstructors.map(
                          (name) => Padding(
                            padding: const EdgeInsets.only(
                              right: 12.0,
                              bottom: 2.0,
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              Text('תאריך: $date'),
              const SizedBox(height: 8),
              Text('תרגיל: ${feedback.exercise}'),
              const SizedBox(height: 8),
              if (feedback.folder.isNotEmpty) ...[
                Text('תיקייה: ${feedback.folder}'),
                const SizedBox(height: 8),
              ],
              if (feedback.scenario.isNotEmpty) ...[
                Text('תרחיש: ${feedback.scenario}'),
                const SizedBox(height: 8),
              ],
              if ((feedback.folderKey == 'shooting_ranges' ||
                      feedback.folder == 'מטווחי ירי' ||
                      feedback.module == 'shooting_ranges') &&
                  feedback.attendeesCount > 0) ...[
                Text(
                  'מספר חניכים/נוכחים באימון: ${feedback.attendeesCount}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Conditional display: Check training summary first, then ranges, surprise drills, and finally regular feedbacks
              if (feedback.folder == 'משוב סיכום אימון 474' ||
                  feedback.module == 'training_summary')
                Text('נוכחים: ${feedback.attendeesCount}')
              else if (feedback.folder == 'משוב תרגילי הפתעה' ||
                  feedback.module == 'surprise_drill')
                const SizedBox.shrink() // No role display for surprise drills
              else if (feedback.folderKey == 'shooting_ranges' ||
                  feedback.folderKey == 'ranges_474' ||
                  feedback.folder == 'מטווחי ירי' ||
                  feedback.folder == 'מטווחים 474' ||
                  feedback.module == 'shooting_ranges')
                Text(
                  'טווח: ${feedback.rangeSubType.isNotEmpty ? feedback.rangeSubType : 'לא ידוע'}',
                )
              else
                Text('תפקיד: ${feedback.role}'),
              const SizedBox(height: 8),
              // Display settlement/name based on feedback type
              if (feedback.folderKey == 'shooting_ranges' ||
                  feedback.folder == 'מטווחי ירי' ||
                  feedback.module == 'shooting_ranges')
                Text('יישוב: ${feedback.settlement}')
              else if (feedback.folder == 'משוב תרגילי הפתעה' ||
                  feedback.module == 'surprise_drill')
                Text(
                  'יישוב: ${feedback.name}',
                ) // For surprise drills, 'name' field contains settlement
              else if (feedback.folder == 'משוב סיכום אימון 474' ||
                  feedback.module == 'training_summary')
                Text('יישוב: ${feedback.settlement}')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('שם: ${feedback.name}'),
                    if (feedback.settlement.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('יישוב: ${feedback.settlement}'),
                    ],
                  ],
                ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'קריטריונים:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // show saved criteria names if present, otherwise fall back to scores map (only non-zero)
              if (feedback.criteriaList.isNotEmpty)
                ...feedback.criteriaList.map((name) {
                  final score = feedback.scores[name] ?? '';
                  final note = feedback.notes[name] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$name — $score'),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('הערה: $note'),
                        ],
                      ],
                    ),
                  );
                })
              else
                ...feedback.scores.entries.where((e) => e.value != 0).map((e) {
                  final name = e.key;
                  final score = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text('$name — $score')],
                    ),
                  );
                }),
              const SizedBox(height: 20),

              // סיכום ופירוט למשובי סיכום אימון
              ...(feedback.folder == 'משוב סיכום אימון 474' ||
                          feedback.module == 'training_summary') &&
                      feedback.id != null &&
                      feedback.id!.isNotEmpty
                  ? <Widget>[
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('feedbacks')
                            .doc(feedback.id)
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            return const SizedBox.shrink();
                          }

                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          if (data == null) {
                            return const SizedBox.shrink();
                          }

                          final trainingType =
                              (data['trainingType'] as String?) ?? '';
                          final attendees =
                              (data['attendees'] as List?)?.cast<String>() ??
                              [];
                          final summary = (data['summary'] as String?) ?? '';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'פרטי האימון',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Training type
                              if (trainingType.isNotEmpty) ...[
                                Card(
                                  color: Colors.blueGrey.shade700,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'סוג אימון',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          trainingType,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Attendees list
                              if (attendees.isNotEmpty) ...[
                                Text(
                                  'נוכחים (${attendees.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Card(
                                  color: Colors.blueGrey.shade800,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      children: attendees.asMap().entries.map((
                                        entry,
                                      ) {
                                        final index = entry.key;
                                        final name = entry.value;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4.0,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: const BoxDecoration(
                                                  color: Colors.orangeAccent,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${index + 1}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Summary
                              if (summary.isNotEmpty) ...[
                                const Text(
                                  'סיכום האימון',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Card(
                                  color: Colors.blueGrey.shade700,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Text(
                                      summary,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // ✨ Linked personal feedbacks section
                              Builder(
                                builder: (context) {
                                  final linkedFeedbackIds =
                                      (data['linkedFeedbackIds'] as List?)
                                          ?.cast<String>() ??
                                      [];

                                  if (linkedFeedbackIds.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 20),
                                      const Divider(thickness: 2),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: const [
                                          Icon(
                                            Icons.link,
                                            color: Colors.orangeAccent,
                                            size: 24,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'משובים אישיים מקושרים',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orangeAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${linkedFeedbackIds.length} משובים מקושרים',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Load and display each linked feedback
                                      ...linkedFeedbackIds.map((feedbackId) {
                                        return FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance
                                              .collection('feedbacks')
                                              .doc(feedbackId)
                                              .get()
                                              .timeout(
                                                const Duration(seconds: 5),
                                              ),
                                          builder: (context, linkedSnapshot) {
                                            if (!linkedSnapshot.hasData ||
                                                !linkedSnapshot.data!.exists) {
                                              return Card(
                                                color: Colors.blueGrey.shade700,
                                                margin: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(12.0),
                                                  child: Text(
                                                    'טוען משוב...',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }

                                            final linkedData =
                                                linkedSnapshot.data!.data()
                                                    as Map<String, dynamic>?;

                                            if (linkedData == null) {
                                              return const SizedBox.shrink();
                                            }

                                            final linkedFeedback =
                                                FeedbackModel.fromMap(
                                                  linkedData,
                                                  id: feedbackId,
                                                );

                                            if (linkedFeedback == null) {
                                              return const SizedBox.shrink();
                                            }

                                            // Calculate average score
                                            final scores = linkedFeedback
                                                .scores
                                                .values
                                                .where((v) => v > 0)
                                                .toList();
                                            final avgScore = scores.isNotEmpty
                                                ? (scores.reduce(
                                                            (a, b) => a + b,
                                                          ) /
                                                          scores.length)
                                                      .toStringAsFixed(1)
                                                : '-';

                                            return Card(
                                              color: Colors.blueGrey.shade700,
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: InkWell(
                                                onTap: () {
                                                  // Navigate to the linked feedback details
                                                  Navigator.of(
                                                    context,
                                                  ).pushNamed(
                                                    '/feedback_details',
                                                    arguments: linkedFeedback,
                                                  );
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12.0,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      // Avatar with score
                                                      Container(
                                                        width: 50,
                                                        height: 50,
                                                        decoration: BoxDecoration(
                                                          color: Colors
                                                              .orangeAccent,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            avgScore,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .black,
                                                                  fontSize: 16,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      // Feedback info
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              '${linkedFeedback.role} — ${linkedFeedback.name}',
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 15,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              'תרגיל: ${linkedFeedback.exercise}',
                                                              style:
                                                                  const TextStyle(
                                                                    color: Colors
                                                                        .white70,
                                                                    fontSize:
                                                                        13,
                                                                  ),
                                                            ),
                                                            Text(
                                                              'מדריך: ${linkedFeedback.instructorName}',
                                                              style:
                                                                  const TextStyle(
                                                                    color: Colors
                                                                        .white70,
                                                                    fontSize:
                                                                        13,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // Arrow icon
                                                      const Icon(
                                                        Icons.arrow_forward_ios,
                                                        color: Colors.white70,
                                                        size: 16,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      }),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ]
                  : [],

              // סיכום ופירוט עקרונות למשובי תרגילי הפתעה
              ...(feedback.folder == 'משוב תרגילי הפתעה' ||
                          feedback.module == 'surprise_drill') &&
                      feedback.id != null &&
                      feedback.id!.isNotEmpty
                  ? <Widget>[
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('feedbacks')
                            .doc(feedback.id)
                            .get(),
                        builder: (context, snapshot) {
                          debugPrint('\n🔍 SURPRISE DRILLS DETAILS SCREEN');
                          debugPrint('   Feedback ID: ${feedback.id}');
                          debugPrint('   Folder: ${feedback.folder}');
                          debugPrint('   Module: ${feedback.module}');
                          debugPrint(
                            '   Has data: ${snapshot.hasData}, Exists: ${snapshot.data?.exists}',
                          );

                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            debugPrint(
                              '   ❌ No snapshot data or doc not exists',
                            );
                            return const SizedBox.shrink();
                          }

                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          if (data == null) {
                            debugPrint('   ❌ Snapshot data is null');
                            return const SizedBox.shrink();
                          }

                          debugPrint(
                            '   ✅ Document keys: ${data.keys.toList()}',
                          );

                          final stations =
                              (data['stations'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [];
                          final trainees =
                              (data['trainees'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [];

                          debugPrint(
                            '   Stations (principles) count: ${stations.length}',
                          );
                          debugPrint('   Trainees count: ${trainees.length}');

                          if (stations.isEmpty && trainees.isEmpty) {
                            debugPrint(
                              '   ⚠️ Both stations and trainees are empty',
                            );
                            return const SizedBox.shrink();
                          }

                          // For surprise drills: stations = principles
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Show principles list
                              if (stations.isNotEmpty) ...[
                                const Text(
                                  'עקרונות',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...stations.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final station = entry.value;
                                  final principleName =
                                      station['name'] ?? 'עיקרון ${index + 1}';

                                  return Card(
                                    color: Colors.blueGrey.shade700,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: const BoxDecoration(
                                              color: Colors.orangeAccent,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${index + 1}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              principleName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 16),
                              ],

                              // Show trainees table
                              if (trainees.isNotEmpty) ...[
                                const Text(
                                  'חניכים',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Card(
                                  color: Colors.blueGrey.shade800,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                              Colors.blueGrey.shade700,
                                            ),
                                        columns: [
                                          const DataColumn(
                                            label: Text(
                                              'שם',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          ...stations.asMap().entries.map((
                                            entry,
                                          ) {
                                            final station = entry.value;
                                            final name =
                                                station['name'] ??
                                                'עיקרון ${entry.key + 1}';
                                            return DataColumn(
                                              label: Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            );
                                          }),
                                          DataColumn(
                                            label: Text(
                                              'ממוצע',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                        rows: trainees.map((trainee) {
                                          final name = (trainee['name'] ?? '')
                                              .toString();
                                          final hitsMap =
                                              (trainee['hits'] as Map?)
                                                  ?.cast<String, dynamic>() ??
                                              {};

                                          // Calculate average of filled criteria (ignore null/empty)
                                          final filledValues = <int>[];
                                          for (
                                            var i = 0;
                                            i < stations.length;
                                            i++
                                          ) {
                                            final value = hitsMap['station_$i'];
                                            if (value != null && value is num) {
                                              final intVal = value.toInt();
                                              if (intVal > 0) {
                                                filledValues.add(intVal);
                                              }
                                            }
                                          }

                                          // Calculate average
                                          String avgDisplay;
                                          if (filledValues.isEmpty) {
                                            avgDisplay = '-';
                                          } else {
                                            final sum = filledValues.reduce(
                                              (a, b) => a + b,
                                            );
                                            final avg =
                                                sum / filledValues.length;
                                            // Format: integer without decimals, otherwise 1 decimal
                                            if (avg == avg.toInt()) {
                                              avgDisplay = avg
                                                  .toInt()
                                                  .toString();
                                            } else {
                                              avgDisplay = avg.toStringAsFixed(
                                                1,
                                              );
                                            }
                                          }

                                          return DataRow(
                                            cells: [
                                              DataCell(
                                                Text(
                                                  name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              ...stations.asMap().entries.map((
                                                entry,
                                              ) {
                                                final stationIdx = entry.key;
                                                final score =
                                                    (hitsMap['station_$stationIdx']
                                                            as num?)
                                                        ?.toInt() ??
                                                    0;
                                                return DataCell(
                                                  Text(
                                                    score.toString(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                );
                                              }),
                                              DataCell(
                                                Text(
                                                  avgDisplay,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orangeAccent,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // ✅ הצגת סיכום האימון לתרגילי הפתעה
                              Builder(
                                builder: (context) {
                                  final summary =
                                      (data['summary'] as String?) ?? '';
                                  if (summary.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 16),
                                      const Text(
                                        'סיכום האימון',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Card(
                                        color: Colors.blueGrey.shade700,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Text(
                                            summary,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              height: 1.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ]
                  : [],

              // סיכום ופירוט מקצים למשובי מטווחים 474
              ...is474Ranges && feedback.id != null && feedback.id!.isNotEmpty
                  ? <Widget>[
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('feedbacks')
                            .doc(feedback.id)
                            .get(),
                        builder: (context, snapshot) {
                          debugPrint('\n🔍 474 RANGES DETAILS SCREEN');
                          debugPrint('   Feedback ID: ${feedback.id}');
                          debugPrint('   Folder: ${feedback.folder}');
                          debugPrint('   FolderKey: ${feedback.folderKey}');
                          debugPrint(
                            '   Has data: ${snapshot.hasData}, Exists: ${snapshot.data?.exists}',
                          );

                          // ✅ DEBUG: Log fetched document path for טווח רחוק bug verification
                          final debugFeedbackType = feedback.type;
                          final debugRangeSubType = feedback.rangeSubType;
                          final debugIsLongRange =
                              debugFeedbackType == 'range_long' ||
                              debugFeedbackType == 'דווח רחוק' ||
                              debugRangeSubType == 'טווח רחוק';
                          if (debugIsLongRange) {
                            debugPrint(
                              '🔍 טווח רחוק FETCHED: collection=feedbacks, docId=${feedback.id}',
                            );
                            debugPrint('   Path: feedbacks/${feedback.id}');
                            debugPrint(
                              '   Document exists: ${snapshot.data?.exists}',
                            );
                            debugPrint(
                              '   feedbackType: $debugFeedbackType, rangeSubType: $debugRangeSubType',
                            );
                          }

                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            debugPrint(
                              '   ❌ No snapshot data or doc not exists',
                            );
                            return const SizedBox.shrink();
                          }

                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          if (data == null) {
                            debugPrint('   ❌ Snapshot data is null');
                            return const SizedBox.shrink();
                          }

                          debugPrint(
                            '   ✅ Document keys: ${data.keys.toList()}',
                          );

                          final stations =
                              (data['stations'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [];
                          final trainees =
                              (data['trainees'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [];

                          debugPrint('   Stations count: ${stations.length}');
                          debugPrint('   Trainees count: ${trainees.length}');

                          if (trainees.isNotEmpty) {
                            final firstTrainee = trainees[0];
                            final firstTraineeHits = firstTrainee['hits'] ?? {};
                            debugPrint(
                              '   First trainee: ${firstTrainee['name']}',
                            );
                            debugPrint(
                              '   First trainee hits keys: ${firstTraineeHits is Map ? firstTraineeHits.keys.toList() : 'Not a map'}',
                            );
                          }

                          // Skip empty message for training summary (not a range feedback)
                          if (stations.isEmpty || trainees.isEmpty) {
                            debugPrint(
                              '   ⚠️ Either stations or trainees are empty',
                            );
                            return const SizedBox.shrink();
                          }

                          // ✅ DETECT LONG RANGE: Check BOTH feedbackType AND rangeSubType for compatibility
                          final feedbackType =
                              (data['feedbackType'] as String?) ?? '';
                          final rangeSubType =
                              (data['rangeSubType'] as String?) ?? '';
                          final isLongRange =
                              feedbackType == 'range_long' ||
                              feedbackType == 'דווח רחוק' ||
                              rangeSubType == 'טווח רחוק';

                          debugPrint(
                            '\n🔍 ===== 474 RANGES FEEDBACK DETAILS =====',
                          );
                          debugPrint('   Feedback ID: ${feedback.id}');
                          debugPrint('   feedbackType: $feedbackType');
                          debugPrint('   rangeSubType: $rangeSubType');
                          debugPrint('   isLongRange: $isLongRange');
                          debugPrint(
                            '   trainees.length (N): ${trainees.length}',
                          );
                          debugPrint('   stations.length: ${stations.length}');

                          // ✅ AUTO-MIGRATE: Fix old long-range feedbacks missing maxScorePoints
                          bool needsMigration = false;
                          if (isLongRange) {
                            for (int i = 0; i < stations.length; i++) {
                              final station = stations[i];
                              final maxScorePoints = station['maxScorePoints'];
                              if (maxScorePoints == null) {
                                needsMigration = true;
                                // Use legacy maxPoints if exists, else 0 (NEVER default to 10)
                                final legacyMaxPoints =
                                    (station['maxPoints'] as num?)?.toInt() ??
                                    0;
                                stations[i]['maxScorePoints'] = legacyMaxPoints;
                                debugPrint(
                                  '   🔧 MIGRATION: station[$i] missing maxScorePoints, set to $legacyMaxPoints (from legacy maxPoints)',
                                );
                              }
                            }

                            if (needsMigration && feedback.id != null) {
                              debugPrint(
                                '   💾 MIGRATION: Writing corrected stations to Firestore...',
                              );
                              // Schedule migration outside builder to avoid async in sync context
                              Future.microtask(() async {
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('feedbacks')
                                      .doc(feedback.id)
                                      .update({'stations': stations});
                                  debugPrint(
                                    '   ✅ MIGRATION: Stations updated in Firestore',
                                  );
                                } catch (e) {
                                  debugPrint('   ❌ MIGRATION ERROR: $e');
                                }
                              });
                            }
                          }

                          // ✅ CONDITIONAL LOGIC: Points for long range, hits for short range
                          int totalValue = 0;
                          int totalMax = 0;

                          if (isLongRange) {
                            // LONG RANGE: Use points-based calculation
                            debugPrint(
                              '\n   📊 LONG RANGE CALCULATION (POINTS):',
                            );

                            // Sum achieved points from trainees
                            for (final trainee in trainees) {
                              final traineePoints =
                                  (trainee['totalHits'] as num?)?.toInt() ?? 0;
                              totalValue += traineePoints;
                            }

                            // Calculate totalMax from N * SUM(maxScorePoints)
                            int sumMaxScorePoints = 0;
                            for (int i = 0; i < stations.length; i++) {
                              final station = stations[i];
                              final stageName = station['name'] ?? 'Stage $i';
                              final maxScorePoints =
                                  (station['maxScorePoints'] as num?)
                                      ?.toInt() ??
                                  0;
                              final legacyMaxPoints =
                                  (station['maxPoints'] as num?)?.toInt() ?? 0;
                              final bulletsTracking =
                                  (station['bulletsCount'] as num?)?.toInt() ??
                                  0;

                              debugPrint('   Stage[$i]: "$stageName"');
                              debugPrint(
                                '      maxScorePoints: $maxScorePoints',
                              );
                              debugPrint(
                                '      legacy maxPoints: $legacyMaxPoints',
                              );
                              debugPrint(
                                '      bulletsTracking: $bulletsTracking',
                              );
                              debugPrint(
                                '      ✅ USED maxScorePoints: $maxScorePoints',
                              );

                              sumMaxScorePoints += maxScorePoints;
                            }

                            totalMax = trainees.length * sumMaxScorePoints;
                            debugPrint('\n   📐 TOTAL MAX CALCULATION:');
                            debugPrint(
                              '      N (trainees): ${trainees.length}',
                            );
                            debugPrint(
                              '      SUM(maxScorePoints): $sumMaxScorePoints',
                            );
                            debugPrint(
                              '      totalMax = N × SUM = ${trainees.length} × $sumMaxScorePoints = $totalMax',
                            );
                            debugPrint(
                              '      totalValue (achieved): $totalValue',
                            );
                            debugPrint('      RESULT: $totalValue / $totalMax');
                          } else {
                            // SHORT RANGE: Use hits/bullets (existing logic)
                            for (final trainee in trainees) {
                              totalValue +=
                                  (trainee['totalHits'] as num?)?.toInt() ?? 0;
                            }
                            int totalBulletsPerTrainee = 0;
                            for (final station in stations) {
                              totalBulletsPerTrainee +=
                                  (station['bulletsCount'] as num?)?.toInt() ??
                                  0;
                            }
                            totalMax = trainees.length * totalBulletsPerTrainee;
                          }

                          // חישוב אחוז כללי
                          final percentage = totalMax > 0
                              ? ((totalValue / totalMax) * 100).toStringAsFixed(
                                  1,
                                )
                              : '0.0';

                          // ✅ LONG RANGE: Calculate total bullets fired (tracking only)
                          int totalBulletsFired = 0;
                          if (isLongRange) {
                            for (final station in stations) {
                              final bulletsTracking =
                                  (station['bulletsCount'] as num?)?.toInt() ??
                                  0;
                              totalBulletsFired +=
                                  bulletsTracking * trainees.length;
                            }
                          }

                          debugPrint(
                            '🔍 ===== END 474 RANGES FEEDBACK DETAILS =====\n',
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // כרטיס סיכום כללי למטווח 474
                              Card(
                                color: Colors.blueGrey.shade800,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'סיכום כללי - מטווח 474',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      // ✅ LONG RANGE: Show points, percentage, and bullets fired
                                      isLongRange
                                          ? Column(
                                              children: [
                                                // Points display
                                                Text(
                                                  'סך נקודות',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  '$totalValue / $totalMax',
                                                  style: const TextStyle(
                                                    fontSize: 32,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orangeAccent,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                // Percentage (from points only)
                                                Text(
                                                  '$percentage%',
                                                  style: const TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.greenAccent,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                const Text(
                                                  'אחוז הצלחה',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                // Total bullets fired (tracking only)
                                                Text(
                                                  'סה"כ כדורים שנורו: $totalBulletsFired',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white70,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                Column(
                                                  children: [
                                                    const Text(
                                                      'סך פגיעות/כדורים',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '$totalValue/$totalMax',
                                                      style: const TextStyle(
                                                        fontSize: 24,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Colors.orangeAccent,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  children: [
                                                    const Text(
                                                      'אחוז פגיעה כללי',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '$percentage%',
                                                      style: const TextStyle(
                                                        fontSize: 32,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Colors.greenAccent,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // פירוט מקצים למטווח 474
                              const Text(
                                'פירוט מקצים',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),

                              ...stations.asMap().entries.map((entry) {
                                final index = entry.key;
                                final station = entry.value;
                                final stationName =
                                    station['name'] ?? 'מקצה ${index + 1}';

                                // ✅ CONDITIONAL: For long range use maxScorePoints, for short use bullets
                                final stationMaxPerTrainee = isLongRange
                                    ? ((station['maxScorePoints'] as num?)
                                              ?.toInt() ??
                                          0)
                                    : ((station['bulletsCount'] as num?)
                                              ?.toInt() ??
                                          0);

                                // חישוב סך פגיעות/נקודות למקצה
                                int stationValue = 0;
                                for (final trainee in trainees) {
                                  final hits =
                                      trainee['hits'] as Map<String, dynamic>?;
                                  if (hits != null) {
                                    stationValue +=
                                        (hits['station_$index'] as num?)
                                            ?.toInt() ??
                                        0;
                                  }
                                }

                                // חישוב נכון: מספר חניכים × max per trainee
                                final totalStationMax =
                                    trainees.length * stationMaxPerTrainee;

                                // חישוב אחוז פגיעות למקצה
                                final stationPercentage = totalStationMax > 0
                                    ? ((stationValue / totalStationMax) * 100)
                                          .toStringAsFixed(1)
                                    : '0.0';

                                // ✅ LONG RANGE: Calculate stage bullets fired (tracking only)
                                final stageBulletsFired = isLongRange
                                    ? ((station['bulletsCount'] as num?)
                                                  ?.toInt() ??
                                              0) *
                                          trainees.length
                                    : 0;

                                return InkWell(
                                  onTap: () {
                                    // For long range: pass maxPoints instead of bullets
                                    final modalMaxValue = isLongRange
                                        ? stationMaxPerTrainee
                                        : stationMaxPerTrainee;
                                    _showStationDetailsModal(
                                      context,
                                      index,
                                      stationName.toString(),
                                      modalMaxValue,
                                      trainees,
                                    );
                                  },
                                  child: Card(
                                    color: Colors.blueGrey.shade700,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // שורה 1: שם המקצה
                                          Text(
                                            stationName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          // מדדים מרוכזים בשורה אחת
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: [
                                              // סך כל כדורים/נקודות מקסימליות
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '$totalStationMax',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white70,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Text(
                                                    isLongRange
                                                        ? 'סך נקודות מקס'
                                                        : 'סך כל כדורים',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white60,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // סך כל פגיעות/נקודות
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '$stationValue',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.orangeAccent,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Text(
                                                    isLongRange
                                                        ? 'סך נקודות'
                                                        : 'סך כל פגיעות',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white60,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // אחוז - SHOW FOR BOTH (from points for long, from hits for short)
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '$stationPercentage%',
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.greenAccent,
                                                    ),
                                                  ),
                                                  Text(
                                                    isLongRange
                                                        ? 'אחוז הצלחה'
                                                        : 'אחוז פגיעות',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white60,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          // ✅ LONG RANGE: Show bullets fired for this stage
                                          if (isLongRange &&
                                              stageBulletsFired > 0) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'כדורים שנורו במקצה: $stageBulletsFired',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white60,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          const Text(
                                            'לחץ לפרטי החניכים במקצה',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),

                              // ✅ הצגת סיכום האימון למטווחים 474
                              Builder(
                                builder: (context) {
                                  final summary =
                                      (data['summary'] as String?) ?? '';
                                  if (summary.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 16),
                                      const Text(
                                        'סיכום האימון',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Card(
                                        color: Colors.blueGrey.shade700,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Text(
                                            summary,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              height: 1.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ]
                  : [],

              // סיכום ופירוט מקצים למשובי מטווחים
              ...feedback.folder == 'מטווחי ירי' &&
                      feedback.id != null &&
                      feedback.id!.isNotEmpty
                  ? <Widget>[
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('feedbacks')
                            .doc(feedback.id)
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            return const SizedBox.shrink();
                          }

                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          if (data == null) {
                            return const SizedBox.shrink();
                          }

                          final stations =
                              (data['stations'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [];
                          final trainees =
                              (data['trainees'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [];

                          if (stations.isEmpty || trainees.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          // ✅ DETECT LONG RANGE: Check BOTH feedbackType AND rangeSubType for compatibility
                          final feedbackType =
                              (data['feedbackType'] as String?) ?? '';
                          final rangeSubType =
                              (data['rangeSubType'] as String?) ?? '';
                          final isLongRange =
                              feedbackType == 'range_long' ||
                              feedbackType == 'דווח רחוק' ||
                              rangeSubType == 'טווח רחוק';

                          // ✅ CONDITIONAL LOGIC: Points for long range, hits for short range
                          int totalValue = 0;
                          int totalMax = 0;

                          if (isLongRange) {
                            // LONG RANGE: Use points (raw values as stored)
                            for (final trainee in trainees) {
                              totalValue +=
                                  (trainee['totalHits'] as num?)?.toInt() ??
                                  0; // Raw points stored in totalHits
                            }
                            // Sum maxPoints from stations
                            for (final station in stations) {
                              final stationMaxPoints =
                                  (station['maxPoints'] as num?)?.toInt() ?? 0;
                              totalMax += stationMaxPoints * trainees.length;
                            }
                          } else {
                            // SHORT RANGE: Use hits/bullets (existing logic)
                            for (final trainee in trainees) {
                              totalValue +=
                                  (trainee['totalHits'] as num?)?.toInt() ?? 0;
                            }
                            // ✅ חישוב נכון: מספר חניכים × סך כדורים בכל המקצים
                            int totalBulletsPerTrainee = 0;
                            for (final station in stations) {
                              totalBulletsPerTrainee +=
                                  (station['bulletsCount'] as num?)?.toInt() ??
                                  0;
                            }
                            totalMax = trainees.length * totalBulletsPerTrainee;
                          }

                          // חישוב אחוז כללי
                          final percentage = totalMax > 0
                              ? ((totalValue / totalMax) * 100).toStringAsFixed(
                                  1,
                                )
                              : '0.0';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // כרטיס סיכום כללי
                              Card(
                                color: Colors.blueGrey.shade800,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'סיכום כללי',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      // ✅ LONG RANGE: Show ONLY points, NO percentage
                                      isLongRange
                                          ? Column(
                                              children: [
                                                const Text(
                                                  'סך נקודות',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  '$totalValue / $totalMax',
                                                  style: const TextStyle(
                                                    fontSize: 32,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orangeAccent,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                const Text(
                                                  'נקודות',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                Column(
                                                  children: [
                                                    const Text(
                                                      'סך פגיעות/כדורים',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '$totalValue/$totalMax',
                                                      style: const TextStyle(
                                                        fontSize: 24,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Colors.orangeAccent,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  children: [
                                                    const Text(
                                                      'אחוז פגיעה כללי',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '$percentage%',
                                                      style: const TextStyle(
                                                        fontSize: 32,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Colors.greenAccent,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // פירוט מקצים
                              const Text(
                                'פירוט מקצים',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),

                              ...stations.asMap().entries.map((entry) {
                                final index = entry.key;
                                final station = entry.value;
                                final stationName =
                                    station['name'] ?? 'מקצה ${index + 1}';

                                // ✅ CONDITIONAL: Points for long range, hits for short range
                                int stationValue = 0;
                                int stationMax = 0;

                                if (isLongRange) {
                                  // LONG RANGE: Use points (raw values)
                                  for (final trainee in trainees) {
                                    final hits =
                                        trainee['hits']
                                            as Map<String, dynamic>?;
                                    if (hits != null) {
                                      stationValue +=
                                          (hits['station_$index'] as num?)
                                              ?.toInt() ??
                                          0; // Raw points stored in hits map
                                    }
                                  }
                                  // Use maxPoints from station
                                  final maxPoints =
                                      (station['maxPoints'] as num?)?.toInt() ??
                                      0;
                                  stationMax = trainees.length * maxPoints;
                                } else {
                                  // SHORT RANGE: Use hits/bullets
                                  final stationBulletsPerTrainee =
                                      (station['bulletsCount'] as num?)
                                          ?.toInt() ??
                                      0;

                                  for (final trainee in trainees) {
                                    final hits =
                                        trainee['hits']
                                            as Map<String, dynamic>?;
                                    if (hits != null) {
                                      stationValue +=
                                          (hits['station_$index'] as num?)
                                              ?.toInt() ??
                                          0;
                                    }
                                  }

                                  // ✅ חישוב נכון: מספר חניכים × כדורים במקצה
                                  stationMax =
                                      trainees.length *
                                      stationBulletsPerTrainee;
                                }

                                // חישוב אחוז
                                final stationPercentage = stationMax > 0
                                    ? ((stationValue / stationMax) * 100)
                                          .toStringAsFixed(1)
                                    : '0.0';

                                return InkWell(
                                  onTap: () {
                                    // For long range: pass maxPoints instead of bullets
                                    final modalMaxValue = isLongRange
                                        ? ((station['maxPoints'] as num?)
                                                  ?.toInt() ??
                                              0)
                                        : (trainees.isNotEmpty
                                              ? (stationMax ~/ trainees.length)
                                              : 0);
                                    _showStationDetailsModal(
                                      context,
                                      index,
                                      stationName.toString(),
                                      modalMaxValue,
                                      trainees,
                                    );
                                  },
                                  child: Card(
                                    color: Colors.blueGrey.shade700,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // שורה 1: שם המקצה
                                          Text(
                                            stationName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          // מדדים מרוכזים בשורה אחת
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: [
                                              // סך כל כדורים/נקודות מקסימליות
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '$stationMax',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white70,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Text(
                                                    isLongRange
                                                        ? 'סך נקודות מקס'
                                                        : 'סך כל כדורים',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white60,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // סך כל פגיעות/נקודות
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '$stationValue',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.orangeAccent,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Text(
                                                    isLongRange
                                                        ? 'סך נקודות'
                                                        : 'סך כל פגיעות',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white60,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // אחוז פגיעות/נקודות - HIDE FOR LONG RANGE
                                              if (!isLongRange)
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      '$stationPercentage%',
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Colors.greenAccent,
                                                      ),
                                                    ),
                                                    const Text(
                                                      'אחוז פגיעות',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white60,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'לחץ לפרטי החניכים במקצה',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),

                              // ✅ הצגת סיכום האימון למטווחי ירי
                              Builder(
                                builder: (context) {
                                  final summary =
                                      (data['summary'] as String?) ?? '';
                                  if (summary.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 16),
                                      const Text(
                                        'סיכום האימון',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Card(
                                        color: Colors.blueGrey.shade700,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Text(
                                            summary,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              height: 1.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ]
                  : <Widget>[
                      Builder(
                        builder: (ctx) {
                          final scores = feedback.scores.values
                              .where((v) => v > 0)
                              .toList();
                          if (scores.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final avg =
                              scores.reduce((a, b) => a + b) / scores.length;
                          return Card(
                            color: Colors.blueGrey.shade800,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Text(
                                    'ציון ממוצע',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${avg.toStringAsFixed(1)} / 5',
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
              const SizedBox(height: 12),
              // Summary box (visible for general feedbacks - מעגל פתוח, מעגל פרוץ, סריקות רחוב)
              if (!hideCommandBox && feedback.summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.blueGrey.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'סיכום משוב',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          feedback.summary,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // כפתור ייצוא ל-XLSX מקומי (רק לאדמין)
              if (isAdmin) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'ייצוא נתונים',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Check if this is a training summary for specialized export button
                Builder(
                  builder: (context) {
                    final isTrainingSummary =
                        feedback.folder == 'משוב סיכום אימון 474' ||
                        feedback.module == 'training_summary';

                    if (isTrainingSummary) {
                      // Dedicated training summary export button
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  setState(() => _isExporting = true);
                                  try {
                                    if (feedback.id == null ||
                                        feedback.id!.isEmpty) {
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'שגיאה: חסר מזהה למשוב, לא ניתן לייצא',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      return;
                                    }

                                    // Fetch full document from Firestore to get all training data
                                    final doc = await FirebaseFirestore.instance
                                        .collection('feedbacks')
                                        .doc(feedback.id)
                                        .get();

                                    if (!doc.exists || doc.data() == null) {
                                      throw Exception(
                                        'לא נמצאו נתוני סיכום אימון',
                                      );
                                    }

                                    await FeedbackExportService.exportTrainingSummaryDetails(
                                      feedbackData: doc.data()!,
                                      fileNamePrefix:
                                          'סיכום_אימון_${feedback.settlement}',
                                    );

                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('הקובץ נוצר בהצלחה!'),
                                        backgroundColor: Colors.green,
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  } catch (e) {
                                    debugPrint(
                                      '❌ Training summary export error: $e',
                                    );
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'שגיאה בייצוא סיכום האימון: $e',
                                        ),
                                        backgroundColor: Colors.red,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isExporting = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.deepOrange,
                          ),
                          icon: _isExporting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: Text(
                            _isExporting
                                ? 'מייצא...'
                                : 'ייצוא פרטי סיכום האימון',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      );
                    } else {
                      // Standard export button for non-training summaries
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting
                              ? null
                              : () async {
                                  setState(() => _isExporting = true);
                                  try {
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );

                                    // Check if this is a surprise drill feedback
                                    final isSurpriseDrill =
                                        (feedback.folder ==
                                                'משוב תרגילי הפתעה' ||
                                            feedback.module ==
                                                'surprise_drill') &&
                                        feedback.id != null &&
                                        feedback.id!.isNotEmpty;

                                    // Check if this is a range/reporter feedback
                                    final isRangeFeedback =
                                        (feedback.folder == 'מטווחי ירי' ||
                                            feedback.folder == 'מטווחים 474' ||
                                            feedback.folderKey ==
                                                'shooting_ranges' ||
                                            feedback.folderKey ==
                                                'ranges_474') &&
                                        feedback.id != null &&
                                        feedback.id!.isNotEmpty;

                                    if (isSurpriseDrill) {
                                      // Export surprise drills with full station/trainee data
                                      try {
                                        // Fetch full document data from Firestore
                                        final doc = await FirebaseFirestore
                                            .instance
                                            .collection('feedbacks')
                                            .doc(feedback.id)
                                            .get();

                                        if (!doc.exists || doc.data() == null) {
                                          throw Exception(
                                            'לא נמצאו נתוני משוב תרגיל הפתעה',
                                          );
                                        }

                                        final feedbackData = doc.data()!;

                                        // Call exportSurpriseDrillsToXlsx with single feedback
                                        await FeedbackExportService.exportSurpriseDrillsToXlsx(
                                          feedbacksData: [feedbackData],
                                          fileNamePrefix:
                                              'תרגיל_הפתעה_${feedback.settlement}',
                                        );

                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('הקובץ נוצר בהצלחה!'),
                                            backgroundColor: Colors.green,
                                            duration: Duration(seconds: 3),
                                          ),
                                        );
                                      } catch (e) {
                                        debugPrint(
                                          '❌ Surprise drill export error: $e',
                                        );
                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'שגיאה בייצוא תרגיל הפתעה: $e',
                                            ),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(
                                              seconds: 5,
                                            ),
                                          ),
                                        );
                                      }
                                    } else if (isRangeFeedback) {
                                      // Use reporter comparison export for range feedbacks
                                      try {
                                        // Fetch full document data from Firestore
                                        final doc = await FirebaseFirestore
                                            .instance
                                            .collection('feedbacks')
                                            .doc(feedback.id)
                                            .get();

                                        if (!doc.exists || doc.data() == null) {
                                          throw Exception(
                                            'לא נמצאו נתוני משוב',
                                          );
                                        }

                                        final feedbackData = doc.data()!;

                                        // Check if this feedback has trainee comparison data
                                        final hasComparisonData =
                                            feedbackData['stations'] != null &&
                                            feedbackData['trainees'] != null;

                                        if (hasComparisonData) {
                                          await FeedbackExportService.exportReporterComparisonToGoogleSheets(
                                            feedbackData: feedbackData,
                                            fileNamePrefix:
                                                'reporter_comparison',
                                          );
                                        } else {
                                          // Fallback to standard export if no comparison data
                                          final keys = [
                                            'id',
                                            'role',
                                            'name',
                                            'exercise',
                                            'scores',
                                            'notes',
                                            'criteriaList',
                                            'createdAt',
                                            'instructorName',
                                            'instructorRole',
                                            'commandText',
                                            'commandStatus',
                                            'folder',
                                            'scenario',
                                            'settlement',
                                            'attendeesCount',
                                          ];
                                          final headers = [
                                            'ID',
                                            'תפקיד',
                                            'שם',
                                            'תרגיל',
                                            'ציונים',
                                            'הערות',
                                            'קריטריונים',
                                            'תאריך יצירה',
                                            'מדריך',
                                            'תפקיד מדריך',
                                            'טקסט פקודה',
                                            'סטטוס פקודה',
                                            'תיקייה',
                                            'תרחיש',
                                            'יישוב',
                                            'מספר נוכחים',
                                          ];
                                          await FeedbackExportService.exportWithSchema(
                                            keys: keys,
                                            headers: headers,
                                            feedbacks: [feedback],
                                            fileNamePrefix: 'feedback_single',
                                          );
                                        }

                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('הקובץ נוצר בהצלחה!'),
                                            backgroundColor: Colors.green,
                                            duration: Duration(seconds: 3),
                                          ),
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text('שגיאה בייצוא: $e'),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(
                                              seconds: 5,
                                            ),
                                          ),
                                        );
                                      }
                                    } else {
                                      // STANDARD feedback export
                                      try {
                                        await FeedbackExportService.exportSingleFeedbackDetails(
                                          feedback: feedback,
                                          fileNamePrefix:
                                              'משוב_${feedback.name}',
                                        );

                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('הקובץ נוצר בהצלחה!'),
                                            backgroundColor: Colors.green,
                                            duration: Duration(seconds: 3),
                                          ),
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text('שגיאה בייצוא: $e'),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(
                                              seconds: 5,
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isExporting = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.green,
                          ),
                          icon: _isExporting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: Text(
                            _isExporting ? 'מייצא...' : 'ייצוא לקובץ מקומי',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// helper removed: statuses are not editable in UI (read-only for admin)

/* ================== STUBS ================== */

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  String selectedRoleFilter = 'כל התפקידים';
  String selectedInstructor = 'כל המדריכים';
  String selectedExercise = 'כל התרגילים';
  String selectedSettlement = 'כל היישובים'; // חדש!
  String selectedFolder = 'כל התיקיות'; // חדש!
  DateTime? dateFrom;
  DateTime? dateTo;

  List<FeedbackModel> getFiltered() {
    final isAdmin = currentUser?.role == 'Admin';
    final currentUid = currentUser?.uid ?? '';
    return feedbackStorage.where((f) {
      // instructor permission: non-admins (instructors) see feedback they created OR where they're listed as additional instructor
      if (!isAdmin) {
        if (currentUser == null) return false;
        final isCreator = f.instructorName == (currentUser?.name ?? '');
        final isAdditionalInstructor = f.instructors.contains(currentUid);
        if (!isCreator && !isAdditionalInstructor) {
          return false;
        }
      }

      if (selectedRoleFilter != 'כל התפקידים' && f.role != selectedRoleFilter) {
        return false;
      }
      if (selectedInstructor != 'כל המדריכים' &&
          f.instructorName != selectedInstructor) {
        return false;
      }
      if (selectedExercise != 'כל התרגילים' && f.exercise != selectedExercise) {
        return false;
      }
      if (selectedSettlement != 'כל היישובים' &&
          f.settlement != selectedSettlement) {
        return false;
      }
      if (selectedFolder != 'כל התיקיות' && f.folder != selectedFolder) {
        return false;
      }
      if (dateFrom != null && f.createdAt.isBefore(dateFrom!)) return false;
      if (dateTo != null && f.createdAt.isAfter(dateTo!)) return false;
      return true;
    }).toList();
  }

  Future<void> pickFrom(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateFrom ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateFrom = r);
  }

  Future<void> pickTo(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateTo ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateTo = r);
  }

  double avgOf(List<int> vals) {
    if (vals.isEmpty) return 0.0;
    final sum = vals.reduce((a, b) => a + b);
    return sum / vals.length;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סטטיסטיקה'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Button for General Statistics
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/general_statistics');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  child: const Text('סטטיסטיקת משובים'),
                ),
              ),
              const SizedBox(height: 32),
              // Button for Range Statistics
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/range_statistics');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  child: const Text('סטטיסטיקה מטווחים'),
                ),
              ),
              const SizedBox(height: 32),
              // Button for Surprise Drills Statistics
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamed('/surprise_drills_statistics');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  child: const Text('סטטיסטיקה תרגילי הפתעה'),
                ),
              ),
              const SizedBox(height: 32),
              // Button for Brigade 474 Final Statistics
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/brigade_474_statistics');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  child: const Text('סטטיסטיקת הגמר חטיבה 474'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GeneralStatisticsPage extends StatefulWidget {
  const GeneralStatisticsPage({super.key});

  @override
  State<GeneralStatisticsPage> createState() => _GeneralStatisticsPageState();
}

class _GeneralStatisticsPageState extends State<GeneralStatisticsPage> {
  // topic display names (Hebrew)
  static const Map<String, String> topicMap = {
    'פוש': 'פוש',
    'הכרזה': 'הכרזה',
    'הפצה': 'הפצה',
    'מיקום המפקד': 'מיקום המפקד',
    'מיקום הכוח': 'מיקום הכוח',
    'חיילות פרט': 'חיילות פרט',
    'מקצועיות המחלקה': 'מקצועיות המחלקה',
    'הבנת האירוע': 'הבנת האירוע',
    'תפקוד באירוע': 'תפקוד באירוע',
  };

  // roles available for filtering (Hebrew)
  static const List<String> availableRoles = [
    'כל התפקידים',
    'רבש"ץ',
    'סגן רבש"ץ',
    'מפקד מחלקה',
    'סגן מפקד מחלקה',
    'לוחם',
  ];

  String selectedRoleFilter = 'כל התפקידים';
  String selectedInstructor = 'כל המדריכים';
  String selectedExercise = 'כל התרגילים';
  String selectedSettlement = 'כל היישובים'; // חדש!
  String selectedFolder = 'הכל'; // Default for משובים section
  String personFilter = '';
  DateTime? dateFrom;
  DateTime? dateTo;

  List<FeedbackModel> getFiltered() {
    final isAdmin = currentUser?.role == 'Admin';
    return feedbackStorage.where((f) {
      // instructor permission: non-admins (instructors) see feedback they created OR where they're listed as additional instructor
      if (!isAdmin) {
        if (currentUser == null) return false;
        final isCreator = f.instructorName == (currentUser?.name ?? '');
        final isAdditionalInstructor = f.instructors.contains(
          currentUser?.name ?? '',
        );
        if (!isCreator && !isAdditionalInstructor) {
          return false;
        }
      }

      if (selectedRoleFilter != 'כל התפקידים' && f.role != selectedRoleFilter) {
        return false;
      }
      if (selectedInstructor != 'כל המדריכים' &&
          f.instructorName != selectedInstructor) {
        return false;
      }
      if (selectedExercise != 'כל התרגילים' && f.exercise != selectedExercise) {
        return false;
      }
      if (selectedSettlement != 'כל היישובים' &&
          f.settlement != selectedSettlement) {
        return false;
      }
      // Enforce משובים scope: only allow these two folders
      const allowedFolders = ['משובים – כללי', 'מחלקות ההגנה – חטיבה 474'];
      if (!allowedFolders.contains(f.folder)) {
        return false;
      }
      // Apply specific folder filter if not 'הכל'
      if (selectedFolder != 'הכל' && f.folder != selectedFolder) {
        return false;
      }
      if (personFilter.isNotEmpty && !f.name.contains(personFilter)) {
        return false;
      }
      if (dateFrom != null && f.createdAt.isBefore(dateFrom!)) return false;
      if (dateTo != null && f.createdAt.isAfter(dateTo!)) return false;
      return true;
    }).toList();
  }

  Future<void> pickFrom(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateFrom ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateFrom = r);
  }

  Future<void> pickTo(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateTo ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateTo = r);
  }

  double avgOf(List<int> vals) {
    if (vals.isEmpty) return 0.0;
    final sum = vals.reduce((a, b) => a + b);
    return sum / vals.length;
  }

  void _clearFilters() {
    setState(() {
      selectedRoleFilter = 'כל התפקידים';
      selectedInstructor = 'כל המדריכים';
      selectedExercise = 'כל התרגילים';
      selectedSettlement = 'כל היישובים';
      selectedFolder = 'הכל';
      personFilter = '';
      dateFrom = null;
      dateTo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = getFiltered();
    final total = filtered.length;

    final isAdmin = currentUser?.role == 'Admin';

    // topic aggregates
    final Map<String, List<int>> topicValues = {
      for (final k in topicMap.keys) k: [],
    };
    // role aggregates
    final Map<String, List<int>> roleValues = {};
    // instructor aggregates
    final Map<String, List<int>> instrValues = {};

    for (final f in filtered) {
      for (final t in topicMap.keys) {
        final val = f.scores[t];
        if (val != null && val != 0) topicValues[t]!.add(val);
      }
      roleValues.putIfAbsent(f.role, () => []);
      for (final v in f.scores.values) {
        if (v != 0) {
          final list = roleValues[f.role];
          if (list == null) {
            roleValues[f.role] = [v];
          } else {
            list.add(v);
          }
        }
      }
      if (f.instructorName.isNotEmpty) {
        instrValues.putIfAbsent(f.instructorName, () => []);
        for (final v in f.scores.values) {
          if (v != 0) {
            final list = instrValues[f.instructorName];
            if (list == null) {
              instrValues[f.instructorName] = [v];
            } else {
              list.add(v);
            }
          }
        }
      }
    }

    // lists for dropdowns
    final exercises = <String>[
      'כל התרגילים',
      'מעגל פתוח',
      'מעגל פרוץ',
      'סריקות רחוב',
    ];
    final instructors = <String>{'כל המדריכים'}
      ..addAll(
        feedbackStorage.map((f) => f.instructorName).where((s) => s.isNotEmpty),
      );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סטטיסטיקת משובים'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'ייצוא',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => StatisticsExportDialog(
                    tabName: 'סטטיסטיקת משובים',
                    availableSections: const [
                      'ממוצע לפי קריטריון',
                      'ממוצע לפי תפקיד',
                      'ממוצע לפי מדריך',
                      'מגמה לאורך זמן',
                    ],
                    onExport: (selectedSections) async {
                      final sectionsData =
                          <String, List<Map<String, dynamic>>>{};

                      if (selectedSections.contains('ממוצע לפי קריטריון')) {
                        final data = <Map<String, dynamic>>[];
                        for (final entry in topicValues.entries) {
                          final vals = entry.value;
                          if (vals.isNotEmpty) {
                            data.add({
                              'קריטריון': topicMap[entry.key] ?? entry.key,
                              'ממוצע': avgOf(vals).toStringAsFixed(1),
                              'מספר הערכות': vals.length,
                            });
                          }
                        }
                        sectionsData['ממוצע לפי קריטריון'] = data;
                      }

                      if (selectedSections.contains('ממוצע לפי תפקיד')) {
                        final data = <Map<String, dynamic>>[];
                        for (final entry in roleValues.entries) {
                          final avg = avgOf(entry.value);
                          data.add({
                            'תפקיד': entry.key,
                            'ממוצע': avg.toStringAsFixed(1),
                            'מספר הערכות': entry.value.length,
                          });
                        }
                        sectionsData['ממוצע לפי תפקיד'] = data;
                      }

                      if (selectedSections.contains('ממוצע לפי מדריך')) {
                        final data = <Map<String, dynamic>>[];
                        for (final entry in instrValues.entries) {
                          final avg = avgOf(entry.value);
                          data.add({
                            'מדריך': entry.key,
                            'ממוצע': avg.toStringAsFixed(1),
                            'מספר הערכות': entry.value.length,
                          });
                        }
                        sectionsData['ממוצע לפי מדריך'] = data;
                      }

                      if (selectedSections.contains('מגמה לאורך זמן')) {
                        final Map<String, List<int>> byDate = {};
                        for (final f in filtered) {
                          final d =
                              '${f.createdAt.year}-${f.createdAt.month}-${f.createdAt.day}';
                          byDate.putIfAbsent(d, () => []);
                          for (final v in f.scores.values) {
                            if (v != 0) byDate[d]!.add(v);
                          }
                        }
                        final data = <Map<String, dynamic>>[];
                        final entries = byDate.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key));
                        for (final entry in entries) {
                          data.add({
                            'תאריך': entry.key,
                            'ממוצע': avgOf(entry.value).toStringAsFixed(1),
                            'מספר הערכות': entry.value.length,
                          });
                        }
                        sectionsData['מגמה לאורך זמן'] = data;
                      }

                      return sectionsData;
                    },
                  ),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView(
            children: [
              // Filters
              Card(
                color: Colors.blueGrey.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'סינון',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          // Role filter (admin only)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'תפקיד',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final items = availableRoles
                                        .toSet()
                                        .toList();
                                    final value =
                                        items.contains(selectedRoleFilter)
                                        ? selectedRoleFilter
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (r) => DropdownMenuItem(
                                              value: r,
                                              child: Text(r),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: isAdmin
                                          ? (v) => setState(
                                              () => selectedRoleFilter =
                                                  v ?? 'כל התפקידים',
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Instructor filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'מדריך ממשב',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final items = instructors.toSet().toList();
                                    final value =
                                        items.contains(selectedInstructor)
                                        ? selectedInstructor
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: isAdmin
                                          ? (v) => setState(
                                              () => selectedInstructor =
                                                  v ?? 'כל המדריכים',
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Exercise filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'תרגיל',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final items = exercises.toSet().toList();
                                    final value =
                                        items.contains(selectedExercise)
                                        ? selectedExercise
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                        () => selectedExercise =
                                            v ?? 'כל התרגילים',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Settlement filter (for all users)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'יישוב',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final settlements = <String>{'כל היישובים'}
                                      ..addAll(
                                        feedbackStorage
                                            .map((f) => f.settlement)
                                            .where((s) => s.isNotEmpty),
                                      );
                                    final items = settlements.toSet().toList();
                                    final value =
                                        items.contains(selectedSettlement)
                                        ? selectedSettlement
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                        () => selectedSettlement =
                                            v ?? 'כל היישובים',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Folder filter (restricted to משובים scope)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'תיקייה',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    // Restricted folder list for משובים section
                                    final folders = <String>[
                                      'הכל',
                                      'משובים – כללי',
                                      'מחלקות ההגנה – חטיבה 474',
                                    ];

                                    // Display name mapping
                                    String getDisplayName(
                                      String internalValue,
                                    ) {
                                      switch (internalValue) {
                                        case 'מחלקות ההגנה – חטיבה 474':
                                          return 'מחלקות הגנה 474';
                                        default:
                                          return internalValue;
                                      }
                                    }

                                    final items = folders;
                                    final value = items.contains(selectedFolder)
                                        ? selectedFolder
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value ?? 'הכל',
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(getDisplayName(i)),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(() {
                                        selectedFolder = v ?? 'הכל';
                                        // Do NOT auto-reset settlement - user controls it via settlement filter
                                      }),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Date range
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () => pickFrom(context),
                                child: Text(
                                  dateFrom == null
                                      ? 'מתאריך'
                                      : '${dateFrom!.toLocal()}'.split(' ')[0],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => pickTo(context),
                                child: Text(
                                  dateTo == null
                                      ? 'עד תאריך'
                                      : '${dateTo!.toLocal()}'.split(' ')[0],
                                ),
                              ),
                            ],
                          ),

                          // Clear filters button
                          ElevatedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('נקה סינונים'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Text('סה"כ משובים: $total', style: const TextStyle(fontSize: 14)),

              const SizedBox(height: 12),
              const Text(
                'ממוצע לפי קריטריון',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...topicMap.entries.map((e) {
                final key = e.key;
                final label = e.value;
                final vals = topicValues[key] ?? [];
                final a = avgOf(vals);
                final pct = (a / 5.0).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // שם הקריטריון מעל הפס
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: pct,
                                alignment: Alignment.centerRight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.orangeAccent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            vals.isEmpty ? '-' : a.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'ממוצע לפי תפקיד',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...roleValues.entries.map((e) {
                final label = e.key;
                final a = avgOf(e.value);
                final pct = (a / 5.0).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // שם התפקיד מעל הפס
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: pct,
                                alignment: Alignment.centerRight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.lightBlueAccent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            e.value.isEmpty ? '-' : a.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.lightBlueAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'ממוצע לפי מדריך',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (instrValues.isEmpty)
                const ListTile(title: Text('-'))
              else
                ...instrValues.entries.map((e) {
                  final a = avgOf(e.value);
                  return ListTile(
                    dense: true,
                    title: Text(
                      e.key,
                      style: const TextStyle(color: Colors.black87),
                    ),
                    trailing: Text(
                      a.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.greenAccent),
                    ),
                  );
                }),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'מגמה לאורך זמן (ממוצעים לפי יום)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // Simple trend: group by date and show average of all scores that day
              Builder(
                builder: (ctx) {
                  final Map<String, List<int>> byDate = {};
                  for (final f in filtered) {
                    final d =
                        '${f.createdAt.year}-${f.createdAt.month}-${f.createdAt.day}';
                    byDate.putIfAbsent(d, () => []);
                    for (final v in f.scores.values) {
                      if (v != 0) byDate[d]!.add(v);
                    }
                  }
                  final entries = byDate.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key));
                  if (entries.isEmpty) return const Text('-');
                  return Column(
                    children: entries.map((en) {
                      final dayAvg = avgOf(en.value);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                en.key,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: FractionallySizedBox(
                                  widthFactor: (dayAvg / 5.0).clamp(0.0, 1.0),
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.purpleAccent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              dayAvg.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.purpleAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 12),
              const Text('הערה', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'חישובים משתמשים בציונים 1/3/5; ממוצעים מעוגלים לאחת עשרונית.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RangeStatisticsPage extends StatefulWidget {
  const RangeStatisticsPage({super.key});

  @override
  State<RangeStatisticsPage> createState() => _RangeStatisticsPageState();
}

class _RangeStatisticsPageState extends State<RangeStatisticsPage> {
  // topic display names (Hebrew)
  static const Map<String, String> topicMap = {
    'פוש': 'פוש',
    'הכרזה': 'הכרזה',
    'הפצה': 'הפצה',
    'מיקום המפקד': 'מיקום המפקד',
    'מיקום הכוח': 'מיקום הכוח',
    'חיילות פרט': 'חיילות פרט',
    'מקצועיות המחלקה': 'מקצועיות המחלקה',
    'הבנת האירוע': 'הבנת האירוע',
    'תפקוד באירוע': 'תפקוד באירוע',
  };

  String selectedInstructor = 'כל המדריכים';
  String selectedSettlement = 'כל היישובים';
  String selectedStation = 'כל המקצים';
  String selectedFolder = 'הכל'; // Range folder filter
  String selectedRangeType = 'הכל'; // Range type filter
  DateTime? dateFrom;
  DateTime? dateTo;

  // Range-specific data
  Map<String, Map<String, dynamic>> rangeData = {};

  @override
  void initState() {
    super.initState();
    _loadRangeData();
  }

  Future<void> _loadRangeData() async {
    try {
      final filtered = getFiltered();
      for (final f in filtered) {
        if (f.id != null && f.id!.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('feedbacks')
              .doc(f.id)
              .get();
          if (doc.exists) {
            final data = doc.data();
            if (data != null) {
              rangeData[f.id!] = data;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading range data: $e');
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _clearFilters() {
    setState(() {
      selectedInstructor = 'כל המדריכים';
      selectedSettlement = 'כל היישובים';
      selectedStation = 'כל המקצים';
      selectedFolder = 'הכל';
      selectedRangeType = 'הכל';
      dateFrom = null;
      dateTo = null;
    });
  }

  List<FeedbackModel> getFiltered() {
    final isAdmin = currentUser?.role == 'Admin';
    final currentUid = currentUser?.uid ?? '';
    return feedbackStorage.where((f) {
      // Enforce range scope: only allow מטווחי ירי and מטווחים 474
      const allowedFolders = ['מטווחי ירי', 'מטווחים 474'];
      if (!allowedFolders.contains(f.folder)) return false;

      // Apply specific folder filter if not 'הכל'
      if (selectedFolder != 'הכל' && f.folder != selectedFolder) {
        return false;
      }

      // Apply range type filter
      if (selectedRangeType != 'הכל') {
        final feedbackType = f.type;
        final rangeSubType = f.rangeSubType;
        final isLongRange =
            feedbackType == 'range_long' ||
            feedbackType == 'דווח רחוק' ||
            rangeSubType == 'טווח רחוק';
        final isShortRange =
            !isLongRange &&
            (feedbackType == 'range_short' ||
                feedbackType == 'דווח קצר' ||
                rangeSubType == 'טווח קצר' ||
                f.folder == 'מטווחי ירי' ||
                f.folder == 'מטווחים 474');

        if (selectedRangeType == 'טווח קצר' && !isShortRange) {
          return false;
        }
        if (selectedRangeType == 'טווח רחוק' && !isLongRange) {
          return false;
        }
      }

      // instructor permission: non-admins (instructors) see feedback they created OR where they're listed as additional instructor
      if (!isAdmin) {
        if (currentUser == null) return false;
        final isCreator = f.instructorName == (currentUser?.name ?? '');
        // ✅ HYBRID CHECK: instructors array by UID OR name (backward compatible)
        final isAdditionalInstructor =
            f.instructors.contains(currentUid) ||
            f.instructors.contains(currentUser?.name ?? '');
        if (!isCreator && !isAdditionalInstructor) {
          return false;
        }
      }

      if (selectedInstructor != 'כל המדריכים' &&
          f.instructorName != selectedInstructor) {
        return false;
      }
      if (selectedSettlement != 'כל היישובים' &&
          f.settlement != selectedSettlement) {
        return false;
      }
      if (selectedStation != 'כל המקצים') {
        // Check if selected station exists in this feedback's stations
        if (!rangeData.containsKey(f.id)) return false;
        final data = rangeData[f.id];
        final stations =
            (data?['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final hasSelectedStation = stations.any(
          (station) => station['name'] == selectedStation,
        );
        if (!hasSelectedStation) return false;
      }
      if (dateFrom != null && f.createdAt.isBefore(dateFrom!)) return false;
      if (dateTo != null && f.createdAt.isAfter(dateTo!)) return false;

      return true;
    }).toList();
  }

  Future<void> pickFrom(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateFrom ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateFrom = r);
  }

  Future<void> pickTo(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateTo ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateTo = r);
  }

  double avgOf(List<int> vals) {
    if (vals.isEmpty) return 0.0;
    final sum = vals.reduce((a, b) => a + b);
    return sum / vals.length;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = getFiltered();
    final total = filtered.length;

    final isAdmin = currentUser?.role == 'Admin';

    // topic aggregates
    final Map<String, List<int>> topicValues = {
      for (final k in topicMap.keys) k: [],
    };
    for (final f in filtered) {
      for (final t in topicMap.keys) {
        final val = f.scores[t];
        if (val != null && val != 0) topicValues[t]!.add(val);
      }
    }

    // department aggregates (based on settlement) - total hits and bullets
    final Map<String, int> totalHitsPerSettlement = {};
    final Map<String, int> totalBulletsPerSettlement = {};
    final Map<String, bool> isLongRangePerSettlement = {}; // ✅ Track range type
    for (final f in filtered) {
      if (f.settlement.isNotEmpty && rangeData.containsKey(f.id)) {
        final data = rangeData[f.id];
        final stations =
            (data?['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final trainees =
            (data?['trainees'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        // ✅ Detect if this is LONG RANGE
        final feedbackType = (data?['feedbackType'] as String?) ?? '';
        final rangeSubType = (data?['rangeSubType'] as String?) ?? '';
        final isLongRange =
            feedbackType == 'range_long' ||
            feedbackType == 'דווח רחוק' ||
            rangeSubType == 'טווח רחוק';
        isLongRangePerSettlement[f.settlement] = isLongRange;

        int feedbackTotalBullets = 0;
        for (final station in stations) {
          if (isLongRange) {
            // ✅ LONG RANGE: Use maxPoints instead of bulletsCount
            feedbackTotalBullets +=
                ((station['maxPoints'] as num?)?.toInt() ?? 0) *
                trainees.length;
          } else {
            // ✅ SHORT RANGE: Keep using bulletsCount (unchanged)
            feedbackTotalBullets +=
                ((station['bulletsCount'] as num?)?.toInt() ?? 0) *
                trainees.length;
          }
        }
        totalBulletsPerSettlement[f.settlement] =
            (totalBulletsPerSettlement[f.settlement] ?? 0) +
            feedbackTotalBullets;

        int totalHits = 0;
        for (final trainee in trainees) {
          totalHits += (trainee['totalHits'] as num?)?.toInt() ?? 0;
        }
        totalHitsPerSettlement[f.settlement] =
            (totalHitsPerSettlement[f.settlement] ?? 0) + totalHits;
      }
    }

    // lists for dropdowns
    final instructors = <String>{'כל המדריכים'}
      ..addAll(
        feedbackStorage.map((f) => f.instructorName).where((s) => s.isNotEmpty),
      );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סטטיסטיקה מטווחים'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'ייצוא',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => StatisticsExportDialog(
                    tabName: 'סטטיסטיקה מטווחים',
                    availableSections: const [
                      'ממוצע לפי יישוב',
                      'ממוצע לפי מקצה',
                      'מגמה לאורך זמן',
                    ],
                    onExport: (selectedSections) async {
                      final sectionsData =
                          <String, List<Map<String, dynamic>>>{};

                      if (selectedSections.contains('ממוצע לפי יישוב')) {
                        final data = <Map<String, dynamic>>[];
                        for (final entry in totalHitsPerSettlement.entries) {
                          final totalHits = entry.value;
                          final totalBullets =
                              totalBulletsPerSettlement[entry.key] ?? 0;
                          final percentage = totalBullets > 0
                              ? ((totalHits / totalBullets) * 100)
                                    .toStringAsFixed(1)
                              : '0.0';
                          data.add({
                            'יישוב': entry.key,
                            'פגיעות': totalHits,
                            'כדורים': totalBullets,
                            'אחוז': '$percentage%',
                          });
                        }
                        sectionsData['ממוצע לפי יישוב'] = data;
                      }

                      if (selectedSections.contains('ממוצע לפי מקצה')) {
                        final Map<String, int> totalHitsPerStation = {};
                        final Map<String, int> totalBulletsPerStation = {};
                        for (final f in filtered) {
                          if (rangeData.containsKey(f.id)) {
                            final data = rangeData[f.id];
                            final stations =
                                (data?['stations'] as List?)
                                    ?.cast<Map<String, dynamic>>() ??
                                [];
                            final trainees =
                                (data?['trainees'] as List?)
                                    ?.cast<Map<String, dynamic>>() ??
                                [];
                            for (var i = 0; i < stations.length; i++) {
                              final station = stations[i];
                              final stationName =
                                  station['name'] ?? 'מקצה ${i + 1}';
                              final bulletsPerTrainee =
                                  (station['bulletsCount'] as num?)?.toInt() ??
                                  0;
                              final totalBulletsForStation =
                                  trainees.length * bulletsPerTrainee;
                              totalBulletsPerStation[stationName] =
                                  (totalBulletsPerStation[stationName] ?? 0) +
                                  totalBulletsForStation;

                              int stationHits = 0;
                              for (final trainee in trainees) {
                                final hits =
                                    trainee['hits'] as Map<String, dynamic>?;
                                if (hits != null) {
                                  stationHits +=
                                      (hits['station_$i'] as num?)?.toInt() ??
                                      0;
                                }
                              }
                              totalHitsPerStation[stationName] =
                                  (totalHitsPerStation[stationName] ?? 0) +
                                  stationHits;
                            }
                          }
                        }
                        final data = <Map<String, dynamic>>[];
                        for (final entry in totalHitsPerStation.entries) {
                          final totalHits = entry.value;
                          final totalBullets =
                              totalBulletsPerStation[entry.key] ?? 0;
                          final percentage = totalBullets > 0
                              ? ((totalHits / totalBullets) * 100)
                                    .toStringAsFixed(1)
                              : '0.0';
                          data.add({
                            'מקצה': entry.key,
                            'פגיעות': totalHits,
                            'כדורים': totalBullets,
                            'אחוז': '$percentage%',
                          });
                        }
                        sectionsData['ממוצע לפי מקצה'] = data;
                      }

                      if (selectedSections.contains('מגמה לאורך זמן')) {
                        final Map<String, List<int>> byDate = {};
                        for (final f in filtered) {
                          final d =
                              '${f.createdAt.year}-${f.createdAt.month}-${f.createdAt.day}';
                          byDate.putIfAbsent(d, () => []);
                          for (final v in f.scores.values) {
                            if (v != 0) byDate[d]!.add(v);
                          }
                        }
                        final data = <Map<String, dynamic>>[];
                        final entries = byDate.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key));
                        for (final entry in entries) {
                          data.add({
                            'תאריך': entry.key,
                            'ממוצע': avgOf(entry.value).toStringAsFixed(1),
                            'מספר הערכות': entry.value.length,
                          });
                        }
                        sectionsData['מגמה לאורך זמן'] = data;
                      }

                      return sectionsData;
                    },
                  ),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView(
            children: [
              // Filters
              Card(
                color: Colors.blueGrey.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'סינון',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          // Folder filter (restricted to range folders)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'תיקייה',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final folders = <String>[
                                      'הכל',
                                      'מטווחי ירי',
                                      'מטווחים 474',
                                    ];
                                    final items = folders;
                                    final value = items.contains(selectedFolder)
                                        ? selectedFolder
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value ?? 'הכל',
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(() {
                                        selectedFolder = v ?? 'הכל';
                                      }),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Range type filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'סוג מטווח',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final rangeTypes = <String>[
                                      'הכל',
                                      'טווח קצר',
                                      'טווח רחוק',
                                    ];
                                    final items = rangeTypes;
                                    final value =
                                        items.contains(selectedRangeType)
                                        ? selectedRangeType
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value ?? 'הכל',
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(() {
                                        selectedRangeType = v ?? 'הכל';
                                      }),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Instructor filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'מדריך ממשב',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final items = instructors.toSet().toList();
                                    final value =
                                        items.contains(selectedInstructor)
                                        ? selectedInstructor
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: isAdmin
                                          ? (v) => setState(
                                              () => selectedInstructor =
                                                  v ?? 'כל המדריכים',
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Settlement filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'יישוב',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final settlements = <String>{'כל היישובים'}
                                      ..addAll(
                                        feedbackStorage
                                            .map((f) => f.settlement)
                                            .where((s) => s.isNotEmpty),
                                      );
                                    final items = settlements.toSet().toList();
                                    final value =
                                        items.contains(selectedSettlement)
                                        ? selectedSettlement
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                        () => selectedSettlement =
                                            v ?? 'כל היישובים',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Station filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'מקצה',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    // Build station list dynamically from range data
                                    final Set<String> stationNames = {};
                                    final List<String> orderedStations = [];

                                    // Collect station names from all range feedbacks in order
                                    for (final f in filtered) {
                                      if (rangeData.containsKey(f.id)) {
                                        final data = rangeData[f.id];
                                        final stations =
                                            (data?['stations'] as List?)
                                                ?.cast<
                                                  Map<String, dynamic>
                                                >() ??
                                            [];
                                        for (final station in stations) {
                                          final stationName =
                                              station['name'] as String? ?? '';
                                          if (stationName.isNotEmpty &&
                                              !stationNames.contains(
                                                stationName,
                                              )) {
                                            stationNames.add(stationName);
                                            orderedStations.add(stationName);
                                          }
                                        }
                                      }
                                    }

                                    final items =
                                        ['כל המקצים'] + orderedStations;
                                    final value =
                                        items.contains(selectedStation)
                                        ? selectedStation
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                        () =>
                                            selectedStation = v ?? 'כל המקצים',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Date range
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () => pickFrom(context),
                                child: Text(
                                  dateFrom == null
                                      ? 'מתאריך'
                                      : '${dateFrom!.toLocal()}'.split(' ')[0],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => pickTo(context),
                                child: Text(
                                  dateTo == null
                                      ? 'עד תאריך'
                                      : '${dateTo!.toLocal()}'.split(' ')[0],
                                ),
                              ),
                            ],
                          ),

                          // Clear filters button
                          ElevatedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('נקה סינונים'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Text('סה"כ משובים: $total', style: const TextStyle(fontSize: 14)),

              const SizedBox(height: 12),
              const Text(
                'ממוצע לפי יישוב',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              ...totalHitsPerSettlement.entries.map((e) {
                final label = e.key;
                final totalHits = e.value;
                final totalBullets = totalBulletsPerSettlement[e.key] ?? 0;
                final percentage = totalBullets > 0
                    ? ((totalHits / totalBullets) * 100).toStringAsFixed(1)
                    : '0.0';
                final pct = totalBullets > 0
                    ? (totalHits / totalBullets).clamp(0.0, 1.0)
                    : 0.0;
                // ✅ Check if this settlement is LONG RANGE
                final isLongRange = isLongRangePerSettlement[label] ?? false;
                final unitLabel = isLongRange ? 'נקודות' : 'כדורים';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // שם היישוב מעל הפס
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: pct,
                                alignment: Alignment.centerRight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$totalHits מתוך $totalBullets $unitLabel ($percentage%)',
                            style: const TextStyle(
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'ממוצע לפי מקצה',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              // New graph for station totals
              Builder(
                builder: (ctx) {
                  final Map<String, int> totalHitsPerStation = {};
                  final Map<String, int> totalBulletsPerStation = {};
                  final Map<String, bool> isLongRangePerStation =
                      {}; // ✅ Track range type
                  for (final f in filtered) {
                    if (rangeData.containsKey(f.id)) {
                      final data = rangeData[f.id];
                      final stations =
                          (data?['stations'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          [];
                      final trainees =
                          (data?['trainees'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          [];

                      // ✅ Detect if this is LONG RANGE
                      final feedbackType =
                          (data?['feedbackType'] as String?) ?? '';
                      final rangeSubType =
                          (data?['rangeSubType'] as String?) ?? '';
                      final isLongRange =
                          feedbackType == 'range_long' ||
                          feedbackType == 'דווח רחוק' ||
                          rangeSubType == 'טווח רחוק';

                      for (var i = 0; i < stations.length; i++) {
                        final station = stations[i];
                        final stationName = station['name'] ?? 'מקצה ${i + 1}';
                        isLongRangePerStation[stationName] =
                            isLongRange; // ✅ Store type

                        final stationMaxValue = isLongRange
                            ? (station['maxPoints'] as num?)?.toInt() ??
                                  0 // ✅ LONG: points
                            : (station['bulletsCount'] as num?)?.toInt() ??
                                  0; // ✅ SHORT: bullets
                        final totalBulletsForStation =
                            trainees.length * stationMaxValue;
                        totalBulletsPerStation[stationName] =
                            (totalBulletsPerStation[stationName] ?? 0) +
                            totalBulletsForStation;

                        int stationHits = 0;
                        for (final trainee in trainees) {
                          final hits = trainee['hits'] as Map<String, dynamic>?;
                          if (hits != null) {
                            stationHits +=
                                (hits['station_$i'] as num?)?.toInt() ?? 0;
                          }
                        }
                        totalHitsPerStation[stationName] =
                            (totalHitsPerStation[stationName] ?? 0) +
                            stationHits;
                      }
                    }
                  }
                  final entries = totalHitsPerStation.entries.toList();
                  if (entries.isEmpty) return const Text('-');
                  return Column(
                    children: entries.map((en) {
                      final stationName = en.key;
                      final totalHits = en.value;
                      final totalBullets =
                          totalBulletsPerStation[stationName] ?? 0;
                      final percentage = totalBullets > 0
                          ? ((totalHits / totalBullets) * 100).toStringAsFixed(
                              1,
                            )
                          : '0.0';
                      final pct = totalBullets > 0
                          ? (totalHits / totalBullets).clamp(0.0, 1.0)
                          : 0.0;
                      // ✅ Check if this station is LONG RANGE
                      final isLongRange =
                          isLongRangePerStation[stationName] ?? false;
                      final unitLabel = isLongRange ? 'נקודות' : 'כדורים';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stationName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: FractionallySizedBox(
                                      widthFactor: pct,
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '$totalHits מתוך $totalBullets $unitLabel ($percentage%)',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'מגמה לאורך זמן (ממוצעים לפי יום)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // Simple trend: group by date and show average of all scores that day
              Builder(
                builder: (ctx) {
                  final Map<String, List<int>> byDate = {};
                  for (final f in filtered) {
                    final d =
                        '${f.createdAt.year}-${f.createdAt.month}-${f.createdAt.day}';
                    byDate.putIfAbsent(d, () => []);
                    for (final v in f.scores.values) {
                      if (v != 0) byDate[d]!.add(v);
                    }
                  }
                  final entries = byDate.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key));
                  if (entries.isEmpty) return const Text('-');
                  return Column(
                    children: entries.map((en) {
                      final dayAvg = avgOf(en.value);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                en.key,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: FractionallySizedBox(
                                  widthFactor: (dayAvg / 5.0).clamp(0.0, 1.0),
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.purpleAccent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              dayAvg.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.purpleAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Brigade474StatisticsPage extends StatefulWidget {
  const Brigade474StatisticsPage({super.key});

  @override
  State<Brigade474StatisticsPage> createState() =>
      _Brigade474StatisticsPageState();
}

class _Brigade474StatisticsPageState extends State<Brigade474StatisticsPage> {
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isRefreshing = false;
  int totalTrainees = 0;
  int totalBulletsFired = 0;
  int totalPointsScored = 0; // For long range
  int totalMaxPoints = 0; // For long range
  int totalFeedbacks = 0;
  int totalMeshuvim = 0; // מחלקות ההגנה 474 only
  int totalImunim = 0; // מטווחים 474 + תרגילי הפתעה 474 + סיכום אימון 474
  Map<String, int> feedbacksByType = {};
  Set<String> uniqueSettlements = {};
  // Per-settlement data: settlement -> {trainingType -> {count: int, trainees: Set<String>}}
  Map<String, Map<String, Map<String, dynamic>>> settlementData = {};
  // Per-instructor data: instructorName -> {typeKey -> count}
  Map<String, Map<String, int>> instructorData = {};

  /// Helper: Convert internal type key to display name
  String _getTypeDisplayName(String typeKey) {
    switch (typeKey) {
      case 'מחלקות ההגנה – חטיבה 474':
        return 'מחלקות הגנה 474';
      case 'משוב תרגילי הפתעה':
        return 'תרגילי הפתעה 474';
      case 'משוב סיכום אימון 474':
        return 'סיכום אימון 474';
      default:
        return typeKey;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBrigadeData();
  }

  Future<void> _loadBrigadeData() async {
    setState(() => _isLoading = true);

    // ✅ RESET all counters and maps before loading to prevent duplicates
    totalFeedbacks = 0;
    totalMeshuvim = 0;
    totalImunim = 0;
    totalTrainees = 0;
    totalBulletsFired = 0;
    totalPointsScored = 0;
    totalMaxPoints = 0;
    feedbacksByType = {};
    uniqueSettlements = {};
    settlementData = {};
    instructorData = {};

    try {
      // Filter all feedbacks from Brigade 474 folders (FINAL feedbacks only, exclude drafts)
      final brigadeFeeds = feedbackStorage.where((f) {
        // ❌ EXCLUDE temporary/draft feedbacks
        if (f.isTemporary == true) return false;

        // ❌ EXCLUDE general folders (not 474)
        if (f.folder == 'תרגילי הפתעה כללי' ||
            f.folder == 'סיכום אימון כללי' ||
            f.folder == 'משובים – כללי' ||
            f.folder == 'מטווחי ירי' ||
            f.folderKey == 'surprise_drills_general' ||
            f.folderKey == 'training_summary_general' ||
            f.folderKey == 'shooting_ranges') {
          return false;
        }

        // ✅ INCLUDE only 474 specific folders
        return f.folder == 'מטווחים 474' ||
            f.folder == '474 Ranges' ||
            f.folder == 'מחלקות ההגנה – חטיבה 474' ||
            f.folder == 'משוב תרגילי הפתעה' ||
            f.folder == 'משוב סיכום אימון 474' ||
            f.folderKey == 'ranges_474' ||
            f.folderKey == 'training_summary_474';
      }).toList();

      totalFeedbacks = brigadeFeeds.length;
      final Set<String> uniqueTraineesSet = {};
      // Track trainees per type for average calculation
      final Map<String, Set<String>> traineesPerType = {};

      for (final f in brigadeFeeds) {
        // Count by type
        String typeKey = f.folder;
        if (f.folderKey == 'ranges_474' || f.folder == '474 Ranges') {
          typeKey = 'מטווחים 474';
        }
        // Normalize training summary to consistent key
        if (f.module == 'training_summary' ||
            f.folder == 'משוב סיכום אימון 474') {
          typeKey = 'משוב סיכום אימון 474';
        }
        feedbacksByType[typeKey] = (feedbacksByType[typeKey] ?? 0) + 1;
        traineesPerType.putIfAbsent(typeKey, () => {});

        // Count separately: משובים (defense) vs אימונים (ranges, drills, summaries)
        if (typeKey == 'מחלקות ההגנה – חטיבה 474') {
          totalMeshuvim++;
        } else {
          totalImunim++;
        }

        // Collect instructor data
        final instructorName = f.instructorName;
        if (instructorName.isNotEmpty) {
          instructorData.putIfAbsent(instructorName, () => {});
          instructorData[instructorName]![typeKey] =
              (instructorData[instructorName]![typeKey] ?? 0) + 1;
        }

        // Collect settlements (skip defense platoons - they use personal names)
        final isDefensePlatoons = f.folder == 'מחלקות ההגנה – חטיבה 474';
        if (f.settlement.isNotEmpty && !isDefensePlatoons) {
          uniqueSettlements.add(f.settlement);
        }

        // Initialize settlement data structure
        if (f.settlement.isNotEmpty && !isDefensePlatoons) {
          settlementData.putIfAbsent(f.settlement, () => {});
          settlementData[f.settlement]!.putIfAbsent(
            typeKey,
            () => {'count': 0, 'trainees': <String>{}},
          );

          // ✅ INCREMENT COUNT ONCE - at the start of loop for this feedback
          settlementData[f.settlement]![typeKey]!['count'] =
              (settlementData[f.settlement]![typeKey]!['count'] as int) + 1;
        }

        // ✅ SINGLE Firestore read per feedback - load all data at once
        if (f.id != null && f.id!.isNotEmpty) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('feedbacks')
                .doc(f.id)
                .get()
                .timeout(const Duration(seconds: 8));

            if (doc.exists) {
              final data = doc.data()!;

              // 1. Add additional instructors (for all feedback types)
              final additionalInstructors =
                  (data['instructors'] as List?)?.cast<String>() ?? [];
              for (final additionalInstructor in additionalInstructors) {
                if (additionalInstructor.isNotEmpty &&
                    additionalInstructor != instructorName) {
                  instructorData.putIfAbsent(additionalInstructor, () => {});
                  instructorData[additionalInstructor]![typeKey] =
                      (instructorData[additionalInstructor]![typeKey] ?? 0) + 1;
                }
              }

              // 2. Process based on feedback type
              final isRanges474 =
                  f.folder == 'מטווחים 474' ||
                  f.folder == '474 Ranges' ||
                  f.folderKey == 'ranges_474';
              final isTrainingSummary =
                  f.folder == 'משוב סיכום אימון 474' ||
                  f.module == 'training_summary';
              final isSurpriseDrill =
                  f.folder == 'משוב תרגילי הפתעה' ||
                  f.module == 'surprise_drill';

              // 2a. מטווחים 474 - load trainees from trainees array
              if (isRanges474) {
                final stations =
                    (data['stations'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];
                final trainees =
                    (data['trainees'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];

                // Add trainee names
                for (final t in trainees) {
                  final name = t['name'] as String? ?? '';
                  if (name.isNotEmpty) {
                    uniqueTraineesSet.add(name);
                    traineesPerType[typeKey]!.add(name);
                    if (f.settlement.isNotEmpty && !isDefensePlatoons) {
                      (settlementData[f.settlement]![typeKey]!['trainees']
                              as Set<String>)
                          .add(name);
                    }
                  }
                }

                // Detect long range
                final feedbackType = (data['feedbackType'] as String?) ?? '';
                final rangeSubType = (data['rangeSubType'] as String?) ?? '';
                final isLongRange =
                    feedbackType == 'range_long' ||
                    feedbackType == 'דווח רחוק' ||
                    rangeSubType == 'טווח רחוק';

                // Sum bullets fired
                for (final station in stations) {
                  final bullets =
                      (station['bulletsCount'] as num?)?.toInt() ?? 0;
                  totalBulletsFired += bullets * trainees.length;

                  if (isLongRange) {
                    final maxPoints =
                        (station['maxPoints'] as num?)?.toInt() ?? 0;
                    totalMaxPoints += maxPoints * trainees.length;
                  }
                }

                // Sum points scored (for long range)
                if (isLongRange) {
                  for (final trainee in trainees) {
                    totalPointsScored +=
                        (trainee['totalHits'] as num?)?.toInt() ?? 0;
                  }
                }
              }

              // 2b. סיכום אימון - load attendees
              if (isTrainingSummary) {
                final attendees =
                    (data['attendees'] as List?)?.cast<String>() ?? [];

                for (final name in attendees) {
                  if (name.isNotEmpty) {
                    uniqueTraineesSet.add(name);
                    traineesPerType[typeKey]!.add(name);
                    if (f.settlement.isNotEmpty && !isDefensePlatoons) {
                      (settlementData[f.settlement]![typeKey]!['trainees']
                              as Set<String>)
                          .add(name);
                    }
                  }
                }
              }

              // 2c. תרגילי הפתעה - load trainees
              if (isSurpriseDrill) {
                final trainees =
                    (data['trainees'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];

                for (final t in trainees) {
                  final name = t['name'] as String? ?? '';
                  if (name.isNotEmpty) {
                    uniqueTraineesSet.add(name);
                    traineesPerType[typeKey]!.add(name);
                    if (f.settlement.isNotEmpty && !isDefensePlatoons) {
                      (settlementData[f.settlement]![typeKey]!['trainees']
                              as Set<String>)
                          .add(name);
                    }
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Error loading feedback data for ${f.id}: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          totalTrainees = uniqueTraineesSet.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading brigade data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      // Reload feedbacks from Firestore
      final isAdmin = currentUser?.role == 'Admin';
      await loadFeedbacksForCurrentUser(isAdmin: isAdmin);

      // Reload brigade data
      await _loadBrigadeData();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('הנתונים עודכנו')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה ברענון: $e')));
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _exportStatistics() async {
    setState(() => _isExporting = true);

    try {
      final sectionsData = <String, List<Map<String, dynamic>>>{};

      // Section 1: סיכום כללי
      sectionsData['סיכום כללי'] = [
        {'מדד': 'סה"כ חניכים', 'ערך': totalTrainees},
        {'מדד': 'סה"כ כדורים שנורו', 'ערך': totalBulletsFired},
        {'מדד': 'סה"כ משובים (מחלקות הגנה)', 'ערך': totalMeshuvim},
        {'מדד': 'סה"כ אימונים', 'ערך': totalImunim},
        {'מדד': 'סה"כ יישובים', 'ערך': uniqueSettlements.length},
      ];

      // Section 2: פילוח לפי סוג אימון
      final typeBreakdown = <Map<String, dynamic>>[];
      for (final entry in feedbacksByType.entries) {
        final type = entry.key;
        final count = entry.value;
        final percentage = totalFeedbacks > 0
            ? ((count / totalFeedbacks) * 100).toStringAsFixed(1)
            : '0.0';

        // Calculate average trainees (except for defense platoons)
        final isDefensePlatoons = type == 'מחלקות ההגנה – חטיבה 474';
        int totalTraineesForType = 0;
        if (!isDefensePlatoons) {
          for (final settlementEntry in settlementData.entries) {
            final settlementTypes = settlementEntry.value;
            if (settlementTypes.containsKey(type)) {
              final trainees =
                  settlementTypes[type]!['trainees'] as Set<String>? ?? {};
              totalTraineesForType += trainees.length;
            }
          }
        }
        final avgTrainees = !isDefensePlatoons && count > 0
            ? (totalTraineesForType / count).toStringAsFixed(2)
            : 'לא רלוונטי';

        typeBreakdown.add({
          'סוג אימון': type,
          'מספר אימונים': count,
          'אחוז': '$percentage%',
          'ממוצע חניכים באימון': avgTrainees,
        });
      }
      sectionsData['פילוח לפי סוג אימון'] = typeBreakdown;

      // Section 3: פילוח לפי יישוב
      final settlementBreakdown = <Map<String, dynamic>>[];
      final sortedSettlements = uniqueSettlements.toList()..sort();
      for (final settlement in sortedSettlements) {
        final data = settlementData[settlement];
        if (data == null || data.isEmpty) continue;

        // Calculate totals for this settlement
        int totalSettlementTrainings = 0;
        int totalSettlementTrainees = 0;
        final Map<String, int> typeCounts = {};

        for (final typeData in data.entries) {
          final type = typeData.key;
          final count = (typeData.value['count'] as int?) ?? 0;
          final trainees = (typeData.value['trainees'] as Set<String>?) ?? {};

          totalSettlementTrainings += count;
          totalSettlementTrainees += trainees.length;
          typeCounts[type] = count;
        }

        final average = totalSettlementTrainings > 0
            ? (totalSettlementTrainees / totalSettlementTrainings)
                  .toStringAsFixed(2)
            : '0.00';

        // Build type breakdown string
        final typeBreakdownStr = typeCounts.entries
            .map((e) => '${e.key}: ${e.value}')
            .join(', ');

        settlementBreakdown.add({
          'יישוב': settlement,
          'סה"כ אימונים': totalSettlementTrainings,
          'פירוט לפי סוג': typeBreakdownStr,
          'סה"כ חניכים ייחודיים': totalSettlementTrainees,
          'ממוצע חניכים לאימון': average,
        });
      }
      sectionsData['פילוח לפי יישוב'] = settlementBreakdown;

      // Section 4: פילוח לפי מדריך
      final instructorBreakdown = <Map<String, dynamic>>[];
      // Sort instructors by total trainings (descending)
      final sortedInstructors = instructorData.entries.toList()
        ..sort((a, b) {
          final totalA = a.value.values.fold(0, (acc, val) => acc + val);
          final totalB = b.value.values.fold(0, (acc, val) => acc + val);
          return totalB.compareTo(totalA);
        });

      for (final entry in sortedInstructors) {
        final instructorName = entry.key;
        final typeCounts = entry.value;
        final totalInstructorTrainings = typeCounts.values.fold(
          0,
          (acc, val) => acc + val,
        );

        // Build type breakdown string
        final typeBreakdownStr = typeCounts.entries
            .map((e) => '${e.key}: ${e.value}')
            .join(', ');

        instructorBreakdown.add({
          'מדריך': instructorName,
          'סה"כ אימונים': totalInstructorTrainings,
          'פירוט לפי סוג': typeBreakdownStr,
        });
      }
      sectionsData['פילוח לפי מדריך'] = instructorBreakdown;

      // Export to Google Sheets
      await FeedbackExportService.exportStatisticsToGoogleSheets(
        tabName: 'סטטיסטיקת הגמר חטיבה 474',
        sections: sectionsData,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקובץ יוצא בהצלחה!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('אין הרשאה'),
          leading: const StandardBackButton(),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('דף זה מיועד למנהלים בלבד', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סטטיסטיקת הגמר חטיבה 474'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'רענן נתונים',
              onPressed: _isRefreshing ? null : _refreshData,
            ),
            IconButton(
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download),
              tooltip: 'ייצוא',
              onPressed: _isExporting ? null : _exportStatistics,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('טוען נתונים...'),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(12.0),
                child: ListView(
                  children: [
                    // Main summary card
                    Card(
                      color: Colors.deepOrange.shade700,
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            const Text(
                              '📊 סיכום כללי - הגמר חטיבה 474',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            _buildSummaryRow(
                              '👥 חניכים',
                              '$totalTrainees',
                              Colors.greenAccent,
                            ),
                            const SizedBox(height: 12),
                            _buildSummaryRow(
                              '🎯 סה"כ כדורים שנורו',
                              '$totalBulletsFired',
                              Colors.orangeAccent,
                            ),
                            const SizedBox(height: 12),
                            _buildSummaryRow(
                              '� סה"כ משובים (מחלקות הגנה)',
                              '$totalMeshuvim',
                              Colors.lightBlueAccent,
                            ),
                            const SizedBox(height: 12),
                            _buildSummaryRow(
                              '🏋️ סה"כ אימונים',
                              '$totalImunim',
                              Colors.cyanAccent,
                            ),
                            const SizedBox(height: 12),
                            _buildSummaryRow(
                              '🏘️ סה"כ יישובים',
                              '${uniqueSettlements.length}',
                              Colors.purpleAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Breakdown by type
                    const Text(
                      'פילוח לפי סוג אימון',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...feedbacksByType.entries.map((entry) {
                      final type = entry.key;
                      final count = entry.value;
                      final percentage = totalFeedbacks > 0
                          ? ((count / totalFeedbacks) * 100).toStringAsFixed(1)
                          : '0.0';
                      final pct = totalFeedbacks > 0
                          ? (count / totalFeedbacks)
                          : 0.0;

                      // Check if this is defense platoons (personal names, not settlements)
                      final isDefensePlatoons =
                          type == 'מחלקות ההגנה – חטיבה 474';

                      // Calculate average trainees (only for non-defense types)
                      int totalTraineesForType = 0;
                      if (!isDefensePlatoons) {
                        // Count unique trainees across all settlements for this type
                        for (final settlementEntry in settlementData.entries) {
                          final settlementTypes = settlementEntry.value;
                          if (settlementTypes.containsKey(type)) {
                            final trainees =
                                settlementTypes[type]!['trainees']
                                    as Set<String>? ??
                                {};
                            totalTraineesForType += trainees.length;
                          }
                        }
                      }
                      final avgTrainees = !isDefensePlatoons && count > 0
                          ? (totalTraineesForType / count).toStringAsFixed(2)
                          : null;

                      IconData icon;
                      Color color;
                      switch (type) {
                        case 'מטווחים 474':
                          icon = Icons.gps_fixed;
                          color = Colors.deepOrange;
                          break;
                        case 'מחלקות ההגנה – חטיבה 474':
                          icon = Icons.shield;
                          color = Colors.blue;
                          break;
                        case 'משוב תרגילי הפתעה':
                          icon = Icons.flash_on;
                          color = Colors.amber;
                          break;
                        case 'משוב סיכום אימון 474':
                          icon = Icons.assessment;
                          color = Colors.green;
                          break;
                        default:
                          icon = Icons.info;
                          color = Colors.grey;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Card(
                          color: Colors.blueGrey.shade800,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(icon, color: color, size: 28),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _getTypeDisplayName(type),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: FractionallySizedBox(
                                          widthFactor: pct.clamp(0.0, 1.0),
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '$percentage%',
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                // Show average trainees (only for non-defense platoons)
                                if (avgTrainees != null) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.people,
                                        color: Colors.lightBlueAccent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'ממוצע חניכים באימון: $avgTrainees',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.lightBlueAccent,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Instructor breakdown
                    const Text(
                      'פילוח לפי מדריך',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...(instructorData.entries.toList()..sort((a, b) {
                          final totalA = a.value.values.fold(
                            0,
                            (acc, value) => acc + value,
                          );
                          final totalB = b.value.values.fold(
                            0,
                            (acc, value) => acc + value,
                          );
                          return totalB.compareTo(
                            totalA,
                          ); // Sort by total descending
                        }))
                        .map((entry) {
                          final instructorName = entry.key;
                          final typeCounts = entry.value;
                          final totalInstructorTrainings = typeCounts.values
                              .fold(0, (acc, value) => acc + value);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Card(
                              color: Colors.blueGrey.shade700,
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Instructor header
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.person,
                                          color: Colors.lightBlueAccent,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            instructorName,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.lightBlueAccent,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          'סה"כ: $totalInstructorTrainings',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orangeAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Training types breakdown
                                    ...typeCounts.entries.map((typeEntry) {
                                      final type = typeEntry.key;
                                      final count = typeEntry.value;

                                      IconData icon;
                                      Color color;
                                      switch (type) {
                                        case 'מטווחים 474':
                                          icon = Icons.gps_fixed;
                                          color = Colors.deepOrange;
                                          break;
                                        case 'מחלקות ההגנה – חטיבה 474':
                                          icon = Icons.shield;
                                          color = Colors.blue;
                                          break;
                                        case 'משוב תרגילי הפתעה':
                                          icon = Icons.flash_on;
                                          color = Colors.amber;
                                          break;
                                        case 'משוב סיכום אימון 474':
                                          icon = Icons.assessment;
                                          color = Colors.green;
                                          break;
                                        default:
                                          icon = Icons.info;
                                          color = Colors.grey;
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(icon, color: color, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _getTypeDisplayName(type),
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '$count אימונים',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Settlements detailed breakdown
                    const Text(
                      'פילוח לפי יישוב',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Sort settlements alphabetically
                    ...(uniqueSettlements.toList()..sort()).map((settlement) {
                      final data = settlementData[settlement];
                      if (data == null || data.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      // Calculate total trainees and trainings for this settlement
                      int totalSettlementTrainings = 0;
                      int totalSettlementTrainees = 0;

                      for (final typeData in data.values) {
                        totalSettlementTrainings +=
                            (typeData['count'] as int?) ?? 0;
                        totalSettlementTrainees +=
                            ((typeData['trainees'] as Set<String>?) ?? {})
                                .length;
                      }

                      // Calculate average
                      final average = totalSettlementTrainings > 0
                          ? (totalSettlementTrainees / totalSettlementTrainings)
                          : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Card(
                          color: Colors.blueGrey.shade700,
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Settlement header
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Colors.orangeAccent,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      settlement,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orangeAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Training types breakdown (only show if exists)
                                if (data.containsKey('מטווחים 474') &&
                                    data['מטווחים 474']!['count'] > 0) ...[
                                  Row(
                                    children: [
                                      const Text(
                                        '🎯 מטווחים:',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${data['מטווחים 474']!['count']} אימונים',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const Text(
                                        ' | ',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                      Text(
                                        '${(data['מטווחים 474']!['trainees'] as Set<String>).length} חניכים',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                if (data.containsKey('משוב תרגילי הפתעה') &&
                                    data['משוב תרגילי הפתעה']!['count'] >
                                        0) ...[
                                  Row(
                                    children: [
                                      const Text(
                                        '⚡ תרגילי הפתעה:',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${data['משוב תרגילי הפתעה']!['count']} אימונים',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const Text(
                                        ' | ',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                      Text(
                                        '${(data['משוב תרגילי הפתעה']!['trainees'] as Set<String>).length} חניכים',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                if (data.containsKey(
                                      'מחלקות ההגנה – חטיבה 474',
                                    ) &&
                                    data['מחלקות ההגנה – חטיבה 474']!['count'] >
                                        0) ...[
                                  Row(
                                    children: [
                                      const Text(
                                        '🛡️ מחלקות הגנה:',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${data['מחלקות ההגנה – חטיבה 474']!['count']} אימונים',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      // No trainees count for defense platoons (personal names)
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                if (data.containsKey('משוב סיכום אימון 474') &&
                                    data['משוב סיכום אימון 474']!['count'] >
                                        0) ...[
                                  Row(
                                    children: [
                                      const Text(
                                        '📋 סיכום אימון:',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${data['משוב סיכום אימון 474']!['count']} אימונים',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const Text(
                                        ' | ',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                      Text(
                                        '${(data['משוב סיכום אימון 474']!['trainees'] as Set<String>).length} חניכים',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // Divider before average
                                const Divider(
                                  color: Colors.white30,
                                  thickness: 1,
                                ),
                                const SizedBox(height: 8),

                                // Average trainees per training
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.analytics,
                                      color: Colors.lightBlueAccent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'ממוצע:',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${average.toStringAsFixed(2)} חניכים באימון',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.lightBlueAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class SurpriseDrillsStatisticsPage extends StatefulWidget {
  const SurpriseDrillsStatisticsPage({super.key});

  @override
  State<SurpriseDrillsStatisticsPage> createState() =>
      _SurpriseDrillsStatisticsPageState();
}

class _SurpriseDrillsStatisticsPageState
    extends State<SurpriseDrillsStatisticsPage> {
  String selectedInstructor = 'כל המדריכים';
  String selectedSettlement = 'כל היישובים';
  String selectedPrinciple = 'כל העקרונות';
  String selectedFolder = 'הכל';
  DateTime? dateFrom;
  DateTime? dateTo;

  // Surprise drills data cache
  Map<String, Map<String, dynamic>> surpriseDrillsData = {};

  @override
  void initState() {
    super.initState();
    _loadSurpriseDrillsData();
  }

  Future<void> _loadSurpriseDrillsData() async {
    try {
      final filtered = getFiltered();
      for (final f in filtered) {
        if (f.id != null && f.id!.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('feedbacks')
              .doc(f.id)
              .get();
          if (doc.exists) {
            final data = doc.data();
            if (data != null) {
              surpriseDrillsData[f.id!] = data;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading surprise drills data: $e');
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _clearFilters() {
    setState(() {
      selectedInstructor = 'כל המדריכים';
      selectedSettlement = 'כל היישובים';
      selectedPrinciple = 'כל העקרונות';
      selectedFolder = 'הכל';
      dateFrom = null;
      dateTo = null;
    });
  }

  List<FeedbackModel> getFiltered() {
    final isAdmin = currentUser?.role == 'Admin';
    final currentUid = currentUser?.uid ?? '';
    return feedbackStorage.where((f) {
      // Only surprise drills feedbacks (both 474 and general)
      if (f.folder != 'משוב תרגילי הפתעה' &&
          f.folder != 'תרגילי הפתעה כללי' &&
          f.module != 'surprise_drill') {
        return false;
      }

      // Exclude temporary drafts
      if (f.isTemporary == true) return false;

      // Instructor permission: see feedback they created OR where they're listed as additional instructor
      if (!isAdmin) {
        if (currentUser == null) return false;
        final isCreator = f.instructorName == (currentUser?.name ?? '');
        // ✅ HYBRID CHECK: instructors array by UID OR name (backward compatible)
        final isAdditionalInstructor =
            f.instructors.contains(currentUid) ||
            f.instructors.contains(currentUser?.name ?? '');
        if (!isCreator && !isAdditionalInstructor) {
          return false;
        }
      }

      if (selectedInstructor != 'כל המדריכים' &&
          f.instructorName != selectedInstructor) {
        return false;
      }
      if (selectedSettlement != 'כל היישובים' &&
          f.settlement != selectedSettlement) {
        return false;
      }
      // ✅ FOLDER FILTER: Support both 474 and general
      if (selectedFolder != 'הכל') {
        if (selectedFolder == 'משוב תרגילי הפתעה' &&
            f.folder != 'משוב תרגילי הפתעה') {
          return false;
        }
        if (selectedFolder == 'תרגילי הפתעה כללי' &&
            f.folder != 'תרגילי הפתעה כללי') {
          return false;
        }
      }
      if (dateFrom != null && f.createdAt.isBefore(dateFrom!)) return false;
      if (dateTo != null && f.createdAt.isAfter(dateTo!)) return false;

      return true;
    }).toList();
  }

  Future<void> pickFrom(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateFrom ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateFrom = r);
  }

  Future<void> pickTo(BuildContext ctx) async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: ctx,
      initialDate: dateTo ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (r != null) setState(() => dateTo = r);
  }

  double avgOf(List<int> vals) {
    if (vals.isEmpty) return 0.0;
    final sum = vals.reduce((a, b) => a + b);
    return sum / vals.length;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = getFiltered();
    final total = filtered.length;
    final isAdmin = currentUser?.role == 'Admin';

    // Build principle aggregates across all settlements
    final Map<String, List<int>> principleValuesGlobal = {};
    final Map<String, int> principleCountsGlobal = {};

    // Build settlement aggregates with principles per settlement
    final Map<String, Map<String, List<int>>> settlementPrincipleValues = {};
    final Map<String, Map<String, int>> settlementPrincipleCounts = {};

    for (final f in filtered) {
      if (!surpriseDrillsData.containsKey(f.id)) continue;
      final data = surpriseDrillsData[f.id];
      final stations =
          (data?['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final trainees =
          (data?['trainees'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      for (var i = 0; i < stations.length; i++) {
        final station = stations[i];
        final principleName = station['name'] ?? 'עיקרון ${i + 1}';

        // Apply principle filter if selected
        if (selectedPrinciple != 'כל העקרונות' &&
            principleName != selectedPrinciple) {
          continue;
        }

        for (final trainee in trainees) {
          final hits = trainee['hits'] as Map<String, dynamic>?;
          if (hits != null) {
            final score = (hits['station_$i'] as num?)?.toInt() ?? 0;
            if (score > 0) {
              // Global principle stats
              principleValuesGlobal.putIfAbsent(principleName, () => []);
              principleValuesGlobal[principleName]!.add(score);
              principleCountsGlobal[principleName] =
                  (principleCountsGlobal[principleName] ?? 0) + 1;

              // Per-settlement principle stats
              final settlement = f.settlement;
              if (settlement.isNotEmpty) {
                settlementPrincipleValues.putIfAbsent(settlement, () => {});
                settlementPrincipleCounts.putIfAbsent(settlement, () => {});

                settlementPrincipleValues[settlement]!.putIfAbsent(
                  principleName,
                  () => [],
                );
                settlementPrincipleValues[settlement]![principleName]!.add(
                  score,
                );

                settlementPrincipleCounts[settlement]![principleName] =
                    (settlementPrincipleCounts[settlement]![principleName] ??
                        0) +
                    1;
              }
            }
          }
        }
      }
    }

    // Build lists for dropdowns
    final instructors = <String>{'כל המדריכים'}
      ..addAll(
        feedbackStorage.map((f) => f.instructorName).where((s) => s.isNotEmpty),
      );

    final settlements = <String>{'כל היישובים'}
      ..addAll(
        feedbackStorage.map((f) => f.settlement).where((s) => s.isNotEmpty),
      );

    // Build principle list from all surprise drills data
    final Set<String> principleNames = {};
    for (final data in surpriseDrillsData.values) {
      final stations =
          (data['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (var i = 0; i < stations.length; i++) {
        final station = stations[i];
        final name = station['name'] ?? 'עיקרון ${i + 1}';
        principleNames.add(name);
      }
    }
    final principles = ['כל העקרונות'] + principleNames.toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סטטיסטיקה תרגילי הפתעה'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'ייצוא',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => StatisticsExportDialog(
                    tabName: 'סטטיסטיקה תרגילי הפתעה',
                    availableSections: const [
                      'ממוצע לפי עיקרון (כללי)',
                      'ממוצע לפי יישוב',
                    ],
                    onExport: (selectedSections) async {
                      final sectionsData =
                          <String, List<Map<String, dynamic>>>{};

                      if (selectedSections.contains(
                        'ממוצע לפי עיקרון (כללי)',
                      )) {
                        final data = <Map<String, dynamic>>[];
                        for (final entry in principleValuesGlobal.entries) {
                          final values = entry.value;
                          final avg = avgOf(values);
                          final count = principleCountsGlobal[entry.key] ?? 0;
                          data.add({
                            'עיקרון': entry.key,
                            'ממוצע': avg.toStringAsFixed(1),
                            'מספר הערכות': count,
                          });
                        }
                        sectionsData['ממוצע לפי עיקרון (כללי)'] = data;
                      }

                      if (selectedSections.contains('ממוצע לפי יישוב')) {
                        final data = <Map<String, dynamic>>[];
                        for (final settlementEntry
                            in settlementPrincipleValues.entries) {
                          final settlement = settlementEntry.key;
                          final principlesMap = settlementEntry.value;

                          // Overall settlement average
                          final List<int> allSettlementValues = [];
                          for (final values in principlesMap.values) {
                            allSettlementValues.addAll(values);
                          }
                          final settlementAvg = avgOf(allSettlementValues);

                          // Add settlement row
                          data.add({
                            'יישוב': settlement,
                            'עיקרון': 'ממוצע כללי',
                            'ממוצע': settlementAvg.toStringAsFixed(1),
                            'מספר הערכות': allSettlementValues.length,
                          });

                          // Add principle rows for this settlement
                          for (final principleEntry in principlesMap.entries) {
                            final principleName = principleEntry.key;
                            final values = principleEntry.value;
                            final avg = avgOf(values);
                            final count =
                                settlementPrincipleCounts[settlement]![principleName] ??
                                0;
                            data.add({
                              'יישוב': settlement,
                              'עיקרון': principleName,
                              'ממוצע': avg.toStringAsFixed(1),
                              'מספר הערכות': count,
                            });
                          }
                        }
                        sectionsData['ממוצע לפי יישוב'] = data;
                      }

                      return sectionsData;
                    },
                  ),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView(
            children: [
              // Filters
              Card(
                color: Colors.blueGrey.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'סינון',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          // Instructor filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'מדריך ממשב',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final items = instructors.toSet().toList();
                                    final value =
                                        items.contains(selectedInstructor)
                                        ? selectedInstructor
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: isAdmin
                                          ? (v) => setState(
                                              () => selectedInstructor =
                                                  v ?? 'כל המדריכים',
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Settlement filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'יישוב',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final items = settlements.toSet().toList();
                                    final value =
                                        items.contains(selectedSettlement)
                                        ? selectedSettlement
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                        () => selectedSettlement =
                                            v ?? 'כל היישובים',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Principle filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'עיקרון',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final items = principles;
                                    final value =
                                        items.contains(selectedPrinciple)
                                        ? selectedPrinciple
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(i),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                        () => selectedPrinciple =
                                            v ?? 'כל העקרונות',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Folder filter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'תיקייה',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                width: 240,
                                child: Builder(
                                  builder: (ctx) {
                                    final folders = <String>[
                                      'הכל',
                                      'משוב תרגילי הפתעה',
                                      'תרגילי הפתעה כללי',
                                    ];

                                    // Display name mapping
                                    String getDisplayName(
                                      String internalValue,
                                    ) {
                                      switch (internalValue) {
                                        case 'משוב תרגילי הפתעה':
                                          return 'תרגילי הפתעה 474';
                                        default:
                                          return internalValue;
                                      }
                                    }

                                    final items = folders;
                                    final value = items.contains(selectedFolder)
                                        ? selectedFolder
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: value ?? 'הכל',
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                      ),
                                      items: items
                                          .map(
                                            (i) => DropdownMenuItem(
                                              value: i,
                                              child: Text(getDisplayName(i)),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(() {
                                        selectedFolder = v ?? 'הכל';
                                      }),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Date range
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () => pickFrom(context),
                                child: Text(
                                  dateFrom == null
                                      ? 'מתאריך'
                                      : '${dateFrom!.toLocal()}'.split(' ')[0],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => pickTo(context),
                                child: Text(
                                  dateTo == null
                                      ? 'עד תאריך'
                                      : '${dateTo!.toLocal()}'.split(' ')[0],
                                ),
                              ),
                            ],
                          ),

                          // Clear filters button
                          ElevatedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('נקה סינונים'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Text('סה"כ משובים: $total', style: const TextStyle(fontSize: 14)),

              const SizedBox(height: 12),
              const Text(
                'ממוצע לפי עיקרון (כללי)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...principleValuesGlobal.entries.map((e) {
                final principleName = e.key;
                final values = e.value;
                final avg = avgOf(values);
                final count = principleCountsGlobal[principleName] ?? 0;
                final pct = (avg / 5.0).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        principleName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: pct,
                                alignment: Alignment.centerRight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.orangeAccent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${avg.toStringAsFixed(1)} ($count)',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'ממוצע לפי יישוב',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...settlementPrincipleValues.entries.map((settlementEntry) {
                final settlement = settlementEntry.key;
                final principlesMap = settlementEntry.value;

                // Calculate overall settlement average
                final List<int> allSettlementValues = [];
                for (final values in principlesMap.values) {
                  allSettlementValues.addAll(values);
                }
                final settlementAvg = avgOf(allSettlementValues);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Card(
                    color: Colors.blueGrey.shade700,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Settlement header with overall average
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  settlement,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                              ),
                              Text(
                                'ממוצע כללי: ${settlementAvg.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Principles within this settlement
                          ...principlesMap.entries.map((principleEntry) {
                            final principleName = principleEntry.key;
                            final values = principleEntry.value;
                            final avg = avgOf(values);
                            final count =
                                settlementPrincipleCounts[settlement]![principleName] ??
                                0;
                            final pct = (avg / 5.0).clamp(0.0, 1.0);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    principleName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                          child: FractionallySizedBox(
                                            widthFactor: pct,
                                            alignment: Alignment.centerRight,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.lightBlueAccent,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${avg.toStringAsFixed(1)} ($count)',
                                        style: const TextStyle(
                                          color: Colors.lightBlueAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable dialog for selecting statistics sections to export
class StatisticsExportDialog extends StatefulWidget {
  final String tabName;
  final List<String> availableSections;
  final Future<Map<String, List<Map<String, dynamic>>>> Function(
    List<String> selectedSections,
  )
  onExport;

  const StatisticsExportDialog({
    super.key,
    required this.tabName,
    required this.availableSections,
    required this.onExport,
  });

  @override
  State<StatisticsExportDialog> createState() => _StatisticsExportDialogState();
}

class _StatisticsExportDialogState extends State<StatisticsExportDialog> {
  late Map<String, bool> selectedSections;
  bool isExporting = false;

  @override
  void initState() {
    super.initState();
    // Default: all sections selected
    selectedSections = {
      for (final section in widget.availableSections) section: true,
    };
  }

  Future<void> _performExport() async {
    final selected = selectedSections.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אנא בחר לפחות מדור אחד לייצוא')),
      );
      return;
    }

    setState(() => isExporting = true);

    try {
      final sectionsData = await widget.onExport(selected);
      await FeedbackExportService.exportStatisticsToGoogleSheets(
        tabName: widget.tabName,
        sections: sectionsData,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקובץ יוצא בהצלחה!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('ייצוא ${widget.tabName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('בחר מדורים לייצוא:'),
            const SizedBox(height: 16),
            ...widget.availableSections.map(
              (section) => CheckboxListTile(
                title: Text(section),
                value: selectedSections[section] ?? false,
                onChanged: isExporting
                    ? null
                    : (value) {
                        setState(() {
                          selectedSections[section] = value ?? false;
                        });
                      },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: isExporting ? null : () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: isExporting ? null : _performExport,
            child: isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ייצוא'),
          ),
        ],
      ),
    );
  }
}

/* ================== BRIGADE 474 FINAL - INTERMEDIATE FOLDERS SCREEN ================== */

/// Intermediate screen showing 4 sub-folders of "הגמר חטיבה 474"
class Brigade474FinalFoldersPage extends StatefulWidget {
  const Brigade474FinalFoldersPage({super.key});

  @override
  State<Brigade474FinalFoldersPage> createState() =>
      _Brigade474FinalFoldersPageState();
}

class _Brigade474FinalFoldersPageState
    extends State<Brigade474FinalFoldersPage> {
  bool _isRefreshing = false;

  Future<void> _refreshFeedbacks() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      final isAdmin = currentUser?.role == 'Admin';
      debugPrint('🔄 Manual refresh triggered for הגמר חטיבה 474');
      await loadFeedbacksForCurrentUser(isAdmin: isAdmin);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('רשימת המשובים עודכנה')));
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('שגיאה בטעינת משובים')));
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The 4 sub-folders from _feedbackFoldersConfig (now hidden from main list)
    final subFolders = [
      {
        'title': 'מטווחים 474',
        'internalValue': '474 Ranges',
        'icon': Icons.gps_fixed,
        'color': Colors.deepOrange,
      },
      {
        'title': 'מחלקות הגנה 474',
        'internalValue': 'מחלקות ההגנה – חטיבה 474',
        'icon': Icons.shield,
        'color': Colors.blue,
      },
      {
        'title': 'תרגילי הפתעה 474',
        'internalValue': 'משוב תרגילי הפתעה',
        'icon': Icons.flash_on,
        'color': Colors.amber,
      },
      {
        'title': 'סיכום אימון 474',
        'internalValue': 'משוב סיכום אימון 474',
        'icon': Icons.assessment,
        'color': Colors.green,
      },
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('הגמר חטיבה 474'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isRefreshing ? null : _refreshFeedbacks,
              tooltip: 'רענן רשימה',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView.builder(
            itemCount: subFolders.length,
            itemBuilder: (ctx, i) {
              final folder = subFolders[i];
              final title = folder['title'] as String;
              final internalValue = folder['internalValue'] as String;
              final icon = folder['icon'] as IconData;
              final color = folder['color'] as Color;

              // Count feedbacks for this folder
              int count;
              if (title == 'משובים – כללי') {
                count = feedbackStorage
                    .where((f) => f.folder == title || f.folder.isEmpty)
                    .length;
              } else {
                count = feedbackStorage
                    .where(
                      (f) => f.folder == title || f.folder == internalValue,
                    )
                    .length;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 2,
                child: InkWell(
                  onTap: () {
                    // Navigate to FeedbacksPage with selected folder
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _FeedbacksPageWithFolder(
                          selectedFolder: internalValue,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(icon, size: 32, color: color),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.start,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '$count משובים',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Helper widget to show FeedbacksPage with pre-selected folder
class _FeedbacksPageWithFolder extends StatefulWidget {
  final String selectedFolder;

  const _FeedbacksPageWithFolder({required this.selectedFolder});

  @override
  State<_FeedbacksPageWithFolder> createState() =>
      _FeedbacksPageWithFolderState();
}

class _FeedbacksPageWithFolderState extends State<_FeedbacksPageWithFolder> {
  @override
  Widget build(BuildContext context) {
    // Simply navigate back to FeedbacksPage and set the folder
    // This is done by creating a new FeedbacksPage instance with modified state
    return FeedbacksPageDirectView(initialFolder: widget.selectedFolder);
  }
}

/// Direct view of feedbacks for a specific folder (used by Brigade474FinalFoldersPage)
class FeedbacksPageDirectView extends StatefulWidget {
  final String initialFolder;

  const FeedbacksPageDirectView({super.key, required this.initialFolder});

  @override
  State<FeedbacksPageDirectView> createState() =>
      _FeedbacksPageDirectViewState();
}

class _FeedbacksPageDirectViewState extends State<FeedbacksPageDirectView> {
  late String _selectedFolder;
  bool _isRefreshing = false;

  // New filter state variables
  String _filterSettlement = 'הכל';
  String _filterExercise = 'הכל';
  String _filterRole = 'הכל';
  String _filterRangeType = 'הכל';
  String _filterInstructor = 'הכל'; // Instructor filter for range folders
  DateTime? _filterDateFrom; // Date from filter for range folders
  DateTime? _filterDateTo; // Date to filter for range folders

  // Selection mode state
  bool _selectionMode = false;
  final Set<String> _selectedFeedbackIds = {};
  bool _isExporting = false;

  // Collapsible filters state
  bool _isFiltersExpanded = true;

  /// Helper: Get Hebrew display label for folder (handles internal values like '474 Ranges')
  String _getDisplayLabel(String internalValue) {
    final config = _feedbackFoldersConfig.firstWhere(
      (c) => (c['internalValue'] ?? c['title']) == internalValue,
      orElse: () => {'title': internalValue},
    );
    return (config['displayLabel'] ?? config['title'] ?? internalValue)
        as String;
  }

  @override
  void initState() {
    super.initState();
    _selectedFolder = widget.initialFolder;
  }

  // Copy paste filter and export methods from _FeedbacksPageState
  void _clearFilters() {
    setState(() {
      _filterSettlement = 'הכל';
      _filterExercise = 'הכל';
      _filterRole = 'הכל';
      _filterRangeType = 'הכל';
      _filterInstructor = 'הכל';
      _filterDateFrom = null;
      _filterDateTo = null;
    });
  }

  bool get _hasActiveFilters =>
      _filterSettlement != 'הכל' ||
      _filterExercise != 'הכל' ||
      _filterRole != 'הכל' ||
      _filterRangeType != 'הכל' ||
      _filterInstructor != 'הכל' ||
      _filterDateFrom != null ||
      _filterDateTo != null;

  List<String> _getSettlementOptions(List<FeedbackModel> feedbacks) {
    final settlements = feedbacks
        .map((f) => f.settlement)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    settlements.sort();
    return ['הכל', ...settlements];
  }

  List<String> _getExerciseOptions(List<FeedbackModel> feedbacks) {
    // For training summary folders, use trainingType instead of exercise
    final isTrainingSummaryFolder =
        _selectedFolder == 'משוב סיכום אימון 474' ||
        _selectedFolder == 'סיכום אימון כללי';

    final exercises = feedbacks
        .map((f) {
          if (isTrainingSummaryFolder && f.trainingType.isNotEmpty) {
            return f.trainingType;
          }
          return f.exercise;
        })
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    exercises.sort();
    return ['הכל', ...exercises];
  }

  List<String> _getRoleOptions(List<FeedbackModel> feedbacks) {
    final roles = feedbacks
        .map((f) => f.role)
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();
    roles.sort();
    return ['הכל', ...roles];
  }

  List<String> _getInstructorOptions(List<FeedbackModel> feedbacks) {
    final instructors = feedbacks
        .map((f) => f.instructorName)
        .where((i) => i.isNotEmpty)
        .toSet()
        .toList();
    instructors.sort();
    return ['הכל', ...instructors];
  }

  List<FeedbackModel> _applyFilters(List<FeedbackModel> feedbacks) {
    // For training summary folders, filter by trainingType instead of exercise
    final isTrainingSummaryFolder =
        _selectedFolder == 'משוב סיכום אימון 474' ||
        _selectedFolder == 'סיכום אימון כללי';

    return feedbacks.where((f) {
      if (_filterSettlement != 'הכל') {
        if (f.settlement.isEmpty || f.settlement != _filterSettlement) {
          return false;
        }
      }
      if (_filterExercise != 'הכל') {
        // For training summary, compare against trainingType
        if (isTrainingSummaryFolder) {
          if (f.trainingType.isEmpty || f.trainingType != _filterExercise) {
            return false;
          }
        } else {
          if (f.exercise.isEmpty || f.exercise != _filterExercise) {
            return false;
          }
        }
      }
      if (_filterRole != 'הכל') {
        if (f.role.isEmpty || f.role != _filterRole) {
          return false;
        }
      }
      if (_filterRangeType != 'הכל') {
        if (f.rangeSubType.isEmpty || f.rangeSubType != _filterRangeType) {
          return false;
        }
      }
      // Instructor filter
      if (_filterInstructor != 'הכל') {
        if (f.instructorName.isEmpty || f.instructorName != _filterInstructor) {
          return false;
        }
      }
      // Date from filter
      if (_filterDateFrom != null) {
        final feedbackDate = DateTime(
          f.createdAt.year,
          f.createdAt.month,
          f.createdAt.day,
        );
        final fromDate = DateTime(
          _filterDateFrom!.year,
          _filterDateFrom!.month,
          _filterDateFrom!.day,
        );
        if (feedbackDate.isBefore(fromDate)) {
          return false;
        }
      }
      // Date to filter
      if (_filterDateTo != null) {
        final feedbackDate = DateTime(
          f.createdAt.year,
          f.createdAt.month,
          f.createdAt.day,
        );
        final toDate = DateTime(
          _filterDateTo!.year,
          _filterDateTo!.month,
          _filterDateTo!.day,
        );
        if (feedbackDate.isAfter(toDate)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _refreshFeedbacks() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      final isAdmin = currentUser?.role == 'Admin';
      await loadFeedbacksForCurrentUser(isAdmin: isAdmin);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('רשימת המשובים עודכנה')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה בטעינת משובים')));
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _confirmDeleteFeedback(String feedbackId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משוב'),
          content: Text('האם למחוק את המשוב "$title"?\n\nפעולה זו בלתי הפיכה.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _deleteFeedback(feedbackId, title);
    }
  }

  Future<void> _deleteFeedback(String feedbackId, String title) async {
    try {
      await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(feedbackId)
          .delete();

      feedbackStorage.removeWhere((f) => f.id == feedbackId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('המשוב "$title" נמחק בהצלחה')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה במחיקת משוב: $e')));
    }
  }

  Future<void> _exportSelectedFeedbacks() async {
    setState(() => _isExporting = true);

    try {
      final messenger = ScaffoldMessenger.of(context);

      if (_selectedFeedbackIds.isEmpty) {
        throw Exception('לא נבחרו משובים לייצוא');
      }

      final feedbacksData = await Future.wait(
        _selectedFeedbackIds.map((id) async {
          final doc = await FirebaseFirestore.instance
              .collection('feedbacks')
              .doc(id)
              .get()
              .timeout(const Duration(seconds: 10));

          if (doc.exists && doc.data() != null) {
            return doc.data()!;
          }
          return <String, dynamic>{};
        }),
      );

      final validData = feedbacksData.where((data) => data.isNotEmpty).toList();

      if (validData.isEmpty) {
        throw Exception('לא נמצאו נתוני משוב תקינים');
      }

      if (_selectedFolder == 'מטווחים 474' || _selectedFolder == '474 Ranges') {
        await FeedbackExportService.export474RangesFeedbacks(
          feedbacksData: validData,
          fileNamePrefix: '474_ranges_selected',
        );
      } else if (_selectedFolder == 'מטווחי ירי') {
        await FeedbackExportService.export474RangesFeedbacks(
          feedbacksData: validData,
          fileNamePrefix: 'shooting_ranges_selected',
        );
      } else if (_selectedFolder == 'משוב תרגילי הפתעה' ||
          _selectedFolder == 'תרגילי הפתעה כללי') {
        await FeedbackExportService.exportSurpriseDrillsToXlsx(
          feedbacksData: validData,
          fileNamePrefix: 'surprise_drills_selected',
        );
      } else {
        final feedbackModels = validData
            .map(
              (data) => FeedbackModel.fromMap(data, id: data['id'] as String?),
            )
            .whereType<FeedbackModel>()
            .toList();

        final keys = [
          'id',
          'role',
          'name',
          'exercise',
          'scores',
          'notes',
          'criteriaList',
          'instructorName',
          'instructorRole',
          'commandText',
          'commandStatus',
          'folder',
          'scenario',
          'settlement',
          'attendeesCount',
        ];
        final headers = [
          'ID',
          'תפקיד',
          'שם',
          'תרגיל',
          'ציונים',
          'הערות',
          'קריטריונים',
          'מדריך',
          'תפקיד מדריך',
          'טקסט פקודה',
          'סטטוס פקודה',
          'תיקייה',
          'תרחיש',
          'יישוב',
          'מספר נוכחים',
        ];
        await FeedbackExportService.exportWithSchema(
          keys: keys,
          headers: headers,
          feedbacks: feedbackModels,
          fileNamePrefix: '${_selectedFolder}_selected',
        );
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('הקובץ נוצר בהצלחה!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      setState(() {
        _selectionMode = false;
        _selectedFeedbackIds.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בייצוא: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';

    // Filter feedbacks based on selected folder (copy from FeedbacksPage logic)
    List<FeedbackModel> filteredFeedbacks;

    if (_selectedFolder == 'משובים – כללי') {
      filteredFeedbacks = feedbackStorage
          .where(
            (f) =>
                (f.folder == _selectedFolder || f.folder.isEmpty) &&
                f.isTemporary == false,
          )
          .toList();
    } else if (_selectedFolder == 'משוב תרגילי הפתעה') {
      filteredFeedbacks = feedbackStorage.where((f) {
        if (f.isTemporary == true) return false;
        // Exclude general surprise drills
        if (f.folder == 'תרגילי הפתעה כללי' ||
            f.folderKey == 'surprise_drills_general') {
          return false;
        }
        if (f.module.isNotEmpty) {
          return f.module == 'surprise_drill';
        }
        return f.folder == _selectedFolder;
      }).toList();
    } else if (_selectedFolder == 'תרגילי הפתעה כללי') {
      filteredFeedbacks = feedbackStorage.where((f) {
        if (f.isTemporary == true) return false;
        return f.folder == 'תרגילי הפתעה כללי' ||
            f.folderKey == 'surprise_drills_general';
      }).toList();
    } else if (_selectedFolder == 'מטווחי ירי') {
      filteredFeedbacks = feedbackStorage.where((f) {
        if (f.isTemporary == true) return false;
        if (f.folderKey.isNotEmpty) return f.folderKey == 'shooting_ranges';
        if (f.module.isNotEmpty) return f.module == 'shooting_ranges';
        return f.folder == _selectedFolder;
      }).toList();
    } else if (_selectedFolder == '474 Ranges' ||
        _selectedFolder == 'מטווחים 474') {
      filteredFeedbacks = feedbackStorage.where((f) {
        if (f.isTemporary == true) return false;
        if (f.module == 'training_summary' || f.type == 'training_summary') {
          return false;
        }
        if (f.folder == 'משוב סיכום אימון 474') {
          return false;
        }
        if (f.folderKey.isNotEmpty) return f.folderKey == 'ranges_474';
        if (f.module.isNotEmpty && f.module == 'shooting_ranges') {
          final lowFolder = f.folder.toLowerCase();
          if (lowFolder.contains('474') ||
              lowFolder.contains('474 ranges') ||
              lowFolder.contains('מטווחים 474')) {
            return true;
          }
        }
        return f.folder == _selectedFolder || f.folder == 'מטווחים 474';
      }).toList();
    } else if (_selectedFolder == 'משוב סיכום אימון 474') {
      // ✅ TRAINING SUMMARY 474: Include ONLY 474 training summaries (exclude general)
      filteredFeedbacks = feedbackStorage.where((f) {
        if (f.isTemporary == true) return false;

        // ❌ EXCLUDE general training summaries
        if (f.folder == 'סיכום אימון כללי' ||
            f.folderKey == 'training_summary_general') {
          return false;
        }

        // NEW SCHEMA: Has module field populated AND is 474
        if (f.module.isNotEmpty) {
          // Check folderKey for 474 specifically
          if (f.folderKey == 'training_summary_474') {
            return true;
          }
          // Fallback: module is training_summary AND folder is 474
          if (f.module == 'training_summary' &&
              f.folder == 'משוב סיכום אימון 474') {
            return true;
          }
          return false;
        }

        // Legacy schema: use folder match (only 474)
        return f.folder == _selectedFolder;
      }).toList();
    } else {
      filteredFeedbacks = feedbackStorage
          .where((f) => f.folder == _selectedFolder && f.isTemporary == false)
          .toList();
    }

    final isRangeFolder =
        _selectedFolder == 'מטווחי ירי' ||
        _selectedFolder == '474 Ranges' ||
        _selectedFolder == 'מטווחים 474';

    final isSurpriseDrillsFolder =
        _selectedFolder == 'משוב תרגילי הפתעה' ||
        _selectedFolder == 'תרגילי הפתעה כללי';

    final isTrainingSummaryFolder =
        _selectedFolder == 'משוב סיכום אימון 474' ||
        _selectedFolder == 'סיכום אימון כללי';

    final List<FeedbackModel> finalFilteredFeedbacks = _applyFilters(
      filteredFeedbacks,
    );

    final settlementOptions = _getSettlementOptions(filteredFeedbacks);
    final exerciseOptions = _getExerciseOptions(filteredFeedbacks);
    final roleOptions = _getRoleOptions(filteredFeedbacks);
    final instructorOptions = _getInstructorOptions(filteredFeedbacks);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getDisplayLabel(_selectedFolder)),
          leading: const StandardBackButton(),
          actions: [
            if ((_selectedFolder == 'מטווחים 474' ||
                    _selectedFolder == '474 Ranges' ||
                    _selectedFolder == 'מטווחי ירי' ||
                    _selectedFolder == 'מחלקות ההגנה – חטיבה 474' ||
                    _selectedFolder == 'משובים – כללי' ||
                    _selectedFolder == 'משוב תרגילי הפתעה' ||
                    _selectedFolder == 'תרגילי הפתעה כללי') &&
                isAdmin &&
                finalFilteredFeedbacks.isNotEmpty)
              IconButton(
                icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
                onPressed: () {
                  setState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) {
                      _selectedFeedbackIds.clear();
                    }
                  });
                },
                tooltip: _selectionMode ? 'בטל בחירה' : 'בחר לייצוא',
              ),
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isRefreshing ? null : _refreshFeedbacks,
              tooltip: 'רענן רשימה',
            ),
          ],
        ),
        body: finalFilteredFeedbacks.isEmpty && !_hasActiveFilters
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('אין משובים בתיקייה זו'),
                  ],
                ),
              )
            : Column(
                children: [
                  if (_selectionMode)
                    Container(
                      color: Colors.blueGrey.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'נבחרו: ${_selectedFeedbackIds.length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          if (_selectedFeedbackIds.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: _isExporting
                                  ? null
                                  : _exportSelectedFeedbacks,
                              icon: _isExporting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(Icons.download, size: 18),
                              label: const Text('ייצוא'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectionMode = false;
                                _selectedFeedbackIds.clear();
                              });
                            },
                            child: const Text('בטל'),
                          ),
                        ],
                      ),
                    ),
                  Card(
                    color: Colors.blueGrey.shade800,
                    margin: const EdgeInsets.all(8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header row with toggle button
                          InkWell(
                            onTap: () => setState(
                              () => _isFiltersExpanded = !_isFiltersExpanded,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.filter_list,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'סינון',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (_hasActiveFilters) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orangeAccent,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          'פעיל',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Icon(
                                  _isFiltersExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: Colors.white70,
                                ),
                              ],
                            ),
                          ),
                          // Collapsible filter content
                          if (_isFiltersExpanded) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.start,
                              children: [
                                if (settlementOptions.length > 1)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'יישוב',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      SizedBox(
                                        width: 200,
                                        child: DropdownButtonFormField<String>(
                                          initialValue:
                                              settlementOptions.contains(
                                                _filterSettlement,
                                              )
                                              ? _filterSettlement
                                              : 'הכל',
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 16,
                                                ),
                                          ),
                                          items: settlementOptions
                                              .map(
                                                (s) => DropdownMenuItem(
                                                  value: s,
                                                  child: Text(
                                                    s,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setState(
                                            () =>
                                                _filterSettlement = v ?? 'הכל',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (!isRangeFolder &&
                                    exerciseOptions.length > 1)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isTrainingSummaryFolder
                                            ? 'סוג אימון'
                                            : 'תרגיל',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      SizedBox(
                                        width: 200,
                                        child: DropdownButtonFormField<String>(
                                          initialValue:
                                              exerciseOptions.contains(
                                                _filterExercise,
                                              )
                                              ? _filterExercise
                                              : 'הכל',
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 16,
                                                ),
                                          ),
                                          items: exerciseOptions
                                              .map(
                                                (e) => DropdownMenuItem(
                                                  value: e,
                                                  child: Text(
                                                    e,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setState(
                                            () => _filterExercise = v ?? 'הכל',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (isRangeFolder)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'מטווח',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      SizedBox(
                                        width: 200,
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _filterRangeType,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 16,
                                                ),
                                          ),
                                          items:
                                              ['הכל', 'טווח קצר', 'טווח רחוק']
                                                  .map(
                                                    (t) => DropdownMenuItem(
                                                      value: t,
                                                      child: Text(
                                                        t,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                          onChanged: (v) => setState(
                                            () => _filterRangeType = v ?? 'הכל',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                // Instructor filter (only for range folders)
                                if (isRangeFolder &&
                                    instructorOptions.length > 1)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'מדריך',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      SizedBox(
                                        width: 200,
                                        child: DropdownButtonFormField<String>(
                                          initialValue:
                                              instructorOptions.contains(
                                                _filterInstructor,
                                              )
                                              ? _filterInstructor
                                              : 'הכל',
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 16,
                                                ),
                                          ),
                                          items: instructorOptions
                                              .map(
                                                (i) => DropdownMenuItem(
                                                  value: i,
                                                  child: Text(
                                                    i,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setState(
                                            () =>
                                                _filterInstructor = v ?? 'הכל',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                // Date filters (only for range folders)
                                if (isRangeFolder)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'תאריך',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 120,
                                            child: ElevatedButton(
                                              onPressed: () async {
                                                final now = DateTime.now();
                                                final picked =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate:
                                                          _filterDateFrom ??
                                                          now,
                                                      firstDate: DateTime(2020),
                                                      lastDate: now,
                                                    );
                                                if (picked != null) {
                                                  setState(
                                                    () => _filterDateFrom =
                                                        picked,
                                                  );
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 12,
                                                    ),
                                              ),
                                              child: Text(
                                                _filterDateFrom == null
                                                    ? 'מתאריך'
                                                    : '${_filterDateFrom!.day}/${_filterDateFrom!.month}/${_filterDateFrom!.year}',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 120,
                                            child: ElevatedButton(
                                              onPressed: () async {
                                                final now = DateTime.now();
                                                final picked =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate:
                                                          _filterDateTo ?? now,
                                                      firstDate: DateTime(2020),
                                                      lastDate: now,
                                                    );
                                                if (picked != null) {
                                                  setState(
                                                    () =>
                                                        _filterDateTo = picked,
                                                  );
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 12,
                                                    ),
                                              ),
                                              child: Text(
                                                _filterDateTo == null
                                                    ? 'עד תאריך'
                                                    : '${_filterDateTo!.day}/${_filterDateTo!.month}/${_filterDateTo!.year}',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                // Instructor filter (for defense and general folders, including surprise drills)
                                if (!isRangeFolder &&
                                    instructorOptions.length > 1)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'מדריך',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      SizedBox(
                                        width: 200,
                                        child: DropdownButtonFormField<String>(
                                          initialValue:
                                              instructorOptions.contains(
                                                _filterInstructor,
                                              )
                                              ? _filterInstructor
                                              : 'הכל',
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 16,
                                                ),
                                          ),
                                          items: instructorOptions
                                              .map(
                                                (i) => DropdownMenuItem(
                                                  value: i,
                                                  child: Text(
                                                    i,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setState(
                                            () =>
                                                _filterInstructor = v ?? 'הכל',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                // Date filters (for defense, general folders, and surprise drills)
                                if (!isRangeFolder)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'תאריך',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 120,
                                            child: ElevatedButton(
                                              onPressed: () async {
                                                final now = DateTime.now();
                                                final picked =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate:
                                                          _filterDateFrom ??
                                                          now,
                                                      firstDate: DateTime(2020),
                                                      lastDate: now,
                                                    );
                                                if (picked != null) {
                                                  setState(
                                                    () => _filterDateFrom =
                                                        picked,
                                                  );
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 12,
                                                    ),
                                              ),
                                              child: Text(
                                                _filterDateFrom == null
                                                    ? 'מתאריך'
                                                    : '${_filterDateFrom!.day}/${_filterDateFrom!.month}/${_filterDateFrom!.year}',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 120,
                                            child: ElevatedButton(
                                              onPressed: () async {
                                                final now = DateTime.now();
                                                final picked =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate:
                                                          _filterDateTo ?? now,
                                                      firstDate: DateTime(2020),
                                                      lastDate: now,
                                                    );
                                                if (picked != null) {
                                                  setState(
                                                    () =>
                                                        _filterDateTo = picked,
                                                  );
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 12,
                                                    ),
                                              ),
                                              child: Text(
                                                _filterDateTo == null
                                                    ? 'עד תאריך'
                                                    : '${_filterDateTo!.day}/${_filterDateTo!.month}/${_filterDateTo!.year}',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                // Role filter (only for non-range and non-surprise-drills folders)
                                if (!isRangeFolder &&
                                    !isSurpriseDrillsFolder &&
                                    roleOptions.length > 1)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'תפקיד',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      SizedBox(
                                        width: 200,
                                        child: DropdownButtonFormField<String>(
                                          initialValue:
                                              roleOptions.contains(_filterRole)
                                              ? _filterRole
                                              : 'הכל',
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 16,
                                                ),
                                          ),
                                          items: roleOptions
                                              .map(
                                                (r) => DropdownMenuItem(
                                                  value: r,
                                                  child: Text(
                                                    r,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setState(
                                            () => _filterRole = v ?? 'הכל',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (_hasActiveFilters)
                                  TextButton.icon(
                                    onPressed: _clearFilters,
                                    icon: const Icon(Icons.clear, size: 18),
                                    label: const Text('נקה פילטרים'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.orangeAccent,
                                    ),
                                  ),
                              ],
                            ),
                            if (_hasActiveFilters) ...[
                              const SizedBox(height: 8),
                              Text(
                                'מציג ${finalFilteredFeedbacks.length} מתוך ${filteredFeedbacks.length} משובים',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ], // end of _isFiltersExpanded
                        ],
                      ),
                    ),
                  ),
                  // Settlement header for "מחלקות ההגנה – חטיבה 474" only
                  if (_selectedFolder == 'מחלקות ההגנה – חטיבה 474' &&
                      finalFilteredFeedbacks.isNotEmpty)
                    Builder(
                      builder: (context) {
                        // Show settlement name if filtered by settlement OR if all feedbacks are from same settlement
                        String? settlementToShow;

                        if (_filterSettlement != 'הכל') {
                          // User filtered by specific settlement
                          settlementToShow = _filterSettlement;
                        } else {
                          // Check if all feedbacks are from the same settlement
                          final settlements = finalFilteredFeedbacks
                              .map((f) => f.settlement)
                              .where((s) => s.isNotEmpty)
                              .toSet();
                          if (settlements.length == 1) {
                            settlementToShow = settlements.first;
                          }
                        }

                        if (settlementToShow == null ||
                            settlementToShow.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orangeAccent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.orangeAccent,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'יישוב: $settlementToShow',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  if (finalFilteredFeedbacks.isEmpty && _hasActiveFilters)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            const Text('לא נמצאו משובים התואמים לסינון'),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.clear),
                              label: const Text('נקה פילטרים'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12.0),
                        itemCount: finalFilteredFeedbacks.length,
                        itemBuilder: (_, i) {
                          final f = finalFilteredFeedbacks[i];

                          final title =
                              (f.folderKey == 'shooting_ranges' ||
                                  f.module == 'shooting_ranges' ||
                                  f.folder == 'מטווחי ירי')
                              ? (f.settlement.isNotEmpty
                                    ? f.settlement
                                    : f.name)
                              : '${f.role} — ${f.name}';

                          final date = f.createdAt.toLocal();
                          final dateStr =
                              '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

                          final metadataLines = <String>[];
                          if (_selectedFolder == 'מחלקות ההגנה – חטיבה 474') {
                            // Special order for Defense Companies folder only
                            if (f.settlement.isNotEmpty) {
                              metadataLines.add('יישוב: ${f.settlement}');
                            }
                            if (f.exercise.isNotEmpty) {
                              metadataLines.add('תרגיל: ${f.exercise}');
                            }
                            if (f.instructorName.isNotEmpty) {
                              metadataLines.add('מדריך: ${f.instructorName}');
                            }
                            metadataLines.add('תאריך: $dateStr');
                          } else {
                            // Original order for all other folders
                            if (f.exercise.isNotEmpty) {
                              metadataLines.add('תרגיל: ${f.exercise}');
                            }
                            // הוסף סוג אימון למשובי סיכום אימון 474
                            if ((f.folder == 'משוב סיכום אימון 474' ||
                                    f.module == 'training_summary') &&
                                f.trainingType.isNotEmpty) {
                              metadataLines.add('סוג אימון: ${f.trainingType}');
                            }
                            if (f.instructorName.isNotEmpty) {
                              metadataLines.add('מדריך: ${f.instructorName}');
                            }
                            if (f.attendeesCount > 0) {
                              metadataLines.add('משתתפים: ${f.attendeesCount}');
                            }
                            metadataLines.add('תאריך: $dateStr');
                          }

                          final feedbackData = <String, dynamic>{
                            'feedbackType': f.type,
                            'exercise': f.exercise,
                            'folder': f.folder,
                            'module': f.module,
                            'rangeType': '',
                            'rangeSubType': f.rangeSubType,
                          };
                          final blueTagLabel = getBlueTagLabelFromDoc(
                            feedbackData,
                          );

                          // Check delete permissions - only admin for now (proper check requires async)
                          final canDelete = currentUser?.role == 'Admin';

                          final supportsSelectionMode =
                              _selectedFolder == 'מטווחים 474' ||
                              _selectedFolder == '474 Ranges' ||
                              _selectedFolder == 'מטווחי ירי' ||
                              _selectedFolder == 'מחלקות ההגנה – חטיבה 474' ||
                              _selectedFolder == 'משובים – כללי' ||
                              _selectedFolder == 'משוב תרגילי הפתעה';

                          return FeedbackListTileCard(
                            title: title,
                            metadataLines: metadataLines,
                            blueTagLabel: blueTagLabel,
                            canDelete: canDelete && !_selectionMode,
                            selectionMode:
                                _selectionMode && supportsSelectionMode,
                            isSelected: _selectedFeedbackIds.contains(f.id),
                            onSelectionToggle: f.id != null && f.id!.isNotEmpty
                                ? () {
                                    setState(() {
                                      if (_selectedFeedbackIds.contains(f.id)) {
                                        _selectedFeedbackIds.remove(f.id);
                                      } else {
                                        _selectedFeedbackIds.add(f.id!);
                                      }
                                    });
                                  }
                                : null,
                            onOpen: () {
                              if (_selectionMode && supportsSelectionMode) {
                                if (f.id != null && f.id!.isNotEmpty) {
                                  setState(() {
                                    if (_selectedFeedbackIds.contains(f.id)) {
                                      _selectedFeedbackIds.remove(f.id);
                                    } else {
                                      _selectedFeedbackIds.add(f.id!);
                                    }
                                  });
                                }
                              } else {
                                Navigator.of(
                                  context,
                                ).pushNamed('/feedback_details', arguments: f);
                              }
                            },
                            onDelete:
                                f.id != null &&
                                    f.id!.isNotEmpty &&
                                    !_selectionMode
                                ? () => _confirmDeleteFeedback(f.id!, title)
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class MaterialsPage extends StatelessWidget {
  const MaterialsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Final implementation: list of cards leading to detail screens
    final cards = [
      {'title': 'מעגל פרוץ', 'subtitle': 'עבודה על פי חיר', 'route': 'poruz'},
      {'title': 'מעגל פתוח', 'subtitle': 'סריקות ותגובה', 'route': 'patuach'},
      {
        'title': 'סריקות רחוב',
        'subtitle': 'איתור וזיהוי איומים',
        'route': 'sarikot',
      },
      {
        'title': 'שבע עקרונות לחימה',
        'subtitle': 'עקרונות פעולה בשטח',
        'route': 'sheva',
      },
      {'title': 'סעב"ל', 'subtitle': 'סדר עדיפויות בלחימה', 'route': 'saabal'},
      {
        'title': 'אודות המערכת',
        'subtitle': 'מידע על האפליקציה',
        'route': 'about',
      },
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('חומר עיוני'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ListView.separated(
            itemCount: cards.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final item = cards[i];
              return Card(
                color: Colors.grey.shade50,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    final route = item['route'];
                    if (route == 'patuach') {
                      Navigator.of(ctx).pushNamed('/maagal_patuach');
                    } else if (route == 'sheva') {
                      Navigator.of(ctx).pushNamed('/sheva');
                    } else if (route == 'saabal') {
                      Navigator.of(ctx).pushNamed('/saabal');
                    } else if (route == 'poruz') {
                      Navigator.of(ctx).pushNamed('/poruz');
                    } else if (route == 'sarikot') {
                      Navigator.of(ctx).pushNamed('/sarikot');
                    } else if (route == 'about') {
                      Navigator.of(ctx).pushNamed('/about');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16.0,
                      horizontal: 14.0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title']!,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item['subtitle']!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_back_ios, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/* ================== DETAILS PAGES FOR MATERIALS ================== */

class DetailsPlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;
  const DetailsPlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(title), leading: const StandardBackButton()),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text('תוכן יתווסף בהמשך', style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class MaagalPatuachPage extends StatelessWidget {
  const MaagalPatuachPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מעגל פתוח'),
          leading: const StandardBackButton(),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main title
              const Text(
                'מעגל פתוח – המענה המבצעי',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Section: חתירה למגע וסריקות
              const Text(
                'חתירה למגע וסריקות',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'מעגל פתוח מתבסס על יוזמה, תנועה והתקדמות לעבר האיום, תוך ביצוע סריקות רציפות ושליטה במרחב.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),

              // Section: הצפת היישוב בכוחות
              const Text(
                'הצפת היישוב בכוחות',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'הזרמת כוחות למרחב האירוע במטרה ליצור נוכחות, לחץ מבצעי ויכולת תגובה מהירה למספר תרחישים במקביל.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),

              // Section: למה זה עובד?
              const Text(
                'למה זה עובד?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'אפקטיביות מבצעית –',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'באופן זה הפיגוע "נחנק" כבר בשלב מוקדם,\nבאמצעות מהירות יחסית ו־היפוך קערה לטובת הכוח הפועל.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Section: שלושה שלבים במעגל פתוח
              const Text(
                'שלושה שלבים במעגל פתוח',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Stage 1: מגע
              Card(
                color: Colors.blueGrey.shade700,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '1. מגע',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'יצירת מגע ראשוני עם האיום, עצירתו או קיבועו.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Stage 2: סריקות
              Card(
                color: Colors.blueGrey.shade700,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '2. סריקות',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'סריקות יזומות במרחב – שלילת איומים נוספים, איתור מחבלים נוספים או אמלח.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Stage 3: זיכוי
              Card(
                color: Colors.blueGrey.shade700,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '3. זיכוי',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'ניקוי המרחב מאיומים, מעבר לשליטה וביטחון יחסי.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Section: הערת מדריך
              Card(
                color: Colors.orangeAccent.withValues(alpha: 0.2),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Colors.orangeAccent,
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'הערת מדריך',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'מעגל פתוח אינו "המתנה לאירוע", אלא פעולה אקטיבית שמטרתה לקצר זמן פגיעה ולהעביר יוזמה לכוח.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class ShevaPrinciplesPage extends StatelessWidget {
  const ShevaPrinciplesPage({super.key});

  static const List<String> items = [
    'בחירת ציר התקדמות',
    'קשר עין',
    'איום עיקרי / איום משני',
    'זיהוי והזדהות',
    'קצב אש ומרחק',
    'קו ירי נקי',
    'וידוא ניטרול',
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('שבע עקרונות לחימה'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'שבע עקרונות לחימה',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}.',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              items[i],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SaabalPage extends StatelessWidget {
  const SaabalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סעב"ל – סדר עדיפויות בלחימה'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              const SizedBox(height: 8),
              const Text(
                'סעב"ל – סדר עדיפויות בלחימה',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildStep('1. מחבל בעין'),
              const SizedBox(height: 12),
              _buildStep('2. התייחסות לגירוי'),
              const SizedBox(height: 12),
              _buildStep('3. וידוא ניטרול'),
              const SizedBox(height: 12),
              _buildStep('4. המשך חיפוש לחימה'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String text) {
    return Card(
      color: Colors.grey.shade50,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class MaagalPoruzPage extends StatelessWidget {
  const MaagalPoruzPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מעגל פרוץ'),
          leading: const StandardBackButton(),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Highlighted header banner
              Card(
                color: Colors.orangeAccent,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 20.0,
                    horizontal: 16.0,
                  ),
                  child: Text(
                    '"מי שרואה אותי – הורג אותי | מי שלא רואה אותי – מת ממני"',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Main title
              const Text(
                'מעגל פרוץ – המענה המבצעי',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Core principles
              Card(
                color: Colors.blueGrey.shade700,
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '1. עומק ועתודה',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '2. היערכות להגנה והתקפת נגד',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Section: עומק ועתודה
              const Text(
                'עומק – היערכות במספר קווי הגנה',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              const Text(
                'עתודה – לתגבור או להתקפת נגד',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'הקצאת כוח עתודה',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),

              // Section: בידוד המרחב
              const Text(
                'בידוד המרחב –',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'ייצוב קו הגנה בתוך היישוב אשר יבודד בין השטח שנכבש ובין שאר היישוב.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),

              // Section: התקפת נגד
              const Text(
                'התקפת נגד – על פי יחסי העוצמה',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                color: Colors.blueGrey.shade800,
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'השבת המצב לקדמותו –',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'שחרור שטח שנכבש, הדיפת האויב או השמדתו, הצלת התושבים באזור זה.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'פשיטות ומארבים –',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'פעולות מקומיות לפגיעה באויב או להצלת תושבים',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Section: דגשים שונים ללחימה
              const Text(
                'מעגל פרוץ – דגשים שונים ללחימה',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Numbered list of combat points
              _buildCombatPoint('1', 'כוננות מחסנית מלאה'),
              _buildCombatPoint('2', 'מיגון מלא'),
              _buildCombatPoint('3', 'כלכלת חימוש'),
              _buildCombatPoint('4', 'אבטחה – לחימה בחוליות וממחסות ועמדות'),
              _buildCombatPoint('5', 'לחימה שקטה'),
              _buildCombatPoint('6', 'דיווחים מדויקים'),
              _buildCombatPoint('7', 'מודעות לאמל"ח מגוון ולמידת האיום'),
              _buildCombatPoint('8', 'אש לחיפוי'),
              _buildCombatPoint('9', 'תנועה בתחבולה'),
              _buildCombatPoint('10', 'תרגולות לפי תמונת המצב'),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildCombatPoint(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.orangeAccent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(text, style: TextStyle(fontSize: 16, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// Clean, fixed version of Sarikot page to avoid compile issues
class SarikotFixedPage extends StatelessWidget {
  const SarikotFixedPage({super.key});

  static Widget _item(String number, String text) {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: const BoxDecoration(
            color: Colors.orangeAccent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _item('1', 'אבטחה היקפית'),
      _item('2', 'שמירה על קשר בתוך הכוח הסורק'),
      _item('3', 'שליטה בכוח'),
      _item('4', 'יצירת גירוי והאזנה לשטח'),
      _item('5', 'עבודה ממרכז הרחוב והחוצה'),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סריקות רחוב'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'עקרונות סריקות רחוב',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...items.map(
                (w) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: w,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String version = 'טוען...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          version = 'גרסה ${packageInfo.version}+${packageInfo.buildNumber}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          version = 'גרסה לא זמינה';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('אודות המערכת'),
          leading: const StandardBackButton(),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // App icon/logo placeholder
                Icon(Icons.feedback, size: 80, color: Colors.orangeAccent),
                const SizedBox(height: 24),

                // App name
                const Text(
                  'משוב מבצר',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Version - now dynamic!
                Text(
                  version,
                  style: const TextStyle(fontSize: 18, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Creator
                const Text(
                  'נוצר על-ידי',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'יותם אלון',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'דוד בן צבי',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Description placeholder
                Card(
                  color: Colors.grey.shade50,
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: const Text(
                      'מערכת משובים לבית הספר להגנת היישוב\nחטיבה 474',
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
