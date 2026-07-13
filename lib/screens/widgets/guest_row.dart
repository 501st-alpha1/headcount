import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/guest.dart';
import '../../models/person.dart';

/// The statuses where last-contact info is meaningful to show inline —
/// resolved statuses (yes/no) don't need it since there's nothing to chase.
const _unresolvedStatuses = {
  RsvpStatus.toInvite,
  RsvpStatus.noResponse,
  RsvpStatus.maybe,
  RsvpStatus.probably,
  RsvpStatus.probablyNot,
};

/// One row in the event detail screen's guest list: name, RSVP status
/// chip, platform, last contact info (for unresolved statuses), and a
/// follow-up indicator when relevant. Tapping the row is handled by the
/// caller (opens the RSVP sheet).
class GuestRow extends StatelessWidget {
  final Guest guest;
  final Person person;
  final bool needsFollowUp;
  final VoidCallback onTap;

  const GuestRow({
    super.key,
    required this.guest,
    required this.person,
    required this.needsFollowUp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _buildSubtitle();

    return ListTile(
      onTap: onTap,
      title: Text(person.name),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (needsFollowUp) ...[
            Icon(
              Icons.notifications_outlined,
              size: 18,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
          ] else if (guest.followUpSuppressed) ...[
            // Suppressed — muted icon to show this person is intentionally
            // excluded from the follow-up list without drawing attention.
            Icon(
              Icons.notifications_off_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
          ],
          _RsvpChip(status: guest.rsvp),
        ],
      ),
    );
  }

  String? _buildSubtitle() {
    final parts = <String>[];

    if (guest.platform.isNotEmpty) {
      parts.add('${guest.invitedVia.label} · ${guest.platform}');
    }

    // Show last contact info only for unresolved statuses where it's
    // actually meaningful — no point showing "last contacted Jun 10" for
    // someone who's already confirmed yes or no.
    if (_unresolvedStatuses.contains(guest.rsvp)) {
      if (guest.lastFollowUp == null) {
        parts.add('never contacted');
      } else {
        parts.add('last ${guest.lastFollowUp!.toIsoString()}');
      }
    }

    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _RsvpChip extends StatelessWidget {
  final RsvpStatus status;

  const _RsvpChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = _colorsFor(status, theme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }

  (Color, Color) _colorsFor(RsvpStatus status, ThemeData theme) {
    final scheme = theme.colorScheme;
    return switch (status) {
      // toInvite: tertiary container — distinct from the noResponse gray,
      // signals "action needed" without the urgency of error red.
      RsvpStatus.toInvite => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      RsvpStatus.yes => (scheme.primaryContainer, scheme.onPrimaryContainer),
      RsvpStatus.probably => (
          scheme.primaryContainer.withValues(alpha: 0.5),
          scheme.onPrimaryContainer,
        ),
      RsvpStatus.maybe => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      RsvpStatus.probablyNot => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      RsvpStatus.no => (scheme.errorContainer, scheme.onErrorContainer),
      RsvpStatus.noResponse => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };
  }
}
