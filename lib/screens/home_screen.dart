import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../providers/data_providers.dart';
import '../repository/load_result.dart';
import 'archive_screen.dart';
import 'event_detail_screen.dart';
import 'event_editor_screen.dart';
import 'groups_list_screen.dart';
import 'people_list_screen.dart';
import 'tags_list_screen.dart';
import 'widgets/event_card.dart';
import 'widgets/load_issues_banner.dart';

enum _HomeMenuAction { people, groups, tags, archive }

/// The app's home screen: pinned events (upcoming, or recently past and
/// still within the grace period), soonest first, with a way to reach
/// everything else via the overflow menu.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Headcount'),
        actions: [
          PopupMenuButton<_HomeMenuAction>(
            onSelected: (action) {
              final screen = switch (action) {
                _HomeMenuAction.people => const PeopleListScreen(),
                _HomeMenuAction.groups => const GroupsListScreen(),
                _HomeMenuAction.tags => const TagsListScreen(),
                _HomeMenuAction.archive => const ArchiveScreen(),
              };
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => screen),
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HomeMenuAction.people,
                child: ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('People'),
                ),
              ),
              PopupMenuItem(
                value: _HomeMenuAction.groups,
                child: ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Groups'),
                ),
              ),
              PopupMenuItem(
                value: _HomeMenuAction.tags,
                child: ListTile(
                  leading: Icon(Icons.interests_outlined),
                  title: Text('Tags'),
                ),
              ),
              PopupMenuItem(
                value: _HomeMenuAction.archive,
                child: ListTile(
                  leading: Icon(Icons.archive_outlined),
                  title: Text('Archive'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _HomeBody(
            events: value.eventsOnHomeScreen,
            issues: value.issues,
          ),
        AsyncError(:final error) => _ErrorState(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const EventEditorScreen(),
            ),
          );
        },
        tooltip: 'New event',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  final List<Event> events;
  final List<LoadIssue> issues;

  const _HomeBody({required this.events, required this.issues});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LoadIssuesBanner(issues: issues),
        Expanded(
          child: events.isEmpty
              ? const _EmptyState()
              : ListView.builder(
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
                              builder: (_) =>
                                  EventDetailScreen(eventId: event.id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No events yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first event.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('Could not load your data: $error'),
      ),
    );
  }
}
