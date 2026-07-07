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

  /// Date of last contact — either the initial invite or an explicit
  /// logged follow-up, whichever is most recent. Null means never
  /// contacted at all (shouldn't normally happen in practice, since
  /// adding a guest sets this immediately, but old hand-edited files
  /// or pre-migration data may lack it).
  final SimpleDate? lastFollowUp;
  final String notes;

  /// Days that must pass since [lastFollowUp] before a guest in an
  /// unresolved RSVP state is considered due for another follow-up.
  /// Prevents "needs follow-up" from firing again the moment you've
  /// just invited or followed up with someone. Not yet user-configurable
  /// — see needsFollowUp's doc comment.
  static const int followUpCooldownDays = 5;

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

  /// Whether this guest is currently due for a follow-up: the event is
  /// upcoming, their RSVP is still unresolved or pre-invite, and at
  /// least [followUpCooldownDays] have passed since they were last
  /// contacted (or they've never been contacted at all). toInvite always
  /// returns true when the event is upcoming — you haven't reached out
  /// yet, so there's nothing to cool down on.
  bool needsFollowUp(bool eventIsUpcoming, {SimpleDate? today}) {
    if (!eventIsUpcoming) return false;

    final isUnresolved = rsvp == RsvpStatus.toInvite ||
        rsvp == RsvpStatus.noResponse ||
        rsvp == RsvpStatus.maybe ||
        rsvp == RsvpStatus.probably ||
        rsvp == RsvpStatus.probablyNot;
    if (!isUnresolved) return false;

    // toInvite means never contacted — always needs follow-up.
    if (lastFollowUp == null) return true;

    final effectiveToday = today ?? SimpleDate.today();
    final daysSinceContact = lastFollowUp!.daysUntil(effectiveToday);
    return daysSinceContact >= followUpCooldownDays;
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
