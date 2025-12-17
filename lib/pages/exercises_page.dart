import 'package:flutter/material.dart';
import 'feedback_form_page.dart';

class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final exercises = ['מעגל פתוח', 'מעגל פרוץ', 'סריקות רחוב'];

    return Scaffold(
      appBar: AppBar(title: const Text('תרגילים')),
      body: ListView.builder(
        itemCount: exercises.length,
        itemBuilder: (_, i) {
          final ex = exercises[i];
          return ListTile(
            title: Text(ex),
            trailing: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FeedbackFormPage(exercise: ex)),
                );
              },
              child: const Text('פתח משוב'),
            ),
          );
        },
      ),
    );
  }
}
