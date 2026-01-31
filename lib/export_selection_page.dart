import 'package:flutter/material.dart';
import 'main.dart';
import 'feedback_export_service.dart';
import 'widgets/standard_back_button.dart';

/// דף בחירת נתונים לייצוא - רק לאדמין
class ExportSelectionPage extends StatefulWidget {
  const ExportSelectionPage({super.key});

  @override
  State<ExportSelectionPage> createState() => _ExportSelectionPageState();
}

class _ExportSelectionPageState extends State<ExportSelectionPage> {
  // סוג ייצוא: 'single' או 'multiple'
  String _exportType = 'single';

  // סינונים לייצוא מרובה
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _selectedRangeType; // קצרים/ארוכים/הפתעה
  String? _selectedInstructor;

  bool _isExporting = false;

  Future<void> _pickDateFrom() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),

    );
    if (result != null) {
      setState(() => _dateFrom = result);
    }
  }

  Future<void> _pickDateTo() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),

    );
    if (result != null) {
      setState(() => _dateTo = result);
    }
  }

  Future<void> _exportSingle() async {
    // מציג רשימת משובים לבחירה
    final feedbacks =
        feedbackStorage.where((f) => f.folder == 'מטווחי ירי').toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (feedbacks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין משובי מטווחים זמינים לייצוא')),
      );
      return;
    }

    // דיאלוג בחירת משוב בודד
    final selected = await showDialog<FeedbackModel>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('בחר משוב לייצוא'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: feedbacks.length,
              itemBuilder: (_, i) {
                final f = feedbacks[i];
                return ListTile(
                  title: Text('${f.name} - ${f.settlement}'),
                  subtitle: Text(
                    f.createdAt.toLocal().toString().split('.').first,
                  ),
                  onTap: () => Navigator.pop(ctx, f),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
          ],
        ),
      ),
    );

    if (selected == null || selected.id == null) return;

    setState(() => _isExporting = true);

    try {
      // Prepare schema (page defines its own columns)
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
        feedbacks: [selected],
        fileNamePrefix: 'feedbacks_range',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקובץ נוצר בהצלחה!'),
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

  Future<void> _exportMultiple() async {
    // סינון משובים לפי הקריטריונים
    var filtered = feedbackStorage.where((f) => f.folder == 'מטווחי ירי');

    if (_dateFrom != null) {
      filtered = filtered.where((f) => f.createdAt.isAfter(_dateFrom!));
    }

    if (_dateTo != null) {
      final endOfDay = DateTime(
        _dateTo!.year,
        _dateTo!.month,
        _dateTo!.day,
        23,
        59,
        59,
      );
      filtered = filtered.where((f) => f.createdAt.isBefore(endOfDay));
    }

    if (_selectedRangeType != null && _selectedRangeType!.isNotEmpty) {
      filtered = filtered.where((f) {
        // נחפש בשדות הרלוונטיים
        return f.notes['general']?.contains(_selectedRangeType!) ?? false;
      });
    }

    if (_selectedInstructor != null && _selectedInstructor!.isNotEmpty) {
      filtered = filtered.where((f) => f.instructorName == _selectedInstructor);
    }

    final feedbacksList = filtered.toList();

    if (feedbacksList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נמצאו משובים תואמים לסינון')),
      );
      return;
    }

    // Prepare schema (page defines its own columns)
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

    // Ask user to optionally select a subset of the filtered feedbacks.
    final maybeSelectedIds = await showDialog<List<String>?>(
      context: context,
      builder: (ctx) {
        final Set<String> selectedIds = {};
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('בחר משובים לייצוא (או לחץ "ייצא את כולם")'),
            content: SizedBox(
              width: double.maxFinite,
              child: StatefulBuilder(
                builder: (innerCtx, setInner) {
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: feedbacksList.length,
                    itemBuilder: (_, i) {
                      final f = feedbacksList[i];
                      final id = f.id ?? i.toString();
                      return CheckboxListTile(
                        value: selectedIds.contains(id),
                        title: Text('${f.name} — ${f.settlement}'),
                        subtitle: Text(
                          f.createdAt.toLocal().toString().split('.').first,
                        ),
                        onChanged: (v) => setInner(() {
                          if (v == true) {
                            selectedIds.add(id);
                          } else {
                            selectedIds.remove(id);
                          }
                        }),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selectedIds.toList()),
                child: const Text('ייצא נבחרים'),
              ),
            ],
          ),
        );
      },
    );

    // If dialog was cancelled, do nothing
    if (maybeSelectedIds == null) return;

    // Require explicit selections: do not export everything implicitly
    if (maybeSelectedIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('לא נבחרו משובים לייצוא')));
      return;
    }

    final selectedSet = maybeSelectedIds.toSet();
    final List<FeedbackModel> toExport = feedbacksList
        .where((f) => selectedSet.contains(f.id))
        .toList();
    if (toExport.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נבחרו משובים תקפים לייצוא')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      await FeedbackExportService.exportWithSchema(
        keys: keys,
        headers: headers,
        feedbacks: toExport,
        fileNamePrefix: 'feedbacks_range_multiple',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${toExport.length} משובים יוצאו בהצלחה לקובץ מקומי!'),
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
    final instructors =
        feedbackStorage
            .where((f) => f.folder == 'מטווחי ירי')
            .map((f) => f.instructorName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ייצוא משובי מטווחים'),
          leading: const StandardBackButton(),
        ),
        body: _isExporting
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('מייצא נתונים...'),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // בחירת סוג ייצוא
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'בחר סוג ייצוא:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment<String>(
                                  value: 'single',
                                  label: Text('ייצוא משוב בודד'),
                                ),
                                ButtonSegment<String>(
                                  value: 'multiple',
                                  label: Text('ייצוא קבוצת משובים'),
                                ),
                              ],
                              selected: {_exportType},
                              onSelectionChanged: (selection) {
                                if (selection.isNotEmpty) {
                                  setState(() => _exportType = selection.first);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // סינונים (רק אם בחרו ייצוא מרובה)
                    if (_exportType == 'multiple') ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'סינון נתונים:',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // תאריכים
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickDateFrom,
                                      icon: const Icon(Icons.calendar_today),
                                      label: Text(
                                        _dateFrom == null
                                            ? 'מתאריך'
                                            : '${_dateFrom!.day}/${_dateFrom!.month}/${_dateFrom!.year}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickDateTo,
                                      icon: const Icon(Icons.calendar_today),
                                      label: Text(
                                        _dateTo == null
                                            ? 'עד תאריך'
                                            : '${_dateTo!.day}/${_dateTo!.month}/${_dateTo!.year}',
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // סוג מטווח
                              DropdownButtonFormField<String>(
                                initialValue: _selectedRangeType,
                                hint: const Text('סוג מטווח (הכל)'),
                                decoration: const InputDecoration(
                                  labelText: 'סוג מטווח',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('כל הסוגים'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'קצרים',
                                    child: Text('טווח קצר'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'טווח רחוק',
                                    child: Text('טווח רחוק'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'הפתעה',
                                    child: Text('תרגילי הפתעה'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _selectedRangeType = v),
                              ),

                              const SizedBox(height: 16),

                              // מדריך
                              DropdownButtonFormField<String>(
                                initialValue: _selectedInstructor,
                                hint: const Text('מדריך (הכל)'),
                                decoration: const InputDecoration(
                                  labelText: 'מדריך',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('כל המדריכים'),
                                  ),
                                  ...instructors.map(
                                    (name) => DropdownMenuItem(
                                      value: name,
                                      child: Text(name),
                                    ),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _selectedInstructor = v),
                              ),

                              const SizedBox(height: 16),

                              // כפתור ניקוי סינונים
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _dateFrom = null;
                                    _dateTo = null;
                                    _selectedRangeType = null;
                                    _selectedInstructor = null;
                                  });
                                },
                                icon: const Icon(Icons.clear),
                                label: const Text('נקה סינונים'),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],

                    // כפתור ייצוא
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isExporting
                            ? null
                            : (_exportType == 'single'
                                  ? _exportSingle
                                  : _exportMultiple),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.file_download, size: 28),
                        label: Text(
                          _exportType == 'single'
                              ? 'ייצא משוב בודד'
                              : 'ייצא קבוצת משובים',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // הערה
                    const Card(
                      color: Colors.blueGrey,
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'הערות חשובות:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text('• ניתן לייצא רק משובים שכבר נשמרו בפיירבייס'),
                            Text('• כל ייצוא יוצר קובץ XLSX מקומי'),
                            Text('• הקובץ יישמר אוטומטית במכשיר'),
                            Text(
                              '• בייצוא מרובה, ניתן לסנן לפי תאריך, סוג וכו\'',
                            ),
                          ],
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
