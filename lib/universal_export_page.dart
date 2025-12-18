import 'package:flutter/material.dart';
import 'main.dart';
import 'feedback_export_service.dart';

/// דף ייצוא משובים אוניברסלי - רק לאדמין
/// תומך בבחירה מרובה, "בחר הכל", סינונים מתקדמים
class UniversalExportPage extends StatefulWidget {
  const UniversalExportPage({super.key});

  @override
  State<UniversalExportPage> createState() => _UniversalExportPageState();
}

class _UniversalExportPageState extends State<UniversalExportPage> {
  // משובים נבחרים (IDs)
  final Set<String> _selectedFeedbackIds = {};

  // סינונים
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _feedbackType; // 'מטווחים' / 'אחר'
  String? _rangeSubType; // 'קצרים' / 'ארוכים' / 'הפתעה'
  String? _selectedInstructor;
  String? _selectedFolder;
  String _searchText = '';

  bool _isExporting = false;
  bool _showOnlySelected = false;

  // קבלת רשימת משובים מסוננת
  List<FeedbackModel> _getFilteredFeedbacks() {
    var filtered = feedbackStorage.where((f) => f.id != null);

    // סינון לפי תאריך
    if (_dateFrom != null) {
      final startOfDay = DateTime(
        _dateFrom!.year,
        _dateFrom!.month,
        _dateFrom!.day,
      );
      filtered = filtered.where((f) => f.createdAt.isAfter(startOfDay));
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

    // סינון לפי סוג משוב (מטווחים / אחר)
    if (_feedbackType != null) {
      if (_feedbackType == 'מטווחים') {
        filtered = filtered.where((f) => f.folder == 'מטווחי ירי');
      } else if (_feedbackType == 'אחר') {
        filtered = filtered.where((f) => f.folder != 'מטווחי ירי');
      }
    }

    // סינון לפי תיקייה
    if (_selectedFolder != null && _selectedFolder!.isNotEmpty) {
      filtered = filtered.where((f) => f.folder == _selectedFolder);
    }

    // סינון לפי תת-סוג מטווח
    if (_rangeSubType != null && _rangeSubType!.isNotEmpty) {
      filtered = filtered.where((f) {
        final general = f.notes['general'] ?? '';
        return general.contains(_rangeSubType!);
      });
    }

    // סינון לפי מדריך
    if (_selectedInstructor != null && _selectedInstructor!.isNotEmpty) {
      filtered = filtered.where((f) => f.instructorName == _selectedInstructor);
    }

    // סינון לפי חיפוש טקסט
    if (_searchText.isNotEmpty) {
      filtered = filtered.where((f) {
        return f.name.contains(_searchText) ||
            f.role.contains(_searchText) ||
            f.exercise.contains(_searchText);
      });
    }

    // הצגת נבחרים בלבד
    if (_showOnlySelected) {
      filtered = filtered.where((f) => _selectedFeedbackIds.contains(f.id));
    }

    return filtered.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // בחירת הכל / ביטול בחירת הכל
  void _toggleSelectAll() {
    setState(() {
      final filtered = _getFilteredFeedbacks();
      if (_selectedFeedbackIds.length == filtered.length) {
        // ביטול הכל
        _selectedFeedbackIds.clear();
      } else {
        // בחירת הכל
        _selectedFeedbackIds.clear();
        for (final f in filtered) {
          if (f.id != null) _selectedFeedbackIds.add(f.id!);
        }
      }
    });
  }

  // ניקוי כל הסינונים
  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _feedbackType = null;
      _rangeSubType = null;
      _selectedInstructor = null;
      _selectedFolder = null;
      _searchText = '';
      _showOnlySelected = false;
    });
  }

  // בחירת תאריך התחלה
  Future<void> _pickDateFrom() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('he'),
    );
    if (result != null) {
      setState(() => _dateFrom = result);
    }
  }

  // בחירת תאריך סיום
  Future<void> _pickDateTo() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('he'),
    );
    if (result != null) {
      setState(() => _dateTo = result);
    }
  }

  // ייצוא המשובים הנבחרים
  Future<void> _exportSelected() async {
    if (_selectedFeedbackIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אנא בחר לפחות משוב אחד לייצוא')),
      );
      return;
    }

    // בדיקת הרשאות
    if (currentUser?.role != 'Admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('רק מנהל מערכת יכול לייצא משובים')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      // מציאת המשובים הנבחרים
      final selectedFeedbacks = feedbackStorage
          .where((f) => f.id != null && _selectedFeedbackIds.contains(f.id))
          .toList();

      if (selectedFeedbacks.isEmpty) {
        throw Exception('לא נמצאו משובים נבחרים');
      }

      // ייצוא לגיליונות נפרדים
      final url =
          await FeedbackExportService.exportMultipleFeedbacksToSeparateSheets(
            context: context,
            feedbacks: selectedFeedbacks,
          );

      if (url != null && url.isNotEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${selectedFeedbacks.length} משובים יוצאו בהצלחה!\nכל משוב בגיליון נפרד.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // פתיחה אוטומטית
        await FeedbackExportService.openGoogleSheet(url);

        // ניקוי הבחירה
        setState(() => _selectedFeedbackIds.clear());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ שגיאה בייצוא: $e'),
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
    final filteredFeedbacks = _getFilteredFeedbacks();
    final instructors =
        feedbackStorage
            .map((f) => f.instructorName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final allSelected =
        filteredFeedbacks.isNotEmpty &&
        _selectedFeedbackIds.length == filteredFeedbacks.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ייצוא משובים (${_selectedFeedbackIds.length} נבחרו)'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            // כפתור עזרה
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      title: const Text('עזרה'),
                      content: const SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'איך להשתמש:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text('1. סנן משובים לפי הצורך'),
                            Text('2. בחר משובים בודדים או לחץ "בחר הכל"'),
                            Text('3. לחץ "ייצא משובים נבחרים"'),
                            SizedBox(height: 12),
                            Text(
                              'ייצוא:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text('• כל משוב יוצא לגיליון/טאב נפרד'),
                            Text('• הקובץ ייפתח אוטומטית'),
                            Text('• לא נדרסים קבצים קיימים'),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('סגור'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: _isExporting
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('מייצא נתונים...'),
                    SizedBox(height: 8),
                    Text(
                      'אנא המתן, זה עשוי לקחת מספר שניות',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // פאנל סינון
                  ExpansionTile(
                    title: const Text(
                      'סינון משובים',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    initiallyExpanded: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // חיפוש טקסט
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'חיפוש (שם / תפקיד / תרגיל)',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => _searchText = v),
                            ),
                            const SizedBox(height: 12),

                            // תאריכים
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _pickDateFrom,
                                    icon: const Icon(
                                      Icons.calendar_today,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _dateFrom == null
                                          ? 'מתאריך'
                                          : '${_dateFrom!.day}/${_dateFrom!.month}/${_dateFrom!.year}',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _pickDateTo,
                                    icon: const Icon(
                                      Icons.calendar_today,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _dateTo == null
                                          ? 'עד תאריך'
                                          : '${_dateTo!.day}/${_dateTo!.month}/${_dateTo!.year}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // סוג משוב
                            DropdownButtonFormField<String>(
                              value: _feedbackType,
                              decoration: const InputDecoration(
                                labelText: 'סוג משוב',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('הכל'),
                                ),
                                DropdownMenuItem(
                                  value: 'מטווחים',
                                  child: Text('מטווחים'),
                                ),
                                DropdownMenuItem(
                                  value: 'אחר',
                                  child: Text('אחר (לא מטווחים)'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _feedbackType = v),
                            ),
                            const SizedBox(height: 12),

                            // תיקייה
                            DropdownButtonFormField<String>(
                              value: _selectedFolder,
                              decoration: const InputDecoration(
                                labelText: 'תיקייה',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('כל התיקיות'),
                                ),
                                ...feedbackFolders.map(
                                  (f) => DropdownMenuItem(
                                    value: f,
                                    child: Text(f),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedFolder = v),
                            ),
                            const SizedBox(height: 12),

                            // תת-קטגוריה (רק למטווחים)
                            if (_feedbackType == 'מטווחים' ||
                                _selectedFolder == 'מטווחי ירי')
                              Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    value: _rangeSubType,
                                    decoration: const InputDecoration(
                                      labelText: 'תת-קטגוריה',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: null,
                                        child: Text('הכל'),
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
                                        setState(() => _rangeSubType = v),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),

                            // מדריך
                            DropdownButtonFormField<String>(
                              value: _selectedInstructor,
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
                            const SizedBox(height: 12),

                            // כפתורים
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _clearFilters,
                                    icon: const Icon(Icons.clear_all),
                                    label: const Text('נקה סינונים'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _showOnlySelected = !_showOnlySelected;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _showOnlySelected
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                    child: Text(
                                      _showOnlySelected
                                          ? 'הצג הכל'
                                          : 'הצג נבחרים',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // סרגל פעולות
                  Container(
                    color: Colors.blueGrey.shade800,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${filteredFeedbacks.length} משובים | ${_selectedFeedbackIds.length} נבחרו',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ElevatedButton.icon(
                          onPressed: _toggleSelectAll,
                          icon: Icon(
                            allSelected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                          ),
                          label: Text(allSelected ? 'בטל הכל' : 'בחר הכל'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // רשימת משובים
                  Expanded(
                    child: filteredFeedbacks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.inbox,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text('אין משובים תואמים'),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('נקה סינונים'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredFeedbacks.length,
                            itemBuilder: (ctx, i) {
                              final feedback = filteredFeedbacks[i];
                              final isSelected = _selectedFeedbackIds.contains(
                                feedback.id,
                              );

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.blueGrey.shade800,
                                child: CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedFeedbackIds.add(feedback.id!);
                                      } else {
                                        _selectedFeedbackIds.remove(
                                          feedback.id,
                                        );
                                      }
                                    });
                                  },
                                  title: Text(
                                    '${feedback.role} — ${feedback.name}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('תרגיל: ${feedback.exercise}'),
                                      Text('מדריך: ${feedback.instructorName}'),
                                      if (feedback.settlement.isNotEmpty)
                                        Text('יישוב: ${feedback.settlement}'),
                                      Text(
                                        'תאריך: ${feedback.createdAt.toLocal().toString().split('.').first}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  secondary: Icon(
                                    feedback.folder == 'מטווחי ירי'
                                        ? Icons.my_location
                                        : Icons.assignment,
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // כפתור ייצוא
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed:
                              _selectedFeedbackIds.isEmpty || _isExporting
                              ? null
                              : _exportSelected,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            disabledBackgroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.download, size: 28),
                          label: Text(
                            _selectedFeedbackIds.isEmpty
                                ? 'בחר משובים לייצוא'
                                : 'ייצא ${_selectedFeedbackIds.length} משובים נבחרים',
                            style: const TextStyle(fontSize: 18),
                          ),
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
