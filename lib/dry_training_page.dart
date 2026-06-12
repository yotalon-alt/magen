import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart' show currentUser, brigade474Instructors, kDeleteFeedbackAllowedUid;
import 'widgets/standard_back_button.dart';

// ─────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────
const List<String> kDryTrainingFolders = ['פלסר הגולן'];

const List<String> kDefaultDryCategories = [
  'טכניקה',
  'תפעול הנשק',
  'אגרסיביות',
  'דוגמנות',
  'איכות הלוחם',
];

// ─────────────────────────────────────────────
// Entry page: choose training type (יבשים etc.)
// ─────────────────────────────────────────────
class DryTrainingEntryPage extends StatelessWidget {
  const DryTrainingEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('הכשרות'),
          leading: const StandardBackButton(),
        ),
        body: ListView(
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 2,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DryTrainingYabashimSelectionPage(),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_walk,
                        size: 32,
                        color: Colors.brown,
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'יבשים',
                          style: TextStyle(
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
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Selection: יבשים — חדש / זמני
// ─────────────────────────────────────────────
class DryTrainingYabashimSelectionPage extends StatefulWidget {
  const DryTrainingYabashimSelectionPage({super.key});
  @override
  State<DryTrainingYabashimSelectionPage> createState() =>
      _DryTrainingYabashimSelectionPageState();
}

class _DryTrainingYabashimSelectionPageState
    extends State<DryTrainingYabashimSelectionPage> {
  int _draftCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDraftCount();
  }

  Future<void> _loadDraftCount() async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) return;
      final isAdmin = currentUser?.role == 'Admin';
      Query q = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'dry_training')
          .where('isTemporary', isEqualTo: true);
      if (!isAdmin) q = q.where('instructorId', isEqualTo: uid);
      final snap = await q.limit(100).get().timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _draftCount = snap.docs.length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('יבשים'),
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.directions_walk, size: 60, color: Colors.brown),
              const SizedBox(height: 20),
              const Text(
                'הכשרות יבשים',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              // משוב חדש
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const DryTrainingPage(trainingType: 'יבשים'),
                          ),
                        )
                        .then((_) => _loadDraftCount());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.brown.withValues(alpha: 0.7),
                          Colors.brown,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.add_circle_outline,
                              size: 32,
                              color: Colors.white,
                            ),
                            SizedBox(width: 16),
                            Text(
                              'משוב חדש',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_back_ios, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // משוב זמני
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DryTrainingTempFeedbacksPage(),
                      ),
                    );
                    _loadDraftCount();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.withValues(alpha: 0.7),
                          Colors.green,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.edit_note,
                              size: 32,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'משוב זמני',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (_draftCount > 0) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$_draftCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Icon(Icons.arrow_back_ios, color: Colors.white),
                      ],
                    ),
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

// ─────────────────────────────────────────────
// Temp feedbacks list
// ─────────────────────────────────────────────
class DryTrainingTempFeedbacksPage extends StatefulWidget {
  const DryTrainingTempFeedbacksPage({super.key});
  @override
  State<DryTrainingTempFeedbacksPage> createState() =>
      _DryTrainingTempFeedbacksPageState();
}

