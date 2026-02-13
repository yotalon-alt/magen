import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/standard_back_button.dart';

/// 🔫 Weapon Reset Page - Opens Google Slides presentation
class WeaponResetPage extends StatelessWidget {
  const WeaponResetPage({super.key});

  static const String presentationUrl =
      'https://docs.google.com/presentation/d/e/2PACX-1vQgohLn2s9j1IhzAUpG19tVss9I-F-qKN7syfgcNaHwIOyuVlivZ8I18jrLVt9EphMEIx26P_wP-xGu/pubembed?start=false&loop=false&delayms=3000';

  Future<void> _openPresentation(BuildContext context) async {
    final Uri url = Uri.parse(presentationUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('לא ניתן לפתוח את המצגת'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('איפוס נשק'),
          leading: const StandardBackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                const Icon(
                  Icons.hardware,
                  size: 80,
                  color: Colors.orangeAccent,
                ),
                const SizedBox(height: 24),

                // Title
                const Text(
                  'איפוס 50/200 מ\'',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Main Button
                ElevatedButton.icon(
                  onPressed: () => _openPresentation(context),
                  icon: const Icon(Icons.open_in_new, size: 28),
                  label: const Text(
                    'פתח מצגת',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 20,
                    ),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Flexible(
                        child: Text(
                          'המצגת תיפתח בחלון חדש',
                          style: TextStyle(fontSize: 14, color: Colors.black87),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
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
