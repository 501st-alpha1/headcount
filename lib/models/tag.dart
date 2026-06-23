import 'package:toml/toml.dart';

/// A named interest tag (e.g. "Hiking") together with the set of levels
/// people can be rated at for it. Levels are per-tag, not a fixed global
/// enum — "easy only" makes sense for hiking but not for board games, so
/// each tag defines its own vocabulary. Stored at tags/<id>.toml.
///
/// [levels] is ordered: index 0 is the most enthusiastic, last is the
/// least. This ordering drives sort order in the Interest Browser and
/// anywhere else levels are grouped/displayed. There's no separate
/// "sortRank" field — position in the list IS the rank, which also means
/// reordering levels in the editor is just reordering this list.
class Tag {
  final String id;
  final String name;
  final List<String> levels;

  const Tag({
    required this.id,
    required this.name,
    this.levels = const [],
  });

  Tag copyWith({
    String? id,
    String? name,
    List<String>? levels,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      levels: levels ?? this.levels,
    );
  }

  /// The default level set seeded for tags created automatically during
  /// migration from the old global InterestLevel enum, or for brand-new
  /// tags created via the "+ New" chip (which don't get a chance to
  /// define custom levels up front — they start here and can be edited
  /// later via the Tag Editor).
  ///
  /// These match the old InterestLevel enum's exact string values
  /// (snake_case, e.g. "loves_it") rather than a nicer display form like
  /// "Loves it" — that's deliberate: existing Person files already have
  /// `level = "loves_it"` written on disk, and migration needs those
  /// strings to match a level in the newly-created tag's `levels` list
  /// exactly, or they'd show up as an orphaned/unrecognized level the
  /// moment this ships. A future "rename this level" action in the Tag
  /// Editor is the right place to prettify these, since renames already
  /// cascade to every person using them.
  static const List<String> defaultLevels = [
    'loves_it',
    'easy_only',
    'needs_convincing',
    'not_interested',
  ];

  Map<String, dynamic> toTomlMap() {
    return {
      'id': id,
      'name': name,
      'levels': levels,
    };
  }

  String toTomlString() {
    return TomlDocument.fromMap(toTomlMap()).toString();
  }

  factory Tag.fromTomlMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as String,
      name: map['name'] as String,
      levels: ((map['levels'] as List?) ?? const [])
          .map((l) => l as String)
          .toList(),
    );
  }

  static Tag fromTomlString(String tomlContent) {
    final map = TomlDocument.parse(tomlContent).toMap();
    return Tag.fromTomlMap(map);
  }
}
