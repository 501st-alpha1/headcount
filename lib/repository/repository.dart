import '../models/event.dart';
import '../models/enums.dart';
import '../models/group.dart';
import '../models/guest.dart';
import '../models/person.dart';
import '../models/simple_date.dart';
import '../models/tag.dart';
import 'event_repository.dart';
import 'exceptions.dart';
import 'group_repository.dart';
import 'load_result.dart';
import 'person_repository.dart';
import 'tag_repository.dart';

/// A snapshot of everything loaded from disk at once. Cross-entity
/// in-memory queries (e.g. "what events is this person on") work off this,
/// rather than re-reading the filesystem per query.
class DataSnapshot {
  final List<Person> people;
  final List<Group> groups;
  final List<Event> events;
  final List<Tag> tags;
  final List<LoadIssue> issues;

  const DataSnapshot({
    required this.people,
    required this.groups,
    required this.events,
    required this.tags,
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

  Tag? tagById(String id) {
    for (final tag in tags) {
      if (tag.id == id) return tag;
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

  /// All distinct interest tags currently in use across every person,
  /// sorted alphabetically by name. Every tag in use is expected to have
  /// a corresponding Tag definition by the time a snapshot is built —
  /// Repository.loadAll auto-creates one for any that's missing — so this
  /// reads from [tags] rather than re-scanning people's raw interest
  /// strings.
  List<Tag> get allTagsInUse {
    final sorted = [...tags]..sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }

  /// All distinct platform names currently in use, sorted alphabetically.
  /// Scanned live from both people's platforms and groups' default
  /// platforms — there's no separate platform registry file, same as
  /// tags. A platform only ever set as a group's default (with no person
  /// using it yet) still shows up here, since that's a real, intentional
  /// use of the platform name even before any person has it.
  List<String> get allPlatformsInUse {
    final platforms = <String>{};
    for (final person in people) {
      platforms.addAll(person.platforms);
    }
    for (final group in groups) {
      if (group.defaultPlatform.isNotEmpty) {
        platforms.add(group.defaultPlatform);
      }
    }
    final sorted = platforms.toList()..sort();
    return sorted;
  }

  /// All people with an interest tag matching [tagId] (matched against
  /// InterestTag.tag, which stores a Tag's id), each paired with their
  /// InterestTag for that tag. Sorted by position in the tag's own
  /// levels list (index 0 = most enthusiastic); a person whose stored
  /// level string isn't found in the tag's current levels (e.g. a level
  /// was deleted without reassigning them, or hand-edited data) sorts
  /// last, after every recognized level.
  List<(Person, InterestTag)> peopleWithTag(String tagId) {
    final tag = tagById(tagId);
    final levelRank = <String, int>{
      if (tag != null)
        for (var i = 0; i < tag.levels.length; i++) tag.levels[i]: i,
    };

    final result = <(Person, InterestTag)>[];
    for (final person in people) {
      final interest = person.interestIn(tagId);
      if (interest != null) result.add((person, interest));
    }
    result.sort((a, b) {
      final rankA = levelRank[a.$2.level] ?? levelRank.length;
      final rankB = levelRank[b.$2.level] ?? levelRank.length;
      return rankA.compareTo(rankB);
    });
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

/// Top-level entry point for all data access. Composes the four
/// per-entity repositories and owns the logic that spans more than one
/// of them: dangling-reference checks, group-invite snapshotting, safe
/// deletion, and tag-definition migration/maintenance.
class Repository {
  final String dataRoot;
  final PersonRepository people;
  final GroupRepository groups;
  final EventRepository events;
  final TagRepository tags;

  Repository(this.dataRoot)
      : people = PersonRepository(dataRoot),
        groups = GroupRepository(dataRoot),
        events = EventRepository(dataRoot),
        tags = TagRepository(dataRoot);

  /// Loads people, groups, events, and tags in one pass. Issues from all
  /// of them are merged into a single list so the UI can show one
  /// combined "N files couldn't be read" notice rather than several.
  ///
  /// Also runs tag auto-migration: any tag string in use on a person's
  /// interests that doesn't yet have a tags/<id>.toml definition gets
  /// one created on the spot, seeded with Tag.defaultLevels. This is
  /// what makes the per-tag-custom-levels feature land safely on
  /// existing data — every tag that was previously just a free string
  /// gets a real definition the first time the app loads after this
  /// feature ships, with no separate migration step for the user to run.
  Future<DataSnapshot> loadAll() async {
    final peopleResult = await people.loadAll();
    final groupsResult = await groups.loadAll();
    final eventsResult = await events.loadAll();
    final tagsResult = await tags.loadAll();

    final tagList = await _ensureTagDefinitionsExist(
      people: peopleResult.items,
      existingTags: tagsResult.items,
    );

    return DataSnapshot(
      people: peopleResult.items,
      groups: groupsResult.items,
      events: eventsResult.items,
      tags: tagList,
      issues: [
        ...peopleResult.issues,
        ...groupsResult.issues,
        ...eventsResult.issues,
        ...tagsResult.issues,
      ],
    );
  }

  /// Scans [people] for every tag id in use, creates a Tag file (seeded
  /// with Tag.defaultLevels) for any that aren't already present in
  /// [existingTags], and returns the combined, up-to-date tag list.
  /// Writes happen here (not just in-memory) so this only needs to run
  /// once per tag — the next loadAll() will find it already present.
  Future<List<Tag>> _ensureTagDefinitionsExist({
    required List<Person> people,
    required List<Tag> existingTags,
  }) async {
    final existingIds = existingTags.map((t) => t.id).toSet();
    final tagIdsInUse = <String>{};
    for (final person in people) {
      for (final interest in person.interests) {
        if (interest.tag.isNotEmpty) tagIdsInUse.add(interest.tag);
      }
    }

    final missingIds = tagIdsInUse.difference(existingIds);
    if (missingIds.isEmpty) return existingTags;

    final created = <Tag>[];
    for (final id in missingIds) {
      // The tag id IS the display name at this point, since tags were
      // previously just free strings with no separate name field — the
      // Tag Editor lets the user rename for display later if they want
      // something prettier than the raw tag string.
      final tag = Tag(id: id, name: id, levels: Tag.defaultLevels);
      await tags.save(tag);
      created.add(tag);
    }

    return [...existingTags, ...created];
  }

  /// Saves [tag] directly, with no validation — used for simple edits
  /// (renaming the tag's display name) that don't touch the levels list.
  /// For changes to levels themselves, use renameTagLevel/deleteTagLevel,
  /// which also keep every person's interest entries consistent.
  Future<void> saveTag(Tag tag) async {
    await tags.save(tag);
  }

  /// Renames a level within [tag] from [oldLevel] to [newLevel],
  /// updating the tag's own levels list AND every person currently using
  /// [oldLevel] on this tag, so nothing is left referencing a name that
  /// no longer exists. This is the only path for renaming a level —
  /// there's no way to rename just the tag's list without the cascade,
  /// since that would silently orphan everyone using the old name.
  Future<void> renameTagLevel({
    required Tag tag,
    required String oldLevel,
    required String newLevel,
  }) async {
    final updatedLevels =
        tag.levels.map((l) => l == oldLevel ? newLevel : l).toList();
    await tags.save(tag.copyWith(levels: updatedLevels));

    final peopleResult = await people.loadAll();
    for (final person in peopleResult.items) {
      var changed = false;
      final updatedInterests = person.interests.map((interest) {
        if (interest.tag == tag.id && interest.level == oldLevel) {
          changed = true;
          return interest.copyWith(level: newLevel);
        }
        return interest;
      }).toList();
      if (changed) {
        await people.save(person.copyWith(interests: updatedInterests));
      }
    }
  }

  /// Everyone currently at [level] on [tag] — the list shown to the user
  /// before deleting a level, so they know who needs reassigning.
  Future<List<Person>> peopleAtTagLevel(Tag tag, String level) async {
    final peopleResult = await people.loadAll();
    return peopleResult.items
        .where((p) => p.interestIn(tag.id)?.level == level)
        .toList();
  }

  /// Deletes [levelToDelete] from [tag], reassigning everyone currently
  /// at that level to [reassignTo] first. [reassignTo] must be a
  /// different level still present in [tag] after the deletion — pass
  /// one of [tag]'s other levels (see peopleAtTagLevel to show the user
  /// who's affected before calling this, and let them pick where those
  /// people land).
  Future<void> deleteTagLevel({
    required Tag tag,
    required String levelToDelete,
    required String reassignTo,
  }) async {
    if (reassignTo == levelToDelete) {
      throw ArgumentError(
        'reassignTo ("$reassignTo") must differ from the level being deleted.',
      );
    }
    if (!tag.levels.contains(reassignTo)) {
      throw ArgumentError(
        'reassignTo ("$reassignTo") is not one of this tag\'s levels.',
      );
    }

    final updatedLevels =
        tag.levels.where((l) => l != levelToDelete).toList();
    await tags.save(tag.copyWith(levels: updatedLevels));

    final affected = await peopleAtTagLevel(tag, levelToDelete);
    for (final person in affected) {
      final updatedInterests = person.interests.map((interest) {
        if (interest.tag == tag.id && interest.level == levelToDelete) {
          return interest.copyWith(level: reassignTo);
        }
        return interest;
      }).toList();
      await people.save(person.copyWith(interests: updatedInterests));
    }
  }

  /// Deletes a tag entirely, removing the matching InterestTag entry
  /// from every person who has it (rather than leaving a dangling
  /// reference to a tag definition that no longer exists).
  Future<void> deleteTag(String tagId) async {
    final peopleResult = await people.loadAll();
    for (final person in peopleResult.items) {
      if (person.interestIn(tagId) == null) continue;
      final updatedInterests =
          person.interests.where((i) => i.tag != tagId).toList();
      await people.save(person.copyWith(interests: updatedInterests));
    }
    await tags.delete(tagId);
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

  /// Bulk-adds every member of [group] to [event] as new guests. Always
  /// uses invited_via = group_message with the group's own
  /// [Group.defaultPlatform] — there's no reason to invite "via this
  /// group" through any other method, so this isn't a caller-supplied
  /// parameter the way it used to be. This is the snapshot behavior
  /// described in the design doc: membership is copied once, with no
  /// ongoing link to the group afterward. People already on the event's
  /// guest list (matched by person_id) are skipped — re-inviting a group
  /// never duplicates or clobbers existing RSVP state.
  ///
  /// Returns the updated Event (caller is responsible for persisting it
  /// via saveEvent, so this stays a pure in-memory operation that's easy
  /// to test and easy to preview before committing to disk).
  Event inviteGroupToEvent({
    required Event event,
    required Group group,
  }) {
    final existingIds = event.guests.map((g) => g.personId).toSet();
    final today = SimpleDate.today();
    final newGuests = group.memberIds
        .where((id) => !existingIds.contains(id))
        .map((id) => Guest(
              personId: id,
              rsvp: RsvpStatus.noResponse,
              invitedVia: InviteMethod.groupMessage,
              platform: group.defaultPlatform,
              // Being invited counts as the first contact, so the
              // follow-up cooldown starts now rather than showing this
              // person as already overdue the moment they're added.
              lastFollowUp: today,
            ))
        .toList();

    return event.copyWith(guests: [...event.guests, ...newGuests]);
  }
}
