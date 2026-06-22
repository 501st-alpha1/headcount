import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/person.dart';
import '../providers/data_providers.dart';
import 'person_detail_screen.dart';
import 'person_editor_screen.dart';

/// All people, grouped under A–Z section headers by first letter of
/// name. Includes a search field that filters across all groups at once.
class PeopleListScreen extends ConsumerStatefulWidget {
  const PeopleListScreen({super.key});

  @override
  ConsumerState<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends ConsumerState<PeopleListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _buildBody(context, value.people),
        AsyncError(:final error) =>
          Center(child: Text('Could not load your data: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PersonEditorScreen()),
          );
        },
        tooltip: 'New person',
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<Person> people) {
    final filtered = _query.isEmpty
        ? people
        : people
            .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final grouped = _groupByFirstLetter(filtered);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search people',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: people.isEmpty
              ? _buildEmptyState(context)
              : grouped.isEmpty
                  ? Center(
                      child: Text(
                        'No one matches "$_query".',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView(
                      children: [
                        for (final group in grouped) ...[
                          _LetterHeader(letter: group.$1),
                          for (final person in group.$2)
                            ListTile(
                              title: Text(person.name),
                              subtitle: person.platforms.isEmpty
                                  ? null
                                  : Text(person.platforms.join(', ')),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PersonDetailScreen(
                                      personId: person.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No people yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap + to add someone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Groups [people] by the uppercased first letter of their name, sorted
  /// alphabetically both within and across groups. People with a name
  /// starting with anything other than A–Z land in a "#" group at the end.
  List<(String, List<Person>)> _groupByFirstLetter(List<Person> people) {
    final sorted = [...people]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final groups = <String, List<Person>>{};
    for (final person in sorted) {
      final letter = _firstLetterOf(person.name);
      groups.putIfAbsent(letter, () => []).add(person);
    }

    final letterKeys = groups.keys.where((k) => k != '#').toList()..sort();
    final orderedKeys = [...letterKeys, if (groups.containsKey('#')) '#'];

    return [for (final key in orderedKeys) (key, groups[key]!)];
  }

  String _firstLetterOf(String name) {
    if (name.isEmpty) return '#';
    final letter = name[0].toUpperCase();
    return RegExp(r'^[A-Z]$').hasMatch(letter) ? letter : '#';
  }
}

class _LetterHeader extends StatelessWidget {
  final String letter;

  const _LetterHeader({required this.letter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: theme.colorScheme.surfaceContainerLow,
      child: Text(
        letter,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
