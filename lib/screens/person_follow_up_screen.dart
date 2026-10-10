import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/event.dart';
import '../models/guest.dart';
import '../models/person.dart';
import '../models/simple_date.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';

/// The "what's going on with this person across all my events" screen.
/// Shows every pinned event with this person's status for each one
/// ("Not added" if absent). Multi-select checkboxes let you pick which
/// events to log a follow-up for, with a "Mark followed up" button that
/// bumps follow_up_count and sets lastFollowUp to today for all checked
/// events.
class PersonFollowUpScreen extends ConsumerStatefulWidget {
  final String personId;

  const PersonFollowUpScreen({super.key, required this.personId});

  @override
  ConsumerState<PersonFollowUpScreen> createState() =>
      _PersonFollowUpScreenState();
}

class _PersonFollowUpScreenState extends ConsumerState<PersonFollowUpScreen> {
  final Set<String> _checkedEventIds = {};
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return switch (snapshotAsync) {
      AsyncData(:final value) => _buildForSnapshot(context, value),
      AsyncError(:final error) => Scaffold(
          appBar: AppBar(title: const Text('Follow Up')),
          body: Center(child: Text('Could not load your data: $error')),
        ),
      _ => Scaffold(
          appBar: AppBar(title: const Text('Follow Up')),
          body: const Center(child: CircularProgressIndicator()),
        ),
    };
  }

  Widget _buildForSnapshot(BuildContext context, DataSnapshot snapshot) {
    final person = snapshot.personById(widget.personId);
    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Follow Up')),
        body: const Center(child: Text('This person no longer exists.')),
      );
    }

    // Soonest event first — you want to prioritize what's coming up soon.
    // pinnedEventsForPerson returns date-descending, so we reverse it.
    final eventEntries =
        snapshot.pinnedEventsForPerson(widget.personId).reversed.toList();

    // Default: pre-check events where this person needs follow-up,
    // but only on first build (don't reset after user changes).
    if (_checkedEventIds.isEmpty && eventEntries.isNotEmpty) {
      for (final (event, guest) in eventEntries) {
        if (guest != null && guest.needsFollowUp(event.isUpcoming)) {
          _checkedEventIds.add(event.id);
        }
      }
    }

    final checkedCount = _checkedEventIds.length;
    final allChecked =
        checkedCount == eventEntries.length && eventEntries.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Follow up — ${person.name}'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (allChecked) {
                _checkedEventIds.clear();
              } else {
                _checkedEventIds
                    .addAll(eventEntries.map((e) => e.$1.id));
              }
            }),
            child: Text(allChecked ? 'Deselect all' : 'Select all'),
          ),
        ],
      ),
      body: eventEntries.isEmpty
          ? const Center(
              child: Text('No pinned events.'),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                for (final (event, guest) in eventEntries)
                  _EventRow(
                    event: event,
                    guest: guest,
                    checked: _checkedEventIds.contains(event.id),
                    onChanged: (checked) => setState(() {
                      if (checked) {
                        _checkedEventIds.add(event.id);
                      } else {
                        _checkedEventIds.remove(event.id);
                      }
                    }),
                  ),
              ],
            ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          8 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: FilledButton(
          onPressed:
              (_isSaving || checkedCount == 0) ? null : _markFollowedUp,
          child: Text(
            checkedCount == 0
                ? 'Select events to mark'
                : 'Mark followed up ($checkedCount event${checkedCount == 1 ? '' : 's'})',
          ),
        ),
      ),
    );
  }

  Future<void> _markFollowedUp() async {
    setState(() => _isSaving = true);
    final repository = ref.read(repositoryProvider);
    final snapshot = ref.read(dataSnapshotProvider).valueOrNull;
    if (snapshot == null) return;

    final today = SimpleDate.today();

    try {
      for (final eventId in _checkedEventIds) {
        // Find the event.
        Event? event;
        for (final e in snapshot.events) {
          if (e.id == eventId) { event = e; break; }
        }
        if (event == null) continue;

        final guest = event.guestFor(widget.personId);
        final Event updatedEvent;

        if (guest == null) {
          // Person wasn't on this event — add them with noResponse since
          // we're logging a follow-up (i.e. we just invited them).
          final newGuest = Guest(
            personId: widget.personId,
            rsvp: RsvpStatus.noResponse,
            invitedVia: InviteMethod.dm,
            lastFollowUp: today,
          );
          updatedEvent = event.copyWith(
            guests: [...event.guests, newGuest],
          );
        } else {
          // Auto-promote toInvite → noResponse when logging a follow-up,
          // since logging a follow-up means we've now contacted them.
          final promotedRsvp = guest.rsvp == RsvpStatus.toInvite
              ? RsvpStatus.noResponse
              : guest.rsvp;
          final updatedGuest = guest.copyWith(
            rsvp: promotedRsvp,
            followUpCount: guest.followUpCount + 1,
            lastFollowUp: today,
            // Logging a follow-up lifts suppression and clears any snooze.
            followUpSuppressed: false,
            clearSnooze: true,
          );
          updatedEvent = event.copyWith(
            guests: event.guests
                .map((g) => g.personId == widget.personId ? updatedGuest : g)
                .toList(),
          );
        }
        await repository.saveEvent(updatedEvent);
      }

      await ref.read(dataSnapshotProvider.notifier).reload();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Logged follow-up for $checkedCount '
              'event${checkedCount == 1 ? '' : 's'}.',
            ),
          ),
        );
        setState(() {
          _checkedEventIds.clear();
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  int get checkedCount => _checkedEventIds.length;
}

class _EventRow extends StatelessWidget {
  final Event event;
  final Guest? guest;
  final bool checked;
  final void Function(bool) onChanged;

  const _EventRow({
    required this.event,
    required this.guest,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = guest;
    final notAdded = g == null;

    String subtitle;
    if (notAdded) {
      subtitle = 'Not added — checking will invite them with No response';
    } else {
      final parts = <String>[g.rsvp.label];
      if (g.lastFollowUp != null) {
        parts.add('last contact ${g.lastFollowUp!.toIsoString()}');
      } else if (g.rsvp != RsvpStatus.toInvite) {
        parts.add('never contacted');
      }
      if (g.followUpSuppressed) parts.add('follow-up suppressed');
      if (g.isSnoozed()) parts.add('snoozed until ${g.snoozeUntil!.toIsoString()}');
      subtitle = parts.join(' · ');
    }

    return CheckboxListTile(
      value: checked,
      // Not-added rows are checkable — checking them will add the person
      // to the event with noResponse status on save.
      onChanged: (v) => onChanged(v ?? false),
      title: Text(
        event.name,
        style: notAdded
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: Text(
        '${event.date?.toIsoString() ?? 'No date'} · $subtitle',
        style: notAdded
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      secondary: notAdded
          ? Icon(Icons.person_add_outlined,
              color: theme.colorScheme.onSurfaceVariant)
          : _statusIcon(g!, theme),
    );
  }

  Widget _statusIcon(Guest g, ThemeData theme) {
    if (g.needsFollowUp(event.isUpcoming)) {
      return Icon(Icons.notifications_outlined, color: theme.colorScheme.error);
    }
    if (g.isSnoozed()) {
      return Icon(Icons.event_available_outlined,
          color: theme.colorScheme.onSurfaceVariant);
    }
    if (g.followUpSuppressed) {
      return Icon(Icons.notifications_off_outlined,
          color: theme.colorScheme.onSurfaceVariant);
    }
    return const SizedBox.shrink();
  }
}
