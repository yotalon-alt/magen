import 'package:flutter/material.dart';
import 'range_training_page.dart';

/// מסך בחירת סוג מטווח
class RangeSelectionPage extends StatelessWidget {
  const RangeSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מטווחים'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'בחר סוג מטווח',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // טווח קצר
              _buildRangeTypeButton(
                context,
                title: 'טווח קצר',
                icon: Icons.arrow_forward,
                color: Colors.blue,
                rangeType: 'קצרים',
              ),
              const SizedBox(height: 20),

              // טווח רחוק
              _buildRangeTypeButton(
                context,
                title: 'טווח רחוק',
                icon: Icons.arrow_forward,
                color: Colors.orange,
                rangeType: 'ארוכים',
              ),
              const SizedBox(height: 20),

              // תרגילי הפתעה
              _buildRangeTypeButton(
                context,
                title: 'תרגילי הפתעה',
                icon: Icons.flash_on,
                color: Colors.purple,
                rangeType: 'הפתעה',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeTypeButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required String rangeType,
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
              builder: (_) => RangeTrainingPage(rangeType: rangeType),
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
              const Icon(Icons.arrow_back_ios, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
