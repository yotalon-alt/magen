import 'package:flutter/material.dart';
import '../instructor_course_feedback_page.dart';
import 'screenings_in_progress_page.dart';
import '../widgets/standard_back_button.dart';

class ScreeningsMenuPage extends StatefulWidget {
  final String courseType; // expected: 'miunim'
  const ScreeningsMenuPage({super.key, required this.courseType});

  @override
  State<ScreeningsMenuPage> createState() => _ScreeningsMenuPageState();
}

class _ScreeningsMenuPageState extends State<ScreeningsMenuPage> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מיונים לקורס מדריכים'),
          leading: const StandardBackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Icon(Icons.school, size: 80, color: Colors.purple),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'מיונים לקורס מדריכים',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Button 1: Open new screening
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      // Navigate to feedback page without creating draft
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InstructorCourseFeedbackPage(),
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
                    child: const Text('פתיחת משוב חדש'),
                  ),
                ),
                const SizedBox(height: 24),

                // Button 2: Temporary (in-progress) screenings
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScreeningsInProgressPage(
                            courseType: widget.courseType,
                            statusFilter: 'draft',
                          ),
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
                    child: const Text('מיונים זמניים (בתהליך)'),
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
