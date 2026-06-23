import 'package:toml/toml.dart';

/// A single interest tag on a person: what they're into, how much, and
/// any free-text context (e.g. "bad knee, flat trails only").
///
/// [level] is a free string rather than a fixed enum, since levels are
/// now defined per-tag (see Tag) — "easy only" is meaningful for hiking
/// but not for board games, so there's no longer one global vocabulary.
/// This class doesn't validate that [level] is one of the owning Tag's
/// currently defined levels; that check happens where a Tag is available
/// to check against (see Repository), since InterestTag alone has no way
/// to look up its tag's definition.
class InterestTag {
  final String tag;
  final String level;
  final String notes;

  const InterestTag({
    required this.tag,
    required this.level,
    this.notes = '',
  });

  InterestTag copyWith({
    String? tag,
    String? level,
    String? notes,
  }) {
    return InterestTag(
      tag: tag ?? this.tag,
      level: level ?? this.level,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toTomlMap() {
    return {
      'tag': tag,
      'level': level,
      'notes': notes,
    };
  }

  factory InterestTag.fromTomlMap(Map<String, dynamic> map) {
    return InterestTag(
      tag: map['tag'] as String,
      level: map['level'] as String,
      notes: (map['notes'] as String?) ?? '',
    );
  }
}

/// A person you might invite to events. Stored at people/<id>.toml.
class Person {
  final String id;
  final String name;
  final List<String> platforms;
  final String notes;
  final List<InterestTag> interests;

  const Person({
    required this.id,
    required this.name,
    this.platforms = const [],
    this.notes = '',
    this.interests = const [],
  });

  Person copyWith({
    String? id,
    String? name,
    List<String>? platforms,
    String? notes,
    List<InterestTag>? interests,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      platforms: platforms ?? this.platforms,
      notes: notes ?? this.notes,
      interests: interests ?? this.interests,
    );
  }

  /// Returns the interest tag matching [tagName], or null if this person
  /// has no recorded interest in it.
  InterestTag? interestIn(String tagName) {
    for (final interest in interests) {
      if (interest.tag == tagName) return interest;
    }
    return null;
  }

  /// Converts this person to a Dart map matching the TOML schema,
  /// suitable for TomlDocument.fromMap(...).toString().
  Map<String, dynamic> toTomlMap() {
    return {
      'id': id,
      'name': name,
      'platforms': platforms,
      'notes': notes,
      'interests': interests.map((i) => i.toTomlMap()).toList(),
    };
  }

  String toTomlString() {
    return TomlDocument.fromMap(toTomlMap()).toString();
  }

  factory Person.fromTomlMap(Map<String, dynamic> map) {
    final rawInterests = (map['interests'] as List?) ?? const [];
    return Person(
      id: map['id'] as String,
      name: map['name'] as String,
      platforms: ((map['platforms'] as List?) ?? const [])
          .map((p) => p as String)
          .toList(),
      notes: (map['notes'] as String?) ?? '',
      interests: rawInterests
          .map((i) => InterestTag.fromTomlMap(i as Map<String, dynamic>))
          .toList(),
    );
  }

  static Person fromTomlString(String tomlContent) {
    final map = TomlDocument.parse(tomlContent).toMap();
    return Person.fromTomlMap(map);
  }
}
