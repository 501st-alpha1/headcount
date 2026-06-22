import 'package:toml/toml.dart';

import 'simple_date.dart';

/// Conversions between this app's SimpleDate and the toml package's native
/// local-date type. Kept in one place so model classes don't need to import
/// package:toml just to handle dates — they only deal with SimpleDate.
///
/// Note: TomlFullDate's constructor signature is assumed (positional
/// year/month/day) — I couldn't introspect the package source to confirm
/// it. If verify_models.dart throws here, check
/// ~/.pub-cache/hosted/pub.dev/toml-<version>/lib/src/ast/value/date_time.dart
/// for the real signature.
extension SimpleDateTomlCodec on SimpleDate {
  /// Converts to a TomlLocalDate for use as a value in a map passed to
  /// TomlDocument.fromMap. Encoding a bare TomlLocalDate (rather than a
  /// Dart DateTime) is what makes the encoder emit a clean `2026-08-15`
  /// with no time component and no timezone offset.
  TomlLocalDate toTomlLocalDate() {
    return TomlLocalDate(TomlFullDate(year, month, day));
  }
}

/// Reads a SimpleDate out of a map produced by TomlDocument.toMap(), where
/// the decoder will have produced a TomlLocalDate (since that's what we
/// always write). Throws if the value at [key] is missing or not a date,
/// unless [optional] is true, in which case a missing key returns null.
SimpleDate? readSimpleDate(
  Map<String, dynamic> map,
  String key, {
  bool optional = false,
}) {
  final raw = map[key];
  if (raw == null) {
    if (optional) return null;
    throw FormatException('Missing required date field "$key"');
  }
  if (raw is TomlLocalDate) {
    final d = raw.date;
    return SimpleDate(year: d.year, month: d.month, day: d.day);
  }
  // Defensive: if a file was hand-edited with an offset date-time instead
  // of a bare local date, still salvage the calendar date rather than
  // throwing, since the day-portion is all this app cares about.
  if (raw is TomlOffsetDateTime) {
    final d = raw.date;
    return SimpleDate(year: d.year, month: d.month, day: d.day);
  }
  throw FormatException(
    'Field "$key" is not a TOML date (got ${raw.runtimeType}). '
    'If hand-editing the file, use a bare date like 2026-08-15 '
    '(no time, no quotes).',
  );
}
