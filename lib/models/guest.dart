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

  /// When true, this guest is manually excluded from the needs-follow-up
  /// list regardless of their status or cooldown. Useful when you know
  /// someone is unlikely to come but doesn't warrant a firm no, or when
  /// you've had an informal conversation and don't need to chase further.
  ///
  /// Suppression auto-lifts when [rsvp] changes to an unresolved status
  /// — see copyWith. This means suppression means "given their *current*
  /// status, I've decided not to chase," not a permanent mark.
  final bool followUpSuppressed;

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
    this.followUpSuppressed = false,
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
    bool? followUpSuppressed,
  }) {
    final newRsvp = rsvp ?? this.rsvp;

    // Auto-lift suppression when the status changes to something that
    // would normally need follow-up — suppression was a judgment call
    // about the old status, not a blanket decision about this person.
    final unresolved = {
      RsvpStatus.toInvite,
      RsvpStatus.noResponse,
      RsvpStatus.maybe,
      RsvpStatus.probably,
      RsvpStatus.probablyNot,
    };
    final suppressionLifted = rsvp != null &&
        rsvp != this.rsvp &&
        unresolved.contains(newRsvp);

    return Guest(
      personId: personId ?? this.personId,
      rsvp: newRsvp,
      declinedReason: declinedReason ?? this.declinedReason,
      invitedVia: invitedVia ?? this.invitedVia,
      platform: platform ?? this.platform,
      followUpCount: followUpCount ?? this.followUpCount,
      lastFollowUp:
          clearLastFollowUp ? null : (lastFollowUp ?? this.lastFollowUp),
      notes: notes ?? this.notes,
      followUpSuppressed: suppressionLifted
          ? false
          : (followUpSuppressed ?? this.followUpSuppressed),
    );
  }

  /// Whether this guest is currently due for a follow-up. Returns false
  /// immediately if [followUpSuppressed] is true — that's a manual
  /// override that takes priority over all other logic. Otherwise:
  /// the event must be upcoming, the status must be unresolved, and
  /// enough time must have passed since last contact (or there's been
  /// no contact at all).
  bool needsFollowUp(bool eventIsUpcoming, {SimpleDate? today}) {
    if (!eventIsUpcoming) return false;
    if (followUpSuppressed) return false;

    final isUnresolved = rsvp == RsvpStatus.toInvite ||
        rsvp == RsvpStatus.noResponse ||
        rsvp == RsvpStatus.maybe ||
        rsvp == RsvpStatus.probably ||
        rsvp == RsvpStatus.probablyNot;
    if (!isUnresolved) return false;

    // toInvite means never contacted — always needs follow-up
    // (unless suppressed, which is handled above).
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
      // Only write the field when true — omitting it (false by default)
      // keeps existing files clean and uncluttered.
      if (followUpSuppressed) 'follow_up_suppressed': true,
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
      // Missing key = false (backward compat with existing files).
      followUpSuppressed:
          (map['follow_up_suppressed'] as bool?) ?? false,
    );
  }
}
