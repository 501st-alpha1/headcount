import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/event.dart';
import '../models/group.dart';
import '../models/guest.dart';
import '../models/person.dart';
import '../models/simple_date.dart';
import '../models/tag.dart';
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
  Tag? _browsingTag;

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
        title: Text(_browsingTag == null ? 'Add Guest' : _browsingTag!.name),
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
        .where(
          (g) => g.memberIds.any((id) => !existingIds.contains(id)),
        )
        .where((g) => query.isEmpty || g.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final matchingTags = snapshot.allTagsInUse
        .where(
          (t) => snapshot
          .peopleWithTag(t.id)
          .any((pair) => !existingIds.contains(pair.$1.id)),
        )
        .where((t) => query.isEmpty || t.name.toLowerCase().contains(query))
        .toList();

    // Other events (excluding the current one), sorted most-recent-first.
    // Guests already on this event are skipped at add time, so no need
    // to filter the event list here.
    final matchingEvents = snapshot.events
        .where((e) => e.id != event.id && e.guests.isNotEmpty)
        .where((e) => query.isEmpty || e.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
          final aDate = a.date;
          final bDate = b.date;

          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
      });

    if (matchingPeople.isEmpty && matchingGroups.isEmpty &&
        matchingTags.isEmpty && matchingEvents.isEmpty) {
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
              title: Text(tag.name),
              subtitle: Text(
                '${snapshot.peopleWithTag(tag.id).length} people',
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
        if (matchingEvents.isNotEmpty) ...[
          const _ResultSectionHeader(label: 'From another event'),
          for (final other in matchingEvents)
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(other.name),
              subtitle: Text(
                '${other.date?.toIsoString() ?? 'No date'} · ${other.guests.length} '
                '${other.guests.length == 1 ? "guest" : "guests"}',
              ),
              onTap: () => _addFromEvent(event, other),
            ),
        ],
        if (matchingPeople.isNotEmpty) ...[
          const _ResultSectionHeader(label: 'People'),
          for (final person in matchingPeople)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(person.name),
              // Tap opens a quick status picker before adding — default
              // is toInvite (not yet contacted), but the user can switch
              // to noResponse (already invited, just tracking) or any
              // other status right here without needing to open the full
              // RSVP sheet afterward.
              onTap: () => _showAddPersonSheet(context, event, person.id),
            ),
        ],
      ],
    );
  }

  /// Adds all guests from [sourceEvent] to [targetEvent] with status
  /// toInvite. Guests already on [targetEvent] (matched by person_id)
  /// are silently skipped — same dedup logic as everywhere else.
  Future<void> _addFromEvent(Event targetEvent, Event sourceEvent) async {
    final personIds = sourceEvent.guests.map((g) => g.personId).toSet();
    await _addPeopleByIds(targetEvent, personIds,
        status: RsvpStatus.toInvite);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added guests from "${sourceEvent.name}" — '
            'already-added guests were skipped.',
          ),
        ),
      );
    }
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
    );
    await repository.saveEvent(updated);
    await ref.read(dataSnapshotProvider.notifier).reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${group.name}\'s members')),
      );
    }
  }

  /// Shows a bottom sheet letting the user pick a status before adding
  /// the person. Default is toInvite (not yet contacted). Confirming
  /// adds the person with the chosen status and dismisses the sheet.
  Future<void> _showAddPersonSheet(
    BuildContext context,
    Event event,
    String personId,
  ) async {
    RsvpStatus chosen = RsvpStatus.toInvite;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add with status',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final status in RsvpStatus.values)
                          ChoiceChip(
                            label: Text(status.label),
                            selected: chosen == status,
                            onSelected: (_) =>
                                setSheetState(() => chosen = status),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _addPeopleByIds(event, {personId}, status: chosen);
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addPeopleByIds(
    Event event,
    Set<String> personIds, {
    RsvpStatus status = RsvpStatus.toInvite,
  }) async {
    final existingIds = event.guests.map((g) => g.personId).toSet();

    final newGuests = personIds
        .where((id) => !existingIds.contains(id))
        .map((id) => Guest(
              personId: id,
              rsvp: status,
              invitedVia: InviteMethod.dm,
              // toInvite means not yet contacted — leave lastFollowUp null
              // so it always surfaces in the follow-up list. Any other
              // status (e.g. noResponse, meaning already invited) treats
              // the moment of adding as the first contact, starting the
              // cooldown so it doesn't show as immediately overdue.
              lastFollowUp:
                  status == RsvpStatus.toInvite ? null : SimpleDate.today(),
            ))
        .toList();

    if (newGuests.isEmpty) return;

    final repository = ref.read(repositoryProvider);
    final updated = event.copyWith(guests: [...event.guests, ...newGuests]);

    await repository.saveEvent(updated);
    await ref.read(dataSnapshotProvider.notifier).reload();

    if (!mounted) return;

    if (_browsingTag != null) {
      setState(() => _browsingTag = null);
      return;
    }

    if (_query.trim().isNotEmpty) {
      final snapshot = ref.read(dataSnapshotProvider).value;
      if (snapshot != null) {
        final updatedEvent = _findEvent(snapshot, event.id);
        if (updatedEvent != null) {
          final hasResults = _hasSearchResults(
            snapshot,
            updatedEvent,
            _query,
          );

          if (!hasResults) {
            setState(() {
                _query = '';
                _searchController.clear();
            });
          }
        }
      }
    }
  }

  bool _hasSearchResults(
    DataSnapshot snapshot,
    Event event,
    String rawQuery,
  ) {
    final existingIds = event.guests.map((g) => g.personId).toSet();
    final query = rawQuery.trim().toLowerCase();

    final hasPeople = snapshot.people.any(
      (p) =>
      !existingIds.contains(p.id) &&
      (query.isEmpty || p.name.toLowerCase().contains(query)),
    );

    final hasGroups = snapshot.groups.any(
      (g) =>
      g.memberIds.any((id) => !existingIds.contains(id)) &&
      (query.isEmpty || g.name.toLowerCase().contains(query)),
    );

    final hasTags = snapshot.allTagsInUse.any(
      (t) =>
      snapshot
      .peopleWithTag(t.id)
      .any((pair) => !existingIds.contains(pair.$1.id)) &&
      (query.isEmpty || t.name.toLowerCase().contains(query)),
    );

    final hasEvents = snapshot.events.any(
      (e) =>
      e.id != event.id &&
      e.guests.isNotEmpty &&
      (query.isEmpty || e.name.toLowerCase().contains(query)),
    );

    return hasPeople || hasGroups || hasTags || hasEvents;
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

/// Shown when a tag result is tapped. Shows people grouped by their
/// level on the root tag. If the tag has dependents (sub-tags), shows
/// "Refine by…" chips — selecting one narrows to people who have BOTH
/// the root tag AND the sub-tag (AND filtering), grouped by sub-tag
/// level. People with the root tag but no sub-tag value appear in an
/// "Unknown" section at the bottom so you know they exist but haven't
/// been categorized yet.
class _TagInterestBrowser extends StatefulWidget {
  final Tag tag;
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

  /// The active refinement sub-tag, or null for unrefined view.
  Tag? _activeSubtag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingIds = widget.event.guests.map((g) => g.personId).toSet();
    final dependents = widget.snapshot.dependentsOf(widget.tag.id);

    return Column(
      children: [
        // "Refine by…" chips — only shown if this tag has dependents.
        if (dependents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Refine by', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final dep in dependents)
                      FilterChip(
                        label: Text(dep.name),
                        selected: _activeSubtag?.id == dep.id,
                        onSelected: (selected) => setState(() {
                          _activeSubtag = selected ? dep : null;
                          // Clear selection when changing refinement —
                          // a person selected under one sub-tag filter
                          // may not be visible under another.
                          _selected.clear();
                        }),
                      ),
                  ],
                ),
                const Divider(height: 24),
              ],
            ),
          ),
        Expanded(
          child: _activeSubtag == null
              ? _buildRootView(existingIds)
              : _buildRefinedView(existingIds, _activeSubtag!),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed:
                _selected.isEmpty ? null : () => widget.onAddSelected(_selected),
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

  /// Unrefined view — all available people with this tag, grouped by
  /// their level on the root tag.
  Widget _buildRootView(Set<String> existingIds) {
    final available = widget.snapshot
        .peopleWithTag(widget.tag.id)
        .where((p) => !existingIds.contains(p.$1.id))
        .toList();

    if (available.isEmpty) {
      return const Center(child: Text('No one left to add.'));
    }

    return _CheckboxList(
      groups: _groupByLevel(available, widget.tag),
      selected: _selected,
      onToggle: _toggle,
    );
  }

  /// Refined view — people who have BOTH the root tag AND the sub-tag,
  /// grouped by their sub-tag level. An "Unknown" section at the bottom
  /// shows people with the root tag but no sub-tag value.
  Widget _buildRefinedView(Set<String> existingIds, Tag subtag) {
    final withBoth = widget.snapshot
        .peopleWithTagAndSubtag(widget.tag.id, subtag.id)
        .where((p) => !existingIds.contains(p.$1.id))
        .toList();

    final unknown = widget.snapshot
        .peopleWithParentButNotSubtag(widget.tag.id, subtag.id)
        .where((p) => !existingIds.contains(p.id))
        .toList();

    if (withBoth.isEmpty && unknown.isEmpty) {
      return const Center(child: Text('No one left to add.'));
    }

    // Build groups from the sub-tag's level order.
    final groups = _groupByLevel(withBoth, subtag);

    // Add "Unknown" group at the bottom if there are any.
    if (unknown.isNotEmpty) {
      groups.add((
        'Unknown (no ${subtag.name} recorded)',
        unknown.map((p) => (p, InterestTag(tag: subtag.id, level: ''))).toList(),
      ));
    }

    return _CheckboxList(
      groups: groups,
      selected: _selected,
      onToggle: _toggle,
    );
  }

  void _toggle(String personId) {
    setState(() {
      if (_selected.contains(personId)) {
        _selected.remove(personId);
      } else {
        _selected.add(personId);
      }
    });
  }

  List<(String, List<(Person, InterestTag)>)> _groupByLevel(
    List<(Person, InterestTag)> people,
    Tag tag,
  ) {
    final groups = <(String, List<(Person, InterestTag)>)>[];
    for (final level in tag.levels) {
      final inGroup = people.where((p) => p.$2.level == level).toList();
      if (inGroup.isNotEmpty) groups.add((level, inGroup));
    }
    // Anyone whose level isn't in the tag's defined levels (stale data).
    final other = people
        .where((p) => !tag.levels.contains(p.$2.level) && p.$2.level.isNotEmpty)
        .toList();
    if (other.isNotEmpty) groups.add(('Other', other));
    return groups;
  }
}

/// Reusable checkbox list for the interest browser — handles both the
/// root view and the refined sub-tag view.
class _CheckboxList extends StatelessWidget {
  final List<(String, List<(Person, InterestTag)>)> groups;
  final Set<String> selected;
  final void Function(String personId) onToggle;

  const _CheckboxList({
    required this.groups,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              group.$1,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final pair in group.$2)
            CheckboxListTile(
              title: Text(pair.$1.name),
              subtitle: pair.$2.notes.isEmpty ? null : Text(pair.$2.notes),
              value: selected.contains(pair.$1.id),
              onChanged: (_) => onToggle(pair.$1.id),
            ),
        ],
      ],
    );
  }
}
