import 'package:toml/toml.dart';

import 'guest.dart';

/// An event you're tracking RSVPs for.
/// Stored at events/<YYYY>/<MM>/<YYYY-MM-DD>-<id>.toml.
class Event {
  final String id;
  final String name;
  final DateTime date;
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
    DateTime? date,
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
  bool get isUpcoming {
    final today = DateTime.now();
    final dateOnly = DateTime(date.year, date.month, date.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    return !dateOnly.isBefore(todayOnly);
  }

  /// Two-digit zero-padded month, e.g. "06".
  String get _monthSegment => date.month.toString().padLeft(2, '0');

  /// Two-digit zero-padded day, e.g. "05".
  String get _daySegment => date.day.toString().padLeft(2, '0');

  /// The filename for this event, e.g. "2026-08-15-summer-picnic.toml".
  String get filename =>
      '${date.year}-$_monthSegment-$_daySegment-$id.toml';

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
      'date': date,
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
      date: map['date'] as DateTime,
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
