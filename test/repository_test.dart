import 'dart:io';

import 'package:headcount/models/enums.dart';
import 'package:headcount/models/guest.dart';
import 'package:headcount/models/person.dart';
import 'package:headcount/models/simple_date.dart';
import 'package:headcount/models/tag.dart';
import 'package:headcount/repository/exceptions.dart';
import 'package:headcount/repository/repository.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Repository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('headcount_test_');
    repo = Repository(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('loadAll on an empty/nonexistent data directory', () {
    test('returns empty lists, no issues', () async {
      final snapshot = await repo.loadAll();
      expect(snapshot.people, isEmpty);
      expect(snapshot.groups, isEmpty);
      expect(snapshot.events, isEmpty);
      expect(snapshot.hasIssues, isFalse);
    });
  });

  group('PersonRepository', () {
    test('create() writes a file at the expected path', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      expect(alice.id, 'alice-chen');
      expect(await File(repo.people.pathFor('alice-chen')).exists(), isTrue);
    });

    test('create() slugifies the name when no id is given', () async {
      final person = await repo.people.create(name: "Bob O'Reilly");
      expect(person.id, 'bob-oreilly');
    });

    test('create() auto-uniquifies on name collision', () async {
      await repo.people.create(name: 'Alice Chen');
      final second = await repo.people.create(name: 'Alice Chen');
      expect(second.id, 'alice-chen-2');
    });

    test('load() returns null for a nonexistent id', () async {
      expect(await repo.people.load('nobody'), isNull);
    });

    test('load() returns a previously saved person', () async {
      await repo.people.create(name: 'Alice Chen', notes: 'Busy Sundays');
      final loaded = await repo.people.load('alice-chen');
      expect(loaded, isNotNull);
      expect(loaded!.notes, 'Busy Sundays');
    });

    test('delete() removes the file', () async {
      await repo.people.create(name: 'Charlie Diaz');
      await repo.people.delete('charlie-diaz');
      expect(await File(repo.people.pathFor('charlie-diaz')).exists(), isFalse);
    });

    test('create() accepts interests directly', () async {
      final person = await repo.people.create(
        name: 'Alice Chen',
        interests: [
          const InterestTag(
            tag: 'hiking',
            level: 'easy_only',
            notes: 'Bad knee',
          ),
        ],
      );
      expect(person.interests, hasLength(1));

      final reloaded = await repo.people.load(person.id);
      expect(reloaded!.interests.first.tag, 'hiking');
      expect(reloaded.interests.first.level, 'easy_only');
    });

    test('delete() is a no-op for a nonexistent id', () async {
      await repo.people.delete('nobody');
      // No exception means pass.
    });
  });

  group('GroupRepository', () {
    test('create() writes a file and saveGroup validates members', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      final group =
          await repo.groups.create(name: 'Book Club', memberIds: [alice.id, bob.id]);
      expect(await File(repo.groups.pathFor(group.id)).exists(), isTrue);
    });

    test('saveGroup rejects a dangling member_id', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final group = await repo.groups.create(
        name: 'Book Club',
        memberIds: [alice.id],
      );
      final corrupted = group.copyWith(memberIds: [alice.id, 'ghost-person']);

      expect(
        () => repo.saveGroup(corrupted),
        throwsA(isA<DanglingReferenceException>()),
      );
    });
  });

  group('EventRepository', () {
    test('create() writes a file under events/YYYY/MM/', () async {
      final event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      final expectedPath =
          '${tempDir.path}/events/2026/08/2026-08-15-summer-picnic.toml';
      expect(await File(expectedPath).exists(), isTrue);
      expect(event.id, 'summer-picnic');
    });

    test('saveEvent rejects a dangling person_id in guests', () async {
      final event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      final corrupted = event.copyWith(guests: [
        Guest(
          personId: 'ghost-person',
          rsvp: RsvpStatus.noResponse,
          invitedVia: InviteMethod.dm,
        ),
      ]);

      expect(
        () => repo.saveEvent(corrupted),
        throwsA(isA<DanglingReferenceException>()),
      );
    });

    test('changing an event\'s date moves the file and cleans up the old month folder',
        () async {
      final event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      final oldPath =
          '${tempDir.path}/events/2026/08/2026-08-15-summer-picnic.toml';
      expect(await File(oldPath).exists(), isTrue);

      final moved =
          event.copyWith(date: const SimpleDate(year: 2026, month: 9, day: 1));
      await repo.saveEvent(moved, previous: event);

      final newPath =
          '${tempDir.path}/events/2026/09/2026-09-01-summer-picnic.toml';
      expect(await File(oldPath).exists(), isFalse,
          reason: 'old file should be removed after the move');
      expect(await File(newPath).exists(), isTrue,
          reason: 'new file should exist at the new date path');
      expect(await Directory('${tempDir.path}/events/2026/08').exists(), isFalse,
          reason: 'now-empty month folder should be cleaned up');
    });

    test('moving an event within the same month does not delete its own new file',
        () async {
      final event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      final moved =
          event.copyWith(date: const SimpleDate(year: 2026, month: 8, day: 20));
      await repo.saveEvent(moved, previous: event);

      final newPath =
          '${tempDir.path}/events/2026/08/2026-08-20-summer-picnic.toml';
      expect(await File(newPath).exists(), isTrue);
      // The month folder should still exist (it's not empty: it has the new file).
      expect(await Directory('${tempDir.path}/events/2026/08').exists(), isTrue);
    });
  });

  group('Repository.inviteGroupToEvent', () {
    test('adds all group members as no_response guests, using the group\'s '
        'own default platform', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      final group = await repo.groups.create(
        name: 'Book Club',
        memberIds: [alice.id, bob.id],
        defaultPlatform: 'Signal',
      );
      final event = await repo.events.create(
        name: 'Book Club Meeting',
        date: const SimpleDate(year: 2026, month: 6, day: 1),
      );

      final updated = repo.inviteGroupToEvent(event: event, group: group);

      expect(updated.guests, hasLength(2));
      expect(updated.guestFor(alice.id)?.rsvp, RsvpStatus.noResponse);
      expect(updated.guestFor(alice.id)?.invitedVia, InviteMethod.groupMessage);
      expect(updated.guestFor(alice.id)?.platform, 'Signal');
      expect(updated.guestFor(bob.id)?.platform, 'Signal');
    });

    test(
        'newly invited guests do not immediately show as needing follow-up '
        '(invitation counts as contact)', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final group = await repo.groups.create(
        name: 'Book Club',
        memberIds: [alice.id],
        defaultPlatform: 'Signal',
      );
      final event = await repo.events.create(
        name: 'Book Club Meeting',
        date: const SimpleDate(year: 2099, month: 6, day: 1),
      );

      final updated = repo.inviteGroupToEvent(event: event, group: group);

      final aliceGuest = updated.guestFor(alice.id)!;
      expect(aliceGuest.lastFollowUp, SimpleDate.today());
      expect(aliceGuest.needsFollowUp(true), isFalse);
    });

    test('re-inviting the same group does not duplicate or clobber existing guests',
        () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      final group = await repo.groups.create(
        name: 'Book Club',
        memberIds: [alice.id, bob.id],
        defaultPlatform: 'Signal',
      );
      var event = await repo.events.create(
        name: 'Book Club Meeting',
        date: const SimpleDate(year: 2026, month: 6, day: 1),
      );

      event = repo.inviteGroupToEvent(event: event, group: group);
      // Simulate the user having since recorded Alice's RSVP.
      final aliceConfirmed = event.guestFor(alice.id)!.copyWith(rsvp: RsvpStatus.yes);
      event = event.copyWith(
        guests: event.guests.map((g) => g.personId == alice.id ? aliceConfirmed : g).toList(),
      );

      final reInvited = repo.inviteGroupToEvent(event: event, group: group);

      expect(reInvited.guests, hasLength(2));
      expect(reInvited.guestFor(alice.id)?.rsvp, RsvpStatus.yes,
          reason: 're-inviting should not reset an existing RSVP');
    });

    test('editing the group after inviting does not affect the already-invited event',
        () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      var group = await repo.groups.create(
        name: 'Book Club',
        memberIds: [alice.id, bob.id],
        defaultPlatform: 'Signal',
      );
      var event = await repo.events.create(
        name: 'Book Club Meeting',
        date: const SimpleDate(year: 2026, month: 6, day: 1),
      );
      event = repo.inviteGroupToEvent(event: event, group: group);
      await repo.saveEvent(event);

      // Now remove bob from the group.
      group = group.copyWith(memberIds: [alice.id]);
      await repo.saveGroup(group);

      // The event's guest list should be untouched.
      final reloaded = await repo.events.load(event.id);
      expect(reloaded!.guests, hasLength(2));
      expect(reloaded.guestFor(bob.id), isNotNull);
    });

    test('a group with no default platform set produces guests with an '
        'empty platform rather than crashing (model-level fallback; the '
        'editor UI is what actually enforces this is required)', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final group = await repo.groups.create(
        name: 'No Platform Group',
        memberIds: [alice.id],
      );
      final event = await repo.events.create(
        name: 'Some Event',
        date: const SimpleDate(year: 2026, month: 6, day: 1),
      );

      final updated = repo.inviteGroupToEvent(event: event, group: group);

      expect(updated.guestFor(alice.id)?.platform, '');
      expect(updated.guestFor(alice.id)?.invitedVia, InviteMethod.groupMessage);
    });
  });

  group('Repository.deletePerson', () {
    test('rejects deletion when referenced by an event', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      var event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      event = event.copyWith(guests: [
        Guest(personId: alice.id, rsvp: RsvpStatus.yes, invitedVia: InviteMethod.dm),
      ]);
      await repo.saveEvent(event);

      expect(
        () => repo.deletePerson(alice.id),
        throwsA(isA<DanglingReferenceException>()),
      );
    });

    test('rejects deletion when referenced by a group', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      await repo.groups.create(name: 'Book Club', memberIds: [alice.id]);

      expect(
        () => repo.deletePerson(alice.id),
        throwsA(isA<DanglingReferenceException>()),
      );
    });

    test('succeeds for a person with no references', () async {
      final charlie = await repo.people.create(name: 'Charlie Diaz');
      await repo.deletePerson(charlie.id);
      expect(await File(repo.people.pathFor(charlie.id)).exists(), isFalse);
    });
  });

  group('loadAll with a malformed file present', () {
    test('skips the bad file and reports it as an issue, without losing good data',
        () async {
      await repo.people.create(name: 'Alice Chen');
      final junkFile = File('${tempDir.path}/people/broken.toml');
      await junkFile.create(recursive: true);
      await junkFile.writeAsString('this is not valid toml {{{');

      final snapshot = await repo.loadAll();

      expect(snapshot.people, hasLength(1),
          reason: 'the malformed file should be excluded, not crash the load');
      expect(snapshot.hasIssues, isTrue);
      expect(snapshot.issues.first.relativePath, contains('broken.toml'));
    });
  });

  group('DataSnapshot queries', () {
    test('eventsFor returns every event a person is on, paired with their guest entry',
        () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      var event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      event = event.copyWith(guests: [
        Guest(
          personId: alice.id,
          rsvp: RsvpStatus.probably,
          invitedVia: InviteMethod.dm,
        ),
      ]);
      await repo.saveEvent(event);

      final snapshot = await repo.loadAll();
      final results = snapshot.eventsFor(alice.id);

      expect(results, hasLength(1));
      expect(results.first.$1.id, 'summer-picnic');
      expect(results.first.$2.rsvp, RsvpStatus.probably);
    });

    test('upcomingFollowUps only includes upcoming events with guests needing follow-up',
        () async {
      final alice = await repo.people.create(name: 'Alice Chen');

      var upcoming = await repo.events.create(
        name: 'Future Event',
        date: const SimpleDate(year: 2099, month: 1, day: 1),
      );
      upcoming = upcoming.copyWith(guests: [
        Guest(
          personId: alice.id,
          rsvp: RsvpStatus.noResponse,
          invitedVia: InviteMethod.dm,
        ),
      ]);
      await repo.saveEvent(upcoming);

      var past = await repo.events.create(
        name: 'Past Event',
        date: const SimpleDate(year: 2000, month: 1, day: 1),
      );
      past = past.copyWith(guests: [
        Guest(
          personId: alice.id,
          rsvp: RsvpStatus.noResponse,
          invitedVia: InviteMethod.dm,
        ),
      ]);
      await repo.saveEvent(past);

      final snapshot = await repo.loadAll();
      final results = snapshot.upcomingFollowUps();

      expect(results, hasLength(1));
      expect(results.first.$1.name, 'Future Event');
    });
  });

  group('DataSnapshot.eventsOnHomeScreen and archivedEvents', () {
    test('eventsOnHomeScreen includes pinned upcoming events, sorted soonest first',
        () async {
      await repo.events.create(
        name: 'Later',
        date: const SimpleDate(year: 2099, month: 6, day: 1),
      );
      await repo.events.create(
        name: 'Sooner',
        date: const SimpleDate(year: 2099, month: 1, day: 1),
      );

      final snapshot = await repo.loadAll();
      final home = snapshot.eventsOnHomeScreen;

      expect(home, hasLength(2));
      expect(home.first.name, 'Sooner');
      expect(home.last.name, 'Later');
    });

    test('eventsOnHomeScreen excludes unpinned events', () async {
      final event = await repo.events.create(
        name: 'Unpinned',
        date: const SimpleDate(year: 2099, month: 1, day: 1),
        pinned: false,
      );
      await repo.saveEvent(event.copyWith(pinned: false));

      final snapshot = await repo.loadAll();
      expect(snapshot.eventsOnHomeScreen, isEmpty);
      expect(snapshot.archivedEvents, hasLength(1));
    });

    test(
        'eventsOnHomeScreen excludes pinned events past the grace period, '
        'archivedEvents includes them',
        () async {
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      final event = await repo.events.create(
        name: 'Long Past',
        date: SimpleDate(
          year: tenDaysAgo.year,
          month: tenDaysAgo.month,
          day: tenDaysAgo.day,
        ),
      );

      final snapshot = await repo.loadAll();
      expect(snapshot.eventsOnHomeScreen, isEmpty);
      expect(snapshot.archivedEvents.map((e) => e.id), contains(event.id));
    });

    test('archivedEvents is sorted most recent first', () async {
      await repo.events.create(
        name: 'Older',
        date: const SimpleDate(year: 2000, month: 1, day: 1),
        pinned: false,
      );
      await repo.events.create(
        name: 'NewerButStillUnpinned',
        date: const SimpleDate(year: 2010, month: 1, day: 1),
        pinned: false,
      );

      final snapshot = await repo.loadAll();
      final archive = snapshot.archivedEvents;

      expect(archive, hasLength(2));
      expect(archive.first.name, 'NewerButStillUnpinned');
      expect(archive.last.name, 'Older');
    });
  });

  group('DataSnapshot.resolvedGuestsFor', () {
    test('pairs each guest with their Person', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      var event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      event = event.copyWith(guests: [
        Guest(personId: alice.id, rsvp: RsvpStatus.yes, invitedVia: InviteMethod.dm),
        Guest(personId: bob.id, rsvp: RsvpStatus.noResponse, invitedVia: InviteMethod.dm),
      ]);
      await repo.saveEvent(event);

      final snapshot = await repo.loadAll();
      final reloadedEvent = snapshot.events.first;
      final resolved = snapshot.resolvedGuestsFor(reloadedEvent);

      expect(resolved, hasLength(2));
      final names = resolved.map((pair) => pair.$2.name).toSet();
      expect(names, {'Alice Chen', 'Bob Smith'});
    });

    test('skips a guest whose person_id has no matching Person', () async {
      // This shouldn't happen via normal saveEvent (which validates), but
      // resolvedGuestsFor should still degrade gracefully rather than
      // crashing on a stale/hand-edited snapshot.
      final alice = await repo.people.create(name: 'Alice Chen');
      var event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      event = event.copyWith(guests: [
        Guest(personId: alice.id, rsvp: RsvpStatus.yes, invitedVia: InviteMethod.dm),
      ]);
      await repo.saveEvent(event);

      final snapshot = await repo.loadAll();
      final reloadedEvent = snapshot.events.first;
      // Simulate a dangling reference without going through saveEvent's
      // validation, to exercise resolvedGuestsFor's defensive skip.
      final withGhost = reloadedEvent.copyWith(guests: [
        ...reloadedEvent.guests,
        Guest(personId: 'ghost', rsvp: RsvpStatus.no, invitedVia: InviteMethod.dm),
      ]);

      final resolved = snapshot.resolvedGuestsFor(withGhost);
      expect(resolved, hasLength(1));
      expect(resolved.first.$2.name, 'Alice Chen');
    });
  });

  group('RsvpStatus.toInvite default and lastFollowUp behavior', () {
    test('a guest added with toInvite has null lastFollowUp and always '
        'needs follow-up', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      var event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2099, month: 8, day: 15),
      );
      event = event.copyWith(guests: [
        // Simulate what AddGuestScreen does for an individual add
        Guest(
          personId: alice.id,
          rsvp: RsvpStatus.toInvite,
          invitedVia: InviteMethod.dm,
          // lastFollowUp deliberately null — not yet contacted
        ),
      ]);
      await repo.saveEvent(event);

      final snapshot = await repo.loadAll();
      final reloaded = snapshot.events.first;
      final guest = reloaded.guestFor(alice.id)!;

      expect(guest.rsvp, RsvpStatus.toInvite);
      expect(guest.lastFollowUp, isNull);
      expect(guest.needsFollowUp(true), isTrue);
    });

    test('a guest added with noResponse (already invited) gets lastFollowUp '
        'set to today and respects the cooldown', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final today = SimpleDate.today();
      var event = await repo.events.create(
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2099, month: 8, day: 15),
      );
      event = event.copyWith(guests: [
        Guest(
          personId: alice.id,
          rsvp: RsvpStatus.noResponse,
          invitedVia: InviteMethod.dm,
          lastFollowUp: today,
        ),
      ]);
      await repo.saveEvent(event);

      final snapshot = await repo.loadAll();
      final guest = snapshot.events.first.guestFor(alice.id)!;

      expect(guest.rsvp, RsvpStatus.noResponse);
      expect(guest.lastFollowUp, today);
      // Within the cooldown — should NOT need follow-up yet.
      expect(guest.needsFollowUp(true, today: today), isFalse);
    });
  });

  group('DataSnapshot.allPlatformsInUse', () {
    test('collects distinct platforms from people, sorted alphabetically',
        () async {
      await repo.people.create(
        name: 'Alice Chen',
        platforms: ['Signal', 'Instagram'],
      );
      await repo.people.create(
        name: 'Bob Smith',
        platforms: ['Signal'],
      );

      final snapshot = await repo.loadAll();
      expect(snapshot.allPlatformsInUse, ['Instagram', 'Signal']);
    });

    test('includes a group\'s default platform even if no person uses it yet',
        () async {
      await repo.groups.create(name: 'Book Club', defaultPlatform: 'Discord');

      final snapshot = await repo.loadAll();
      expect(snapshot.allPlatformsInUse, contains('Discord'));
    });

    test('returns an empty list when nothing has any platform set',
        () async {
      await repo.people.create(name: 'Alice Chen');
      final snapshot = await repo.loadAll();
      expect(snapshot.allPlatformsInUse, isEmpty);
    });

    test('does not duplicate a platform used by both a person and a group\'s default',
        () async {
      await repo.people.create(name: 'Alice Chen', platforms: ['Signal']);
      await repo.groups.create(name: 'Book Club', defaultPlatform: 'Signal');

      final snapshot = await repo.loadAll();
      expect(snapshot.allPlatformsInUse, ['Signal']);
    });
  });

  group('DataSnapshot.allTagsInUse and peopleWithTag', () {
    test('allTagsInUse returns one Tag per distinct tag in use, sorted by name',
        () async {
      await repo.people.create(
        name: 'Alice Chen',
        interests: [
          const InterestTag(tag: 'hiking', level: 'loves_it'),
          const InterestTag(tag: 'board_games', level: 'easy_only'),
        ],
      );
      await repo.people.create(
        name: 'Bob Smith',
        interests: [
          const InterestTag(tag: 'hiking', level: 'needs_convincing'),
        ],
      );

      final snapshot = await repo.loadAll();
      final names = snapshot.allTagsInUse.map((t) => t.id).toList();
      expect(names, ['board_games', 'hiking']);
    });

    test('peopleWithTag sorts by the tag\'s own level order, enthusiastic first',
        () async {
      await repo.people.create(
        name: 'Charlie Diaz',
        interests: [
          const InterestTag(tag: 'hiking', level: 'not_interested'),
        ],
      );
      await repo.people.create(
        name: 'Alice Chen',
        interests: [
          const InterestTag(tag: 'hiking', level: 'loves_it'),
        ],
      );
      await repo.people.create(
        name: 'Bob Smith',
        interests: [
          const InterestTag(tag: 'hiking', level: 'easy_only'),
        ],
      );

      // loadAll() auto-creates the "hiking" tag with Tag.defaultLevels,
      // whose order is loves_it, easy_only, needs_convincing,
      // not_interested — that's what peopleWithTag sorts by now, not a
      // fixed enum.
      final snapshot = await repo.loadAll();
      final results = snapshot.peopleWithTag('hiking');

      expect(results, hasLength(3));
      expect(results[0].$1.name, 'Alice Chen');
      expect(results[1].$1.name, 'Bob Smith');
      expect(results[2].$1.name, 'Charlie Diaz');
    });

    test('peopleWithTag excludes people without that tag', () async {
      await repo.people.create(
        name: 'Alice Chen',
        interests: [
          const InterestTag(tag: 'hiking', level: 'loves_it'),
        ],
      );
      await repo.people.create(name: 'Bob Smith');

      final snapshot = await repo.loadAll();
      final results = snapshot.peopleWithTag('hiking');

      expect(results, hasLength(1));
      expect(results.first.$1.name, 'Alice Chen');
    });

    test('a person whose level isn\'t in the tag\'s defined levels sorts after '
        'everyone with a recognized level', () async {
      await repo.people.create(
        name: 'Alice Chen',
        interests: [const InterestTag(tag: 'hiking', level: 'loves_it')],
      );
      await repo.people.create(
        name: 'Weird Data Bob',
        interests: [
          const InterestTag(tag: 'hiking', level: 'some_stale_level'),
        ],
      );

      final snapshot = await repo.loadAll();
      final results = snapshot.peopleWithTag('hiking');

      expect(results, hasLength(2));
      expect(results[0].$1.name, 'Alice Chen');
      expect(results[1].$1.name, 'Weird Data Bob');
    });
  });

  group('Tag auto-migration on loadAll', () {
    test('creates a Tag definition (with Tag.defaultLevels) for a tag in use '
        'that has no tags/*.toml file yet', () async {
      await repo.people.create(
        name: 'Alice Chen',
        interests: [const InterestTag(tag: 'hiking', level: 'loves_it')],
      );

      final snapshot = await repo.loadAll();
      final hiking = snapshot.tagById('hiking');

      expect(hiking, isNotNull);
      expect(hiking!.levels, Tag.defaultLevels);
      // The migration also writes the file, not just an in-memory Tag —
      // confirm it's actually on disk so future loads don't redo this.
      expect(await File(repo.tags.pathFor('hiking')).exists(), isTrue);
    });

    test('does not overwrite an existing tag definition', () async {
      await repo.tags.create(
        name: 'Hiking',
        id: 'hiking',
        levels: ['custom_a', 'custom_b'],
      );
      await repo.people.create(
        name: 'Alice Chen',
        interests: [const InterestTag(tag: 'hiking', level: 'custom_a')],
      );

      final snapshot = await repo.loadAll();
      expect(snapshot.tagById('hiking')!.levels, ['custom_a', 'custom_b']);
    });

    test('running loadAll twice does not duplicate or re-create tag files',
        () async {
      await repo.people.create(
        name: 'Alice Chen',
        interests: [const InterestTag(tag: 'hiking', level: 'loves_it')],
      );

      await repo.loadAll();
      final secondSnapshot = await repo.loadAll();

      expect(secondSnapshot.tags.where((t) => t.id == 'hiking'), hasLength(1));
    });

    test('a tag with no one currently using it (e.g. after manual creation) '
        'is left alone, not deleted', () async {
      await repo.tags.create(name: 'Unused Tag', id: 'unused-tag');
      final snapshot = await repo.loadAll();
      expect(snapshot.tagById('unused-tag'), isNotNull);
    });
  });

  group('Repository.renameTagLevel', () {
    test('renames the level in the tag definition and cascades to every '
        'person using it', () async {
      final tag = await repo.tags.create(
        name: 'Hiking',
        levels: ['loves_it', 'easy_only'],
      );
      await repo.people.create(
        name: 'Alice Chen',
        interests: [InterestTag(tag: tag.id, level: 'easy_only')],
      );
      await repo.people.create(
        name: 'Bob Smith',
        interests: [InterestTag(tag: tag.id, level: 'loves_it')],
      );

      await repo.renameTagLevel(
        tag: tag,
        oldLevel: 'easy_only',
        newLevel: 'flat_trails_only',
      );

      final snapshot = await repo.loadAll();
      expect(
        snapshot.tagById(tag.id)!.levels,
        ['loves_it', 'flat_trails_only'],
      );
      final alice = snapshot.personById('alice-chen')!;
      expect(alice.interestIn(tag.id)!.level, 'flat_trails_only');
      // Bob wasn't using the renamed level — untouched.
      final bob = snapshot.personById('bob-smith')!;
      expect(bob.interestIn(tag.id)!.level, 'loves_it');
    });

    test('preserves level order after a rename', () async {
      final tag = await repo.tags.create(
        name: 'Hiking',
        levels: ['a', 'b', 'c'],
      );
      await repo.renameTagLevel(tag: tag, oldLevel: 'b', newLevel: 'b2');
      final reloaded = await repo.tags.load(tag.id);
      expect(reloaded!.levels, ['a', 'b2', 'c']);
    });
  });

  group('Repository.peopleAtTagLevel and deleteTagLevel', () {
    test('peopleAtTagLevel finds everyone currently at a given level',
        () async {
      final tag = await repo.tags.create(
        name: 'Hiking',
        levels: ['loves_it', 'easy_only'],
      );
      await repo.people.create(
        name: 'Alice Chen',
        interests: [InterestTag(tag: tag.id, level: 'easy_only')],
      );
      await repo.people.create(
        name: 'Bob Smith',
        interests: [InterestTag(tag: tag.id, level: 'loves_it')],
      );

      final affected = await repo.peopleAtTagLevel(tag, 'easy_only');
      expect(affected, hasLength(1));
      expect(affected.first.name, 'Alice Chen');
    });

    test('deleteTagLevel removes the level and reassigns affected people',
        () async {
      final tag = await repo.tags.create(
        name: 'Hiking',
        levels: ['loves_it', 'easy_only', 'not_interested'],
      );
      await repo.people.create(
        name: 'Alice Chen',
        interests: [InterestTag(tag: tag.id, level: 'easy_only')],
      );

      await repo.deleteTagLevel(
        tag: tag,
        levelToDelete: 'easy_only',
        reassignTo: 'loves_it',
      );

      final snapshot = await repo.loadAll();
      expect(snapshot.tagById(tag.id)!.levels, ['loves_it', 'not_interested']);
      final alice = snapshot.personById('alice-chen')!;
      expect(alice.interestIn(tag.id)!.level, 'loves_it');
    });

    test('deleteTagLevel rejects reassignTo equal to the level being deleted',
        () async {
      final tag = await repo.tags.create(
        name: 'Hiking',
        levels: ['loves_it', 'easy_only'],
      );
      expect(
        () => repo.deleteTagLevel(
          tag: tag,
          levelToDelete: 'easy_only',
          reassignTo: 'easy_only',
        ),
        throwsArgumentError,
      );
    });

    test('deleteTagLevel rejects a reassignTo that isn\'t one of the tag\'s levels',
        () async {
      final tag = await repo.tags.create(
        name: 'Hiking',
        levels: ['loves_it', 'easy_only'],
      );
      expect(
        () => repo.deleteTagLevel(
          tag: tag,
          levelToDelete: 'easy_only',
          reassignTo: 'nonexistent_level',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Repository.deleteTag', () {
    test('removes the tag file and every person\'s InterestTag entry for it',
        () async {
      final tag = await repo.tags.create(name: 'Hiking');
      await repo.people.create(
        name: 'Alice Chen',
        interests: [InterestTag(tag: tag.id, level: 'loves_it')],
      );

      await repo.deleteTag(tag.id);

      expect(await File(repo.tags.pathFor(tag.id)).exists(), isFalse);
      final reloadedAlice = await repo.people.load('alice-chen');
      expect(reloadedAlice!.interests, isEmpty);
    });

    test('leaves people with other interests untouched', () async {
      final hiking = await repo.tags.create(name: 'Hiking');
      final boardGames = await repo.tags.create(name: 'Board Games');
      await repo.people.create(
        name: 'Alice Chen',
        interests: [
          InterestTag(tag: hiking.id, level: 'loves_it'),
          InterestTag(tag: boardGames.id, level: 'loves_it'),
        ],
      );

      await repo.deleteTag(hiking.id);

      final reloaded = await repo.people.load('alice-chen');
      expect(reloaded!.interests, hasLength(1));
      expect(reloaded.interests.first.tag, boardGames.id);
    });
  });
}
