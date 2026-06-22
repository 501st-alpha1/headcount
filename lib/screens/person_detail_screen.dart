import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/event.dart';
import '../models/guest.dart';
import '../models/person.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';
import 'event_detail_screen.dart';
import 'person_editor_screen.dart';

/// Read-only detail view for one person: contact platforms, global
/// notes, interest tags, and every event they're on with their RSVP
/// status for each — answering "what's this person's status everywhere?"
/// Editing happens via a separate screen (PersonEditorScreen), reached
/// through the edit action in the app bar.
class PersonDetailScreen extends ConsumerWidget {
  final String personId;

  const PersonDetailScreen({super.key, required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return switch (snapshotAsync) {
      AsyncData(:final value) => _buildForSnapshot(context, value),
      AsyncError(:final error) => Scaffold(
          appBar: AppBar(title: const Text('Person')),
          body: Center(child: Text('Could not load your data: $error')),
        ),
      _ => Scaffold(
          appBar: AppBar(title: const Text('Person')),
          body: const Center(child: CircularProgressIndicator()),
        ),
    };
  }

  Widget _buildForSnapshot(BuildContext context, DataSnapshot snapshot) {
    final person = snapshot.personById(personId);

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Person')),
        body: const Center(child: Text('This person no longer exists.')),
      );
    }

    final eventsAndGuests = snapshot.eventsFor(personId)
      ..sort((a, b) => b.$1.date.compareTo(a.$1.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonEditorScreen(personId: person.id),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (person.platforms.isNotEmpty) ...[
            _SectionLabel('Platforms'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final platform in person.platforms)
                  Chip(label: Text(platform)),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (person.notes.isNotEmpty) ...[
            _SectionLabel('Notes'),
            Text(person.notes),
            const SizedBox(height: 20),
          ],
          if (person.interests.isNotEmpty) ...[
            _SectionLabel('Interests'),
            for (final interest in person.interests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InterestRow(interest: interest),
              ),
            const SizedBox(height: 20),
          ],
          _SectionLabel('Events'),
          if (eventsAndGuests.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Not on any events yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final pair in eventsAndGuests)
              _EventRsvpRow(
                event: pair.$1,
                guest: pair.$2,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          EventDetailScreen(eventId: pair.$1.id),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _InterestRow extends StatelessWidget {
  final InterestTag interest;

  const _InterestRow({required this.interest});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            interest.tag,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(interest.level.label, style: theme.textTheme.bodyMedium),
              if (interest.notes.isNotEmpty)
                Text(
                  interest.notes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventRsvpRow extends StatelessWidget {
  final Event event;
  final Guest guest;
  final VoidCallback onTap;

  const _EventRsvpRow({
    required this.event,
    required this.guest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(event.name),
      subtitle: Text(event.date.toIsoString()),
      trailing: Text(guest.rsvp.label),
      onTap: onTap,
    );
  }
}
