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

  /// The platform used by default when inviting this group to an event
  /// (e.g. "Signal", "Instagram"). Required — every group needs one, since
  /// inviting via a group always implies invited_via = group_message on
  /// some specific platform. See Repository.inviteGroupToEvent.
  final String defaultPlatform;

  const Group({
    required this.id,
    required this.name,
    this.memberIds = const [],
    this.notes = '',
    this.defaultPlatform = '',
  });

  Group copyWith({
    String? id,
    String? name,
    List<String>? memberIds,
    String? notes,
    String? defaultPlatform,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      notes: notes ?? this.notes,
      defaultPlatform: defaultPlatform ?? this.defaultPlatform,
    );
  }

  Map<String, dynamic> toTomlMap() {
    return {
      'id': id,
      'name': name,
      'member_ids': memberIds,
      'notes': notes,
      'default_platform': defaultPlatform,
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
      // Optional on read for backward compatibility with group files
      // written before this field existed — they'll show up with an
      // empty default platform, which the UI treats as "needs to be set"
      // rather than crashing on a missing key.
      defaultPlatform: (map['default_platform'] as String?) ?? '',
    );
  }

  static Group fromTomlString(String tomlContent) {
    final map = TomlDocument.parse(tomlContent).toMap();
    return Group.fromTomlMap(map);
  }
}
