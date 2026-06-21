/// Converts a display name into a filesystem- and TOML-safe slug:
/// lowercase, hyphen-separated, alphanumeric only.
///
/// Examples:
///   "Alice Chen"      -> "alice-chen"
///   "Board Game Night" -> "board-game-night"
///   "Bob O'Reilly"     -> "bob-oreilly"
String slugify(String input) {
  final lower = input.trim().toLowerCase();
  final withHyphens = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final trimmed = withHyphens.replaceAll(RegExp(r'^-+|-+$'), '');
  final collapsed = trimmed.replaceAll(RegExp(r'-+'), '-');
  return collapsed.isEmpty ? 'untitled' : collapsed;
}

/// Given a base slug and a set of slugs already in use, returns a unique
/// slug by appending -2, -3, etc. if needed. Used when two people/events/
/// groups would otherwise generate the same slug (e.g. two "Alice Chen"s).
String uniqueSlug(String baseSlug, Set<String> existingSlugs) {
  if (!existingSlugs.contains(baseSlug)) return baseSlug;
  var counter = 2;
  while (existingSlugs.contains('$baseSlug-$counter')) {
    counter++;
  }
  return '$baseSlug-$counter';
}
