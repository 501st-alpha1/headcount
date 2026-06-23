import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/event.dart';
import '../models/guest.dart';
import '../models/person.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';
import 'add_guest_screen.dart';
import 'event_editor_screen.dart';
import 'widgets/guest_rsvp_sheet.dart';
import 'widgets/guest_row.dart';

/// A filter for the guest list. "All" and "needsFollowUp" are computed
/// conditions; the rest map 1:1 to an RsvpStatus.
enum _GuestFilter {
  all,
  needsFollowUp,
  yes,
  probably,
  maybe,
  probablyNot,
  no,
  noResponse,
}

extension on _GuestFilter {
  String get label => switch (this) {
        _GuestFilter.all => 'All',
        _GuestFilter.needsFollowUp => 'Needs follow-up',
        _GuestFilter.yes => RsvpStatus.yes.label,
        _GuestFilter.probably => RsvpStatus.probably.label,
        _GuestFilter.maybe => RsvpStatus.maybe.label,
        _GuestFilter.probablyNot => RsvpStatus.probablyNot.label,
        _GuestFilter.no => RsvpStatus.no.label,
        _GuestFilter.noResponse => RsvpStatus.noResponse.label,
      };
}

/// The event detail screen: guest list grouped by RSVP status, filterable
/// via chips, with tap-to-edit on each guest via the RSVP bottom sheet.
class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  _GuestFilter _filter = _GuestFilter.all;

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return switch (snapshotAsync) {
      AsyncData(:final value) => _buildForSnapshot(context, value),
      AsyncError(:final error) => Scaffold(
          appBar: AppBar(title: const Text('Event')),
          body: Center(child: Text('Could not load your data: $error')),
        ),
      _ => Scaffold(
          appBar: AppBar(title: const Text('Event')),
          body: const Center(child: CircularProgressIndicator()),
        ),
    };
  }

  Widget _buildForSnapshot(BuildContext context, DataSnapshot dataSnapshot) {
    Event? event;
    for (final candidate in dataSnapshot.events) {
      if (candidate.id == widget.eventId) {
        event = candidate;
        break;
      }
    }

    if (event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: const Center(child: Text('This event no longer exists.')),
      );
    }

    final resolved = dataSnapshot.resolvedGuestsFor(event);
    final filtered = _applyFilter(resolved, event);
    final grouped = _groupByStatus(filtered);

    return Scaffold(
      appBar: AppBar(
        title: Text(event.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit event',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventEditorScreen(eventId: event!.id),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _EventMetaHeader(event: event),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _FilterChipsRow(
              selected: _filter,
              onSelected: (f) => setState(() => _filter = f),
            ),
          ),
          Expanded(
            child: grouped.isEmpty
                ? const Center(child: Text('No guests match this filter.'))
                : ListView(
                    children: [
                      for (final group in grouped) ...[
                        _SectionHeader(label: group.$1),
                        for (final pair in group.$2)
                          GuestRow(
                            guest: pair.$1,
                            person: pair.$2,
                            needsFollowUp:
                                pair.$1.needsFollowUp(event!.isUpcoming),
                            onTap: () => _openRsvpSheet(
                              context,
                              event!,
                              pair.$1,
                              pair.$2,
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddGuestScreen(eventId: event!.id),
            ),
          );
        },
        tooltip: 'Add guest',
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }

  List<(Guest, Person)> _applyFilter(
    List<(Guest, Person)> resolved,
    Event event,
  ) {
    return switch (_filter) {
      _GuestFilter.all => resolved,
      _GuestFilter.needsFollowUp => resolved
          .where((p) => p.$1.needsFollowUp(event.isUpcoming))
          .toList(),
      _GuestFilter.yes =>
        resolved.where((p) => p.$1.rsvp == RsvpStatus.yes).toList(),
      _GuestFilter.probably =>
        resolved.where((p) => p.$1.rsvp == RsvpStatus.probably).toList(),
      _GuestFilter.maybe =>
        resolved.where((p) => p.$1.rsvp == RsvpStatus.maybe).toList(),
      _GuestFilter.probablyNot =>
        resolved.where((p) => p.$1.rsvp == RsvpStatus.probablyNot).toList(),
      _GuestFilter.no =>
        resolved.where((p) => p.$1.rsvp == RsvpStatus.no).toList(),
      _GuestFilter.noResponse =>
        resolved.where((p) => p.$1.rsvp == RsvpStatus.noResponse).toList(),
    };
  }

  /// Groups guests into (sectionLabel, guests) pairs ordered by
  /// RsvpStatus's declared order, skipping empty groups. When a specific
  /// status filter is active there's naturally only one group; "All" and
  /// "Needs follow-up" show every status that has at least one guest.
  List<(String, List<(Guest, Person)>)> _groupByStatus(
    List<(Guest, Person)> resolved,
  ) {
    final groups = <(String, List<(Guest, Person)>)>[];
    for (final status in RsvpStatus.values) {
      final inGroup = resolved.where((p) => p.$1.rsvp == status).toList();
      if (inGroup.isNotEmpty) {
        groups.add((status.label, inGroup));
      }
    }
    return groups;
  }

  void _openRsvpSheet(
    BuildContext context,
    Event event,
    Guest guest,
    Person person,
  ) {
    showGuestRsvpSheet(
      context: context,
      guest: guest,
      person: person,
      onSave: (updated) => _saveGuestUpdate(event, updated),
      onRemoveFromEvent: () => _removeGuest(event, guest),
    );
  }

  Future<void> _saveGuestUpdate(Event event, Guest updated) async {
    final newGuests = event.guests
        .map((g) => g.personId == updated.personId ? updated : g)
        .toList();
    final updatedEvent = event.copyWith(guests: newGuests);
    final repository = ref.read(repositoryProvider);
    await repository.saveEvent(updatedEvent);
    await ref.read(dataSnapshotProvider.notifier).reload();
  }

  Future<void> _removeGuest(Event event, Guest guest) async {
    final newGuests =
        event.guests.where((g) => g.personId != guest.personId).toList();
    final updatedEvent = event.copyWith(guests: newGuests);
    final repository = ref.read(repositoryProvider);
    await repository.saveEvent(updatedEvent);
    await ref.read(dataSnapshotProvider.notifier).reload();
  }
}

class _EventMetaHeader extends StatelessWidget {
  final Event event;

  const _EventMetaHeader({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(event.date.toIsoString(), style: theme.textTheme.bodyMedium),
        if (event.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(event.description, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  final _GuestFilter selected;
  final void Function(_GuestFilter) onSelected;

  const _FilterChipsRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final filter in _GuestFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: selected == filter,
                onSelected: (_) => onSelected(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
