import 'package:flutter/material.dart';
import '../data/feedback_store.dart';

class FeedbackFormPage extends StatefulWidget {
  final String? exercise;
  const FeedbackFormPage({super.key, this.exercise});

  @override
  State<FeedbackFormPage> createState() => _FeedbackFormPageState();
}

class _FeedbackFormPageState extends State<FeedbackFormPage> {
  final roles = ['רבש"ץ', 'סגן רב"ץ', 'מפקד מחלקה', 'סגן מפקד מחלקה', 'לוחם'];
  String? selectedRole;
  String name = '';
  String generalNote = '';

  final List<String> criteria = [
    'פוש',
    'הפצה',
    'חיילות פרט',
    'מיקום מפקד',
    'העברת מקל',
    'עמידה ביעדים',
  ];

  final Map<String, int> scores = {};
  final Map<String, String> notes = {};

  @override
  void initState() {
    super.initState();
    for (final c in criteria) {
      scores[c] = 0;
      notes[c] = '';
    }
  }

  void _save() {
    final List<Map<String, dynamic>> criteriaList = [];
    for (final c in criteria) {
      final s = scores[c] ?? 0;
      if (s != 0) {
        criteriaList.add({'name': c, 'score': s, 'note': notes[c] ?? ''});
      }
    }

    FeedbackStore.feedbacks.add({
      'exercise': widget.exercise ?? '',
      'role': selectedRole ?? '',
      'name': name,
      'criteria': criteriaList,
      'comment': generalNote,
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('משוב נשמר')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('משוב - ${widget.exercise ?? ''}')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            const Text('בחר תפקיד'),
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
                  items: items
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedRole = v),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: 'שם'),
              onChanged: (v) => name = v,
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            ...criteria.map((c) {
              final val = scores[c] ?? 0;
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
                    Row(
                      children: [1, 3, 5].map((v) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(v.toString()),
                            selected: val == v,
                            onSelected: (_) => setState(() => scores[c] = v),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'הערה לקריטריון',
                      ),
                      maxLines: 2,
                      onChanged: (t) => notes[c] = t,
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: 'הערה כללית'),
              maxLines: 3,
              onChanged: (v) => generalNote = v,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('שמור משוב'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
