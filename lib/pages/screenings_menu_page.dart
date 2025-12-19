import 'package:flutter/material.dart';
import '../main.dart';
import 'screenings_in_progress_page.dart';

class ScreeningsMenuPage extends StatelessWidget {
  const ScreeningsMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = currentUser?.role == 'Admin';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('תרגילי קורס מיונים'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 4,
                child: ListTile(
                  leading: const Icon(Icons.pending_actions),
                  title: const Text('משובים בתהליך'),
                  subtitle: const Text('מילוי שדות ריקים בלבד'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ScreeningsInProgressPage(
                        statusFilter: 'in_progress',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (isAdmin)
                Card(
                  elevation: 4,
                  child: ListTile(
                    leading: const Icon(Icons.library_add_check),
                    title: const Text('משובים סופיים'),
                    subtitle: const Text('עבור אדמין בלבד'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScreeningsInProgressPage(
                          statusFilter: 'completed',
                        ),
                      ),
                    ),
                  ),
                ),
              if (!isAdmin)
                Card(
                  elevation: 0,
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.lock, color: Colors.grey),
                    title: const Text('משובים סופיים'),
                    subtitle: const Text('זמין לאדמין בלבד'),
                    enabled: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
