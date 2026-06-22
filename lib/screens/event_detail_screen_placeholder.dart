import 'package:flutter/material.dart';

import '../models/event.dart';

/// Temporary placeholder. Will be replaced by the real Event Detail
/// screen (guest list, RSVP filters, follow-up filter, add guest) in an
/// upcoming build step. Exists now so Home/Archive have somewhere to
/// navigate to.
class EventDetailScreenPlaceholder extends StatelessWidget {
  final Event event;

  const EventDetailScreenPlaceholder({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(event.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${event.date.toIsoString()}'),
            const SizedBox(height: 8),
            Text('Description: ${event.description}'),
            const SizedBox(height: 8),
            Text('Guests: ${event.guests.length}'),
            const SizedBox(height: 24),
            const Text(
              'Full guest list and RSVP editing coming in the next build step.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
