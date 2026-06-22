import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/data_providers.dart';

/// Temporary placeholder. Will be replaced by the real pinned-events
/// home screen in the next build step — this exists only to prove the
/// first-launch -> data-loaded routing works end-to-end.
class HomeScreenPlaceholder extends ConsumerWidget {
  const HomeScreenPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);
    final dataPath = ref.watch(dataDirectoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Headcount')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: switch (snapshotAsync) {
          AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Data directory: $dataPath'),
                const SizedBox(height: 16),
                Text('${value.people.length} people loaded'),
                Text('${value.groups.length} groups loaded'),
                Text('${value.events.length} events loaded'),
                if (value.hasIssues) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${value.issues.length} file(s) could not be read:',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  for (final issue in value.issues) Text('• $issue'),
                ],
              ],
            ),
          AsyncError(:final error) => Text('Failed to load data: $error'),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}
