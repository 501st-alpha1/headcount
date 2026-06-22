// Run this with: dart run bin/verify_models.dart
//
// This is a standalone sanity check, not a real test suite — it builds one
// instance of each model, serializes it to TOML, parses it back, and checks
// the round-trip matches. Run it once after `flutter pub get` to confirm
// the toml package version installed actually supports the API used in
// lib/models/. If anything throws or prints a MISMATCH, paste the output
// back and we'll fix the model code.

import 'package:headcount/models/enums.dart';
import 'package:headcount/models/event.dart';
import 'package:headcount/models/group.dart';
import 'package:headcount/models/guest.dart';
import 'package:headcount/models/person.dart';
import 'package:headcount/models/simple_date.dart';
import 'package:headcount/models/slug.dart';

void main() {
  var failures = 0;

  void check(String label, bool condition) {
    if (condition) {
      print('OK   $label');
    } else {
      print('FAIL $label');
      failures++;
    }
  }

  // --- slug ---
  check('slugify basic', slugify('Alice Chen') == 'alice-chen');
  check('slugify punctuation', slugify("Bob O'Reilly") == 'bob-oreilly');
  check(
    'uniqueSlug collision',
    uniqueSlug('alice-chen', {'alice-chen'}) == 'alice-chen-2',
  );

  // --- SimpleDate ---
  check(
    'SimpleDate.parse round-trip',
    SimpleDate.parse('2026-08-15').toIsoString() == '2026-08-15',
  );
  check(
    'SimpleDate comparison',
    const SimpleDate(year: 2026, month: 6, day: 10)
        .isBefore(const SimpleDate(year: 2026, month: 8, day: 15)),
  );

  // --- Person round-trip ---
  final person = Person(
    id: 'alice-chen',
    name: 'Alice Chen',
    platforms: ['Signal', 'Instagram'],
    notes: 'Busy Sundays.',
    interests: [
      InterestTag(
        tag: 'hiking',
        level: InterestLevel.easyOnly,
        notes: 'Bad knee, flat trails only',
      ),
    ],
  );
  final personToml = person.toTomlString();
  print('--- person.toml ---\n$personToml');
  final personParsed = Person.fromTomlString(personToml);
  check('person id round-trip', personParsed.id == person.id);
  check('person name round-trip', personParsed.name == person.name);
  check(
    'person platforms round-trip',
    personParsed.platforms.join(',') == person.platforms.join(','),
  );
  check(
    'person interests round-trip',
    personParsed.interests.length == 1 &&
        personParsed.interests.first.tag == 'hiking' &&
        personParsed.interests.first.level == InterestLevel.easyOnly,
  );

  // --- Group round-trip ---
  final group = Group(
    id: 'book-club',
    name: 'Book Club',
    memberIds: ['alice-chen', 'bob-smith'],
    notes: 'Meets monthly',
  );
  final groupToml = group.toTomlString();
  print('--- group.toml ---\n$groupToml');
  final groupParsed = Group.fromTomlString(groupToml);
  check('group id round-trip', groupParsed.id == group.id);
  check(
    'group memberIds round-trip',
    groupParsed.memberIds.join(',') == group.memberIds.join(','),
  );

  // --- Event round-trip (including guests) ---
  final event = Event(
    id: 'summer-picnic',
    name: 'Summer Picnic',
    date: const SimpleDate(year: 2026, month: 8, day: 15),
    description: 'Griffith Park, near the merry-go-round',
    pinned: true,
    guests: [
      Guest(
        personId: 'alice-chen',
        rsvp: RsvpStatus.softYes,
        invitedVia: InviteMethod.dm,
        platform: 'Signal',
        followUpCount: 1,
        lastFollowUp: const SimpleDate(year: 2026, month: 6, day: 10),
        notes: 'Waiting to confirm with partner',
      ),
      Guest(
        personId: 'bob-smith',
        rsvp: RsvpStatus.noResponse,
        invitedVia: InviteMethod.groupMessage,
        platform: 'Instagram',
      ),
    ],
  );
  check(
    'event filename',
    event.filename == '2026-08-15-summer-picnic.toml',
  );
  check(
    'event relativePath',
    event.relativePath == 'events/2026/08/2026-08-15-summer-picnic.toml',
  );

  final eventToml = event.toTomlString();
  print('--- event.toml ---\n$eventToml');
  check(
    'event.toml date has no time/offset component',
    eventToml.contains('date = 2026-08-15\n'),
  );
  final eventParsed = Event.fromTomlString(eventToml);
  check('event id round-trip', eventParsed.id == event.id);
  check(
    'event date round-trip',
    eventParsed.date == const SimpleDate(year: 2026, month: 8, day: 15),
  );
  check('event guest count round-trip', eventParsed.guests.length == 2);
  check(
    'event guest rsvp round-trip',
    eventParsed.guestFor('alice-chen')?.rsvp == RsvpStatus.softYes,
  );
  check(
    'event guest lastFollowUp round-trip',
    eventParsed.guestFor('alice-chen')?.lastFollowUp ==
        const SimpleDate(year: 2026, month: 6, day: 10),
  );
  check(
    'event guest with null lastFollowUp round-trip',
    eventParsed.guestFor('bob-smith')?.lastFollowUp == null,
  );

  print('\n${failures == 0 ? "ALL CHECKS PASSED" : "$failures CHECK(S) FAILED"}');
}
