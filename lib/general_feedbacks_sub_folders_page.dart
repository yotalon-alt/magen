import 'package:flutter/material.dart';
import 'instructor_course_selection_feedbacks_page.dart';
import 'main.dart';

/// דף תת-תיקיות של "משובים כללי"
/// מציג 2 אופציות: משובים רגילים ומיונים לקורס מדריכים
class GeneralFeedbacksSubFoldersPage extends StatelessWidget {
  const GeneralFeedbacksSubFoldersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משובים – כללי'),
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
              const SizedBox(height: 20),
              const Text(
                'בחר סוג משוב',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // כרטיס משובים רגילים
              _buildOptionCard(
                context: context,
                title: 'משובים רגילים',
                subtitle: 'משובי תרגילים ופעילויות',
                icon: Icons.feedback,
                color: Colors.blueGrey.shade700,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RegularFeedbacksListPage(),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // כרטיס מיונים לקורס מדריכים
              _buildOptionCard(
                context: context,
                title: 'מיונים לקורס מדריכים',
                subtitle: 'משובי מיון למועמדים',
                icon: Icons.school,
                color: Colors.purple.shade700,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const InstructorCourseSelectionFeedbacksPage(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// דף רשימת משובים רגילים (מתוך משובים כללי)
class RegularFeedbacksListPage extends StatefulWidget {
  const RegularFeedbacksListPage({super.key});

  @override
  State<RegularFeedbacksListPage> createState() =>
      _RegularFeedbacksListPageState();
}

class _RegularFeedbacksListPageState extends State<RegularFeedbacksListPage> {
  bool _isRefreshing = false;

  Future<void> _refreshFeedbacks() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      final isAdmin = currentUser?.role == 'Admin';
      await loadFeedbacksForCurrentUser(isAdmin: isAdmin);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('רשימת המשובים עודכנה'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 16, left: 16, right: 16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בטעינת משובים: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter feedbacks for "משובים – כללי"
    final filteredFeedbacks = feedbackStorage
        .where((f) => f.folder == 'משובים – כללי' || f.folder.isEmpty)
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משובים רגילים'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.pop(context),
            tooltip: 'חזרה',
          ),
          actions: [
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isRefreshing ? null : _refreshFeedbacks,
              tooltip: 'רענן רשימה',
            ),
          ],
        ),
        body: filteredFeedbacks.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('אין משובים בתיקייה זו'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('חזרה'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: filteredFeedbacks.length,
                itemBuilder: (_, i) {
                  final f = filteredFeedbacks[i];
                  final date = f.createdAt
                      .toLocal()
                      .toString()
                      .split('.')
                      .first;
                  return ListTile(
                    title: Text('${f.role} — ${f.name}'),
                    subtitle: Text(
                      '${f.exercise} • ${f.instructorName.isNotEmpty ? '${f.instructorName} • ' : ''}$date',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FeedbackDetailsPage(feedback: f),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
