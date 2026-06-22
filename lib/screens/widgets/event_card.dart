import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/event.dart';

/// A tappable card summarizing one event: name, date, and an at-a-glance
/// RSVP breakdown (e.g. "5 yes · 2 no response"). Used on both the home
/// screen and the archive screen.
class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  const EventCard({super.key, required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final followUpCount = event.guestsNeedingFollowUp.length;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      event.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (followUpCount > 0) ...[
                    const SizedBox(width: 8),
                    _FollowUpBadge(count: followUpCount),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(event.date.year, event.date.month, event.date.day),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _RsvpSummaryLine(event: event),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowUpBadge extends StatelessWidget {
  final int count;

  const _FollowUpBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count to follow up',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _RsvpSummaryLine extends StatelessWidget {
  final Event event;

  const _RsvpSummaryLine({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = event.rsvpCounts;

    if (counts.isEmpty) {
      return Text(
        'No guests yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final parts = counts.entries
        .map((entry) => '${entry.value} ${entry.key.label.toLowerCase()}')
        .join(' · ');

    return Text(
      parts,
      style: theme.textTheme.bodySmall,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Formats a date as e.g. "Sat, Aug 15, 2026" without pulling in intl just
/// for this — a small fixed lookup table is simpler and has no locale
/// surprises for a personal-use app.
String _formatDate(int year, int month, int day) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final weekdayIndex = DateTime(year, month, day).weekday - 1;
  return '${weekdays[weekdayIndex]}, ${months[month - 1]} $day, $year';
}
