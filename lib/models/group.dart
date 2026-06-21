import 'package:toml/toml.dart';

/// A named list of people you'd typically invite together
/// (e.g. "Book Club", "College Friends"). Stored at groups/<id>.toml.
///
/// Groups are a pure address-book convenience for bulk-adding guests to
/// an event. Inviting a group snapshots its current member_ids into the
/// event's guest list — there is no ongoing link after that point.
/// Editing a group later never affects events you've already invited it to.
class Group {
  final String id;
  final String name;
  final List<String> memberIds;
  final String notes;

  const Group({
    required this.id,
    required this.name,
    this.memberIds = const [],
    this.notes = '',
  });

  Group copyWith({
    String? id,
    String? name,
    List<String>? memberIds,
    String? notes,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toTomlMap() {
    return {
      'id': id,
      'name': name,
      'member_ids': memberIds,
      'notes': notes,
    };
  }

  String toTomlString() {
    return TomlDocument.fromMap(toTomlMap()).toString();
  }

  factory Group.fromTomlMap(Map<String, dynamic> map) {
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      memberIds: ((map['member_ids'] as List?) ?? const [])
          .map((m) => m as String)
          .toList(),
      notes: (map['notes'] as String?) ?? '',
    );
  }

  static Group fromTomlString(String tomlContent) {
    final map = TomlDocument.parse(tomlContent).toMap();
    return Group.fromTomlMap(map);
  }
}
