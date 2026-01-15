import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  {'title': 'מטווחי ירי', 'isHidden': false},
  {
    'title': 'מטווחים 474',
    'displayLabel': 'מטווחים 474',
    'internalValue': '474 Ranges',
    'isHidden': false,
  },
  {'title': 'מחלקות ההגנה – חטיבה 474', 'isHidden': false},
  {'title': 'מיונים – כללי', 'isHidden': true}, // ✅ SOFT DELETE: Hidden from UI
  {'title': 'מיונים לקורס מדריכים', 'isHidden': false},
  {'title': 'משובים – כללי', 'isHidden': false},
  {
    'title': 'עבודה במבנה',
    'isHidden': true,
  }, // ✅ SOFT DELETE: Unused folder removed from UI
  {'title': 'משוב תרגילי הפתעה', 'isHidden': false},
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
  'אל-רום',
  'אניעם',
  'אפיק',
  'בני יהודה',
  'גבעת יואב',
  'גשור',
  'חד-נס',
  'חיספין',
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

    debugPrint('\n✅ ===== QUERY RESULTS =====');
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
      '📋 loadFeedbacksForCurrentUser: total ${feedbackStorage.length} feedbacks in storage',
    );
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
    return Scaffold(
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
          BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'משובים'),
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
          // Logout button in top left corner
          Positioned(
            top: 16,
            left: 16,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: ElevatedButton.icon(
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
      'מעגל פתוח',
      'מעגל פרוץ',
      'סריקות רחוב',
      'מיונים לקורס מדריכים',
      'מטווחים',
      'תרגילי הפתעה',
    ];

    return Scaffold(
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
                    Icon(Icons.assignment, size: 32, color: Colors.blueAccent),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        ex,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
          );
        },
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
  // Admin command fields
  String adminCommandText = '';
  String adminCommandStatus = 'פתוח';
  static const List<String> adminStatuses = ['פתוח', 'בטיפול', 'בוצע'];

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
        'commandText': adminCommandText,
        'commandStatus': adminCommandStatus,
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
                            child: Text(folder),
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
              // Admin command section
              if (currentUser?.role == 'Admin') ...[
                Card(
                  color: Colors.blueGrey.shade700,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'הנחיה פיקודית',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'טקסט פקודה (אופציונלי)',
                          ),
                          maxLines: 3,
                          onChanged: (v) => adminCommandText = v,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: adminCommandStatus,
                          decoration: const InputDecoration(
                            labelText: 'סטטוס הנחיה',
                          ),
                          items: adminStatuses
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => adminCommandStatus = v ?? adminCommandStatus,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
      } else if (_selectedFolder == 'משוב תרגילי הפתעה') {
        // Export surprise drills
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
    });
  }

  /// Check if any filter is active
  bool get _hasActiveFilters =>
      _filterSettlement != 'הכל' ||
      _filterExercise != 'הכל' ||
      _filterRole != 'הכל';

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
    final exercises = feedbacks
        .map((f) => f.exercise)
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

  /// Apply filters to a list of feedbacks (AND logic)
  List<FeedbackModel> _applyFilters(List<FeedbackModel> feedbacks) {
    return feedbacks.where((f) {
      // Settlement filter
      if (_filterSettlement != 'הכל') {
        if (f.settlement.isEmpty || f.settlement != _filterSettlement) {
          return false;
        }
      }
      // Exercise filter
      if (_filterExercise != 'הכל') {
        if (f.exercise.isEmpty || f.exercise != _filterExercise) {
          return false;
        }
      }
      // Role filter
      if (_filterRole != 'הכל') {
        if (f.role.isEmpty || f.role != _filterRole) {
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
              // כפתור ייצוא משובים - רק לאדמין
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () async {
                    try {
                      // Page defines the export schema (folders overview uses global schema)
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

                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await FeedbackExportService.exportWithSchema(
                          keys: keys,
                          headers: headers,
                          feedbacks: feedbackStorage,
                          fileNamePrefix: 'feedbacks_all',
                        );

                        if (!mounted) return;
                        final message = kIsWeb
                            ? 'הקובץ הורד בהצלחה'
                            : 'הקובץ נשמר בהורדות';
                        messenger.showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text('שגיאה בייצוא: $e')),
                        );
                      }
                    } catch (e) {
                      // outer catch (should never reach here)
                    }
                  },
                  tooltip: 'ייצוא נתונים',
                ),
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: _showRecentRangeSaves,
                  tooltip: 'Recent range saves',
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
          body: LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = constraints.maxWidth;
              final isMobile = screenWidth < 600;
              final isDesktop = screenWidth >= 1200;

              // Responsive typography using clamp-like calculations
              double getResponsiveFontSize(
                double minSize,
                double maxSize,
                double preferredSize,
              ) {
                if (isMobile) return minSize;
                if (isDesktop) return maxSize;
                // For tablet: interpolate between min and max
                final tabletRatio =
                    (screenWidth - 600) / (1200 - 600); // 0 to 1
                return minSize + (maxSize - minSize) * tabletRatio;
              }

              final folderTitleFontSize = getResponsiveFontSize(16, 22, 18);
              final countFontSize = getResponsiveFontSize(14, 18, 15);

              return Padding(
                padding: const EdgeInsets.all(12.0),
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isMobile ? 2 : 3,
                    crossAxisSpacing: isMobile ? 12 : 6,
                    mainAxisSpacing: isMobile ? 12 : 6,
                    childAspectRatio: isMobile ? 1.3 : 2.2,
                  ),
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
                    } else {
                      // Use internal value for filtering to match Firestore data
                      count = feedbackStorage
                          .where(
                            (f) =>
                                f.folder == folder || f.folder == internalValue,
                          )
                          .length;
                    }
                    final isInstructorCourse = folder == 'מיונים לקורס מדריכים';
                    // isMiunimCourse removed - folder is now hidden
                    return Card(
                      elevation: isMobile ? 4 : 2,
                      color: isInstructorCourse
                          ? Colors.purple.shade700
                          : Colors.blueGrey.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(isMobile ? 12 : 6),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(isMobile ? 12 : 6),
                        onTap: () {
                          if (isInstructorCourse) {
                            // Feedbacks view for instructor-course: only closed items via two category buttons
                            Navigator.of(context).pushNamed(
                              '/instructor_course_selection_feedbacks',
                            );
                          } else {
                            // Use internal value for navigation/filtering
                            setState(() => _selectedFolder = internalValue);
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.all(isMobile ? 12.0 : 4.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isInstructorCourse
                                    ? Icons.school
                                    : Icons.folder,
                                size: isMobile ? 48 : 20,
                                color: isInstructorCourse
                                    ? Colors.white
                                    : Colors.orangeAccent,
                              ),
                              SizedBox(height: isMobile ? 8 : 2),
                              Text(
                                folder,
                                textAlign: TextAlign.center,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: folderTitleFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: isMobile ? 4 : 1),
                              Text(
                                '$count משובים',
                                style: TextStyle(
                                  fontSize: countFontSize,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
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
      // SURPRISE DRILLS: Include BOTH new schema AND legacy docs
      filteredFeedbacks = feedbackStorage.where((f) {
        // Exclude temporary drafts
        if (f.isTemporary == true) return false;

        // NEW SCHEMA: Has module field populated
        if (f.module.isNotEmpty) {
          return f.module == 'surprise_drill';
        }

        // LEGACY SCHEMA: No module field, use folder
        return f.folder == _selectedFolder;
      }).toList();
      debugPrint(
        '\n========== SURPRISE DRILLS FILTER (BACKWARD-COMPATIBLE) ==========',
      );
      debugPrint('Total feedbacks in storage: ${feedbackStorage.length}');
      debugPrint('Filtered surprise drills: ${filteredFeedbacks.length}');
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
    } else if (_selectedFolder == '474 Ranges') {
      // ✅ FIX: 474 RANGES MUST EXCLUDE temporary docs
      // Query logic: module==shooting_ranges AND folderKey==ranges_474 AND isTemporary==false
      filteredFeedbacks = feedbackStorage.where((f) {
        // ❌ CRITICAL: Exclude ALL temporary/draft feedbacks
        if (f.isTemporary == true) return false;

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
    } else {
      // Other folders: use standard folder filtering + exclude temporary
      filteredFeedbacks = feedbackStorage
          .where((f) => f.folder == _selectedFolder && f.isTemporary == false)
          .toList();
    }

    final isRangeFolder =
        _selectedFolder == 'מטווחי ירי' || _selectedFolder == '474 Ranges';

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
                    _selectedFolder == 'משוב תרגילי הפתעה') &&
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
                          _selectedFolder == 'משוב תרגילי הפתעה'))
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
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    initialValue:
                                        settlementOptions.contains(
                                          _filterSettlement,
                                        )
                                        ? _filterSettlement
                                        : 'הכל',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'יישוב',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    items: settlementOptions
                                        .map(
                                          (s) => DropdownMenuItem(
                                            value: s,
                                            child: Text(
                                              s,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _filterSettlement = v ?? 'הכל',
                                    ),
                                  ),
                                ),
                              // Exercise filter
                              if (exerciseOptions.length > 1)
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    initialValue:
                                        exerciseOptions.contains(
                                          _filterExercise,
                                        )
                                        ? _filterExercise
                                        : 'הכל',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'תרגיל',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    items: exerciseOptions
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(
                                              e,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _filterExercise = v ?? 'הכל',
                                    ),
                                  ),
                                ),
                              // Role filter
                              if (roleOptions.length > 1)
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    initialValue:
                                        roleOptions.contains(_filterRole)
                                        ? _filterRole
                                        : 'הכל',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'תפקיד',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    items: roleOptions
                                        .map(
                                          (r) => DropdownMenuItem(
                                            value: r,
                                            child: Text(
                                              r,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _filterRole = v ?? 'הכל',
                                    ),
                                  ),
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
                          if (f.exercise.isNotEmpty) {
                            metadataLines.add('תרגיל: ${f.exercise}');
                          }
                          if (f.instructorName.isNotEmpty) {
                            metadataLines.add('מדריך: ${f.instructorName}');
                          }
                          if (f.attendeesCount > 0) {
                            metadataLines.add('משתתפים: ${f.attendeesCount}');
                          }
                          metadataLines.add('תאריך: $dateStr');

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

                          // Check delete permissions
                          final canDelete =
                              currentUser?.role == 'Admin' ||
                              f.instructorName == currentUser?.name;

                          // Check if folder supports selection mode
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
  String editCommandText = '';
  String editCommandStatus = 'פתוח';
  String? resolvedInstructorName; // Cached resolved name
  bool isResolvingName = false;

  @override
  void initState() {
    super.initState();
    feedback = widget.feedback;
    editCommandText = feedback.commandText;
    editCommandStatus = feedback.commandStatus;
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

  bool _isEditingCommand = false;
  bool _isSaving = false;
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

  Future<void> _saveCommandChanges() async {
    if (feedback.id == null || feedback.id!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('לא ניתן לעדכן משוב ללא מזהה')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(feedback.id)
          .update({
            'commandText': editCommandText,
            'commandStatus': editCommandStatus,
          });

      setState(() {
        feedback = feedback.copyWith(
          commandText: editCommandText,
          commandStatus: editCommandStatus,
        );
        _isEditingCommand = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('הנחיה פיקודית עודכנה')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('שגיאה בעדכון: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = feedback.createdAt.toLocal().toString().split('.').first;
    final canViewCommand =
        currentUser != null &&
        (currentUser?.role == 'Admin' || currentUser?.role == 'Instructor');
    final isAdmin = currentUser?.role == 'Admin';
    final is474Ranges =
        feedback.folder == 'מטווחים 474' ||
        feedback.folder == '474 Ranges' ||
        feedback.folderKey == 'ranges_474';

    return Scaffold(
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
            // Conditional display: "טווח:" for ranges, nothing for surprise drills, "תפקיד:" for others
            if (feedback.folderKey == 'shooting_ranges' ||
                feedback.folderKey == 'ranges_474' ||
                feedback.folder == 'מטווחי ירי' ||
                feedback.folder == 'מטווחים 474' ||
                feedback.module == 'shooting_ranges')
              Text(
                'טווח: ${feedback.rangeSubType.isNotEmpty ? feedback.rangeSubType : 'לא ידוע'}',
              )
            else if (feedback.folder == 'משוב תרגילי הפתעה' ||
                feedback.module == 'surprise_drill')
              const SizedBox.shrink() // No role display for surprise drills
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
                          debugPrint('   ❌ No snapshot data or doc not exists');
                          return const SizedBox.shrink();
                        }

                        final data =
                            snapshot.data!.data() as Map<String, dynamic>?;
                        if (data == null) {
                          debugPrint('   ❌ Snapshot data is null');
                          return const SizedBox.shrink();
                        }

                        debugPrint('   ✅ Document keys: ${data.keys.toList()}');

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
                                      headingRowColor: WidgetStateProperty.all(
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
                                          final avg = sum / filledValues.length;
                                          // Format: integer without decimals, otherwise 1 decimal
                                          if (avg == avg.toInt()) {
                                            avgDisplay = avg.toInt().toString();
                                          } else {
                                            avgDisplay = avg.toStringAsFixed(1);
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
                          debugPrint('   ❌ No snapshot data or doc not exists');
                          return const SizedBox.shrink();
                        }

                        final data =
                            snapshot.data!.data() as Map<String, dynamic>?;
                        if (data == null) {
                          debugPrint('   ❌ Snapshot data is null');
                          return const SizedBox.shrink();
                        }

                        debugPrint('   ✅ Document keys: ${data.keys.toList()}');

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

                        if (stations.isEmpty || trainees.isEmpty) {
                          debugPrint(
                            '   ⚠️ Either stations or trainees are empty',
                          );
                          return Card(
                            color: Colors.blueGrey.shade800,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Text(
                                    'מטווח 474 - אין נתונים מפורטים',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'מקצים: ${stations.length}, חניכים: ${trainees.length}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
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
                                  (station['maxPoints'] as num?)?.toInt() ?? 0;
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
                                (station['maxScorePoints'] as num?)?.toInt() ??
                                0;
                            final legacyMaxPoints =
                                (station['maxPoints'] as num?)?.toInt() ?? 0;
                            final bulletsTracking =
                                (station['bulletsCount'] as num?)?.toInt() ?? 0;

                            debugPrint('   Stage[$i]: "$stageName"');
                            debugPrint('      maxScorePoints: $maxScorePoints');
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
                          debugPrint('      N (trainees): ${trainees.length}');
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
                                (station['bulletsCount'] as num?)?.toInt() ?? 0;
                          }
                          totalMax = trainees.length * totalBulletsPerTrainee;
                        }

                        // חישוב אחוז כללי
                        final percentage = totalMax > 0
                            ? ((totalValue / totalMax) * 100).toStringAsFixed(1)
                            : '0.0';

                        // ✅ LONG RANGE: Calculate total bullets fired (tracking only)
                        int totalBulletsFired = 0;
                        if (isLongRange) {
                          for (final station in stations) {
                            final bulletsTracking =
                                (station['bulletsCount'] as num?)?.toInt() ?? 0;
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
                                                  const Text('אחוז פגיעה כללי'),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '$percentage%',
                                                    style: const TextStyle(
                                                      fontSize: 32,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.greenAccent,
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
                                                    fontWeight: FontWeight.bold,
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
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orangeAccent,
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
                                                    fontWeight: FontWeight.bold,
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
                                (station['bulletsCount'] as num?)?.toInt() ?? 0;
                          }
                          totalMax = trainees.length * totalBulletsPerTrainee;
                        }

                        // חישוב אחוז כללי
                        final percentage = totalMax > 0
                            ? ((totalValue / totalMax) * 100).toStringAsFixed(1)
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
                                                  const Text('אחוז פגיעה כללי'),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '$percentage%',
                                                    style: const TextStyle(
                                                      fontSize: 32,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.greenAccent,
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
                                      trainee['hits'] as Map<String, dynamic>?;
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
                                      trainee['hits'] as Map<String, dynamic>?;
                                  if (hits != null) {
                                    stationValue +=
                                        (hits['station_$index'] as num?)
                                            ?.toInt() ??
                                        0;
                                  }
                                }

                                // ✅ חישוב נכון: מספר חניכים × כדורים במקצה
                                stationMax =
                                    trainees.length * stationBulletsPerTrainee;
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
                                                    fontWeight: FontWeight.bold,
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
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orangeAccent,
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
                                                      color: Colors.greenAccent,
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
            // Command box (visible to Admin + Instructors)
            if (canViewCommand) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.blueGrey.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'הנחיה פיקודית',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (isAdmin)
                            IconButton(
                              icon: Icon(
                                _isEditingCommand ? Icons.close : Icons.edit,
                              ),
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(() {
                                        _isEditingCommand = !_isEditingCommand;
                                        if (!_isEditingCommand) {
                                          // Reset to original values on cancel
                                          editCommandText =
                                              feedback.commandText;
                                          editCommandStatus =
                                              feedback.commandStatus;
                                        }
                                      });
                                    },
                              tooltip: _isEditingCommand ? 'ביטול' : 'עריכה',
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_isEditingCommand) ...[
                        TextField(
                          controller:
                              TextEditingController(text: editCommandText)
                                ..selection = TextSelection.collapsed(
                                  offset: editCommandText.length,
                                ),
                          decoration: const InputDecoration(
                            labelText: 'טקסט הנחיה',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                          onChanged: (v) => editCommandText = v,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: editCommandStatus,
                          decoration: const InputDecoration(
                            labelText: 'סטטוס',
                            border: OutlineInputBorder(),
                          ),
                          items: const ['פתוח', 'בטיפול', 'בוצע']
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => editCommandStatus = v ?? editCommandStatus,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveCommandChanges,
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('שמור שינויים'),
                        ),
                      ] else ...[
                        Text(
                          feedback.commandText.isNotEmpty
                              ? feedback.commandText
                              : '-',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'סטטוס: ${feedback.commandStatus}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () async {
                          setState(() => _isExporting = true);
                          try {
                            final messenger = ScaffoldMessenger.of(context);

                            // Check if this is a range/reporter feedback
                            final isRangeFeedback =
                                (feedback.folder == 'מטווחי ירי' ||
                                    feedback.folder == 'מטווחים 474' ||
                                    feedback.folderKey == 'shooting_ranges' ||
                                    feedback.folderKey == 'ranges_474') &&
                                feedback.id != null &&
                                feedback.id!.isNotEmpty;

                            if (isRangeFeedback) {
                              // Use reporter comparison export for range feedbacks
                              try {
                                // Fetch full document data from Firestore
                                final doc = await FirebaseFirestore.instance
                                    .collection('feedbacks')
                                    .doc(feedback.id)
                                    .get();

                                if (!doc.exists || doc.data() == null) {
                                  throw Exception('לא נמצאו נתוני משוב');
                                }

                                final feedbackData = doc.data()!;

                                // Check if this feedback has trainee comparison data
                                final hasComparisonData =
                                    feedbackData['stations'] != null &&
                                    feedbackData['trainees'] != null;

                                if (hasComparisonData) {
                                  await FeedbackExportService.exportReporterComparisonToGoogleSheets(
                                    feedbackData: feedbackData,
                                    fileNamePrefix: 'reporter_comparison',
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
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            } else {
                              // DEDICATED export for single feedback details ("פרטי משוב" screen)
                              // Structure: סוג משוב, שם המדריך המשב, שם, תפקיד, חטיבה, יישוב, תאריך
                              // Then ONLY criteria that exist in THIS feedback
                              // Then ציון ממוצע, then הערות
                              try {
                                debugPrint(
                                  '📊 Exporting single feedback details',
                                );
                                debugPrint('   Screen: פרטי משוב');
                                debugPrint(
                                  '   Feedback: ${feedback.name} (${feedback.exercise})',
                                );

                                await FeedbackExportService.exportSingleFeedbackDetails(
                                  feedback: feedback,
                                  fileNamePrefix: 'משוב_${feedback.name}',
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
                                debugPrint('❌ Export error: $e');
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('שגיאה בייצוא: $e'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 5),
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
              ),
            ],
          ],
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
  String personFilter = '';
  DateTime? dateFrom;
  DateTime? dateTo;

  List<FeedbackModel> getFiltered() {
    final isAdmin = currentUser?.role == 'Admin';
    return feedbackStorage.where((f) {
      // instructor permission: non-admins (instructors) only see feedback they submitted
      if (!isAdmin) {
        if (currentUser == null) return false;
        if (currentUser?.role == 'Instructor' &&
            f.instructorName != (currentUser?.name ?? '')) {
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
      locale: const Locale('he'),
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
      locale: const Locale('he'),
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
      // instructor permission: non-admins (instructors) only see feedback they submitted
      if (!isAdmin) {
        if (currentUser == null) return false;
        if (currentUser?.role == 'Instructor' &&
            f.instructorName != (currentUser?.name ?? '')) {
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
      locale: const Locale('he'),
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
      locale: const Locale('he'),
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
    final exercises = <String>{'כל התרגילים'}
      ..addAll(feedbackStorage.map((f) => f.exercise));
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
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Role filter (admin only)
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final items = availableRoles.toSet().toList();
                                final value = items.contains(selectedRoleFilter)
                                    ? selectedRoleFilter
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'תפקיד',
                                    isDense: true,
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

                          // Person filter (free text)
                          SizedBox(
                            width: 200,
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'שם הנבדק',
                              ),
                              onChanged: (v) =>
                                  setState(() => personFilter = v),
                            ),
                          ),

                          // Instructor filter
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final items = instructors.toSet().toList();
                                final value = items.contains(selectedInstructor)
                                    ? selectedInstructor
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'מדריך ממשב',
                                    isDense: true,
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

                          // Exercise filter
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final items = exercises.toSet().toList();
                                final value = items.contains(selectedExercise)
                                    ? selectedExercise
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'תרגיל',
                                    isDense: true,
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
                                    () => selectedExercise = v ?? 'כל התרגילים',
                                  ),
                                );
                              },
                            ),
                          ),

                          // Settlement filter (for all users)
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
                                final value = items.contains(selectedSettlement)
                                    ? selectedSettlement
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'יישוב',
                                    isDense: true,
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
                                        selectedSettlement = v ?? 'כל היישובים',
                                  ),
                                );
                              },
                            ),
                          ),

                          // Folder filter (restricted to משובים scope)
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
                                final items = folders;
                                final value = items.contains(selectedFolder)
                                    ? selectedFolder
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value ?? 'הכל',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'תיקייה',
                                    isDense: true,
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
                                    // Do NOT auto-reset settlement - user controls it via settlement filter
                                  }),
                                );
                              },
                            ),
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
  String personFilter = '';
  String searchText = '';
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

  List<FeedbackModel> getFiltered() {
    final isAdmin = currentUser?.role == 'Admin';
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

      // instructor permission: non-admins (instructors) only see feedback they submitted
      if (!isAdmin) {
        if (currentUser == null) return false;
        if (currentUser?.role == 'Instructor' &&
            f.instructorName != (currentUser?.name ?? '')) {
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
      if (personFilter.isNotEmpty && !f.name.contains(personFilter)) {
        return false;
      }
      if (dateFrom != null && f.createdAt.isBefore(dateFrom!)) return false;
      if (dateTo != null && f.createdAt.isAfter(dateTo!)) return false;

      // Free text search
      if (searchText.isNotEmpty) {
        final searchLower = searchText.toLowerCase();
        final nameMatch = f.name.toLowerCase().contains(searchLower);
        final settlementMatch = f.settlement.toLowerCase().contains(
          searchLower,
        );
        final scenarioMatch = f.scenario.toLowerCase().contains(searchLower);
        final dateMatch = f.createdAt
            .toLocal()
            .toString()
            .split('.')
            .first
            .toLowerCase()
            .contains(searchLower);
        if (!nameMatch && !settlementMatch && !scenarioMatch && !dateMatch) {
          return false;
        }
      }

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
      locale: const Locale('he'),
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
      locale: const Locale('he'),
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
    for (final f in filtered) {
      if (f.settlement.isNotEmpty && rangeData.containsKey(f.id)) {
        final data = rangeData[f.id];
        final stations =
            (data?['stations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final trainees =
            (data?['trainees'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        int feedbackTotalBullets = 0;
        for (final station in stations) {
          feedbackTotalBullets +=
              ((station['bulletsCount'] as num?)?.toInt() ?? 0) *
              trainees.length;
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
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Folder filter (restricted to range folders)
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
                                  decoration: const InputDecoration(
                                    labelText: 'תיקייה',
                                    isDense: true,
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

                          // Range type filter
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
                                final value = items.contains(selectedRangeType)
                                    ? selectedRangeType
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value ?? 'הכל',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'סוג מטווח',
                                    isDense: true,
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

                          // Person filter (free text)
                          SizedBox(
                            width: 200,
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'שם הנבדק',
                              ),
                              onChanged: (v) =>
                                  setState(() => personFilter = v),
                            ),
                          ),

                          // Instructor filter
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final items = instructors.toSet().toList();
                                final value = items.contains(selectedInstructor)
                                    ? selectedInstructor
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'מדריך ממשב',
                                    isDense: true,
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

                          // Settlement filter
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
                                final value = items.contains(selectedSettlement)
                                    ? selectedSettlement
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'יישוב',
                                    isDense: true,
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
                                        selectedSettlement = v ?? 'כל היישובים',
                                  ),
                                );
                              },
                            ),
                          ),

                          // Station filter
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
                                            ?.cast<Map<String, dynamic>>() ??
                                        [];
                                    for (final station in stations) {
                                      final stationName =
                                          station['name'] as String? ?? '';
                                      if (stationName.isNotEmpty &&
                                          !stationNames.contains(stationName)) {
                                        stationNames.add(stationName);
                                        orderedStations.add(stationName);
                                      }
                                    }
                                  }
                                }

                                final items = ['כל המקצים'] + orderedStations;
                                final value = items.contains(selectedStation)
                                    ? selectedStation
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'מקצה',
                                    isDense: true,
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
                                    () => selectedStation = v ?? 'כל המקצים',
                                  ),
                                );
                              },
                            ),
                          ),

                          // Free text search
                          SizedBox(
                            width: 280,
                            child: TextField(
                              decoration: InputDecoration(
                                labelText:
                                    'חיפוש לפי שוב / יישוב / מקצה / תאריך',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: searchText.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () =>
                                            setState(() => searchText = ''),
                                      )
                                    : null,
                                isDense: true,
                              ),
                              onChanged: (v) => setState(() => searchText = v),
                            ),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                            '$totalHits מתוך $totalBullets כדורים ($percentage%)',
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // New graph for station totals
              Builder(
                builder: (ctx) {
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
                        final stationName = station['name'] ?? 'מקצה ${i + 1}';
                        final bulletsPerTrainee =
                            (station['bulletsCount'] as num?)?.toInt() ?? 0;
                        final totalBulletsForStation =
                            trainees.length * bulletsPerTrainee;
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
                                  '$totalHits מתוך $totalBullets כדורים ($percentage%)',
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

  List<FeedbackModel> getFiltered() {
    final isAdmin = currentUser?.role == 'Admin';
    return feedbackStorage.where((f) {
      // Only surprise drills feedbacks
      if (f.folder != 'משוב תרגילי הפתעה' && f.module != 'surprise_drill') {
        return false;
      }

      // Exclude temporary drafts
      if (f.isTemporary == true) return false;

      // Instructor permission
      if (!isAdmin) {
        if (currentUser == null) return false;
        if (currentUser?.role == 'Instructor' &&
            f.instructorName != (currentUser?.name ?? '')) {
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
      if (selectedFolder != 'הכל' && f.folder != selectedFolder) {
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
      locale: const Locale('he'),
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
      locale: const Locale('he'),
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
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Instructor filter
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final items = instructors.toSet().toList();
                                final value = items.contains(selectedInstructor)
                                    ? selectedInstructor
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'מדריך ממשב',
                                    isDense: true,
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

                          // Settlement filter
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final items = settlements.toSet().toList();
                                final value = items.contains(selectedSettlement)
                                    ? selectedSettlement
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'יישוב',
                                    isDense: true,
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
                                        selectedSettlement = v ?? 'כל היישובים',
                                  ),
                                );
                              },
                            ),
                          ),

                          // Principle filter
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final items = principles;
                                final value = items.contains(selectedPrinciple)
                                    ? selectedPrinciple
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'עיקרון',
                                    isDense: true,
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
                                        selectedPrinciple = v ?? 'כל העקרונות',
                                  ),
                                );
                              },
                            ),
                          ),

                          // Folder filter
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final folders = <String>[
                                  'הכל',
                                  'משוב תרגילי הפתעה',
                                ];
                                final items = folders;
                                final value = items.contains(selectedFolder)
                                    ? selectedFolder
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value ?? 'הכל',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'תיקייה',
                                    isDense: true,
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
                        style: TextStyle(fontSize: 16, height: 1.5),
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
                        style: TextStyle(fontSize: 16, height: 1.5),
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
                        style: TextStyle(fontSize: 16, height: 1.5),
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
                    'מי שרואה אותי – הורג אותי | מי שלא רואה אותי – מת ממני',
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
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '2. היערכות להגנה והתקפת נגד',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
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
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'שחרור שטח שנכבש, הדיפת האויב או השמדתו, הצלת התושבים באזור זה.',
                        style: TextStyle(fontSize: 16, height: 1.5),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'פשיטות ומארבים –',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'פעולות מקומיות לפגיעה באויב או להצלת תושבים',
                        style: TextStyle(fontSize: 16, height: 1.5),
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

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('אודות המערכת'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
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

                // Version
                const Text(
                  'גרסה 1.0.0',
                  style: TextStyle(fontSize: 18, color: Colors.black54),
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
