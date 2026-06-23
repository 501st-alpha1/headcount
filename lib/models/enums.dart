/// RSVP status for a guest on a specific event.
enum RsvpStatus {
  yes,
  probably,
  maybe,
  probablyNot,
  no,
  noResponse;

  /// The string used in TOML files. Kept stable even if enum names change.
  String get tomlValue => switch (this) {
        RsvpStatus.yes => 'yes',
        RsvpStatus.probably => 'probably',
        RsvpStatus.maybe => 'maybe',
        RsvpStatus.probablyNot => 'probably_not',
        RsvpStatus.no => 'no',
        RsvpStatus.noResponse => 'no_response',
      };

  static RsvpStatus fromToml(String value) {
    return switch (value) {
      'yes' => RsvpStatus.yes,
      'probably' => RsvpStatus.probably,
      'maybe' => RsvpStatus.maybe,
      'probably_not' => RsvpStatus.probablyNot,
      'no' => RsvpStatus.no,
      'no_response' => RsvpStatus.noResponse,
      // Backward compatibility with files written before this status set
      // changed: "soft_yes"/"soft_no" were renamed, and "declined" was
      // merged into "no" (declined_reason still applies — see Guest).
      'soft_yes' => RsvpStatus.probably,
      'soft_no' => RsvpStatus.probablyNot,
      'declined' => RsvpStatus.no,
      _ => throw FormatException('Unknown RSVP status: $value'),
    };
  }

  /// Human-readable label for UI display.
  String get label => switch (this) {
        RsvpStatus.yes => 'Yes',
        RsvpStatus.probably => 'Probably',
        RsvpStatus.maybe => 'Maybe',
        RsvpStatus.probablyNot => 'Probably not',
        RsvpStatus.no => 'No',
        RsvpStatus.noResponse => 'No response',
      };
}

/// How a guest was invited to an event.
enum InviteMethod {
  dm,
  groupMessage,
  inPerson,
  email;

  String get tomlValue => switch (this) {
        InviteMethod.dm => 'dm',
        InviteMethod.groupMessage => 'group_message',
        InviteMethod.inPerson => 'in_person',
        InviteMethod.email => 'email',
      };

  static InviteMethod fromToml(String value) {
    return switch (value) {
      'dm' => InviteMethod.dm,
      'group_message' => InviteMethod.groupMessage,
      'in_person' => InviteMethod.inPerson,
      'email' => InviteMethod.email,
      _ => throw FormatException('Unknown invite method: $value'),
    };
  }

  String get label => switch (this) {
        InviteMethod.dm => 'DM',
        InviteMethod.groupMessage => 'Group message',
        InviteMethod.inPerson => 'In person',
        InviteMethod.email => 'Email',
      };
}
