/// RSVP status for a guest on a specific event.
enum RsvpStatus {
  yes,
  softYes,
  maybe,
  softNo,
  no,
  declined,
  noResponse;

  /// The string used in TOML files. Kept stable even if enum names change.
  String get tomlValue => switch (this) {
        RsvpStatus.yes => 'yes',
        RsvpStatus.softYes => 'soft_yes',
        RsvpStatus.maybe => 'maybe',
        RsvpStatus.softNo => 'soft_no',
        RsvpStatus.no => 'no',
        RsvpStatus.declined => 'declined',
        RsvpStatus.noResponse => 'no_response',
      };

  static RsvpStatus fromToml(String value) {
    return switch (value) {
      'yes' => RsvpStatus.yes,
      'soft_yes' => RsvpStatus.softYes,
      'maybe' => RsvpStatus.maybe,
      'soft_no' => RsvpStatus.softNo,
      'no' => RsvpStatus.no,
      'declined' => RsvpStatus.declined,
      'no_response' => RsvpStatus.noResponse,
      _ => throw FormatException('Unknown RSVP status: $value'),
    };
  }

  /// Human-readable label for UI display.
  String get label => switch (this) {
        RsvpStatus.yes => 'Yes',
        RsvpStatus.softYes => 'Soft yes',
        RsvpStatus.maybe => 'Maybe',
        RsvpStatus.softNo => 'Soft no',
        RsvpStatus.no => 'No',
        RsvpStatus.declined => 'Declined',
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

/// How interested a person is in a given tagged activity/topic.
enum InterestLevel {
  lovesIt,
  easyOnly,
  needsConvincing,
  notInterested;

  String get tomlValue => switch (this) {
        InterestLevel.lovesIt => 'loves_it',
        InterestLevel.easyOnly => 'easy_only',
        InterestLevel.needsConvincing => 'needs_convincing',
        InterestLevel.notInterested => 'not_interested',
      };

  static InterestLevel fromToml(String value) {
    return switch (value) {
      'loves_it' => InterestLevel.lovesIt,
      'easy_only' => InterestLevel.easyOnly,
      'needs_convincing' => InterestLevel.needsConvincing,
      'not_interested' => InterestLevel.notInterested,
      _ => throw FormatException('Unknown interest level: $value'),
    };
  }

  String get label => switch (this) {
        InterestLevel.lovesIt => 'Loves it',
        InterestLevel.easyOnly => 'Easy only',
        InterestLevel.needsConvincing => 'Needs convincing',
        InterestLevel.notInterested => 'Not interested',
      };

  /// Sort order for the Interest Browser: enthusiastic people first,
  /// not-interested people last (and hidden by default in the UI).
  int get sortRank => switch (this) {
        InterestLevel.lovesIt => 0,
        InterestLevel.easyOnly => 1,
        InterestLevel.needsConvincing => 2,
        InterestLevel.notInterested => 3,
      };
}
