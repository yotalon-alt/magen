import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:excel/excel.dart';
import 'dart:typed_data';
import 'package:universal_html/html.dart' as html;
import '../main.dart';
import '../services/training_program_474_service.dart';
import 'training_event_form_page.dart';

/// דף תוכנית אימונים 474 - טבלה + סינונים + ייצוא
class TrainingProgram474Page extends StatefulWidget {
  const TrainingProgram474Page({super.key});

  @override
  State<TrainingProgram474Page> createState() => _TrainingProgram474PageState();
}

class _TrainingProgram474PageState extends State<TrainingProgram474Page> {
  // Filters state
  String? _filterSettlement;
  String? _filterTrainingType;
  String? _filterInstructor;
  final TextEditingController _filterLocationController =
      TextEditingController();
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  @override
  void dispose() {
    _filterLocationController.dispose();
    super.dispose();
  }

  /// נקה כל הסינונים
  void _clearFilters() {
    setState(() {
      _filterSettlement = null;
      _filterTrainingType = null;
      _filterInstructor = null;
      _filterLocationController.clear();
      _filterStartDate = null;
      _filterEndDate = null;
    });
  }

  /// בחירת תאריך התחלה
  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'בחר תאריך התחלה',
    );
    if (picked != null && mounted) {
      setState(() => _filterStartDate = picked);
    }
  }

  /// בחירת תאריך סיום
  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterEndDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'בחר תאריך סיום',
    );
    if (picked != null && mounted) {
      setState(() => _filterEndDate = picked);
    }
  }

  /// פתיחת טופס הוספה
  Future<void> _addEvent() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (ctx) => const TrainingEventFormPage()),
    );
    // רענון אוטומטי מ-StreamBuilder
  }

  /// פתיחת טופס עריכה
  Future<void> _editEvent(String eventId) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => TrainingEventFormPage(eventId: eventId),
      ),
    );
    // רענון אוטומטי מ-StreamBuilder
  }

  /// מחיקת אירוע (רק אדמין)
  Future<void> _deleteEvent(TrainingEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת אירוע'),
          content: Text(
            'האם למחוק את האירוע בתאריך ${DateFormat('dd/MM/yyyy').format(event.date)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('מחק', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && event.id != null) {
      final success = await TrainingProgram474Service.deleteTrainingEvent(
        event.id!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'אירוע נמחק בהצלחה' : 'שגיאה במחיקה'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  /// ייצוא לאקסל
  Future<void> _exportToExcel(List<TrainingEvent> events) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['תוכנית אימונים'];

      // Headers
      sheet.appendRow([
        TextCellValue('תאריך'),
        TextCellValue('ישוב'),
        TextCellValue('סוג אימון'),
        TextCellValue('מדריכים'),
        TextCellValue('מיקום'),
      ]);

      // Style header row
      for (int col = 0; col < 5; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
        );
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.blue,
          fontColorHex: ExcelColor.white,
        );
      }

      // Data rows
      for (final event in events) {
        sheet.appendRow([
          TextCellValue(DateFormat('dd/MM/yyyy').format(event.date)),
          TextCellValue(event.settlement),
          TextCellValue(event.trainingType),
          TextCellValue(event.instructors.join(', ')),
          TextCellValue(event.location),
        ]);
      }

      // Auto-fit columns
      for (int col = 0; col < 5; col++) {
        sheet.setColumnWidth(col, 20);
      }

      // Save and download
      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final blob = html.Blob([Uint8List.fromList(fileBytes)]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute(
            'download',
            'תוכנית_אימונים_474_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx',
          )
          ..click();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('הקובץ יוצא בהצלחה'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בייצוא: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('תוכנית אימונים הגמ"ר 474'),
          backgroundColor: Colors.green[800],
        ),
        body: StreamBuilder<List<TrainingEvent>>(
          stream: TrainingProgram474Service.getTrainingEventsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('שגיאה: ${snapshot.error}'));
            }

            final allEvents = snapshot.data ?? [];

            // Apply filters
            final filteredEvents = TrainingProgram474Service.filterEvents(
              allEvents,
              settlementFilter: _filterSettlement,
              trainingTypeFilter: _filterTrainingType,
              instructorFilter: _filterInstructor,
              locationFilter: _filterLocationController.text.trim(),
              startDate: _filterStartDate,
              endDate: _filterEndDate,
            );

            // Get unique values for dropdowns
            final settlements = TrainingProgram474Service.getUniqueSettlements(
              allEvents,
            );
            final trainingTypes =
                TrainingProgram474Service.getUniqueTrainingTypes(allEvents);
            final instructors = TrainingProgram474Service.getUniqueInstructors(
              allEvents,
            );

            return Column(
              children: [
                // Filters section
                _buildFiltersSection(settlements, trainingTypes, instructors),

                // Add button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addEvent,
                      icon: const Icon(Icons.add, size: 24),
                      label: const Text(
                        'הוספת אימון חדש',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),

                // Table
                Expanded(
                  child: filteredEvents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                allEvents.isEmpty
                                    ? 'אין אירועי אימון עדיין'
                                    : 'לא נמצאו אירועים מתאימים לסינון',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildEventsTable(filteredEvents),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFiltersSection(
    List<String> settlements,
    List<String> trainingTypes,
    List<String> instructors,
  ) {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔍 סינונים',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Row 1: Settlement, Training Type, Instructor
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // Settlement filter
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _filterSettlement,
                  decoration: const InputDecoration(
                    labelText: 'ישוב',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('הכל')),
                    ...settlements.map(
                      (s) => DropdownMenuItem(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: (val) => setState(() => _filterSettlement = val),
                ),
              ),

              // Training type filter
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _filterTrainingType,
                  decoration: const InputDecoration(
                    labelText: 'סוג אימון',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('הכל')),
                    ...trainingTypes.map(
                      (t) => DropdownMenuItem(value: t, child: Text(t)),
                    ),
                  ],
                  onChanged: (val) => setState(() => _filterTrainingType = val),
                ),
              ),

              // Instructor filter
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _filterInstructor,
                  decoration: const InputDecoration(
                    labelText: 'מדריך',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('הכל')),
                    ...instructors.map(
                      (i) => DropdownMenuItem(value: i, child: Text(i)),
                    ),
                  ],
                  onChanged: (val) => setState(() => _filterInstructor = val),
                ),
              ),

              // Location filter
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _filterLocationController,
                  decoration: const InputDecoration(
                    labelText: 'מיקום',
                    hintText: 'חיפוש חלקי...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Date range
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // Start date
              SizedBox(
                width: 200,
                child: InkWell(
                  onTap: _pickStartDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'מתאריך',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.calendar_today, size: 20),
                    ),
                    child: Text(
                      _filterStartDate != null
                          ? DateFormat('dd/MM/yyyy').format(_filterStartDate!)
                          : 'לא נבחר',
                      style: TextStyle(
                        color: _filterStartDate != null
                            ? Colors.black
                            : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),

              // End date
              SizedBox(
                width: 200,
                child: InkWell(
                  onTap: _pickEndDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'עד תאריך',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.calendar_today, size: 20),
                    ),
                    child: Text(
                      _filterEndDate != null
                          ? DateFormat('dd/MM/yyyy').format(_filterEndDate!)
                          : 'לא נבחר',
                      style: TextStyle(
                        color: _filterEndDate != null
                            ? Colors.black
                            : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('נקה סינון'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black87,
                ),
              ),
              const SizedBox(width: 12),
              StreamBuilder<List<TrainingEvent>>(
                stream: TrainingProgram474Service.getTrainingEventsStream(),
                builder: (context, snapshot) {
                  final allEvents = snapshot.data ?? [];
                  final filteredEvents = TrainingProgram474Service.filterEvents(
                    allEvents,
                    settlementFilter: _filterSettlement,
                    trainingTypeFilter: _filterTrainingType,
                    instructorFilter: _filterInstructor,
                    locationFilter: _filterLocationController.text.trim(),
                    startDate: _filterStartDate,
                    endDate: _filterEndDate,
                  );
                  return ElevatedButton.icon(
                    onPressed: filteredEvents.isEmpty
                        ? null
                        : () => _exportToExcel(filteredEvents),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('ייצוא ל-Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventsTable(List<TrainingEvent> events) {
    final isAdmin = currentUser?.role == 'Admin';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.green[100]),
          columns: const [
            DataColumn(
              label: Text(
                'תאריך',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'ישוב',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'סוג אימון',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'מדריכים',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'מיקום',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'פעולות',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: events.map((event) {
            return DataRow(
              cells: [
                DataCell(Text(DateFormat('dd/MM/yyyy').format(event.date))),
                DataCell(Text(event.settlement)),
                DataCell(Text(event.trainingType)),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      event.instructors.join(', '),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      event.location,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: event.id != null
                            ? () => _editEvent(event.id!)
                            : null,
                        tooltip: 'ערוך',
                      ),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteEvent(event),
                          tooltip: 'מחק',
                        ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
