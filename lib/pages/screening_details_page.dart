import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../feedback_export_service.dart';

class ScreeningDetailsPage extends StatefulWidget {
  final String screeningId;
  const ScreeningDetailsPage({super.key, required this.screeningId});

  @override
  State<ScreeningDetailsPage> createState() => _ScreeningDetailsPageState();
}

class _ScreeningDetailsPageState extends State<ScreeningDetailsPage> {
  bool _saving = false;

  Future<void> _fillField(String name, int value) async {
    setState(() => _saving = true);
    // Capture messenger before async gap to avoid using BuildContext later
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FeedbackExportService.saveFieldWithHistory(
        screeningId: widget.screeningId,
        fieldName: name,
        value: value,
        instructorId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
      messenger.showSnackBar(const SnackBar(content: Text('נשמר')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('שגיאה: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';
    final isInstructor = currentUser?.role == 'Instructor';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('פרטי משוב'),
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.lock),
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await FeedbackExportService.setScreeningLock(
                            screeningId: widget.screeningId,
                            lock: true,
                          );
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('שגיאה: ${e.toString()}')),
                          );
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                tooltip: 'נעל משוב',
              ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('instructor_course_screenings')
              .doc(widget.screeningId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.data!.exists) {
              return const Center(child: Text('מסמך לא נמצא'));
            }
            final data = snapshot.data!.data()!;
            final status = (data['status'] as String?) ?? 'in_progress';
            final locked = (data['isFinalLocked'] as bool?) ?? false;
            final fields =
                (data['fields'] as Map?)?.cast<String, dynamic>() ?? {};
            // all fields filled?
            bool allFilled = true;
            for (final e in fields.entries) {
              final meta = (e.value as Map?)?.cast<String, dynamic>() ?? {};
              if (meta['value'] == null) {
                allFilled = false;
                break;
              }
            }

            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: ListView(
                children: [
                  ListTile(
                    title: Text(
                      'סטטוס: ${status == 'completed' ? 'סופי' : 'בתהליך'}',
                    ),
                    subtitle: Text(locked ? 'נעול' : 'פתוח'),
                  ),
                  const Divider(),
                  ...fields.entries.map((e) {
                    final name = e.key;
                    final meta =
                        (e.value as Map?)?.cast<String, dynamic>() ?? {};
                    final val = meta['value'];
                    final isEditable =
                        isInstructor &&
                        !locked &&
                        status == 'in_progress' &&
                        val == null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextFormField(
                        initialValue: val?.toString(),
                        enabled: isEditable,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: name,
                          filled: true,
                          fillColor: isEditable ? null : Colors.grey.shade300,
                          suffixIcon: isEditable
                              ? const Icon(Icons.edit)
                              : const Icon(Icons.lock),
                          helperText: isEditable
                              ? 'ניתן למילוי'
                              : 'שדה זה ננעל לאחר מילוי',
                        ),
                        onFieldSubmitted: isEditable
                            ? (val) {
                                final parsed = int.tryParse(val);
                                if (parsed != null) {
                                  _fillField(name, parsed);
                                }
                              }
                            : null,
                      ),
                    );
                  }),
                  const Divider(),
                  // Instructor can finalize when all fields are filled and not locked
                  if (isInstructor && !locked && status == 'in_progress')
                    ElevatedButton.icon(
                      onPressed: !_saving && allFilled
                          ? () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(context);
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('אישור סיום משוב'),
                                  content: const Text(
                                    'האם אתה בטוח שברצונך לסיים ולסגור את המשוב?\nהפעולה סוגרת את המשוב לצמיתות.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('ביטול'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('סיים וסגור'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              setState(() => _saving = true);
                              try {
                                await FeedbackExportService.finalizeScreeningAndCreateFeedback(
                                  screeningId: widget.screeningId,
                                );
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('המשוב הושלם ונשמר'),
                                  ),
                                );
                                navigator.pop();
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'שגיאה בסיום: ${e.toString()}',
                                    ),
                                  ),
                                );
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('סיום משוב'),
                    ),

                  const SizedBox(height: 8),
                  if (isAdmin && status == 'in_progress')
                    ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('אישור סיום משוב'),
                                  content: const Text(
                                    'האם אתה בטוח שברצונך לסיים ולסגור את המשוב?\nהפעולה סוגרת את המשוב לצמיתות.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('ביטול'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('סיים וסגור'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              setState(() => _saving = true);
                              try {
                                // Admin explicit completion: also finalize and create feedback
                                await FeedbackExportService.finalizeScreeningAndCreateFeedback(
                                  screeningId: widget.screeningId,
                                );
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('שגיאה: ${e.toString()}'),
                                  ),
                                );
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('סמן כסופי (אדמין)'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
