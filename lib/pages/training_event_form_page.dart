import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../main.dart';
import '../services/training_program_474_service.dart';

/// טופס הוספה/עריכה של אירוע אימון
class TrainingEventFormPage extends StatefulWidget {
  final String? eventId; // null = הוספה חדשה, לא null = עריכה

  const TrainingEventFormPage({super.key, this.eventId});

  @override
  State<TrainingEventFormPage> createState() => _TrainingEventFormPageState();
}

class _TrainingEventFormPageState extends State<TrainingEventFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _customSettlementController = TextEditingController();
  final _customTrainingTypeController = TextEditingController();
  final _customInstructorController = TextEditingController();
  final _locationController = TextEditingController();

  // State
  DateTime _selectedDate = DateTime.now();
  String? _selectedSettlement;
  String? _selectedTrainingType;
  final Set<String> _selectedInstructors = {};
  bool _isLoading = false;
  bool _showCustomSettlement = false;
  bool _showCustomTrainingType = false;

  // Training types
  static const List<String> _trainingTypes = [
    'מטווחים',
    'מגנט',
    'אימון ביישוב',
    'לשבייה',
    'אחר...',
  ];

  TrainingEvent? _existingEvent;

  @override
  void initState() {
    super.initState();
    if (widget.eventId != null) {
      _loadExistingEvent();
    }
  }

  @override
  void dispose() {
    _customSettlementController.dispose();
    _customTrainingTypeController.dispose();
    _customInstructorController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _isEditMode => widget.eventId != null;
  bool get _isAdmin => currentUser?.role == 'Admin';
  bool get _isInstructor => currentUser?.role == 'Instructor';

  /// טען אירוע קיים לעריכה
  Future<void> _loadExistingEvent() async {
    setState(() => _isLoading = true);

    final event = await TrainingProgram474Service.getTrainingEventById(
      widget.eventId!,
    );

    if (event != null && mounted) {
      setState(() {
        _existingEvent = event;
        _selectedDate = event.date;
        _locationController.text = event.location;
        _selectedInstructors.addAll(event.instructors);

        // Settlement
        if (golanSettlements.contains(event.settlement)) {
          _selectedSettlement = event.settlement;
        } else {
          _selectedSettlement = 'אחר...';
          _showCustomSettlement = true;
          _customSettlementController.text = event.settlement;
        }

        // Training type
        if (_trainingTypes.contains(event.trainingType)) {
          _selectedTrainingType = event.trainingType;
        } else {
          _selectedTrainingType = 'אחר...';
          _showCustomTrainingType = true;
          _customTrainingTypeController.text = event.trainingType;
        }
      });
    }

    setState(() => _isLoading = false);
  }

  /// האם מדריך יכול לערוך את המדריך הספציפי
  bool _canEditInstructor(String instructor) {
    if (_isAdmin) return true; // אדמין יכול הכל
    if (!_isEditMode) return true; // הוספה חדשה = כולם יכולים הכל
    // עריכה + מדריך = רק השם שלו
    return instructor == currentUser?.name;
  }

  /// האם השדה נעול
  bool _isFieldLocked() {
    return _isEditMode && _isInstructor && !_isAdmin;
  }

  /// בחירת תאריך
  Future<void> _pickDate() async {
    if (_isFieldLocked()) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  /// הוספת מדריך ידני
  void _addCustomInstructor() {
    final name = _customInstructorController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('נא להזין שם מדריך')));
      return;
    }

    setState(() {
      _selectedInstructors.add(name);
      _customInstructorController.clear();
    });
  }

  /// שמירת אירוע
  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    // בדיקות
    if (_selectedInstructors.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('נא לבחור לפחות מדריך אחד')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // קבל ערכים
      final settlement = _showCustomSettlement
          ? _customSettlementController.text.trim()
          : _selectedSettlement ?? '';

      final trainingType = _showCustomTrainingType
          ? _customTrainingTypeController.text.trim()
          : _selectedTrainingType ?? '';

      final location = _locationController.text.trim();

      if (settlement.isEmpty || trainingType.isEmpty || location.isEmpty) {
        throw Exception('נא למלא את כל השדות');
      }

      final event = TrainingEvent(
        id: widget.eventId,
        date: _selectedDate,
        settlement: settlement,
        trainingType: trainingType,
        instructors: _selectedInstructors.toList()..sort(),
        location: location,
        createdBy: _existingEvent?.createdBy ?? currentUser?.uid ?? '',
        createdAt: _existingEvent?.createdAt ?? DateTime.now(),
        lastModified: DateTime.now(),
        lastModifiedBy: currentUser?.uid ?? '',
      );

      bool success;
      if (_isEditMode) {
        success = await TrainingProgram474Service.updateTrainingEvent(event);
      } else {
        final id = await TrainingProgram474Service.addTrainingEvent(event);
        success = id != null;
      }

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditMode ? 'אירוע עודכן בהצלחה' : 'אירוע נוסף בהצלחה',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // חזור עם אינדיקציה שהצליח
      } else {
        throw Exception('שגיאה בשמירה');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? 'עריכת אירוע אימון' : 'הוספת אירוע אימון'),
          actions: [
            if (_isEditMode && _isInstructor && !_isAdmin)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Chip(
                  label: const Text(
                    'עריכה מוגבלת',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  backgroundColor: Colors.orange,
                  avatar: const Icon(Icons.lock, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // הודעה למדריך בעריכה
                      if (_isEditMode && _isInstructor && !_isAdmin)
                        Card(
                          color: Colors.orange.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.orange.shade800,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'כמדריך, ניתן להוסיף/להסיר רק את השם שלך מרשימת המדריכים',
                                    style: TextStyle(
                                      color: Colors.orange.shade900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // תאריך
                      _buildDateField(),
                      const SizedBox(height: 16),

                      // ישוב
                      _buildSettlementField(),
                      const SizedBox(height: 16),

                      // סוג אימון
                      _buildTrainingTypeField(),
                      const SizedBox(height: 16),

                      // מיקום
                      _buildLocationField(),
                      const SizedBox(height: 24),

                      // מדריכים
                      _buildInstructorsSection(),
                      const SizedBox(height: 32),

                      // כפתור שמירה
                      ElevatedButton(
                        onPressed: _isLoading ? null : _saveEvent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: Text(
                          _isEditMode ? 'שמור שינויים' : 'הוסף אירוע',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildDateField() {
    final isLocked = _isFieldLocked();
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.calendar_today,
          color: isLocked ? Colors.grey : Colors.blue,
        ),
        title: const Text(
          'תאריך',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          DateFormat('dd/MM/yyyy').format(_selectedDate),
          style: const TextStyle(fontSize: 16),
        ),
        trailing: isLocked
            ? const Icon(Icons.lock, color: Colors.grey)
            : const Icon(Icons.edit, color: Colors.blue),
        enabled: !isLocked,
        onTap: isLocked ? null : _pickDate,
      ),
    );
  }

  Widget _buildSettlementField() {
    final isLocked = _isFieldLocked();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedSettlement,
          decoration: InputDecoration(
            labelText: 'ישוב',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(
              Icons.location_city,
              color: isLocked ? Colors.grey : null,
            ),
            suffixIcon: isLocked
                ? const Icon(Icons.lock, color: Colors.grey)
                : null,
          ),
          items: [
            ...golanSettlements.map(
              (s) => DropdownMenuItem(value: s, child: Text(s)),
            ),
            const DropdownMenuItem(
              value: 'אחר...',
              child: Text('אחר (הזן ידנית)...'),
            ),
          ],
          onChanged: isLocked
              ? null
              : (val) {
                  setState(() {
                    _selectedSettlement = val;
                    _showCustomSettlement = val == 'אחר...';
                  });
                },
          validator: (val) =>
              val == null || val.isEmpty ? 'נא לבחור ישוב' : null,
        ),
        if (_showCustomSettlement) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _customSettlementController,
            enabled: !isLocked,
            decoration: InputDecoration(
              labelText: 'שם הישוב',
              border: const OutlineInputBorder(),
              prefixIcon: Icon(
                Icons.edit,
                color: isLocked ? Colors.grey : null,
              ),
              suffixIcon: isLocked
                  ? const Icon(Icons.lock, color: Colors.grey)
                  : null,
            ),
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'נא להזין שם ישוב' : null,
          ),
        ],
      ],
    );
  }

  Widget _buildTrainingTypeField() {
    final isLocked = _isFieldLocked();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedTrainingType,
          decoration: InputDecoration(
            labelText: 'סוג אימון',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(
              Icons.fitness_center,
              color: isLocked ? Colors.grey : null,
            ),
            suffixIcon: isLocked
                ? const Icon(Icons.lock, color: Colors.grey)
                : null,
          ),
          items: _trainingTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: isLocked
              ? null
              : (val) {
                  setState(() {
                    _selectedTrainingType = val;
                    _showCustomTrainingType = val == 'אחר...';
                  });
                },
          validator: (val) =>
              val == null || val.isEmpty ? 'נא לבחור סוג אימון' : null,
        ),
        if (_showCustomTrainingType) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _customTrainingTypeController,
            enabled: !isLocked,
            decoration: InputDecoration(
              labelText: 'סוג האימון',
              border: const OutlineInputBorder(),
              prefixIcon: Icon(
                Icons.edit,
                color: isLocked ? Colors.grey : null,
              ),
              suffixIcon: isLocked
                  ? const Icon(Icons.lock, color: Colors.grey)
                  : null,
            ),
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'נא להזין סוג אימון' : null,
          ),
        ],
      ],
    );
  }

  Widget _buildLocationField() {
    final isLocked = _isFieldLocked();
    return TextFormField(
      controller: _locationController,
      enabled: !isLocked,
      decoration: InputDecoration(
        labelText: 'מיקום',
        hintText: 'לדוגמה: מטווח קצרין, בסיס 474',
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.place, color: isLocked ? Colors.grey : null),
        suffixIcon: isLocked
            ? const Icon(Icons.lock, color: Colors.grey)
            : null,
      ),
      validator: (val) =>
          val == null || val.trim().isEmpty ? 'נא להזין מיקום' : null,
    );
  }

  Widget _buildInstructorsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'מדריכים',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // מדריכים נבחרים (chips)
            if (_selectedInstructors.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedInstructors.map((instructor) {
                  final canEdit = _canEditInstructor(instructor);
                  return Chip(
                    label: Text(instructor),
                    deleteIcon: canEdit
                        ? const Icon(Icons.close, size: 18)
                        : null,
                    onDeleted: canEdit
                        ? () => setState(
                            () => _selectedInstructors.remove(instructor),
                          )
                        : null,
                    backgroundColor: canEdit
                        ? Colors.blue.shade100
                        : Colors.grey.shade300,
                  );
                }).toList(),
              ),
            const Divider(height: 24),

            // רשימת מדריכים - checkboxes
            const Text(
              'בחר מהרשימה:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...brigade474Instructors.map((instructor) {
              final canEdit = _canEditInstructor(instructor);
              return CheckboxListTile(
                title: Text(instructor),
                value: _selectedInstructors.contains(instructor),
                enabled: canEdit,
                onChanged: canEdit
                    ? (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedInstructors.add(instructor);
                          } else {
                            _selectedInstructors.remove(instructor);
                          }
                        });
                      }
                    : null,
                secondary: canEdit
                    ? null
                    : const Icon(Icons.lock, size: 16, color: Colors.grey),
              );
            }),
            const Divider(height: 24),

            // הוספת מדריך ידני
            const Text(
              'הוסף מדריך נוסף:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customInstructorController,
                    decoration: const InputDecoration(
                      hintText: 'הזן שם מדריך...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addCustomInstructor(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addCustomInstructor,
                  icon: const Icon(Icons.add),
                  label: const Text('הוסף'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
