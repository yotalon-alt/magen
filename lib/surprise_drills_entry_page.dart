import 'package:flutter/material.dart';
import 'range_training_page.dart';
import 'surprise_drills_temp_feedbacks_page.dart';

/// תרגילי הפתעה - Surprise Drills Entry Screen
///
/// This screen provides TWO options:
/// 1. Add New Feedback - Opens the form (RangeTrainingPage in surprise mode)
/// 2. Temporary Feedback - Opens list of drafts specific to surprise drills
class SurpriseDrillsEntryPage extends StatelessWidget {
  const SurpriseDrillsEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('תרגילי הפתעה 474'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Icon(Icons.bolt, size: 80, color: Colors.orangeAccent),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'תרגילי הפתעה 474',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Button 1: Add New Feedback
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RangeTrainingPage(
                            rangeType: 'הפתעה',
                            mode: 'surprise',
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
                    child: const Text('הוסף משוב חדש'),
                  ),
                ),
                const SizedBox(height: 24),

                // Button 2: Temporary Feedback
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const SurpriseDrillsTempFeedbacksPage(),
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
                    child: const Text('משובים זמניים'),
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
