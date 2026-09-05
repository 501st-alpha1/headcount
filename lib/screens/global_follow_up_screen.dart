import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../models/person.dart';
import '../providers/data_providers.dart';
import 'person_follow_up_screen.dart';

/// A flat list of everyone who needs follow-up on at least one pinned
/// event, sorted by who hasn't been contacted in the longest time.
/// Tapping a person opens PersonFollowUpScreen for that person.
class GlobalFollowUpScreen extends ConsumerWidget {
  const GlobalFollowUpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Follow-up list')),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _buildBody(context, value.globalFollowUpList()),
        AsyncError(:final error) =>
          Center(child: Text('Could not load your data: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<(Person, List<Event>)> entries,
  ) {
    if (entries.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'All caught up',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'No one needs follow-up right now.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final (person, needingEvents) = entries[index];
        final eventNames = needingEvents.map((e) => e.name).join(', ');

        return ListTile(
          leading: CircleAvatar(
            child: Text(
              person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
            ),
          ),
          title: Text(person.name),
          subtitle: Text(
            '${needingEvents.length} event${needingEvents.length == 1 ? '' : 's'}: $eventNames',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    PersonFollowUpScreen(personId: person.id),
              ),
            );
          },
        );
      },
    );
  }
}
