import 'package:flutter/material.dart';

import '../../repository/load_result.dart';

/// A banner warning that some data files couldn't be read. Shown at the
/// top of the home screen (and anywhere else that watches
/// dataSnapshotProvider) whenever DataSnapshot.hasIssues is true — e.g.
/// a hand-edited TOML file with a syntax error. Tapping it expands to
/// show exactly which files and why, so a bad edit is never silently
/// invisible.
class LoadIssuesBanner extends StatefulWidget {
  final List<LoadIssue> issues;

  const LoadIssuesBanner({super.key, required this.issues});

  @override
  State<LoadIssuesBanner> createState() => _LoadIssuesBannerState();
}

class _LoadIssuesBannerState extends State<LoadIssuesBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.issues.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final count = widget.issues.length;

    return Material(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    color: theme.colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      count == 1
                          ? '1 file could not be read'
                          : '$count files could not be read',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                for (final issue in widget.issues)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${issue.relativePath}\n${issue.message}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Fix the file\'s TOML syntax and restart the app, or '
                  'remove it if it was a test.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
