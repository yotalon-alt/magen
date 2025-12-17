import 'package:flutter/material.dart';
import '../data/feedback_store.dart';

class FeedbacksPage extends StatelessWidget {
  const FeedbacksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('משובים')),
      body: ListView.builder(
        itemCount: FeedbackStore.feedbacks.length,
        itemBuilder: (_, i) {
          final f = FeedbackStore.feedbacks[i];
          final title = '${f['exercise'] ?? ''} ${f['role'] ?? ''} - ${f['name'] ?? ''}';
          return ListTile(
            title: Text(title),
            subtitle: Text(f['comment'] ?? ''),
          );
        },
      ),
    );
  }
}
