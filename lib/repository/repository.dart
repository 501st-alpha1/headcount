import '../models/event.dart';
import '../models/enums.dart';
import '../models/group.dart';
import '../models/guest.dart';
import '../models/person.dart';
import 'event_repository.dart';
import 'exceptions.dart';
import 'group_repository.dart';
import 'load_result.dart';
import 'person_repository.dart';

/// A snapshot of everything loaded from disk at once. Cross-entity
/// in-memory queries (e.g. "what events is this person on") work off this,
/// rather than re-reading the filesystem per query.
class DataSnapshot {
  final List<Person> people;
  final List<Group> groups;
  final List<Event> events;
  final List<LoadIssue> issues;

  const DataSnapshot({
    required this.people,
    required this.groups,
    required this.events,
    required this.issues,
  });

  bool get hasIssues => issues.isNotEmpty;

  Person? personById(String id) {
    for (final person in people) {
      if (person.id == id) return person;
    }
    return null;
  }

  Group? groupById(String id) {
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  /// All events (past and future) that [personId] appears on, each paired
  /// with that person's guest entry for quick access to their RSVP status.
  List<(Event, Guest)> eventsFor(String personId) {
    final result = <(Event, Guest)>[];
    for (final event in events) {
      final guest = event.guestFor(personId);
      if (guest != null) result.add((event, guest));
    }
    return result;
  }

  /// Events that currently belong on the home screen — pinned and either
  /// upcoming or still within the post-event grace period — sorted by
  /// date ascending (soonest first). See Event.showsOnHomeScreen for the
  /// exact rule.
  List<Event> get eventsOnHomeScreen {
    final result = events.where((e) => e.showsOnHomeScreen).toList();
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// Everything that does NOT currently show on the home screen: unpinned
  /// events, and pinned events whose grace period has expired. Sorted by
  /// date descending (most recent first), since that's the more useful
  /// order when scrolling back through history.
  List<Event> get archivedEvents {
    final result = events.where((e) => !e.showsOnHomeScreen).toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// All guests on [event], each paired with the Person they refer to.
  /// Guests whose person_id has no matching Person are silently skipped
  /// (this should never happen in practice — saveEvent rejects dangling
  /// references — but a stale in-memory snapshot mid-edit shouldn't crash
  /// the UI over it).
  List<(Guest, Person)> resolvedGuestsFor(Event event) {
    final result = <(Guest, Person)>[];
    for (final guest in event.guests) {
      final person = personById(guest.personId);
      if (person != null) result.add((guest, person));
    }
    return result;
  }

  /// All upcoming events with at least one guest needing follow-up,
  /// each paired with just those guest entries — the data behind the
  /// Global Follow-Up List screen.
  List<(Event, List<Guest>)> upcomingFollowUps() {
    final result = <(Event, List<Guest>)>[];
    for (final event in events) {
      if (!event.isUpcoming) continue;
      final needing = event.guestsNeedingFollowUp;
      if (needing.isNotEmpty) result.add((event, needing));
    }
    return result;
  }
}

/// Top-level entry point for all data access. Composes the three
/// per-entity repositories and owns the logic that spans more than one
/// of them: dangling-reference checks, group-invite snapshotting, and
/// safe deletion.
class Repository {
  final String dataRoot;
  final PersonRepository people;
  final GroupRepository groups;
  final EventRepository events;

  Repository(this.dataRoot)
      : people = PersonRepository(dataRoot),
        groups = GroupRepository(dataRoot),
        events = EventRepository(dataRoot);

  /// Loads people, groups, and events in one pass. Issues from all three
  /// are merged into a single list so the UI can show one combined
  /// "N files couldn't be read" notice rather than three.
  Future<DataSnapshot> loadAll() async {
    final peopleResult = await people.loadAll();
    final groupsResult = await groups.loadAll();
    final eventsResult = await events.loadAll();

    return DataSnapshot(
      people: peopleResult.items,
      groups: groupsResult.items,
      events: eventsResult.items,
      issues: [
        ...peopleResult.issues,
        ...groupsResult.issues,
        ...eventsResult.issues,
      ],
    );
  }

  /// Saves [event], validating that every guest's person_id corresponds
  /// to an existing person first. Pass [previous] when the event's date
  /// may have changed, so the old file gets cleaned up.
  ///
  /// This is the method UI code should call — it always validates.
  /// EventRepository.save with knownPersonIds: null (no validation) is
  /// only for internal/bulk operations that have already validated.
  Future<void> saveEvent(Event event, {Event? previous}) async {
    final peopleResult = await people.loadAll();
    final knownIds = peopleResult.items.map((p) => p.id).toSet();
    await events.save(event, previous: previous, knownPersonIds: knownIds);
  }

  /// Saves [group], validating that every member_id corresponds to an
  /// existing person first.
  Future<void> saveGroup(Group group) async {
    final peopleResult = await people.loadAll();
    final knownIds = peopleResult.items.map((p) => p.id).toSet();
    final dangling =
        group.memberIds.where((id) => !knownIds.contains(id)).toSet();
    if (dangling.isNotEmpty) {
      throw DanglingReferenceException(
        'Group "${group.id}" has member_id(s) referencing unknown '
        'people: ${dangling.join(', ')}.',
      );
    }
    await groups.save(group);
  }

  /// Deletes a person, but only if they're not referenced by any event's
  /// guest list or any group's member_ids. Throws DanglingReferenceException
  /// naming the referencing events/groups if so — deleting a person who's
  /// still on guest lists would silently corrupt those events' references.
  Future<void> deletePerson(String personId) async {
    final snapshot = await loadAll();

    final referencingEvents = snapshot.events
        .where((e) => e.guestFor(personId) != null)
        .map((e) => e.name)
        .toList();
    final referencingGroups = snapshot.groups
        .where((g) => g.memberIds.contains(personId))
        .map((g) => g.name)
        .toList();

    if (referencingEvents.isNotEmpty || referencingGroups.isNotEmpty) {
      final parts = <String>[];
      if (referencingEvents.isNotEmpty) {
        parts.add('events: ${referencingEvents.join(', ')}');
      }
      if (referencingGroups.isNotEmpty) {
        parts.add('groups: ${referencingGroups.join(', ')}');
      }
      throw DanglingReferenceException(
        'Cannot delete person "$personId" — still referenced by '
        '${parts.join('; ')}. Remove them from these first.',
      );
    }

    await people.delete(personId);
  }

  /// Bulk-adds every member of [group] to [event] as new guests, using
  /// the given [invitedVia]/[platform] defaults for all of them. This is
  /// the snapshot behavior described in the design doc: membership is
  /// copied once, with no ongoing link to the group afterward. People
  /// already on the event's guest list (matched by person_id) are
  /// skipped — re-inviting a group never duplicates or clobbers existing
  /// RSVP state.
  ///
  /// Returns the updated Event (caller is responsible for persisting it
  /// via saveEvent, so this stays a pure in-memory operation that's easy
  /// to test and easy to preview before committing to disk).
  Event inviteGroupToEvent({
    required Event event,
    required Group group,
    required InviteMethod invitedVia,
    String platform = '',
  }) {
    final existingIds = event.guests.map((g) => g.personId).toSet();
    final newGuests = group.memberIds
        .where((id) => !existingIds.contains(id))
        .map((id) => Guest(
              personId: id,
              rsvp: RsvpStatus.noResponse,
              invitedVia: invitedVia,
              platform: platform,
            ))
        .toList();

    return event.copyWith(guests: [...event.guests, ...newGuests]);
  }
}
