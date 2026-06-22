import 'package:headcount/models/enums.dart';
import 'package:headcount/models/event.dart';
import 'package:headcount/models/group.dart';
import 'package:headcount/models/guest.dart';
import 'package:headcount/models/person.dart';
import 'package:headcount/models/simple_date.dart';
import 'package:headcount/models/slug.dart';
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

  group('Person TOML round-trip', () {
    test('round-trips all fields including interests', () {
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

      final parsed = Person.fromTomlString(person.toTomlString());

      expect(parsed.id, person.id);
      expect(parsed.name, person.name);
      expect(parsed.platforms, person.platforms);
      expect(parsed.notes, person.notes);
      expect(parsed.interests, hasLength(1));
      expect(parsed.interests.first.tag, 'hiking');
      expect(parsed.interests.first.level, InterestLevel.easyOnly);
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
          InterestTag(tag: 'hiking', level: InterestLevel.lovesIt),
        ],
      );
      expect(person.interestIn('hiking')?.level, InterestLevel.lovesIt);
      expect(person.interestIn('board_games'), isNull);
    });
  });

  group('Group TOML round-trip', () {
    test('round-trips member_ids and notes', () {
      final group = Group(
        id: 'book-club',
        name: 'Book Club',
        memberIds: ['alice-chen', 'bob-smith'],
        notes: 'Meets monthly',
      );
      final parsed = Group.fromTomlString(group.toTomlString());
      expect(parsed.id, group.id);
      expect(parsed.name, group.name);
      expect(parsed.memberIds, group.memberIds);
      expect(parsed.notes, group.notes);
    });

    test('round-trips an empty member list', () {
      final group = Group(id: 'empty-group', name: 'Empty Group');
      final parsed = Group.fromTomlString(group.toTomlString());
      expect(parsed.memberIds, isEmpty);
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

      final parsed = Event.fromTomlString(event.toTomlString());

      expect(parsed.id, event.id);
      expect(parsed.date, event.date);
      expect(parsed.description, event.description);
      expect(parsed.guests, hasLength(2));

      final alice = parsed.guestFor('alice-chen');
      expect(alice, isNotNull);
      expect(alice!.rsvp, RsvpStatus.softYes);
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
    test('no_response on an upcoming event needs follow-up', () {
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

    test('soft_yes with zero follow-ups needs a follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.softYes,
        invitedVia: InviteMethod.dm,
        followUpCount: 0,
      );
      expect(guest.needsFollowUp(true), isTrue);
    });

    test('soft_yes after at least one follow-up does not need another', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.softYes,
        invitedVia: InviteMethod.dm,
        followUpCount: 1,
      );
      expect(guest.needsFollowUp(true), isFalse);
    });

    test('a firm yes never needs follow-up', () {
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

    test('declined never needs follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.declined,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isFalse);
    });

    test('maybe on an upcoming event needs follow-up', () {
      final guest = Guest(
        personId: 'p',
        rsvp: RsvpStatus.maybe,
        invitedVia: InviteMethod.dm,
      );
      expect(guest.needsFollowUp(true), isTrue);
    });
  });
}
