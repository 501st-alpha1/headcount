import 'dart:io';

import 'package:headcount/models/enums.dart';
import 'package:headcount/models/guest.dart';
import 'package:headcount/models/simple_date.dart';
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
    test('adds all group members as no_response guests', () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      final group =
          await repo.groups.create(name: 'Book Club', memberIds: [alice.id, bob.id]);
      final event = await repo.events.create(
        name: 'Book Club Meeting',
        date: const SimpleDate(year: 2026, month: 6, day: 1),
      );

      final updated = repo.inviteGroupToEvent(
        event: event,
        group: group,
        invitedVia: InviteMethod.groupMessage,
        platform: 'Signal',
      );

      expect(updated.guests, hasLength(2));
      expect(updated.guestFor(alice.id)?.rsvp, RsvpStatus.noResponse);
      expect(updated.guestFor(alice.id)?.invitedVia, InviteMethod.groupMessage);
      expect(updated.guestFor(alice.id)?.platform, 'Signal');
    });

    test('re-inviting the same group does not duplicate or clobber existing guests',
        () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      final group =
          await repo.groups.create(name: 'Book Club', memberIds: [alice.id, bob.id]);
      var event = await repo.events.create(
        name: 'Book Club Meeting',
        date: const SimpleDate(year: 2026, month: 6, day: 1),
      );

      event = repo.inviteGroupToEvent(
        event: event,
        group: group,
        invitedVia: InviteMethod.groupMessage,
      );
      // Simulate the user having since recorded Alice's RSVP.
      final aliceConfirmed = event.guestFor(alice.id)!.copyWith(rsvp: RsvpStatus.yes);
      event = event.copyWith(
        guests: event.guests.map((g) => g.personId == alice.id ? aliceConfirmed : g).toList(),
      );

      final reInvited = repo.inviteGroupToEvent(
        event: event,
        group: group,
        invitedVia: InviteMethod.groupMessage,
      );

      expect(reInvited.guests, hasLength(2));
      expect(reInvited.guestFor(alice.id)?.rsvp, RsvpStatus.yes,
          reason: 're-inviting should not reset an existing RSVP');
    });

    test('editing the group after inviting does not affect the already-invited event',
        () async {
      final alice = await repo.people.create(name: 'Alice Chen');
      final bob = await repo.people.create(name: 'Bob Smith');
      var group =
          await repo.groups.create(name: 'Book Club', memberIds: [alice.id, bob.id]);
      var event = await repo.events.create(
        name: 'Book Club Meeting',
        date: const SimpleDate(year: 2026, month: 6, day: 1),
      );
      event = repo.inviteGroupToEvent(
        event: event,
        group: group,
        invitedVia: InviteMethod.groupMessage,
      );
      await repo.saveEvent(event);

      // Now remove bob from the group.
      group = group.copyWith(memberIds: [alice.id]);
      await repo.saveGroup(group);

      // The event's guest list should be untouched.
      final reloaded = await repo.events.load(event.id);
      expect(reloaded!.guests, hasLength(2));
      expect(reloaded.guestFor(bob.id), isNotNull);
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
          rsvp: RsvpStatus.softYes,
          invitedVia: InviteMethod.dm,
        ),
      ]);
      await repo.saveEvent(event);

      final snapshot = await repo.loadAll();
      final results = snapshot.eventsFor(alice.id);

      expect(results, hasLength(1));
      expect(results.first.$1.id, 'summer-picnic');
      expect(results.first.$2.rsvp, RsvpStatus.softYes);
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
}