class _DryTrainingTempFeedbacksPageState
    extends State<DryTrainingTempFeedbacksPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _drafts = [];

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    setState(() => _isLoading = true);
    try {
      final uid = currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }
      final isAdmin = currentUser?.role == 'Admin';
      Query q = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('module', isEqualTo: 'dry_training')
          .where('isTemporary', isEqualTo: true);
      if (!isAdmin) q = q.where('instructorId', isEqualTo: uid);
      final snap = await q.get();
      final drafts = snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data() as Map);
        data['id'] = d.id;
        return data;
      }).toList();
      drafts.sort((a, b) {
        final ta = a['updatedAt'];
        final tb = b['updatedAt'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      });
      if (mounted) {
        setState(() {
          _drafts = drafts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ DRY_TEMP_LOAD: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteDraft(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת משוב זמני'),
          content: const Text('האם למחוק את המשוב הזמני לצמיתות?'),
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
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance.collection('feedbacks').doc(id).delete();
      if (mounted) {
        setState(() => _drafts.removeWhere((d) => d['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('המשוב נמחק')),
        );
      }
    } catch (e) {
      debugPrint('❌ DRY_DELETE: $e');
    }
  }

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year} '
          '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משובים זמניים — יבשים'),
          leading: const StandardBackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDrafts,
              tooltip: 'רענן',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _drafts.isEmpty
            ? const Center(child: Text('אין משובים זמניים'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _drafts.length,
                itemBuilder: (ctx, i) {
                  final draft = _drafts[i];
                  final id = draft['id'] as String;
                  final teamName =
                      (draft['teamName'] as String?)?.isNotEmpty == true
                      ? draft['teamName'] as String
                      : 'ללא שם צוות';
                  final folder = (draft['folder'] as String?) ?? '';
                  final date = _formatDate(draft['updatedAt']);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => DryTrainingPage(
                                  trainingType: 'יבשים',
                                  feedbackId: id,
                                ),
                              ),
                            )
                            .then((_) => _loadDrafts());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_note,
                              color: Colors.green,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    teamName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (folder.isNotEmpty)
                                    Text(
                                      'תיקייה: $folder',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (date.isNotEmpty)
                                    Text(
                                      'עודכן: $date',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.grey,
                            ),
                            if (currentUser?.uid == kDeleteFeedbackAllowedUid)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: 'מחק משוב זמני',
                                onPressed: () => _deleteDraft(id),
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

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

class DryTraineeModel {
  final String name;
  // scores: categoryIndex → score (0–10)
  final Map<int, int> scores;
  // notes: categoryIndex → note text
  final Map<int, String> notes;
  // general note for this trainee
  String generalNote;

  DryTraineeModel({
    required this.name,
    Map<int, int>? scores,
    Map<int, String>? notes,
    this.generalNote = '',
  }) : scores = scores ?? {},
       notes = notes ?? {};

  double get average {
    if (scores.isEmpty) return 0;
    final total = scores.values.fold(0, (a, b) => a + b);
    return total / scores.length;
  }

  Map<String, dynamic> toFirestore() {
    final scoresMap = <String, int>{};
    scores.forEach((k, v) => scoresMap['cat_$k'] = v);
    final notesMap = <String, String>{};
    notes.forEach((k, v) => notesMap['cat_$k'] = v);
    return {
      'name': name.trim(),
      'scores': scoresMap,
      'notes': notesMap,
      'generalNote': generalNote,
    };
  }

  static DryTraineeModel fromFirestore(Map<String, dynamic> data) {
    final name = (data['name'] as String?) ?? '';
    final scoresRaw = (data['scores'] as Map<String, dynamic>?) ?? {};
    final notesRaw = (data['notes'] as Map<String, dynamic>?) ?? {};
    final generalNote = (data['generalNote'] as String?) ?? '';

    final scores = <int, int>{};
    scoresRaw.forEach((k, v) {
      if (k.startsWith('cat_')) {
        final idx = int.tryParse(k.replaceFirst('cat_', ''));
        if (idx != null) scores[idx] = (v as num).toInt();
      }
    });

    final notes = <int, String>{};
    notesRaw.forEach((k, v) {
      if (k.startsWith('cat_')) {
        final idx = int.tryParse(k.replaceFirst('cat_', ''));
        if (idx != null) notes[idx] = v.toString();
      }
    });

    return DryTraineeModel(
      name: name,
      scores: scores,
      notes: notes,
      generalNote: generalNote,
    );
  }
}

// ─────────────────────────────────────────────
// Main page
// ─────────────────────────────────────────────

class DryTrainingPage extends StatefulWidget {
  final String trainingType; // e.g. 'יבשים'
  final String? feedbackId; // null = new, non-null = edit existing draft

  const DryTrainingPage({
    super.key,
    required this.trainingType,
    this.feedbackId,
  });

  @override
  State<DryTrainingPage> createState() => _DryTrainingPageState();
}

class _DryTrainingPageState extends State<DryTrainingPage> {
  // ── top-level fields ──────────────────────────────────
  String? _selectedFolder;
  final _teamNameController = TextEditingController();
  final _attendeesCountController = TextEditingController();
  final _trainingSummaryController = TextEditingController();

  // ── instructors ───────────────────────────────────────
  int _instructorsCount = 0;
  final _instructorsCountController = TextEditingController();
  final Map<int, TextEditingController> _instructorNameControllers = {};

  // ── categories ───────────────────────────────────────
  List<String> _categories = List.from(kDefaultDryCategories);

  // ── trainees ─────────────────────────────────────────
  List<DryTraineeModel> _trainees = [];
  final Map<int, TextEditingController> _nameControllers = {};

  // ── state flags ───────────────────────────────────────
  bool _isSaving = false;
  String? _editingFeedbackId;
  Timer? _autoSaveTimer;

  // ── auto-save debounce ────────────────────────────────
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 700), _saveTemporarily);
  }

  // ─────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _editingFeedbackId = widget.feedbackId;
    if (_editingFeedbackId != null) {
      _loadExisting(_editingFeedbackId!);
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (_autoSaveTimer?.isActive == true) {
      _autoSaveTimer?.cancel();
      _saveTemporarily();
    }
    _teamNameController.dispose();
    _instructorsCountController.dispose();
    _attendeesCountController.dispose();
    _trainingSummaryController.dispose();
    for (final c in _instructorNameControllers.values) {
      c.dispose();
    }
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────
  // Load existing draft
  // ─────────────────────────────────────────────────────
  Future<void> _loadExisting(String id) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(id)
          .get();
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;

      setState(() {
        _selectedFolder = data['folder'] as String?;
        _teamNameController.text = (data['teamName'] as String?) ?? '';
        // instructors
        final instrCount = (data['instructorsCount'] as num?)?.toInt() ?? 0;
        _instructorsCount = instrCount;
        _instructorsCountController.text = instrCount > 0
            ? instrCount.toString()
            : '';
        final instrNames = (data['instructors'] as List?)?.cast<String>() ?? [];
        for (int i = 0; i < instrCount; i++) {
          _instructorNameControllers[i] = TextEditingController(
            text: i < instrNames.length ? instrNames[i] : '',
          );
        }
        _attendeesCountController.text =
            (data['attendeesCount'] as num?)?.toString() ?? '';
        _trainingSummaryController.text =
            (data['trainingSummary'] as String?) ?? '';

        final cats = (data['categories'] as List?)?.cast<String>();
        if (cats != null && cats.isNotEmpty) _categories = cats;

        final traineesRaw = (data['trainees'] as List?) ?? [];
        _trainees = traineesRaw
            .map(
              (t) => DryTraineeModel.fromFirestore(t as Map<String, dynamic>),
            )
            .toList();
        _rebuildNameControllers();
      });
    } catch (e) {
      debugPrint('❌ DRY_LOAD: $e');
    }
  }

  void _rebuildNameControllers() {
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    _nameControllers.clear();
    for (int i = 0; i < _trainees.length; i++) {
      _nameControllers[i] = TextEditingController(text: _trainees[i].name);
    }
  }

  // ─────────────────────────────────────────────────────
  // Instructor count change
  // ─────────────────────────────────────────────────────
  void _onInstructorsCountChanged(String value) {
    final count = int.tryParse(value) ?? 0;
    setState(() {
      _instructorsCount = count;
      while (_instructorNameControllers.length < count) {
        final idx = _instructorNameControllers.length;
        _instructorNameControllers[idx] = TextEditingController();
      }
      while (_instructorNameControllers.length > count) {
        final idx = _instructorNameControllers.length - 1;
        _instructorNameControllers[idx]?.dispose();
        _instructorNameControllers.remove(idx);
      }
    });
    _scheduleAutoSave();
  }

  List<String> _collectInstructorNames() {
    final names = <String>[];
    for (int i = 0; i < _instructorsCount; i++) {
      final name = _instructorNameControllers[i]?.text.trim() ?? '';
      if (name.isNotEmpty) names.add(name);
    }
    return names;
  }

  // ─────────────────────────────────────────────────────
  // Update trainee count when attendees number changes
  // ─────────────────────────────────────────────────────
  void _onAttendeesChanged(String value) {
    final count = int.tryParse(value) ?? 0;
    setState(() {
      while (_trainees.length < count) {
        final idx = _trainees.length;
        _trainees.add(DryTraineeModel(name: ''));
        _nameControllers[idx] = TextEditingController();
      }
      while (_trainees.length > count) {
        final idx = _trainees.length - 1;
        _nameControllers[idx]?.dispose();
        _nameControllers.remove(idx);
        _trainees.removeLast();
      }
    });
    _scheduleAutoSave();
  }

  // ─────────────────────────────────────────────────────
  // Save draft (temporary)
  // ─────────────────────────────────────────────────────
  Future<void> _saveTemporarily() async {
    if (_isSaving) return;
    if (_selectedFolder == null) return;

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final docId =
          _editingFeedbackId ??
          FirebaseFirestore.instance.collection('feedbacks').doc().id;

      // Sync names from controllers
      for (int i = 0; i < _trainees.length; i++) {
        final ctrl = _nameControllers[i];
        if (ctrl != null) {
          _trainees[i] = DryTraineeModel(
            name: ctrl.text,
            scores: _trainees[i].scores,
            notes: _trainees[i].notes,
            generalNote: _trainees[i].generalNote,
          );
        }
      }

      final patch = <String, dynamic>{
        'status': 'temporary',
        'isTemporary': true,
        'module': 'dry_training',
        'folder': _selectedFolder,
        'feedbackType': 'dry_training',
        'trainingType': widget.trainingType,
        'teamName': _teamNameController.text.trim(),
        'instructorsCount': _instructorsCount,
        'instructors': _collectInstructorNames(),
        'attendeesCount': int.tryParse(_attendeesCountController.text) ?? 0,
        'trainingSummary': _trainingSummaryController.text,
        'categories': _categories,
        'trainees': _trainees.map((t) => t.toFirestore()).toList(),
        'instructorId': uid,
        'updatedByUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByName': currentUser?.name ?? '',
      };

      await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(docId)
          .set(patch, SetOptions(merge: true));

      if (_editingFeedbackId == null && mounted) {
        setState(() => _editingFeedbackId = docId);
      }
    } catch (e) {
      debugPrint('❌ DRY_SAVE: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─────────────────────────────────────────────────────
  // Save final
  // ─────────────────────────────────────────────────────
  Future<void> _saveFinal() async {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('יש לבחור תיקייה')));
      return;
    }
    if (_isSaving) return;

    // Sync names
    for (int i = 0; i < _trainees.length; i++) {
      final ctrl = _nameControllers[i];
      if (ctrl != null) {
        _trainees[i] = DryTraineeModel(
          name: ctrl.text,
          scores: _trainees[i].scores,
          notes: _trainees[i].notes,
          generalNote: _trainees[i].generalNote,
        );
      }
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final docId =
          _editingFeedbackId ??
          FirebaseFirestore.instance.collection('feedbacks').doc().id;

      final patch = <String, dynamic>{
        'status': 'final',
        'isTemporary': false,
        'finalizedAt': FieldValue.serverTimestamp(),
        'module': 'dry_training',
        'folder': _selectedFolder,
        'feedbackType': 'dry_training',
        'trainingType': widget.trainingType,
        'teamName': _teamNameController.text.trim(),
        'instructorsCount': _instructorsCount,
        'instructors': _collectInstructorNames(),
        'attendeesCount': int.tryParse(_attendeesCountController.text) ?? 0,
        'trainingSummary': _trainingSummaryController.text,
        'categories': _categories,
        'trainees': _trainees.map((t) => t.toFirestore()).toList(),
        'instructorId': uid,
        'instructorName': currentUser?.name ?? '',
        'updatedByUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(docId)
          .set(patch, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ המשוב נשמר בהצלחה'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('❌ DRY_FINAL_SAVE: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בשמירה: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─────────────────────────────────────────────────────
  // Score + note dialog
  // ─────────────────────────────────────────────────────
  Future<void> _showScoreDialog({
    required int traineeIdx,
    required int categoryIdx,
    required String traineeName,
    required String categoryName,
  }) async {
    final trainee = _trainees[traineeIdx];
    int? currentScore = trainee.scores[categoryIdx];
    String currentNote = trainee.notes[categoryIdx] ?? '';

    String scoreInput = currentScore != null ? currentScore.toString() : '';
    final noteController = TextEditingController(text: currentNote);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        traineeName.isNotEmpty
                            ? traineeName
                            : 'חניך ${traineeIdx + 1}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        categoryName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Score input display
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'ציון (0–10)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              scoreInput.isEmpty ? '–' : scoreInput,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Number buttons
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Column(
                          children: [
                            _numRow(
                              ['1', '2', '3'],
                              scoreInput,
                              setDialogState,
                              (v) => scoreInput = v,
                            ),
                            _numRow(
                              ['4', '5', '6'],
                              scoreInput,
                              setDialogState,
                              (v) => scoreInput = v,
                            ),
                            _numRow(
                              ['7', '8', '9'],
                              scoreInput,
                              setDialogState,
                              (v) => scoreInput = v,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      onPressed: () => setDialogState(() {
                                        // 10 shortcut
                                        scoreInput = '10';
                                      }),
                                      child: const Text(
                                        '10',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      onPressed: () => setDialogState(() {
                                        scoreInput += '0';
                                      }),
                                      child: const Text(
                                        '0',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      onPressed: () => setDialogState(() {
                                        if (scoreInput.isNotEmpty) {
                                          scoreInput = scoreInput.substring(
                                            0,
                                            scoreInput.length - 1,
                                          );
                                        }
                                      }),
                                      child: const Text(
                                        '⌫',
                                        style: TextStyle(fontSize: 22),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('ביטול'),
                          ),
                          if (currentScore != null)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _trainees[traineeIdx].scores.remove(
                                    categoryIdx,
                                  );
                                  _trainees[traineeIdx].notes.remove(
                                    categoryIdx,
                                  );
                                });
                                _scheduleAutoSave();
                                Navigator.pop(ctx);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('מחק ציון'),
                            ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              final score = int.tryParse(scoreInput);
                              if (score == null || score < 0 || score > 10) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ציון חייב להיות בין 0 ל-10'),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _trainees[traineeIdx].scores[categoryIdx] =
                                    score;
                                final note = noteController.text.trim();
                                if (note.isNotEmpty) {
                                  _trainees[traineeIdx].notes[categoryIdx] =
                                      note;
                                } else {
                                  _trainees[traineeIdx].notes.remove(
                                    categoryIdx,
                                  );
                                }
                              });
                              _scheduleAutoSave();
                              Navigator.pop(ctx);
                            },
                            child: const Text('אישור'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Helper: a row of 3 number buttons for the dialog
  Widget _numRow(
    List<String> keys,
    String currentInput,
    void Function(void Function()) setDialogState,
    void Function(String) onUpdate,
  ) {
    return Row(
      children: keys
          .map(
            (k) => Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () =>
                      setDialogState(() => onUpdate(currentInput + k)),
                  child: Text(k),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ─────────────────────────────────────────────────────
  // General note dialog for a trainee
  // ─────────────────────────────────────────────────────
  Future<void> _showGeneralNoteDialog(int traineeIdx) async {
    final ctrl = TextEditingController(text: _trainees[traineeIdx].generalNote);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'הערה כללית — ${_trainees[traineeIdx].name.isNotEmpty ? _trainees[traineeIdx].name : "חניך ${traineeIdx + 1}"}',
          ),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'הוסף הערה כללית...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _trainees[traineeIdx] = DryTraineeModel(
                    name: _trainees[traineeIdx].name,
                    scores: _trainees[traineeIdx].scores,
                    notes: _trainees[traineeIdx].notes,
                    generalNote: ctrl.text.trim(),
                  );
                });
                _scheduleAutoSave();
                Navigator.pop(ctx);
              },
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  // ─────────────────────────────────────────────────────
  // Add / Remove categories
  // ─────────────────────────────────────────────────────
  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הוסף קטגוריה'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'שם הקטגוריה',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                setState(() => _categories.add(name));
                _scheduleAutoSave();
                Navigator.pop(ctx);
              },
              child: const Text('הוסף'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  void _removeCategory(int idx) {
    setState(() {
      _categories.removeAt(idx);
      // Remove scores/notes for this category and shift higher indices
      for (final t in _trainees) {
        final updatedScores = <int, int>{};
        final updatedNotes = <int, String>{};
        t.scores.forEach((k, v) {
          if (k < idx) updatedScores[k] = v;
          if (k > idx) updatedScores[k - 1] = v;
        });
        t.notes.forEach((k, v) {
          if (k < idx) updatedNotes[k] = v;
          if (k > idx) updatedNotes[k - 1] = v;
        });
        t.scores
          ..clear()
          ..addAll(updatedScores);
        t.notes
          ..clear()
          ..addAll(updatedNotes);
      }
    });
    _scheduleAutoSave();
  }

  void _onCategoryReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final moved = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, moved);

      // Shift data in trainees
      for (final t in _trainees) {
        // scores
        final oldScore = t.scores.remove(oldIndex);
        final updatedScores = <int, int>{};
        t.scores.forEach((k, v) {
          if (oldIndex < newIndex && k > oldIndex && k <= newIndex) {
            updatedScores[k - 1] = v;
          } else if (oldIndex > newIndex && k >= newIndex && k < oldIndex) {
            updatedScores[k + 1] = v;
          } else {
            updatedScores[k] = v;
          }
        });
        t.scores
          ..clear()
          ..addAll(updatedScores);
        if (oldScore != null) t.scores[newIndex] = oldScore;

        // notes
        final oldNote = t.notes.remove(oldIndex);
        final updatedNotes = <int, String>{};
        t.notes.forEach((k, v) {
          if (oldIndex < newIndex && k > oldIndex && k <= newIndex) {
            updatedNotes[k - 1] = v;
          } else if (oldIndex > newIndex && k >= newIndex && k < oldIndex) {
            updatedNotes[k + 1] = v;
          } else {
            updatedNotes[k] = v;
          }
        });
        t.notes
          ..clear()
          ..addAll(updatedNotes);
        if (oldNote != null) t.notes[newIndex] = oldNote;
      }
    });
    _scheduleAutoSave();
  }

  // ─────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text('הכשרות ${widget.trainingType}'),
          leading: const StandardBackButton(),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Folder ───────────────────────────────────
              DropdownButtonFormField<String>(
                initialValue: _selectedFolder,
                decoration: const InputDecoration(
                  labelText: 'בחר תיקייה',
                  border: OutlineInputBorder(),
                ),
                items: kDryTrainingFolders
                    .map(
                      (f) => DropdownMenuItem<String>(value: f, child: Text(f)),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedFolder = v);
                  _scheduleAutoSave();
                },
              ),
              const SizedBox(height: 12),

              // ── יחידה (fixed from selected folder) ──────────────
              if (_selectedFolder != null) ...[
                TextField(
                  readOnly: true,
                  controller: TextEditingController(text: _selectedFolder),
                  decoration: const InputDecoration(
                    labelText: 'יחידה',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Team name ─────────────────────────────────
              TextField(
                controller: _teamNameController,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'צוות',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _scheduleAutoSave(),
              ),
              const SizedBox(height: 12),

              // ── Instructors count + name rows ─────────────────────
              TextField(
                controller: _instructorsCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'מס׳ מדריכים',
                  border: OutlineInputBorder(),
                ),
                onChanged: _onInstructorsCountChanged,
              ),
              ...List.generate(_instructorsCount, (index) {
                if (!_instructorNameControllers.containsKey(index)) {
                  _instructorNameControllers[index] = TextEditingController();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
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
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Autocomplete<String>(
                          optionsBuilder: (TextEditingValue tv) {
                            if (tv.text.isEmpty) return brigade474Instructors;
                            return brigade474Instructors.where(
                              (n) => n.contains(tv.text),
                            );
                          },
                          onSelected: (String sel) {
                            setState(() {
                              _instructorNameControllers[index]!.text = sel;
                            });
                            _scheduleAutoSave();
                          },
                          fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
                            final master = _instructorNameControllers[index]!;
                            if (ctrl.text.isEmpty && master.text.isNotEmpty) {
                              ctrl.text = master.text;
                            }
                            ctrl.addListener(() {
                              master.text = ctrl.text;
                              _scheduleAutoSave();
                            });
                            return TextField(
                              controller: ctrl,
                              focusNode: focusNode,
                              textDirection: TextDirection.rtl,
                              decoration: const InputDecoration(
                                hintText: 'בחר או הקלד שם מדריך',
                                labelText: 'שם מדריך',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),

              // ── Attendees count ────────────────────────────
              TextField(
                controller: _attendeesCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'כמות נוכחים',
                  border: OutlineInputBorder(),
                ),
                onChanged: _onAttendeesChanged,
              ),
              const SizedBox(height: 20),

              // ── Categories section ─────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'קטגוריות',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addCategory,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('הוסף קטגוריה'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: _onCategoryReorder,
                children: _categories.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final cat = entry.value;
                  return Card(
                    key: ValueKey('cat_$idx'),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: idx,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.drag_handle,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              cat,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed: () => _removeCategory(idx),
                            tooltip: 'מחק קטגוריה',
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Table ──────────────────────────────────────
              if (_trainees.isNotEmpty) ...[
                const Text(
                  'טבלת הערכה',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildTable(),
                const SizedBox(height: 20),
              ],

              // ── Training summary ───────────────────────────
              const Text(
                'סיכום אימון',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _trainingSummaryController,
                maxLines: 4,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'כתוב סיכום אימון...',
                ),
                onChanged: (_) => _scheduleAutoSave(),
              ),
              const SizedBox(height: 24),

              // ── Save final button ──────────────────────────
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveFinal,
                icon: const Icon(Icons.save),
                label: _isSaving
                    ? const Text('שומר...')
                    : const Text('שמור משוב סופי'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // Table widget
  // ─────────────────────────────────────────────────────
  Widget _buildTable() {
    // Column widths
    const double nameColWidth = 100;
    const double scoreColWidth = 72;
    const double avgColWidth = 64;
    const double noteColWidth = 90;

    final totalWidth =
        nameColWidth +
        _categories.length * scoreColWidth +
        avgColWidth +
        noteColWidth;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            // Header row
            Container(
              color: Colors.grey.shade200,
              child: Row(
                children: [
                  SizedBox(
                    width: nameColWidth,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Text(
                        'שם',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  ..._categories.asMap().entries.map(
                    (e) => SizedBox(
                      width: scoreColWidth,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          e.value,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: avgColWidth,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Text(
                        'ממוצע',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: noteColWidth,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Text(
                        'הערה כללית',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Trainee rows
            ..._trainees.asMap().entries.map((entry) {
              final traineeIdx = entry.key;
              final trainee = entry.value;
              final avg = trainee.average;
              final avgText = trainee.scores.isEmpty
                  ? '–'
                  : avg.toStringAsFixed(1);

              // Average colour
              Color avgColor = Colors.black;
              if (trainee.scores.isNotEmpty) {
                if (avg >= 8) {
                  avgColor = Colors.green.shade700;
                } else if (avg >= 6) {
                  avgColor = Colors.orange.shade700;
                } else {
                  avgColor = Colors.red;
                }
              }

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                  color: traineeIdx.isEven ? Colors.white : Colors.grey.shade50,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Name column
                    SizedBox(
                      width: nameColWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: _nameControllers[traineeIdx],
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'שם חניך',
                            hintStyle: TextStyle(fontSize: 11),
                          ),
                          onChanged: (_) => _scheduleAutoSave(),
                        ),
                      ),
                    ),

                    // Score cells
                    ..._categories.asMap().entries.map((catEntry) {
                      final catIdx = catEntry.key;
                      final score = trainee.scores[catIdx];
                      final hasNote = (trainee.notes[catIdx] ?? '').isNotEmpty;
                      return SizedBox(
                        width: scoreColWidth,
                        height: 48,
                        child: InkWell(
                          onTap: () => _showScoreDialog(
                            traineeIdx: traineeIdx,
                            categoryIdx: catIdx,
                            traineeName:
                                _nameControllers[traineeIdx]?.text ?? '',
                            categoryName: catEntry.value,
                          ),
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: score != null
                                  ? (score >= 8
                                        ? Colors.green.shade100
                                        : score >= 6
                                        ? Colors.orange.shade100
                                        : Colors.red.shade100)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: score != null
                                    ? Colors.transparent
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  score != null ? '$score' : '–',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: score != null
                                        ? (score >= 8
                                              ? Colors.green.shade800
                                              : score >= 6
                                              ? Colors.orange.shade800
                                              : Colors.red.shade800)
                                        : Colors.grey,
                                  ),
                                ),
                                if (hasNote)
                                  const Icon(
                                    Icons.note_alt,
                                    size: 10,
                                    color: Colors.blueGrey,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    // Average column
                    SizedBox(
                      width: avgColWidth,
                      height: 48,
                      child: Center(
                        child: Text(
                          avgText,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: avgColor,
                          ),
                        ),
                      ),
                    ),

                    // General note column
                    SizedBox(
                      width: noteColWidth,
                      height: 48,
                      child: InkWell(
                        onTap: () => _showGeneralNoteDialog(traineeIdx),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: trainee.generalNote.isNotEmpty
                                ? Colors.blue.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: trainee.generalNote.isNotEmpty
                              ? Text(
                                  trainee.generalNote,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(fontSize: 10),
                                )
                              : const Icon(
                                  Icons.add_comment_outlined,
                                  size: 16,
                                  color: Colors.grey,
                                ),
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
    );
  }
}
