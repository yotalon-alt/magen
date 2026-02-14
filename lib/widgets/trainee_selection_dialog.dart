import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Dialog לבחירת חניכים עם checkboxes
/// מציג רשימה של חניכים לבחירה, עם אפשרות לחיפוש והוספה ידנית
class TraineeSelectionDialog extends StatefulWidget {
  final String settlementName;
  final List<String> availableTrainees;
  final List<String> preSelectedTrainees;

  const TraineeSelectionDialog({
    super.key,
    required this.settlementName,
    required this.availableTrainees,
    this.preSelectedTrainees = const [],
  });

  @override
  State<TraineeSelectionDialog> createState() => _TraineeSelectionDialogState();
}

class _TraineeSelectionDialogState extends State<TraineeSelectionDialog> {
  late Set<String> selectedTrainees;
  Set<String> manuallyAddedTrainees = {}; // ✨ שמות שנוספו ידנית
  String searchQuery = '';
  final TextEditingController manualNameController = TextEditingController();
  bool saveManualToList = false; // ✨ האם לשמור את השם הידני למחלקה

  @override
  void initState() {
    super.initState();
    selectedTrainees = Set<String>.from(widget.preSelectedTrainees);

    // ✅ זיהוי שמות ידניים: שמות שנבחרו אבל לא ברשימה הזמינה
    for (final name in widget.preSelectedTrainees) {
      if (!widget.availableTrainees.contains(name)) {
        manuallyAddedTrainees.add(name);
      }
    }
  }

  @override
  void dispose() {
    manualNameController.dispose();
    super.dispose();
  }

  List<String> get filteredTrainees {
    if (searchQuery.isEmpty) {
      return widget.availableTrainees;
    }
    return widget.availableTrainees
        .where((name) => name.contains(searchQuery))
        .toList();
  }

  void _addManualTrainee() async {
    final name = manualNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן שם')));
      return;
    }

    // בדיקה אם השם כבר קיים
    if (selectedTrainees.contains(name)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('שם זה כבר נבחר')));
      return;
    }

    setState(() {
      selectedTrainees.add(name);
      manuallyAddedTrainees.add(name); // ✨ עקוב אחרי שמות ידניים
      manualNameController.clear();
    });

    // ✨ שמירה למחלקה אם מסומן
    if (saveManualToList) {
      await _saveTraineeToSettlement(name);
    }
  }

  /// ✨ שומר חניך למחלקת היישוב ב-Firestore
  Future<void> _saveTraineeToSettlement(String traineeName) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('settlements')
          .doc(widget.settlementName)
          .collection('trainees')
          .doc(traineeName);

      await docRef.set({
        'name': traineeName,
        'addedAt': FieldValue.serverTimestamp(),
        'addedManually': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ "$traineeName" נשמר למחלקת ${widget.settlementName}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🗑️ מוחק חניך ממחלקת היישוב ב-Firestore
  Future<void> _deleteTraineeFromSettlement(String traineeName) async {
    // דיאלוג אישור
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת חניך'),
          content: Text(
            'האם אתה בטוח שברצונך למחוק את "$traineeName" ממחלקת ${widget.settlementName}?\n\n'
            'פעולה זו תמחק את החניך לצמיתות מרשימת המחלקה.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      // מחיקה מ-Firestore
      await FirebaseFirestore.instance
          .collection('settlements')
          .doc(widget.settlementName)
          .collection('trainees')
          .doc(traineeName)
          .delete();

      // הסרה מהרשימה המקומית
      setState(() {
        widget.availableTrainees.remove(traineeName);
        selectedTrainees.remove(traineeName);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🗑️ "$traineeName" נמחק ממחלקת ${widget.settlementName}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ שגיאה במחיקה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 📱 Dynamic sizing for better mobile experience
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.92).clamp(320.0, 600.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(550.0, 900.0);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'בחר חניכים - ${widget.settlementName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Search field
              TextField(
                decoration: const InputDecoration(
                  hintText: 'חפש חניך...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              ),
              const SizedBox(height: 10),

              // ✨ שיפור 1: הצגת חניכים שנוספו ידנית
              if (manuallyAddedTrainees.isNotEmpty) ...[
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.person_add,
                              size: 20,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'חניכים שנוספו ידנית (${manuallyAddedTrainees.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...manuallyAddedTrainees.map((trainee) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.0),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    trainee,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      manuallyAddedTrainees.remove(trainee);
                                      selectedTrainees.remove(trainee);
                                    });
                                  },
                                  tooltip: 'הסר',
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Select all / Clear buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          selectedTrainees.addAll(widget.availableTrainees);
                        });
                      },
                      icon: const Icon(Icons.check_box, size: 18),
                      label: const Text(
                        'בחר הכל',
                        style: TextStyle(fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          selectedTrainees.clear();
                          manuallyAddedTrainees.clear(); // ✨ נקה גם שמות ידניים
                        });
                      },
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text(
                        'נקה הכל',
                        style: TextStyle(fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),

              // Trainees list
              Expanded(
                child: filteredTrainees.isEmpty
                    ? const Center(child: Text('לא נמצאו חניכים'))
                    : ListView.builder(
                        itemCount: filteredTrainees.length,
                        itemBuilder: (context, index) {
                          final trainee = filteredTrainees[index];
                          final isSelected = selectedTrainees.contains(trainee);

                          return Row(
                            key: ValueKey('row_$trainee'),
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  key: ValueKey('checkbox_$trainee'),
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        selectedTrainees.add(trainee);
                                      } else {
                                        selectedTrainees.remove(trainee);
                                      }
                                    });
                                  },
                                  title: Text(
                                    trainee,
                                    style: const TextStyle(fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  activeColor: Colors.green,
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              // 🗑️ כפתור מחיקה מהמחלקה
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                tooltip: 'מחק חניך זה ממחלקת היישוב',
                                color: Colors.red,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                onPressed: () async {
                                  await _deleteTraineeFromSettlement(trainee);
                                },
                              ),
                            ],
                          );
                        },
                      ),
              ),

              const Divider(),
              const SizedBox(height: 12),

              // Manual entry section
              Card(
                color: Colors.blueGrey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'הוסף חניך ידנית',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: manualNameController,
                              decoration: const InputDecoration(
                                hintText: 'שם חניך',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addManualTrainee(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _addManualTrainee,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('הוסף'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ✨ שיפור 2: Checkbox לשמירה למחלקה
                      CheckboxListTile(
                        value: saveManualToList,
                        onChanged: (value) {
                          setState(() {
                            saveManualToList = value ?? false;
                          });
                        },
                        title: const Text(
                          'שמור שם זה למחלקת היישוב',
                          style: TextStyle(fontSize: 13),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Confirm button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context, selectedTrainees.toList());
                },
                icon: const Icon(Icons.check),
                label: Text('אשר בחירה (${selectedTrainees.length} נבחרו)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
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
