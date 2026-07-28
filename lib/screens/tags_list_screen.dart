import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tag.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';
import 'tag_editor_screen.dart';

/// All tags, with their level count. Root tags are listed alphabetically;
/// their dependents appear immediately below them, indented, so the
/// hierarchy is clear at a glance:
///
///   Hiking
///     ↳ Travel distance
///     ↳ Trail difficulty
///   Board Games
class TagsListScreen extends ConsumerWidget {
  const TagsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _buildBody(context, value),
        AsyncError(:final error) =>
          Center(child: Text('Could not load your data: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TagEditorScreen()),
          );
        },
        tooltip: 'New tag',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DataSnapshot snapshot) {
    final tags = snapshot.allTagsInUse;

    if (tags.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.interests_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('No tags yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Tags are usually created from the Person Editor, but you '
                'can also create one here.',
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

    // Build a flat ordered list: each root tag followed immediately by its
    // dependents (alphabetically), then the next root tag, etc.
    // Any orphaned dependents (parent not in snapshot) appear at the end.
    final items = <(Tag, bool)>[]; // (tag, isDependent)
    for (final root in snapshot.rootTags) {
      items.add((root, false));
      for (final dep in snapshot.dependentsOf(root.id)) {
        items.add((dep, true));
      }
    }
    final listedIds = items.map((i) => i.$1.id).toSet();
    for (final tag in tags) {
      if (!listedIds.contains(tag.id)) items.add((tag, false));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (tag, isDependent) = items[index];
        return ListTile(
          contentPadding: EdgeInsets.only(
            left: isDependent ? 32.0 : 16.0,
            right: 16.0,
          ),
          leading: isDependent
              ? Icon(
                  Icons.subdirectory_arrow_right,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              : null,
          title: Text(tag.name),
          subtitle: Text(
            tag.levels.isEmpty
                ? 'No levels defined'
                : tag.levels.join(' → '),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TagEditorScreen(tagId: tag.id),
              ),
            );
          },
        );
      },
    );
  }
}
