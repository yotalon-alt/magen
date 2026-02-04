import 'package:flutter/material.dart';

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
  String searchQuery = '';
  final TextEditingController manualNameController = TextEditingController();
  bool saveManualToList = false;

  @override
  void initState() {
    super.initState();
    selectedTrainees = Set<String>.from(widget.preSelectedTrainees);
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

  void _addManualTrainee() {
    final name = manualNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא הזן שם')));
      return;
    }

    setState(() {
      selectedTrainees.add(name);
      manualNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: Container(
          width: 500,
          height: 600,
          padding: const EdgeInsets.all(16.0),
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search field
              TextField(
                decoration: const InputDecoration(
                  hintText: 'חפש חניך...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              ),
              const SizedBox(height: 12),

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
                      icon: const Icon(Icons.check_box),
                      label: const Text('בחר הכל'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          selectedTrainees.clear();
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('נקה'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),

              // Trainees list
              Expanded(
                child: filteredTrainees.isEmpty
                    ? const Center(child: Text('לא נמצאו חניכים'))
                    : ListView.builder(
                        itemCount: filteredTrainees.length,
                        itemBuilder: (context, index) {
                          final trainee = filteredTrainees[index];
                          final isSelected = selectedTrainees.contains(trainee);

                          return CheckboxListTile(
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
                            title: Text(trainee),
                            activeColor: Colors.green,
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
