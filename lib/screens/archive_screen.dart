import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../providers/data_providers.dart';
import 'event_detail_screen_placeholder.dart';
import 'widgets/event_card.dart';

/// Everything not currently on the home screen: unpinned events, and
/// pinned events whose post-event grace period has expired. Sorted most
/// recent first, since scrolling back through history is the main use.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _ArchiveBody(events: value.archivedEvents),
        AsyncError(:final error) =>
          Center(child: Text('Could not load your data: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ArchiveBody extends StatelessWidget {
  final List<Event> events;

  const _ArchiveBody({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Center(
        child: Text(
          'Nothing here yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: EventCard(
            event: event,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailScreenPlaceholder(event: event),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
