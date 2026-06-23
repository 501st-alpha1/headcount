import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/event.dart';
import '../models/group.dart';
import '../models/guest.dart';
import '../models/person.dart';
import '../models/simple_date.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';

/// Unified add-guest search for one event: a single search box whose
/// results mix people, groups, and interest tags. Picking a person adds
/// them directly; picking a group bulk-adds its current members
/// (snapshot, see Repository.inviteGroupToEvent); picking a tag opens an
/// inline interest-level browser to multi-select before adding.
///
/// People already on the event are excluded from people/group results
/// (adding a group whose members are already on the list just skips
/// them — see inviteGroupToEvent) so re-searching is always safe.
class AddGuestScreen extends ConsumerStatefulWidget {
  final String eventId;

  const AddGuestScreen({super.key, required this.eventId});

  @override
  ConsumerState<AddGuestScreen> createState() => _AddGuestScreenState();
}

class _AddGuestScreenState extends ConsumerState<AddGuestScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  /// When non-null, we're showing the interest-level browser for this
  /// tag instead of the main search results.
  String? _browsingTag;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_browsingTag == null ? 'Add Guest' : _browsingTag!),
        leading: _browsingTag == null
            ? null
            : BackButton(onPressed: () => setState(() => _browsingTag = null)),
      ),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _buildBody(context, value),
        AsyncError(:final error) =>
          Center(child: Text('Could not load your data: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildBody(BuildContext context, DataSnapshot snapshot) {
    final event = _findEvent(snapshot, widget.eventId);
    if (event == null) {
      return const Center(child: Text('This event no longer exists.'));
    }

    if (_browsingTag != null) {
      return _TagInterestBrowser(
        tag: _browsingTag!,
        snapshot: snapshot,
        event: event,
        onAddSelected: (personIds) => _addPeopleByIds(event, personIds),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search people, groups, or interests',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(child: _buildResults(context, snapshot, event)),
      ],
    );
  }

  Widget _buildResults(
    BuildContext context,
    DataSnapshot snapshot,
    Event event,
  ) {
    final existingIds = event.guests.map((g) => g.personId).toSet();
    final query = _query.trim().toLowerCase();

    final matchingPeople = snapshot.people
        .where((p) => !existingIds.contains(p.id))
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final matchingGroups = snapshot.groups
        .where((g) => query.isEmpty || g.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final matchingTags = snapshot.allTagsInUse
        .where((t) => query.isEmpty || t.toLowerCase().contains(query))
        .toList();

    if (matchingPeople.isEmpty && matchingGroups.isEmpty && matchingTags.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? 'No one left to add.' : 'No matches for "$query".',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView(
      children: [
        if (matchingTags.isNotEmpty) ...[
          const _ResultSectionHeader(label: 'Interests'),
          for (final tag in matchingTags)
            ListTile(
              leading: const Icon(Icons.interests_outlined),
              title: Text(tag),
              subtitle: Text(
                '${snapshot.peopleWithTag(tag).length} people',
              ),
              onTap: () => setState(() => _browsingTag = tag),
            ),
        ],
        if (matchingGroups.isNotEmpty) ...[
          const _ResultSectionHeader(label: 'Groups'),
          for (final group in matchingGroups)
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(group.name),
              subtitle: Text('${group.memberIds.length} members'),
              onTap: () => _inviteGroup(event, group),
            ),
        ],
        if (matchingPeople.isNotEmpty) ...[
          const _ResultSectionHeader(label: 'People'),
          for (final person in matchingPeople)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(person.name),
              onTap: () => _addPeopleByIds(event, {person.id}),
            ),
        ],
      ],
    );
  }

  Event? _findEvent(DataSnapshot snapshot, String id) {
    for (final event in snapshot.events) {
      if (event.id == id) return event;
    }
    return null;
  }

  Future<void> _inviteGroup(Event event, Group group) async {
    final repository = ref.read(repositoryProvider);
    final updated = repository.inviteGroupToEvent(
      event: event,
      group: group,
      invitedVia: InviteMethod.groupMessage,
    );
    await repository.saveEvent(updated);
    await ref.read(dataSnapshotProvider.notifier).reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${group.name}\'s members')),
      );
    }
  }

  Future<void> _addPeopleByIds(Event event, Set<String> personIds) async {
    final existingIds = event.guests.map((g) => g.personId).toSet();
    final today = SimpleDate.today();
    final newGuests = personIds
        .where((id) => !existingIds.contains(id))
        .map((id) => Guest(
              personId: id,
              rsvp: RsvpStatus.noResponse,
              invitedVia: InviteMethod.dm,
              // Being added/invited counts as the first contact, so the
              // follow-up cooldown starts now.
              lastFollowUp: today,
            ))
        .toList();

    if (newGuests.isEmpty) return;

    final repository = ref.read(repositoryProvider);
    final updated = event.copyWith(guests: [...event.guests, ...newGuests]);
    await repository.saveEvent(updated);
    await ref.read(dataSnapshotProvider.notifier).reload();

    if (mounted && _browsingTag != null) {
      setState(() => _browsingTag = null);
    }
  }
}

