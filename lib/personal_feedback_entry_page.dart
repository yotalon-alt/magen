import 'package:flutter/material.dart';
import 'main.dart'; // For FeedbackFormPage
import 'personal_feedback_temp_list_page.dart';
import 'widgets/standard_back_button.dart';

/// מסך כניסה למשובים אישיים (מעגל פתוח / מעגל פרוץ / סריקות רחוב)
///
/// מציג שני כפתורים:
/// 1. משוב חדש - פותח את הטופס
/// 2. משובים זמניים - פותח רשימת טיוטות
class PersonalFeedbackEntryPage extends StatelessWidget {
  final String exercise;

  const PersonalFeedbackEntryPage({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(exercise),
          leading: const StandardBackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                const Icon(Icons.person, size: 80, color: Colors.green),
                const SizedBox(height: 32),

                // Title
                Text(
                  exercise,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // כפתור 1: משוב חדש
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FeedbackFormPage(exercise: exercise),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle, size: 28),
                        SizedBox(width: 12),
                        Text('משוב חדש'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // כפתור 2: משובים זמניים
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PersonalFeedbackTempListPage(exercise: exercise),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_note, size: 28),
                        SizedBox(width: 12),
                        Text('משובים זמניים'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
