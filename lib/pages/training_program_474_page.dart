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
  final String collectionName;
  final String folderDisplayName;

  const TrainingProgram474Page({
    super.key,
    required this.collectionName,
    required this.folderDisplayName,
  });

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
  bool _isFiltersExpanded = false;
  bool _isRefreshing = false;

  @override
  void dispose() {
    _filterLocationController.dispose();
    super.dispose();
  }

  /// רענן נתונים
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
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
      MaterialPageRoute(
        builder: (ctx) => TrainingEventFormPage(
          collectionName: widget.collectionName,
        ),
      ),
    );
    // רענון אוטומטי מ-StreamBuilder
  }

  /// פתיחת טופס עריכה
  Future<void> _editEvent(String eventId) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => TrainingEventFormPage(
          eventId: eventId,
          collectionName: widget.collectionName,
        ),
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
        widget.collectionName,
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

  /// שינוי סטטוס ביצוע אימון (רק אדמין)
  Future<void> _toggleCompleted(TrainingEvent event) async {
    if (event.id == null) return;

    final userName = currentUser?.name ?? 'Admin';
    final bool success;

    if (event.isCompleted) {
      // ביטול סימון "בוצע"
      success = await TrainingProgram474Service.markAsNotCompleted(
        widget.collectionName,
        event.id!,
      );
    } else {
      // סימון כ"בוצע"
      success = await TrainingProgram474Service.markAsCompleted(
        widget.collectionName,
        event.id!,
        userName,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (event.isCompleted
                    ? 'האימון סומן כלא בוצע'
                    : 'האימון סומן כבוצע')
                : 'שגיאה בעדכון הסטטוס',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
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
          title: Text('תוכנית אימונים - ${widget.folderDisplayName}'),
          backgroundColor: Colors.green[800],
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
              onPressed: _isRefreshing ? null : _refreshData,
              tooltip: 'רענן נתונים',
            ),
          ],
        ),
        body: StreamBuilder<List<TrainingEvent>>(
          stream: TrainingProgram474Service.getTrainingEventsStream(
            widget.collectionName,
          ),
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
    // Check if any filters are active
    final hasActiveFilters =
        _filterSettlement != null ||
        _filterTrainingType != null ||
        _filterInstructor != null ||
        _filterLocationController.text.isNotEmpty ||
        _filterStartDate != null ||
        _filterEndDate != null;

    return Card(
      color: Colors.blueGrey.shade800,
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row with toggle button
            InkWell(
              onTap: () =>
                  setState(() => _isFiltersExpanded = !_isFiltersExpanded),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.filter_list,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'סינון',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (hasActiveFilters) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
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
                children: [
                  // Settlement filter
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ישוב',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterSettlement,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('הכל'),
                            ),
                            ...settlements.map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _filterSettlement = val),
                        ),
                      ),
                    ],
                  ),

                  // Training type filter
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'סוג אימון',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterTrainingType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('הכל'),
                            ),
                            ...trainingTypes.map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _filterTrainingType = val),
                        ),
                      ),
                    ],
                  ),

                  // Instructor filter
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'מדריך',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterInstructor,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('הכל'),
                            ),
                            ...instructors.map(
                              (i) => DropdownMenuItem(value: i, child: Text(i)),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _filterInstructor = val),
                        ),
                      ),
                    ],
                  ),

                  // Location filter
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'מיקום',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _filterLocationController,
                          decoration: const InputDecoration(
                            hintText: 'חיפוש חלקי...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),

                  // Start date
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'מתאריך',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        child: InkWell(
                          onTap: _pickStartDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_today, size: 20),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
                              _filterStartDate != null
                                  ? DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(_filterStartDate!)
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
                    ],
                  ),

                  // End date
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'עד תאריך',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 200,
                        child: InkWell(
                          onTap: _pickEndDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_today, size: 20),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
                              _filterEndDate != null
                                  ? DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(_filterEndDate!)
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
                    stream: TrainingProgram474Service.getTrainingEventsStream(
                      widget.collectionName,
                    ),
                    builder: (context, snapshot) {
                      final allEvents = snapshot.data ?? [];
                      final filteredEvents =
                          TrainingProgram474Service.filterEvents(
                            allEvents,
                            settlementFilter: _filterSettlement,
                            trainingTypeFilter: _filterTrainingType,
                            instructorFilter: _filterInstructor,
                            locationFilter: _filterLocationController.text
                                .trim(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildEventsTable(List<TrainingEvent> events) {
    final isAdmin = currentUser?.role == 'Admin';
    final isMobile = MediaQuery.of(context).size.width < 600;
    final fontSize = isMobile ? 12.0 : 14.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.all(Colors.green[100]),
          headingTextStyle: TextStyle(
            fontSize: fontSize + 1,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          dataTextStyle: TextStyle(fontSize: fontSize, color: Colors.black87),
          columns: [
            const DataColumn(
              label: Text(
                'תאריך',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'ישוב',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'סוג אימון',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'מדריכים',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'מיקום',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isAdmin)
              const DataColumn(
                label: Text(
                  'בוצע',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (isAdmin)
              const DataColumn(
                label: Text(
                  'מחיקה',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          rows: events.map((event) {
            return DataRow(
              color: event.isCompleted
                  ? WidgetStateProperty.all(Colors.grey[300])
                  : null,
              onSelectChanged: (selected) {
                if (selected == true && event.id != null) {
                  _editEvent(event.id!);
                }
              },
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
                if (isAdmin)
                  DataCell(
                    Checkbox(
                      value: event.isCompleted,
                      onChanged: (_) => _toggleCompleted(event),
                      activeColor: Colors.green[700],
                    ),
                  ),
                if (isAdmin)
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteEvent(event),
                      tooltip: 'מחק',
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
