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
import 'voice_assistant.dart';
import 'range_selection_page.dart';
import 'feedback_export_service.dart';
import 'export_selection_page.dart';
import 'universal_export_page.dart';

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
const List<String> feedbackFolders = <String>[
  'מטווחי ירי',
  'מחלקות ההגנה – חטיבה 474',
  'מיונים – כללי',
  'מיונים לקורס מדריכים',
  'משובים – כללי',
  'עבודה במבנה',
  'משובים זמניים', // Temporary Feedbacks
];

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
        appBar: AppBar(title: const Text('מדד כשירות')),
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

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';
    if (!isAdmin) return const Scaffold(body: Center(child: Text('אין הרשאה')));
    final alerts = ReadinessService.generateAlerts(feedbackStorage);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('התראות מבצעיות')),
        body: ListView(
          children: alerts.map((a) {
            if (a.containsKey('who')) {
              return ListTile(
                title: Text('נפילה מעל 10%: ${a['who']}'),
                subtitle: Text('מ ${a['from']} ל ${a['to']} — ${a['drop']}'),
              );
            }
            return ListTile(
              title: Text('קטגוריה חלשה: ${a['category']}'),
              subtitle: Text('ממוצע ${a['avg']}'),
            );
          }).toList(),
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
        appBar: AppBar(title: const Text('לוח מבצע')),
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

  void _handleVoiceCommand(String command) {
    VoiceCommandHandler.handleCommand(
      context,
      command,
      selectedIndex,
      _handleFeedbackFilter,
      _handleStatisticsFilter,
      _handleExerciseAction,
      _handleMaterialsAction,
      _handleNavigateBack,
      _handleNavigateToPage,
    );
  }

  void _handleNavigateBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      debugPrint('🔙 Voice Command: Navigate back');
    } else {
      debugPrint('⚠️ Voice Command: Cannot pop, no route to go back');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אין לאן לחזור'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleNavigateToPage(int pageIndex) {
    if (pageIndex >= 0 && pageIndex < _pages.length) {
      setState(() => selectedIndex = pageIndex);
      debugPrint('📡 Voice Command: Navigate to page $pageIndex');
    } else {
      debugPrint('⚠️ Voice Command: Invalid page index $pageIndex');
    }
  }

  void _handleFeedbackFilter(String filter) {
    // Navigate to feedbacks page and apply filter
    setState(() => selectedIndex = 2);
    debugPrint('Feedback filter: $filter');

    // Wait for page to build, then execute action
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      // Action: Open first feedback
      if (filter == 'action_open_first_feedback') {
        if (feedbackStorage.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('אין משובים')));
          return;
        }
        // Sort by date (oldest first) and open first
        final sortedFeedbacks = List<FeedbackModel>.from(feedbackStorage)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        Navigator.of(
          context,
        ).pushNamed('/feedback_details', arguments: sortedFeedbacks.first);
        return;
      }

      // Action: Open last feedback
      if (filter == 'action_open_last_feedback') {
        if (feedbackStorage.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('אין משובים')));
          return;
        }
        // Sort by date (newest first) and open first
        final sortedFeedbacks = List<FeedbackModel>.from(feedbackStorage)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        Navigator.of(
          context,
        ).pushNamed('/feedback_details', arguments: sortedFeedbacks.first);
        return;
      }

      // Action: Search feedback by name
      if (filter.startsWith('search_feedback_')) {
        final name = filter.replaceFirst('search_feedback_', '');
        final matchingFeedbacks = feedbackStorage
            .where((f) => f.name.contains(name))
            .toList();
        if (matchingFeedbacks.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('לא נמצאו משובים עבור $name')));
        } else if (matchingFeedbacks.length == 1) {
          // Open the single matching feedback
          Navigator.of(
            context,
          ).pushNamed('/feedback_details', arguments: matchingFeedbacks.first);
        } else {
          // Multiple matches - show count
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'נמצאו ${matchingFeedbacks.length} משובים עבור $name',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Action: Open any feedback (generic)
      if (filter == 'action_open_feedback') {
        if (feedbackStorage.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('אין משובים')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('לחץ על משוב ברשימה לפתיחה'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Existing filter logic remains unchanged
    });
  }

  void _handleStatisticsFilter(String filter) {
    // Navigate to statistics page
    setState(() => selectedIndex = 3);
    debugPrint('Statistics filter: $filter');

    // Wait for page to build, then apply filter
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final statisticsState = _statisticsKey.currentState;
      if (statisticsState == null) return;

      // Action: Count feedbacks
      if (filter == 'action_count_feedbacks') {
        final total = feedbackStorage.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('סך הכל: $total משובים'),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Action: Count instructor course feedbacks
      if (filter == 'action_count_instructor_feedbacks') {
        final count = feedbackStorage
            .where((f) => f.folder == 'מיונים לקורס מדריכים')
            .length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('משובי קורס מדריכים: $count'),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Action: Count exercise feedbacks (for current filtered exercise)
      if (filter == 'action_count_exercise_feedbacks') {
        final currentExercise = statisticsState.selectedExercise;
        if (currentExercise == 'כל התרגילים') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('אנא בחר תרגיל קודם'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          final count = feedbackStorage
              .where((f) => f.exercise == currentExercise)
              .length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('משובים ב$currentExercise: $count'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Action: Clear all filters
      if (filter == 'action_clear_filters') {
        statisticsState.setState(() {
          statisticsState.selectedRoleFilter = 'כל התפקידים';
          statisticsState.selectedInstructor = 'כל המדריכים';
          statisticsState.selectedExercise = 'כל התרגילים';
          statisticsState.selectedSettlement = 'כל היישובים';
          statisticsState.selectedFolder = 'כל התיקיות';
          statisticsState.personFilter = '';
          statisticsState.dateFrom = null;
          statisticsState.dateTo = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('כל הסינונים אופסו'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Action: Open date filter (placeholder - manual action needed)
      if (filter == 'action_filter_by_date') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('לחץ על כפתורי התאריך לבחירה'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      statisticsState.setState(() {
        if (filter.contains('folder_')) {
          // Extract folder name from filter
          if (filter.contains('matawhim')) {
            statisticsState.selectedFolder = 'מטווחי ירי';
          } else if (filter.contains('hativah')) {
            statisticsState.selectedFolder = 'מחלקות ההגנה – חטיבה 474';
          } else if (filter.contains('binyan')) {
            statisticsState.selectedFolder = 'עבודה במבנה';
          } else if (filter.contains('mioonim_madrichim')) {
            statisticsState.selectedFolder = 'מיונים לקורס מדריכים';
          } else if (filter.contains('mioonim')) {
            statisticsState.selectedFolder = 'מיונים – כללי';
          } else if (filter.contains('general')) {
            statisticsState.selectedFolder = 'משובים – כללי';
          }
        } else if (filter == 'filter_by_role') {
          // Can't automatically select role without knowing which one
          // User needs to specify in voice command
        } else if (filter.contains('settlement_')) {
          // Extract settlement name
          final settlement = filter.replaceFirst('settlement_', '');
          statisticsState.selectedSettlement = settlement;
        } else if (filter.contains('exercise_')) {
          // Filter by exercise
          final exercise = filter.replaceFirst('exercise_', '');
          if (exercise == 'maagal_patuach') {
            statisticsState.selectedExercise = 'מעגל פתוח';
          } else if (exercise == 'maagal_poruz') {
            statisticsState.selectedExercise = 'מעגל פרוץ';
          } else if (exercise == 'sarikot') {
            statisticsState.selectedExercise = 'סריקות רחוב';
          }
        } else if (filter.contains('mioonim')) {
          // מיונים – כללי בוטל; לא מבצעים פעולה
          // השארנו במכוון ללא שינוי כדי להסיר רפרנס
        }
      });
    });
  }

  void _handleExerciseAction(String action) {
    // Navigate to exercises page first
    setState(() => selectedIndex = 1);
    debugPrint('Exercise action: $action');

    // Wait for page to build, then open the specific exercise
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      if (action == 'open_maagal_patuach') {
        Navigator.of(
          context,
        ).pushNamed('/feedback_form', arguments: 'מעגל פתוח');
      } else if (action == 'open_maagal_poruz') {
        Navigator.of(
          context,
        ).pushNamed('/feedback_form', arguments: 'מעגל פרוץ');
      } else if (action == 'open_sarikot') {
        Navigator.of(
          context,
        ).pushNamed('/feedback_form', arguments: 'סריקות רחוב');
      } else if (action == 'open_instructor_selection') {
        Navigator.of(context).pushNamed('/screenings_menu');
      }
    });
  }

  void _handleMaterialsAction(String action) {
    // Navigate to materials page first
    setState(() => selectedIndex = 4);
    debugPrint('Materials action: $action');

    // Wait for page to build, then open the specific material
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      if (action == 'open_maagal_patuach') {
        Navigator.of(context).pushNamed('/maagal_patuach');
      } else if (action == 'open_maagal_poruz') {
        Navigator.of(context).pushNamed('/poruz');
      } else if (action == 'open_sarikot') {
        Navigator.of(context).pushNamed('/sarikot');
      } else if (action == 'open_sheva') {
        Navigator.of(context).pushNamed('/sheva');
      } else if (action == 'open_saabal') {
        Navigator.of(context).pushNamed('/saabal');
      }
    });
  }

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
          // Voice Assistant Button - Fixed position bottom-left (safe zone)
          Positioned(
            bottom: 90,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: VoiceAssistantButton(onVoiceCommand: _handleVoiceCommand),
            ),
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
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('תרגילים')),
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

  // available criteria (user-selectable)
  final List<String> availableCriteria = [
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
    for (final c in availableCriteria) {
      scores[c] = 0;
      notes[c] = '';
      activeCriteria[c] = false; // do NOT display by default
    }
  }

  @override
  void dispose() {
    super.dispose();
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
      final Map<String, dynamic> doc = {
        'role': selectedRole,
        'name': evaluatedName.trim(),
        'exercise': selectedExercise ?? '',
        'scores': finalScores,
        'notes': finalNotes,
        'criteriaList': criteriaList,
        'createdAt': now,
        'instructorName': instructorNameDisplay,
        'instructorRole': instructorRoleDisplay,
        'commandText': adminCommandText,
        'commandStatus': adminCommandStatus,
        'folder': selectedFolder ?? '',
        'scenario': scenario,
        'settlement': settlement,
        'attendeesCount': 0,
        'instructorId': currentUser?.uid ?? '',
      };

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
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
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
                  return DropdownButtonFormField<String>(
                    initialValue: selectedFolder,
                    hint: const Text('בחר תיקייה (חובה)'),
                    decoration: const InputDecoration(
                      labelText: 'תיקייה',
                      border: OutlineInputBorder(),
                    ),
                    items: feedbackFolders
                        .where((folder) => folder != 'מיונים לקורס מדריכים')
                        .map(
                          (folder) => DropdownMenuItem(
                            value: folder,
                            child: Text(folder),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      selectedFolder = v;
                      // איפוס יישוב אם התיקייה השתנתה מ"מחלקות ההגנה – חטיבה 474"
                      if (selectedFolder != 'מחלקות ההגנה – חטיבה 474') {
                        settlement = '';
                      }
                    }),
                  );
                },
              ),
              const SizedBox(height: 12),

              // יישוב (מוצג רק כאשר נבחרה המחלקה "מחלקות ההגנה – חטיבה 474")
              if (selectedFolder == 'מחלקות ההגנה – חטיבה 474') ...[
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
                    labelText: 'יישוב',
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
              ],

              // 2. תפקיד
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

              // 3. שם הנבדק
              TextField(
                decoration: const InputDecoration(
                  labelText: 'שם הנבדק',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => evaluatedName = v,
              ),
              const SizedBox(height: 12),

              // 4. יישוב (Dropdown בלבד)
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
                  labelText: 'יישוב',
                  border: OutlineInputBorder(),
                ),
                items: golanSettlements
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => settlement = v ?? ''),
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
                      await FeedbackExportService.exportAllFeedbacksToXlsx();
                      if (!mounted) return;
                      final message = kIsWeb
                          ? 'הקובץ הורד בהצלחה'
                          : 'הקובץ נשמר בהורדות';
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('שגיאה בייצוא: $e')),
                      );
                    }
                  },
                  tooltip: 'ייצוא נתונים',
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
                    childAspectRatio: isMobile ? 1.5 : 2.2,
                  ),
                  itemCount: feedbackFolders.length,
                  itemBuilder: (ctx, i) {
                    final folder = feedbackFolders[i];
                    // Count feedbacks: regular + old feedbacks without folder (assigned to "משובים – כללי")
                    int count;
                    if (folder == 'משובים – כללי') {
                      count = feedbackStorage
                          .where((f) => f.folder == folder || f.folder.isEmpty)
                          .length;
                    } else {
                      count = feedbackStorage
                          .where((f) => f.folder == folder)
                          .length;
                    }
                    final isInstructorCourse = folder == 'מיונים לקורס מדריכים';
                    final isMiunimCourse = folder == 'מיונים – כללי';
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
                          } else if (isMiunimCourse) {
                            // ניווט למסך מיונים כללי
                            Navigator.of(context).pushNamed('/screenings_menu');
                          } else {
                            setState(() => _selectedFolder = folder);
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.all(isMobile ? 12.0 : 4.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isInstructorCourse || isMiunimCourse
                                    ? Icons.school
                                    : Icons.folder,
                                size: isMobile ? 48 : 20,
                                color: (isInstructorCourse || isMiunimCourse)
                                    ? Colors.white
                                    : Colors.orangeAccent,
                              ),
                              SizedBox(height: isMobile ? 8 : 2),
                              Text(
                                folder,
                                textAlign: TextAlign.center,
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
    // Include old feedbacks without folder in "משובים – כללי"
    final filteredFeedbacks = _selectedFolder == 'משובים – כללי'
        ? feedbackStorage
              .where((f) => f.folder == _selectedFolder || f.folder.isEmpty)
              .toList()
        : feedbackStorage.where((f) => f.folder == _selectedFolder).toList();

    final isRangeFolder = _selectedFolder == 'מטווחי ירי';

    // Apply settlement filter for range feedbacks
    List<FeedbackModel> finalFilteredFeedbacks = filteredFeedbacks;
    if (isRangeFolder) {
      finalFilteredFeedbacks = filteredFeedbacks
          .where(
            (f) =>
                selectedSettlement == 'כל היישובים' ||
                f.settlement == selectedSettlement,
          )
          .toList();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedFolder!),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => setState(() => _selectedFolder = null),
            tooltip: 'חזרה לתיקיות',
          ),
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
        body: finalFilteredFeedbacks.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('אין משובים בתיקייה זו'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _selectedFolder = null),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('חזרה לתיקיות'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (isRangeFolder)
                    Card(
                      color: Colors.blueGrey.shade800,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: 240,
                              child: Builder(
                                builder: (ctx) {
                                  final items =
                                      ['כל היישובים'] + golanSettlements;
                                  final value =
                                      items.contains(selectedSettlement)
                                      ? selectedSettlement
                                      : null;
                                  return DropdownButtonFormField<String>(
                                    initialValue: value,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'בחירת יישוב',
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
                                      () => selectedSettlement =
                                          v ?? 'כל היישובים',
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: finalFilteredFeedbacks.length,
                      itemBuilder: (_, i) {
                        final f = finalFilteredFeedbacks[i];
                        final date = f.createdAt
                            .toLocal()
                            .toString()
                            .split('.')
                            .first;
                        return ListTile(
                          title: Text('${f.role} — ${f.name}'),
                          subtitle: Text(
                            '${f.exercise} • ${f.instructorName.isNotEmpty ? '${f.instructorName} • ' : ''}$date',
                          ),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/feedback_details', arguments: f),
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

  @override
  void initState() {
    super.initState();
    feedback = widget.feedback;
    editCommandText = feedback.commandText;
    editCommandStatus = feedback.commandStatus;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('פרטי משוב'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.pop(context),
          tooltip: 'חזרה',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            Text('מדריך: ${feedback.instructorName}'),
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
            if (feedback.folder == 'מטווחי ירי' &&
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
            Text('תפקיד: ${feedback.role}'),
            const SizedBox(height: 8),
            feedback.folder == 'מטווחי ירי'
                ? Text('יישוב: ${feedback.settlement}')
                : Text('שם: ${feedback.name}'),
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

                        // חישוב סך הכל פגיעות וכדורים
                        int totalHits = 0;

                        // סך כל הפגיעות - סכום כל פגיעות החניכים
                        for (final trainee in trainees) {
                          totalHits +=
                              (trainee['totalHits'] as num?)?.toInt() ?? 0;
                        }

                        // ✅ חישוב נכון: מספר חניכים × סך כדורים בכל המקצים
                        int totalBulletsPerTrainee = 0;
                        for (final station in stations) {
                          totalBulletsPerTrainee +=
                              (station['bulletsCount'] as num?)?.toInt() ?? 0;
                        }
                        final totalBullets =
                            trainees.length * totalBulletsPerTrainee;

                        // חישוב אחוז כללי
                        final percentage = totalBullets > 0
                            ? ((totalHits / totalBullets) * 100)
                                  .toStringAsFixed(1)
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
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        Column(
                                          children: [
                                            const Text('סך פגיעות/כדורים'),
                                            const SizedBox(height: 4),
                                            Text(
                                              '$totalHits/$totalBullets',
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orangeAccent,
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
                                                fontWeight: FontWeight.bold,
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
                              final stationBulletsPerTrainee =
                                  (station['bulletsCount'] as num?)?.toInt() ??
                                  0;

                              // חישוב סך פגיעות למקצה
                              int stationHits = 0;
                              for (final trainee in trainees) {
                                final hits =
                                    trainee['hits'] as Map<String, dynamic>?;
                                if (hits != null) {
                                  stationHits +=
                                      (hits['station_$index'] as num?)
                                          ?.toInt() ??
                                      0;
                                }
                              }

                              // ✅ חישוב נכון: מספר חניכים × כדורים במקצה
                              final totalStationBullets =
                                  trainees.length * stationBulletsPerTrainee;

                              // חישוב אחוז פגיעות למקצה
                              final stationPercentage = totalStationBullets > 0
                                  ? ((stationHits / totalStationBullets) * 100)
                                        .toStringAsFixed(1)
                                  : '0.0';

                              return InkWell(
                                onTap: () {
                                  _showStationDetailsModal(
                                    context,
                                    index,
                                    stationName.toString(),
                                    stationBulletsPerTrainee,
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
                                            // סך כל כדורים
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '$totalStationBullets',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white70,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const Text(
                                                  'סך כל כדורים',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // סך כל פגיעות
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '$stationHits',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orangeAccent,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const Text(
                                                  'סך כל פגיעות',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // אחוז פגיעות
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
                            await FeedbackExportService.exportAllFeedbacksToXlsx();
                            if (!mounted) return;
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('הקובץ נוצר בהצלחה!'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 3),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            // ignore: use_build_context_synchronously
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
        appBar: AppBar(title: const Text('סטטיסטיקה')),
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
                  child: const Text('כל המשובים'),
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
                  child: const Text('משובי מטווחים'),
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
        appBar: AppBar(title: const Text('סטטיסטיקת כל המשובים')),
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

                          // Folder filter (for all users)
                          SizedBox(
                            width: 240,
                            child: Builder(
                              builder: (ctx) {
                                final folders = <String>{'כל התיקיות'}
                                  ..addAll(feedbackFolders);
                                final items = folders.toSet().toList();
                                final value = items.contains(selectedFolder)
                                    ? selectedFolder
                                    : null;
                                return DropdownButtonFormField<String>(
                                  initialValue: value,
                                  isExpanded: true,
                                  items: items
                                      .map(
                                        (i) => DropdownMenuItem(
                                          value: i,
                                          child: Text(i),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setState(() {
                                    selectedFolder = v ?? 'כל התיקיות';
                                    // איפוס יישוב אם התיקייה השתנתה מ"מחלקות ההגנה – חטיבה 474"
                                    if (selectedFolder !=
                                        'מחלקות ההגנה – חטיבה 474') {
                                      selectedSettlement = 'כל היישובים';
                                    }
                                  }),
                                );
                              },
                            ),
                          ),

                          // Settlement filter (only when folder is "מחלקות ההגנה – חטיבה 474")
                          if (selectedFolder == 'מחלקות ההגנה – חטיבה 474')
                            SizedBox(
                              width: 240,
                              child: Builder(
                                builder: (ctx) {
                                  final settlements = <String>{'כל היישובים'}
                                    ..addAll(golanSettlements);
                                  final items = settlements.toSet().toList();
                                  final value =
                                      items.contains(selectedSettlement)
                                      ? selectedSettlement
                                      : null;
                                  return DropdownButtonFormField<String>(
                                    initialValue: value,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'יישוב',
                                      isDense: true,
                                    ),
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 16,
                                    ),
                                    dropdownColor: Colors.white,
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
      // Always filter for range feedbacks only
      if (f.folder != 'מטווחי ירי') return false;

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
        appBar: AppBar(title: const Text('סטטיסטיקת משובי מטווחים')),
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
              Text(
                'סה"כ משובי מטווחים: $total',
                style: const TextStyle(fontSize: 14),
              ),

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
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('חומר עיוני')),
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
        appBar: AppBar(title: Text(title)),
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Text(
                  'מעגל פתוח',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                // Vertical flow with arrows
                Text(
                  'מגע',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Icon(Icons.arrow_downward, size: 32),
                SizedBox(height: 8),
                Text(
                  'סריקות',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Icon(Icons.arrow_downward, size: 32),
                SizedBox(height: 8),
                Text(
                  'זיכוי',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 24),
                Text(
                  'נלחמים לפי עקרונות לחימה',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShevaPrinciplesPage extends StatelessWidget {
  const ShevaPrinciplesPage({super.key});

  static const List<String> items = [
    'קשר עין',
    'בחירת ציר התקדמות',
    'זיהוי איום עיקרי ואיום משני',
    'קצב אש ומרחק',
    'ירי בטוח בתוך קהל',
    'וידוא ניטרול',
    'זיהוי והזדהות',
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('שבע עקרונות לחימה'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Highlighted centered quote
              Card(
                color: Colors.grey.shade100,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 18.0,
                    horizontal: 14.0,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '"מי שרואה אותי – הורג אותי.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ומי שלא רואה אותי – מת ממני."',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Exact list below the quote
              const Text(
                '- עבודה על פי תו״ל חי״ר',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                '- דילוגים ממקום למקום',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text('- מעבר בין מחסות', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              const Text('- עבודה איטית', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
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
      _item('1', 'סריקות רחוב – שמירה על קשר עין'),
      _item('2', 'בחירת ציר התקדמות נכון ובטוח'),
      _item('3', 'זיהוי איום עיקרי ומשני בתנועה'),
      _item('4', 'קצב אש ומרחק בהתאם למצב'),
      _item('5', 'ירי בטוח בתוך קהל'),
      _item('6', 'וידוא ניטרול ומעבר לחיפוש'),
      _item('7', 'זיהוי והזדהות כוחות'),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סריקות רחוב'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
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
