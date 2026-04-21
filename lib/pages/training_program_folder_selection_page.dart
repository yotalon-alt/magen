import 'package:flutter/material.dart';
import 'training_program_474_page.dart';
import '../widgets/standard_back_button.dart';

/// מסך בחירת תיקיית תוכנית אימונים
class TrainingProgramFolderSelectionPage extends StatelessWidget {
  const TrainingProgramFolderSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('שיבוץ מדריכים'),
          backgroundColor: Colors.green[800],
          leading: const StandardBackButton(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon
              Icon(Icons.calendar_month, size: 60, color: Colors.green[700]),
              const SizedBox(height: 20),

              const Text(
                'בחר תיקיית אימונים',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // מחלקות הגנה 474
              _buildFolderButton(
                context,
                title: 'מחלקות הגנה 474',
                icon: Icons.shield,
                color: Colors.green,
                collectionName: 'training_programs_474',
                folderDisplayName: 'מחלקות הגנה 474',
              ),
              const SizedBox(height: 16),

              // אימונים כללי
              _buildFolderButton(
                context,
                title: 'אימונים כללי',
                icon: Icons.fitness_center,
                color: Colors.blue,
                collectionName: 'training_programs_general',
                folderDisplayName: 'אימונים כללי',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required String collectionName,
    required String folderDisplayName,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrainingProgram474Page(
                collectionName: collectionName,
                folderDisplayName: folderDisplayName,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.7), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: Colors.white),
                  const SizedBox(width: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
