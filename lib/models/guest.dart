import 'enums.dart';
import 'simple_date.dart';
import 'toml_codec.dart';

/// A single guest's RSVP record within one event.
/// Lives inside an Event's `guests` list — not a standalone file.
class Guest {
  final String personId;
  final RsvpStatus rsvp;
  final String declinedReason;
  final InviteMethod invitedVia;
  final String platform;
  final int followUpCount;

  /// Date of last follow-up attempt, or null if never followed up.
  final SimpleDate? lastFollowUp;
  final String notes;

  const Guest({
    required this.personId,
    required this.rsvp,
    this.declinedReason = '',
    required this.invitedVia,
    this.platform = '',
    this.followUpCount = 0,
    this.lastFollowUp,
    this.notes = '',
  });

  Guest copyWith({
    String? personId,
    RsvpStatus? rsvp,
    String? declinedReason,
    InviteMethod? invitedVia,
    String? platform,
    int? followUpCount,
    SimpleDate? lastFollowUp,
    bool clearLastFollowUp = false,
    String? notes,
  }) {
    return Guest(
      personId: personId ?? this.personId,
      rsvp: rsvp ?? this.rsvp,
      declinedReason: declinedReason ?? this.declinedReason,
      invitedVia: invitedVia ?? this.invitedVia,
      platform: platform ?? this.platform,
      followUpCount: followUpCount ?? this.followUpCount,
      lastFollowUp:
          clearLastFollowUp ? null : (lastFollowUp ?? this.lastFollowUp),
      notes: notes ?? this.notes,
    );
  }

  /// Whether this guest likely needs a follow-up, per the rules in the
  /// design doc: no_response/maybe with an upcoming event, or a soft
  /// yes/no that's never been followed up on.
  ///
  /// [eventIsUpcoming] is passed in by the caller (Event knows its own date;
  /// Guest doesn't store a reference back to its event).
  bool needsFollowUp(bool eventIsUpcoming) {
    if (!eventIsUpcoming) return false;
    if (rsvp == RsvpStatus.noResponse || rsvp == RsvpStatus.maybe) {
      return true;
    }
    if ((rsvp == RsvpStatus.softYes || rsvp == RsvpStatus.softNo) &&
        followUpCount == 0) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> toTomlMap() {
    return {
      'person_id': personId,
      'rsvp': rsvp.tomlValue,
      'declined_reason': declinedReason,
      'invited_via': invitedVia.tomlValue,
      'platform': platform,
      'follow_up_count': followUpCount,
      if (lastFollowUp != null)
        'last_follow_up': lastFollowUp!.toTomlLocalDate(),
      'notes': notes,
    };
  }

  factory Guest.fromTomlMap(Map<String, dynamic> map) {
    return Guest(
      personId: map['person_id'] as String,
      rsvp: RsvpStatus.fromToml(map['rsvp'] as String),
      declinedReason: (map['declined_reason'] as String?) ?? '',
      invitedVia: InviteMethod.fromToml(map['invited_via'] as String),
      platform: (map['platform'] as String?) ?? '',
      followUpCount: (map['follow_up_count'] as int?) ?? 0,
      lastFollowUp: readSimpleDate(map, 'last_follow_up', optional: true),
      notes: (map['notes'] as String?) ?? '',
    );
  }
}
