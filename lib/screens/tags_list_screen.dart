import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tag.dart';
import '../providers/data_providers.dart';
import 'tag_editor_screen.dart';

/// All tags, with their level count, alphabetically sorted. Tap to edit
/// a tag's name and levels via TagEditorScreen. Tags are mostly created
/// implicitly (via the "+ New" chip in the Person Editor, or
/// auto-migration of pre-existing free-string tags — see
/// Repository.loadAll), but this screen is where you go to actually
/// shape a tag's level vocabulary once it exists.
class TagsListScreen extends ConsumerWidget {
  const TagsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: switch (snapshotAsync) {
        AsyncData(:final value) => _buildBody(context, value.allTagsInUse),
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

  Widget _buildBody(BuildContext context, List<Tag> tags) {
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

    return ListView.builder(
      itemCount: tags.length,
      itemBuilder: (context, index) {
        final tag = tags[index];
        return ListTile(
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
