import 'package:toml/toml.dart';

import 'enums.dart';
import 'guest.dart';
import 'simple_date.dart';
import 'toml_codec.dart';

/// An event you're tracking RSVPs for.
/// Stored at events/<YYYY>/<MM>/<YYYY-MM-DD>-<id>.toml.
class Event {
  final String id;
  final String name;
  final SimpleDate date;
  final String description;
  final bool pinned;
  final List<Guest> guests;

  const Event({
    required this.id,
    required this.name,
    required this.date,
    this.description = '',
    this.pinned = true,
    this.guests = const [],
  });

  Event copyWith({
    String? id,
    String? name,
    SimpleDate? date,
    String? description,
    bool? pinned,
    List<Guest>? guests,
  }) {
    return Event(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      description: description ?? this.description,
      pinned: pinned ?? this.pinned,
      guests: guests ?? this.guests,
    );
  }

  /// True if this event's date is today or in the future.
  bool get isUpcoming => !date.isBefore(SimpleDate.today());

  /// Number of days the home screen keeps showing a pinned event after
  /// its date has passed, before it's treated as archived. This is a
  /// grace period for "did everyone show up?" / final headcount glances
  /// — not a setting, just a constant, so it's easy to find and tune.
  static const int homeScreenGraceDays = 3;

  /// True if this event should appear on the home screen right now.
  /// This is computed from [pinned] and [date] rather than stored, so an
  /// event automatically drops off the home screen a few days after it
  /// happens without any write needing to happen — "pinned" in the file
  /// just means "I want this visible up front," and time does the rest.
  bool get showsOnHomeScreen {
    if (!pinned) return false;
    if (isUpcoming) return true;
    return date.daysUntil(SimpleDate.today()) <= homeScreenGraceDays;
  }

  /// Two-digit zero-padded month, e.g. "06".
  String get _monthSegment => date.month.toString().padLeft(2, '0');

  /// The filename for this event, e.g. "2026-08-15-summer-picnic.toml".
  String get filename => '${date.toIsoString()}-$id.toml';

  /// The relative path (from the data root) for this event's file, e.g.
  /// "events/2026/08/2026-08-15-summer-picnic.toml".
  String get relativePath =>
      'events/${date.year}/$_monthSegment/$filename';

  /// All guests on this event currently flagged as needing follow-up,
  /// per Guest.needsFollowUp.
  List<Guest> get guestsNeedingFollowUp {
    final upcoming = isUpcoming;
    return guests.where((g) => g.needsFollowUp(upcoming)).toList();
  }

  /// Counts guests by RSVP status, e.g. for a home-screen summary like
  /// "5 yes, 2 no response". Only statuses with at least one guest are
  /// included, and iteration order follows RsvpStatus's declared order
  /// (yes, probably, maybe, probablyNot, no, noResponse) so summaries
  /// read consistently across events rather than in file order.
  Map<RsvpStatus, int> get rsvpCounts {
    final counts = <RsvpStatus, int>{};
    for (final status in RsvpStatus.values) {
      final count = guests.where((g) => g.rsvp == status).length;
      if (count > 0) counts[status] = count;
    }
    return counts;
  }

  /// Returns the guest entry for [personId], or null if they're not on
  /// this event's guest list.
  Guest? guestFor(String personId) {
    for (final guest in guests) {
      if (guest.personId == personId) return guest;
    }
    return null;
  }

  Map<String, dynamic> toTomlMap() {
    return {
      'id': id,
      'name': name,
      'date': date.toTomlLocalDate(),
      'description': description,
      'pinned': pinned,
      'guests': guests.map((g) => g.toTomlMap()).toList(),
    };
  }

  String toTomlString() {
    return TomlDocument.fromMap(toTomlMap()).toString();
  }

  factory Event.fromTomlMap(Map<String, dynamic> map) {
    final rawGuests = (map['guests'] as List?) ?? const [];
    return Event(
      id: map['id'] as String,
      name: map['name'] as String,
      date: readSimpleDate(map, 'date')!,
      description: (map['description'] as String?) ?? '',
      pinned: (map['pinned'] as bool?) ?? true,
      guests: rawGuests
          .map((g) => Guest.fromTomlMap(g as Map<String, dynamic>))
          .toList(),
    );
  }

  static Event fromTomlString(String tomlContent) {
    final map = TomlDocument.parse(tomlContent).toMap();
    return Event.fromTomlMap(map);
  }
}
