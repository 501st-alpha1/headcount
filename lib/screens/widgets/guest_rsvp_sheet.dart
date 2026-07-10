import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/guest.dart';
import '../../models/person.dart';
import '../../models/simple_date.dart';

/// Bottom sheet for editing one guest's RSVP record on an event: status,
/// invite method/platform, follow-up count, last follow-up date, and
/// per-event notes. Pure UI — knows nothing about the repository or
/// providers. The caller (EventDetailScreen) is responsible for
/// persisting the result.
///
/// Returns the updated Guest via [onSave], or null is never passed —
/// dismissing without saving just closes the sheet with no callback.
Future<void> showGuestRsvpSheet({
  required BuildContext context,
  required Guest guest,
  required Person person,
  required void Function(Guest updated) onSave,
  required void Function() onRemoveFromEvent,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _GuestRsvpSheetContent(
      initialGuest: guest,
      person: person,
      onSave: onSave,
      onRemoveFromEvent: onRemoveFromEvent,
    ),
  );
}

class _GuestRsvpSheetContent extends StatefulWidget {
  final Guest initialGuest;
  final Person person;
  final void Function(Guest updated) onSave;
  final void Function() onRemoveFromEvent;

  const _GuestRsvpSheetContent({
    required this.initialGuest,
    required this.person,
    required this.onSave,
    required this.onRemoveFromEvent,
  });

  @override
  State<_GuestRsvpSheetContent> createState() =>
      _GuestRsvpSheetContentState();
}

class _GuestRsvpSheetContentState extends State<_GuestRsvpSheetContent> {
  late RsvpStatus _rsvp;
  late InviteMethod _invitedVia;
  late TextEditingController _platformController;
  late TextEditingController _declinedReasonController;
  late TextEditingController _notesController;
  late int _followUpCount;
  late SimpleDate? _lastFollowUp;
  late bool _followUpSuppressed;

  @override
  void initState() {
    super.initState();
    final g = widget.initialGuest;
    _rsvp = g.rsvp;
    _invitedVia = g.invitedVia;
    _platformController = TextEditingController(text: g.platform);
    _declinedReasonController = TextEditingController(text: g.declinedReason);
    _notesController = TextEditingController(text: g.notes);
    _followUpCount = g.followUpCount;
    _lastFollowUp = g.lastFollowUp;
    _followUpSuppressed = g.followUpSuppressed;
  }

  @override
  void dispose() {
    _platformController.dispose();
    _declinedReasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Guest _buildUpdatedGuest() {
    return widget.initialGuest.copyWith(
      rsvp: _rsvp,
      invitedVia: _invitedVia,
      platform: _platformController.text.trim(),
      declinedReason: _declinedReasonController.text.trim(),
      notes: _notesController.text.trim(),
      followUpCount: _followUpCount,
      lastFollowUp: _lastFollowUp,
      clearLastFollowUp: _lastFollowUp == null,
      followUpSuppressed: _followUpSuppressed,
    );
  }

  void _save() {
    widget.onSave(_buildUpdatedGuest());
    Navigator.of(context).pop();
  }

  void _incrementFollowUp() {
    setState(() {
      _followUpCount += 1;
      _lastFollowUp = SimpleDate.today();
      // Logging a follow-up is an active choice to engage — clear
      // suppression so the person surfaces again after the cooldown.
      _followUpSuppressed = false;
    });
  }

  void _onRsvpChanged(RsvpStatus status) {
    setState(() {
      _rsvp = status;
      // Auto-lift suppression when status changes to something unresolved,
      // mirroring the copyWith behavior in Guest itself so the UI stays
      // consistent with what will be saved.
      const unresolved = {
        RsvpStatus.toInvite,
        RsvpStatus.noResponse,
        RsvpStatus.maybe,
        RsvpStatus.probably,
        RsvpStatus.probablyNot,
      };
      if (unresolved.contains(status) && status != widget.initialGuest.rsvp) {
        _followUpSuppressed = false;
      }
    });
  }

  void _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove guest?'),
        content: Text(
          'Remove ${widget.person.name} from this event\'s guest list? '
          'This only affects this event — ${widget.person.name} stays in '
          'your people list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      widget.onRemoveFromEvent();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.person.name,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'View person',
                  onPressed: () {
                    // Navigation to PersonDetailScreen is wired up once
                    // that screen exists; left as a no-op stub for now.
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text('RSVP', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: RsvpStatus.values.map((status) {
                return ChoiceChip(
                  label: Text(status.label),
                  selected: _rsvp == status,
                  onSelected: (_) => _onRsvpChanged(status),
                );
              }).toList(),
            ),

            if (_rsvp == RsvpStatus.no) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _declinedReasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],

            const SizedBox(height: 20),
            Text('Invited via', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: InviteMethod.values.map((method) {
                return ChoiceChip(
                  label: Text(method.label),
                  selected: _invitedVia == method,
                  onSelected: (_) => setState(() => _invitedVia = method),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _platformController,
              decoration: const InputDecoration(
                labelText: 'Platform (e.g. Signal, iMessage)',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),
            Text('Follow-up', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _followUpCount == 0
                      ? 'No follow-ups yet'
                      : '$_followUpCount follow-up${_followUpCount == 1 ? '' : 's'}'
                          '${_lastFollowUp != null ? ' · last ${_lastFollowUp!.toIsoString()}' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _incrementFollowUp,
                  icon: const Icon(Icons.add),
                  label: const Text('Log follow-up'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Follow-up not required'),
              subtitle: const Text(
                'Exclude from the follow-up list regardless of status.',
              ),
              value: _followUpSuppressed,
              onChanged: (value) => setState(() => _followUpSuppressed = value),
            ),

            const SizedBox(height: 20),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes for this event',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _confirmRemove,
                  icon: Icon(
                    Icons.person_remove_outlined,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Remove from event',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
