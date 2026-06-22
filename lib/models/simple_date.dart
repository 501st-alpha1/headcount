/// A calendar date with no time-of-day and no timezone — just year, month,
/// day. Used everywhere this app means "a date" (event date, last follow-up
/// date), since a plain Dart DateTime always carries an implicit time and
/// timezone that don't belong in this domain and cause real bugs: the same
/// "date" could shift to a different calendar day depending on what
/// timezone the app happens to run in.
///
/// This type's only job is to round-trip cleanly through TOML's native
/// "local date" type (e.g. `2026-08-15`, no time, no offset). Conversion
/// to/from the toml package's TomlLocalDate happens at the serialization
/// boundary in toml_codec.dart — model classes never import the toml
/// package directly for this.
class SimpleDate implements Comparable<SimpleDate> {
  final int year;
  final int month;
  final int day;

  const SimpleDate({required this.year, required this.month, required this.day});

  /// Today's date, in the device's local calendar.
  factory SimpleDate.today() {
    final now = DateTime.now();
    return SimpleDate(year: now.year, month: now.month, day: now.day);
  }

  /// Parses a strict "YYYY-MM-DD" string. Throws FormatException otherwise.
  factory SimpleDate.parse(String input) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(input);
    if (match == null) {
      throw FormatException('Expected YYYY-MM-DD, got "$input"');
    }
    return SimpleDate(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
    );
  }

  /// "YYYY-MM-DD", zero-padded. Matches the TOML local-date wire format and
  /// is also what's used for filename date prefixes.
  String toIsoString() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }

  bool isBefore(SimpleDate other) => compareTo(other) < 0;
  bool isAfter(SimpleDate other) => compareTo(other) > 0;

  @override
  int compareTo(SimpleDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is SimpleDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIsoString();
}
