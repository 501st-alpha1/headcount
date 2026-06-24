import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../providers/data_providers.dart';
import 'group_editor_screen.dart';

/// All groups, alphabetically sorted, with member counts. Tap to edit a
/// group's name, notes, and membership via GroupEditorScreen.
class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _buildBody(context, value.groups),
        AsyncError(:final error) =>
          Center(child: Text('Could not load your data: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GroupEditorScreen()),
          );
        },
        tooltip: 'New group',
        child: const Icon(Icons.group_add_outlined),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<Group> groups) {
    if (groups.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('No groups yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Groups are a fast way to invite several people to an '
                'event at once. Tap + to create one.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final sorted = [...groups]..sort((a, b) => a.name.compareTo(b.name));

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final group = sorted[index];
        return ListTile(
          title: Text(group.name),
          subtitle: Text(
            '${group.memberIds.length} '
            '${group.memberIds.length == 1 ? 'member' : 'members'}',
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupEditorScreen(groupId: group.id),
              ),
            );
          },
        );
      },
    );
  }
}
