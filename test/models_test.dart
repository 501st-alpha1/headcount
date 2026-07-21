import 'package:headcount/models/enums.dart';
import 'package:headcount/models/event.dart';
import 'package:headcount/models/group.dart';
import 'package:headcount/models/guest.dart';
import 'package:headcount/models/person.dart';
import 'package:headcount/models/simple_date.dart';
import 'package:headcount/models/slug.dart';
import 'package:headcount/models/tag.dart';
import 'package:test/test.dart';

void main() {
  group('slugify', () {
    test('lowercases and hyphenates', () {
      expect(slugify('Alice Chen'), 'alice-chen');
    });

    test('strips apostrophes instead of hyphenating them', () {
      expect(slugify("Bob O'Reilly"), 'bob-oreilly');
    });

    test('collapses multiple separators', () {
      expect(slugify('Board   Game -- Night'), 'board-game-night');
    });

    test('falls back to "untitled" for empty/symbol-only input', () {
      expect(slugify('   '), 'untitled');
      expect(slugify('!!!'), 'untitled');
    });
  });

  group('uniqueSlug', () {
    test('returns the base slug when not taken', () {
      expect(uniqueSlug('alice-chen', {}), 'alice-chen');
    });

    test('appends -2 on first collision', () {
      expect(uniqueSlug('alice-chen', {'alice-chen'}), 'alice-chen-2');
    });

    test('keeps incrementing past existing numbered collisions', () {
      expect(
        uniqueSlug('alice-chen', {'alice-chen', 'alice-chen-2', 'alice-chen-3'}),
        'alice-chen-4',
      );
    });
  });

  group('SimpleDate', () {
    test('parses strict YYYY-MM-DD', () {
      final date = SimpleDate.parse('2026-08-15');
      expect(date.year, 2026);
      expect(date.month, 8);
      expect(date.day, 15);
    });

    test('rejects malformed input', () {
      expect(() => SimpleDate.parse('2026/08/15'), throwsFormatException);
      expect(() => SimpleDate.parse('not a date'), throwsFormatException);
    });

    test('toIsoString round-trips through parse', () {
      const date = SimpleDate(year: 2026, month: 1, day: 5);
      expect(SimpleDate.parse(date.toIsoString()), date);
    });

    test('zero-pads single-digit month and day', () {
      const date = SimpleDate(year: 2026, month: 1, day: 5);
      expect(date.toIsoString(), '2026-01-05');
    });

    test('isBefore/isAfter compare chronologically', () {
      const earlier = SimpleDate(year: 2026, month: 6, day: 10);
      const later = SimpleDate(year: 2026, month: 8, day: 15);
      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(later.isBefore(earlier), isFalse);
    });

    test('equality is by value, not identity', () {
      const a = SimpleDate(year: 2026, month: 8, day: 15);
      const b = SimpleDate(year: 2026, month: 8, day: 15);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('RsvpStatus.fromToml', () {
    test('parses current values', () {
      expect(RsvpStatus.fromToml('to_invite'), RsvpStatus.toInvite);
      expect(RsvpStatus.fromToml('yes'), RsvpStatus.yes);
      expect(RsvpStatus.fromToml('probably'), RsvpStatus.probably);
      expect(RsvpStatus.fromToml('maybe'), RsvpStatus.maybe);
      expect(RsvpStatus.fromToml('probably_not'), RsvpStatus.probablyNot);
      expect(RsvpStatus.fromToml('no'), RsvpStatus.no);
      expect(RsvpStatus.fromToml('no_response'), RsvpStatus.noResponse);
    });

    test(
        'parses old "soft_yes"/"soft_no"/"declined" values for backward '
        'compatibility with files written before the status rename', () {
      expect(RsvpStatus.fromToml('soft_yes'), RsvpStatus.probably);
      expect(RsvpStatus.fromToml('soft_no'), RsvpStatus.probablyNot);
      expect(RsvpStatus.fromToml('declined'), RsvpStatus.no);
    });

    test('rejects an unrecognized value', () {
      expect(() => RsvpStatus.fromToml('nonsense'), throwsFormatException);
    });

    test('tomlValue never round-trips back to an old/removed value', () {
      // Guards against accidentally reintroducing "soft_yes" etc. as the
      // canonical written form — old values should only ever be read,
      // never written.
      for (final status in RsvpStatus.values) {
        expect(status.tomlValue, isNot('soft_yes'));
        expect(status.tomlValue, isNot('soft_no'));
        expect(status.tomlValue, isNot('declined'));
      }
      // And confirm to_invite writes correctly.
      expect(RsvpStatus.toInvite.tomlValue, 'to_invite');
    });
  });

  group('Person TOML round-trip', () {
    test('round-trips all fields including interests', () {
      final person = Person(
        id: 'alice-chen',
        name: 'Alice Chen',
        platforms: ['Signal', 'Instagram'],
        notes: 'Busy Sundays.',
        interests: [
          const InterestTag(
            tag: 'hiking',
            level: 'easy_only',
            notes: 'Bad knee, flat trails only',
          ),
        ],
      );

      final parsed = Person.fromTomlString(person.toTomlString());

      expect(parsed.id, person.id);
      expect(parsed.name, person.name);
      expect(parsed.platforms, person.platforms);
      expect(parsed.notes, person.notes);
      expect(parsed.interests, hasLength(1));
      expect(parsed.interests.first.tag, 'hiking');
      expect(parsed.interests.first.level, 'easy_only');
      expect(parsed.interests.first.notes, 'Bad knee, flat trails only');
    });

    test('round-trips with no interests and empty notes', () {
      final person = Person(id: 'bob-smith', name: 'Bob Smith');
      final parsed = Person.fromTomlString(person.toTomlString());
      expect(parsed.interests, isEmpty);
      expect(parsed.notes, '');
      expect(parsed.platforms, isEmpty);
    });

    test('interestIn finds a tag by name', () {
      final person = Person(
        id: 'alice-chen',
        name: 'Alice Chen',
        interests: [
          const InterestTag(tag: 'hiking', level: 'loves_it'),
        ],
      );
      expect(person.interestIn('hiking')?.level, 'loves_it');
      expect(person.interestIn('board_games'), isNull);
    });

    test('a tag can have any free-string level, since levels are now '
        'defined per-tag rather than from a fixed enum', () {
      final person = Person(
        id: 'alice-chen',
        name: 'Alice Chen',
        interests: [
          const InterestTag(tag: 'board_games', level: 'will_play_anything'),
        ],
      );
      final parsed = Person.fromTomlString(person.toTomlString());
      expect(parsed.interestIn('board_games')?.level, 'will_play_anything');
    });
  });

  group('Tag TOML round-trip', () {
    test('round-trips id, name, and levels in order', () {
      const tag = Tag(
        id: 'hiking',
        name: 'Hiking',
        levels: ['loves_it', 'easy_only', 'needs_convincing', 'not_interested'],
      );
      final parsed = Tag.fromTomlString(tag.toTomlString());
      expect(parsed.id, 'hiking');
      expect(parsed.name, 'Hiking');
      expect(parsed.levels, [
        'loves_it',
        'easy_only',
        'needs_convincing',
        'not_interested',
      ]);
    });

    test('round-trips an empty levels list', () {
      const tag = Tag(id: 'mystery', name: 'Mystery');
      final parsed = Tag.fromTomlString(tag.toTomlString());
      expect(parsed.levels, isEmpty);
    });

    test('defaultLevels matches the old InterestLevel enum\'s TOML values, '
        'so auto-migrated tags line up exactly with existing person data',
        () {
      expect(Tag.defaultLevels, [
        'loves_it',
        'easy_only',
        'needs_convincing',
        'not_interested',
      ]);
    });

    test('levels preserve order through a round-trip (order is the rank)',
        () {
      const tag = Tag(
        id: 'board_games',
        name: 'Board Games',
        levels: ['will_play_anything', 'casual_only', 'pass'],
      );
      final parsed = Tag.fromTomlString(tag.toTomlString());
      expect(parsed.levels, ['will_play_anything', 'casual_only', 'pass']);
    });

    test('round-trips dependsOn when set', () {
      const tag = Tag(
        id: 'hiking-travel',
        name: 'Travel distance',
        levels: ['local_only', 'day_trip', 'overnight'],
        dependsOn: 'hiking',
      );
      final parsed = Tag.fromTomlString(tag.toTomlString());
      expect(parsed.dependsOn, 'hiking');
      expect(parsed.isDependent, isTrue);
      expect(parsed.isRoot, isFalse);
    });

    test('omits depends_on key entirely when empty (root tag)', () {
      const tag = Tag(id: 'hiking', name: 'Hiking');
      expect(tag.toTomlString(), isNot(contains('depends_on')));
      final parsed = Tag.fromTomlString(tag.toTomlString());
      expect(parsed.dependsOn, '');
      expect(parsed.isRoot, isTrue);
    });

    test('loads a legacy file with no depends_on key as a root tag', () {
      const legacyToml = '''
id = "hiking"
name = "Hiking"
levels = ["loves_it", "easy_only"]
''';
      final parsed = Tag.fromTomlString(legacyToml);
      expect(parsed.dependsOn, '');
      expect(parsed.isRoot, isTrue);
    });

    test('asRoot() clears the dependsOn field', () {
      const tag = Tag(
        id: 'hiking-travel',
        name: 'Travel distance',
        dependsOn: 'hiking',
      );
      expect(tag.asRoot().isRoot, isTrue);
      expect(tag.asRoot().dependsOn, '');
    });
  });

  group('Group TOML round-trip', () {
    test('round-trips member_ids, notes, and defaultPlatform', () {
      final group = Group(
        id: 'book-club',
        name: 'Book Club',
        memberIds: ['alice-chen', 'bob-smith'],
        notes: 'Meets monthly',
        defaultPlatform: 'Signal',
      );
      final parsed = Group.fromTomlString(group.toTomlString());
      expect(parsed.id, group.id);
      expect(parsed.name, group.name);
      expect(parsed.memberIds, group.memberIds);
      expect(parsed.notes, group.notes);
      expect(parsed.defaultPlatform, 'Signal');
    });

    test('round-trips an empty member list', () {
      final group = Group(id: 'empty-group', name: 'Empty Group');
      final parsed = Group.fromTomlString(group.toTomlString());
      expect(parsed.memberIds, isEmpty);
    });

    test(
        'loads a legacy file with no default_platform key as an empty '
        'string rather than crashing', () {
      const legacyToml = '''
id = "book-club"
name = "Book Club"
member_ids = ["alice-chen"]
notes = ""
''';
      final parsed = Group.fromTomlString(legacyToml);
      expect(parsed.defaultPlatform, '');
    });
  });

  group('Event filename and path derivation', () {
    test('filename combines date and id', () {
      final event = Event(
        id: 'summer-picnic',
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      expect(event.filename, '2026-08-15-summer-picnic.toml');
    });

    test('relativePath nests under events/YYYY/MM', () {
      final event = Event(
        id: 'summer-picnic',
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      expect(
        event.relativePath,
        'events/2026/08/2026-08-15-summer-picnic.toml',
      );
    });

    test('month is zero-padded in both filename and path', () {
      final event = Event(
        id: 'new-year-party',
        name: 'New Year Party',
        date: const SimpleDate(year: 2026, month: 1, day: 1),
      );
      expect(event.filename, '2026-01-01-new-year-party.toml');
      expect(event.relativePath, 'events/2026/01/2026-01-01-new-year-party.toml');
    });
  });

  group('Event TOML round-trip', () {
    test('date is encoded with no time or offset component', () {
      final event = Event(
        id: 'summer-picnic',
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
      );
      expect(event.toTomlString(), contains('date = 2026-08-15\n'));
    });

    test('round-trips guests including a null lastFollowUp', () {
      final event = Event(
        id: 'summer-picnic',
        name: 'Summer Picnic',
        date: const SimpleDate(year: 2026, month: 8, day: 15),
        description: 'Griffith Park, near the merry-go-round',
        guests: [
          Guest(
            personId: 'alice-chen',
            rsvp: RsvpStatus.probably,
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

      final parsed = Event.fromTomlString(event.toTomlString());

      expect(parsed.id, event.id);
      expect(parsed.date, event.date);
      expect(parsed.description, event.description);
      expect(parsed.guests, hasLength(2));

      final alice = parsed.guestFor('alice-chen');
      expect(alice, isNotNull);
      expect(alice!.rsvp, RsvpStatus.probably);
      expect(alice.lastFollowUp, const SimpleDate(year: 2026, month: 6, day: 10));

      final bob = parsed.guestFor('bob-smith');
      expect(bob, isNotNull);
      expect(bob!.lastFollowUp, isNull);
    });

    test('omits last_follow_up key entirely rather than writing null', () {
      final event = Event(
        id: 'e',
        name: 'E',
        date: const SimpleDate(year: 2026, month: 1, day: 1),
        guests: [
          Guest(
            personId: 'p',
            rsvp: RsvpStatus.noResponse,
            invitedVia: InviteMethod.dm,
          ),
        ],
      );
      // This is the regression check for the original bug: encoding used
      // to throw because `null` was passed directly as a map value.
      expect(() => event.toTomlString(), returnsNormally);
      expect(event.toTomlString(), isNot(contains('last_follow_up')));
    });

    test(
        'loads a hand-written/legacy file with rsvp = "declined" as '
        'RsvpStatus.no', () {
      const legacyToml = '''
id = "e"
name = "E"
date = 2026-01-01

[[guests]]
person_id = "p"
rsvp = "declined"
declined_reason = "Out of town"
invited_via = "dm"
platform = ""
follow_up_count = 0
notes = ""
''';
      final event = Event.fromTomlString(legacyToml);
      final guest = event.guestFor('p');
      expect(guest, isNotNull);
      expect(guest!.rsvp, RsvpStatus.no);
      expect(guest.declinedReason, 'Out of town');
    });

    test('followUpSuppressed = true is written to and read from TOML', () {
      final event = Event(
        id: 'e',
        name: 'E',
        date: const SimpleDate(year: 2026, month: 1, day: 1),
        guests: [
          Guest(
            personId: 'p',
            rsvp: RsvpStatus.noResponse,
            invitedVia: InviteMethod.dm,
            followUpSuppressed: true,
          ),
        ],
      );
      final toml = event.toTomlString();
      expect(toml, contains('follow_up_suppressed = true'));
      final parsed = Event.fromTomlString(toml);
      expect(parsed.guestFor('p')!.followUpSuppressed, isTrue);
    });

    test('followUpSuppressed = false is omitted from TOML (backward compat)',
        () {
      final event = Event(
        id: 'e',
        name: 'E',
        date: const SimpleDate(year: 2026, month: 1, day: 1),
        guests: [
          Guest(
            personId: 'p',
            rsvp: RsvpStatus.noResponse,
            invitedVia: InviteMethod.dm,
          ),
        ],
      );
      expect(event.toTomlString(), isNot(contains('follow_up_suppressed')));
    });

    test('a legacy file with no follow_up_suppressed key loads as false', () {
      const legacyToml = '''
id = "e"
name = "E"
date = 2026-01-01

[[guests]]
person_id = "p"
rsvp = "no_response"
invited_via = "dm"
platform = ""
follow_up_count = 0
notes = ""
''';
      final event = Event.fromTomlString(legacyToml);
      expect(event.guestFor('p')!.followUpSuppressed, isFalse);
    });
  });

  group('Event.isUpcoming', () {
    test('today counts as upcoming', () {
      final event = Event(
        id: 'today-event',
        name: 'Today',
        date: SimpleDate.today(),
      );
      expect(event.isUpcoming, isTrue);
    });

    test('a date far in the past is not upcoming', () {
      final event = Event(
        id: 'past-event',
        name: 'Past',
        date: const SimpleDate(year: 2000, month: 1, day: 1),
      );
      expect(event.isUpcoming, isFalse);
    });

    test('a date far in the future is upcoming', () {
      final event = Event(
        id: 'future-event',
        name: 'Future',
        date: const SimpleDate(year: 2099, month: 1, day: 1),
      );
      expect(event.isUpcoming, isTrue);
    });
  });

  group('Guest.needsFollowUp', () {
    test('to_invite on an upcoming event always needs follow-up', () {
      // toInvite = never contacted, so always surfaces in the follow-up
      // list regardless of lastFollowUp (which should always be null for
      // a newly-added toInvite guest anyway).
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.toInvite,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isTrue);
    });

    test('to_invite on a past event does not need follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.toInvite,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(false), isFalse);
    });

    test('no_response on an upcoming event with no contact yet needs follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.noResponse,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isTrue);
    });

    test('no_response on a past event does not need follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.noResponse,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(false), isFalse);
    });

    test('soft_yes with no contact yet needs a follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.probably,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isTrue);
    });

    test('soft_yes contacted today is within the cooldown and does not need another', () {
      final today = SimpleDate.today();
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.probably,
        invitedVia: InviteMethod.dm,
        followUpCount: 1,
        lastFollowUp: today,
      );
      expect(guest.needsFollowUp(true, today: today), isFalse);
    });

    test('no_response contacted today (e.g. just invited) does not need follow-up yet', () {
      // This is the original reported bug: adding a guest should count as
      // contact and start the cooldown, not show as needing follow-up
      // immediately.
      final today = SimpleDate.today();
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.noResponse,
        invitedVia: InviteMethod.dm,
        lastFollowUp: today,
      );
      expect(guest.needsFollowUp(true, today: today), isFalse);
    });

    test('contacted exactly at the cooldown boundary needs follow-up again', () {
      const lastContact = SimpleDate(year: 2026, month: 1, day: 1);
      final atBoundary = SimpleDate(
        year: 2026,
        month: 1,
        day: 1 + Guest.followUpCooldownDays,
      );
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.probably,
        invitedVia: InviteMethod.dm,
        lastFollowUp: lastContact,
      );
      expect(guest.needsFollowUp(true, today: atBoundary), isTrue);
    });

    test('contacted one day before the cooldown boundary does not need follow-up yet', () {
      const lastContact = SimpleDate(year: 2026, month: 1, day: 1);
      final justBefore = SimpleDate(
        year: 2026,
        month: 1,
        day: Guest.followUpCooldownDays, // one day short of the boundary
      );
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.probably,
        invitedVia: InviteMethod.dm,
        lastFollowUp: lastContact,
      );
      expect(guest.needsFollowUp(true, today: justBefore), isFalse);
    });

    test('a suppressed guest never needs follow-up regardless of status or cooldown',
        () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.noResponse,
        invitedVia: InviteMethod.dm,
        followUpSuppressed: true,
      );
      expect(guest.needsFollowUp(true), isFalse);
    });

    test('suppression takes priority even for toInvite (never contacted)', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.toInvite,
        invitedVia: InviteMethod.dm,
        followUpSuppressed: true,
      );
      expect(guest.needsFollowUp(true), isFalse);
    });

    test(
        'changing rsvp to an unresolved status auto-lifts suppression in copyWith',
        () {
      final suppressed = Guest(
        personId: 'p',
        rsvp: RsvpStatus.probablyNot,
        invitedVia: InviteMethod.dm,
        followUpSuppressed: true,
      );
      // Changing to maybe (unresolved) should lift suppression.
      final updated = suppressed.copyWith(rsvp: RsvpStatus.maybe);
      expect(updated.followUpSuppressed, isFalse);
    });

    test(
        'changing rsvp to a resolved status does not lift suppression',
        () {
      final suppressed = Guest(
        personId: 'p',
        rsvp: RsvpStatus.probablyNot,
        invitedVia: InviteMethod.dm,
        followUpSuppressed: true,
      );
      // Changing to yes (resolved) — suppression stays, doesn't matter
      // since yes wouldn't trigger follow-up anyway.
      final updated = suppressed.copyWith(rsvp: RsvpStatus.yes);
      expect(updated.followUpSuppressed, isTrue);
    });

    test('a firm yes never needs follow-up regardless of contact history', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.yes,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isFalse);
    });

    test('a firm no never needs follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.no,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isFalse);
    });

    test('maybe on an upcoming event with no contact yet needs follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.maybe,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isTrue);
    });

    test('maybe contacted recently does not need follow-up yet', () {
      final today = SimpleDate.today();
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.maybe,
        invitedVia: InviteMethod.dm,
        lastFollowUp: today,
      );
      expect(guest.needsFollowUp(true, today: today), isFalse);
    });
  });

  group('Event.showsOnHomeScreen', () {
    test('an upcoming pinned event shows on the home screen', () {
      final event = Event(
        id: 'future',
        name: 'Future',
        date: const SimpleDate(year: 2099, month: 1, day: 1),
        pinned: true,
      );
      expect(event.showsOnHomeScreen, isTrue);
    });

    test('an upcoming unpinned event does not show on the home screen', () {
      final event = Event(
        id: 'future',
        name: 'Future',
        date: const SimpleDate(year: 2099, month: 1, day: 1),
        pinned: false,
      );
      expect(event.showsOnHomeScreen, isFalse);
    });

    test('a pinned event still within the grace period shows on the home screen', () {
      final today = SimpleDate.today();
      // Walk back 2 days by constructing from DateTime, since SimpleDate
      // has no subtraction operator of its own (by design — it's a thin
      // value type, not a date-arithmetic library).
      final dt = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 2));
      final event = Event(
        id: 'recent',
        name: 'Recent',
        date: SimpleDate(year: dt.year, month: dt.month, day: dt.day),
        pinned: true,
      );
      expect(event.showsOnHomeScreen, isTrue);
    });

    test('a pinned event past the grace period does not show on the home screen', () {
      final today = SimpleDate.today();
      final dt = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 10));
      final event = Event(
        id: 'old',
        name: 'Old',
        date: SimpleDate(year: dt.year, month: dt.month, day: dt.day),
        pinned: true,
      );
      expect(event.showsOnHomeScreen, isFalse);
    });

    test('an unpinned past event never shows regardless of grace period', () {
      final event = Event(
        id: 'old',
        name: 'Old',
        date: const SimpleDate(year: 2000, month: 1, day: 1),
        pinned: false,
      );
      expect(event.showsOnHomeScreen, isFalse);
    });
  });

  group('Event.rsvpCounts', () {
    test('counts guests by status, omitting statuses with zero guests', () {
      final event = Event(
        id: 'e',
        name: 'E',
        date: const SimpleDate(year: 2026, month: 1, day: 1),
        guests: [
          Guest(personId: 'a', rsvp: RsvpStatus.yes, invitedVia: InviteMethod.dm),
          Guest(personId: 'b', rsvp: RsvpStatus.yes, invitedVia: InviteMethod.dm),
          Guest(
            personId: 'c',
            rsvp: RsvpStatus.noResponse,
            invitedVia: InviteMethod.dm,
          ),
        ],
      );
      final counts = event.rsvpCounts;
      expect(counts[RsvpStatus.yes], 2);
      expect(counts[RsvpStatus.noResponse], 1);
      expect(counts.containsKey(RsvpStatus.no), isFalse);
    });

    test('returns an empty map for an event with no guests', () {
      final event = Event(
        id: 'e',
        name: 'E',
        date: const SimpleDate(year: 2026, month: 1, day: 1),
      );
      expect(event.rsvpCounts, isEmpty);
    });
  });

  group('SimpleDate.daysUntil', () {
    test('is positive when other is later', () {
      const earlier = SimpleDate(year: 2026, month: 1, day: 1);
      const later = SimpleDate(year: 2026, month: 1, day: 4);
      expect(earlier.daysUntil(later), 3);
    });

    test('is negative when other is earlier', () {
      const earlier = SimpleDate(year: 2026, month: 1, day: 1);
      const later = SimpleDate(year: 2026, month: 1, day: 4);
      expect(later.daysUntil(earlier), -3);
    });

    test('is zero for the same date', () {
      const date = SimpleDate(year: 2026, month: 1, day: 1);
      expect(date.daysUntil(date), 0);
    });
  });
}
