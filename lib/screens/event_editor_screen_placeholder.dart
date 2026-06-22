import 'package:flutter/material.dart';

/// Temporary placeholder. Will be replaced by the real event creation
/// form (name, date, description) in an upcoming build step. Exists now
/// so the home screen's "+" button has somewhere to navigate to.
class EventEditorScreenPlaceholder extends StatelessWidget {
  const EventEditorScreenPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Event')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'The event creation form is coming in the next build step.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}