class _ResultSectionHeader extends StatelessWidget {
  final String label;

  const _ResultSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Shown when a tag result is tapped: everyone with that interest tag,
/// grouped by level (enthusiastic first), with not_interested hidden by
/// default. Multi-select via checkboxes, then "Add Selected" applies them
/// all to the event at once.
class _TagInterestBrowser extends StatefulWidget {
  final String tag;
  final DataSnapshot snapshot;
  final Event event;
  final void Function(Set<String> personIds) onAddSelected;

  const _TagInterestBrowser({
    required this.tag,
    required this.snapshot,
    required this.event,
    required this.onAddSelected,
  });

  @override
  State<_TagInterestBrowser> createState() => _TagInterestBrowserState();
}

class _TagInterestBrowserState extends State<_TagInterestBrowser> {
  final Set<String> _selected = {};
  bool _showNotInterested = false;

  @override
  Widget build(BuildContext context) {
    final existingIds = widget.event.guests.map((g) => g.personId).toSet();
    final allMatches = widget.snapshot.peopleWithTag(widget.tag);
    final available = allMatches.where((p) => !existingIds.contains(p.$1.id));

    final visible = available
        .where((p) =>
            _showNotInterested || p.$2.level != InterestLevel.notInterested)
        .toList();

    final hiddenCount = available
        .where((p) => p.$2.level == InterestLevel.notInterested)
        .length;

    return Column(
      children: [
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('No one left to add.'))
              : ListView(
                  children: [
                    for (final group in _groupByLevel(visible))
                      ...[
                        _ResultSectionHeader(label: group.$1.label),
                        for (final pair in group.$2)
                          CheckboxListTile(
                            title: Text(pair.$1.name),
                            subtitle: pair.$2.notes.isEmpty
                                ? null
                                : Text(pair.$2.notes),
                            value: _selected.contains(pair.$1.id),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(pair.$1.id);
                              } else {
                                _selected.remove(pair.$1.id);
                              }
                            }),
                          ),
                      ],
                    if (!_showNotInterested && hiddenCount > 0)
                      TextButton(
                        onPressed: () =>
                            setState(() => _showNotInterested = true),
                        child: Text(
                          'Show $hiddenCount not interested',
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => widget.onAddSelected(_selected),
            child: Text(
              _selected.isEmpty
                  ? 'Select people to add'
                  : 'Add ${_selected.length} selected',
            ),
          ),
        ),
      ],
    );
  }

  List<(InterestLevel, List<(Person, InterestTag)>)> _groupByLevel(
    List<(Person, InterestTag)> people,
  ) {
    final groups = <(InterestLevel, List<(Person, InterestTag)>)>[];
    for (final level in InterestLevel.values) {
      final inGroup = people.where((p) => p.$2.level == level).toList();
      if (inGroup.isNotEmpty) groups.add((level, inGroup));
    }
    return groups;
  }
}
