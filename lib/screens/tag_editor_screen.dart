import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/person.dart';
import '../models/tag.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';

/// Create-or-edit form for a Tag: its display name, and its ordered list
/// of levels. When [tagId] is null this creates a new tag (seeded with
/// Tag.defaultLevels, since a brand-new tag with zero levels isn't
/// useful); when supplied, it edits the existing one.
///
/// Level changes are NOT staged-then-saved like the rest of this form —
/// renaming or deleting a level immediately calls through to
/// Repository.renameTagLevel / deleteTagLevel, since those need to
/// cascade to every person using the tag, and doing that as a batched
/// diff against some "original level list" would be a lot more complex
/// for no real benefit here. The name field and adding brand-new levels
/// (which by definition nothing references yet) still batch into one
/// Save, like other editors in this app.
class TagEditorScreen extends ConsumerStatefulWidget {
  final String? tagId;

  const TagEditorScreen({super.key, this.tagId});

  bool get isEditing => tagId != null;

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  late TextEditingController _nameController;
  List<String> _levels = [];
  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    if (!widget.isEditing) {
      _levels = [...Tag.defaultLevels];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _initializeFrom(Tag tag) {
    if (_isInitialized) return;
    _nameController.text = tag.name;
    _levels = [...tag.levels];
    _isInitialized = true;
  }

  Future<void> _saveNameAndNewLevels(Tag? existing) async {
    setState(() => _isSaving = true);
    final repository = ref.read(repositoryProvider);

    try {
      if (widget.isEditing) {
        if (existing == null) {
          throw StateError('Tag ${widget.tagId} no longer exists.');
        }
        // Level renames/deletes already happened immediately (see
        // _renameLevel/_deleteLevel below) and are reflected on disk.
        // This save only needs to carry forward the name and any
        // brand-new levels appended since — re-read the latest levels
        // from disk first so we don't clobber a rename that happened
        // moments ago with this screen's possibly-stale _levels list.
        final latest = await repository.tags.load(existing.id) ?? existing;
        final newlyAdded = _levels.where((l) => !latest.levels.contains(l));
        final updated = latest.copyWith(
          name: _nameController.text.trim(),
          levels: [...latest.levels, ...newlyAdded],
        );
        await repository.saveTag(updated);
      } else {
        await repository.tags.create(
          name: _nameController.text.trim(),
          levels: _levels,
        );
      }
      await ref.read(dataSnapshotProvider.notifier).reload();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addLevel(BuildContext context) async {
    final name = await _promptForText(
      context,
      title: 'New level',
      hintText: 'e.g. Easy only',
    );
    if (name != null && name.isNotEmpty && !_levels.contains(name)) {
      setState(() => _levels.add(name));
    }
  }

  Future<void> _renameLevel(BuildContext context, Tag tag, String level) async {
    final newName = await _promptForText(
      context,
      title: 'Rename level',
      initialValue: level,
    );
    if (newName == null || newName.isEmpty || newName == level) return;

    final repository = ref.read(repositoryProvider);
    await repository.renameTagLevel(
      tag: tag,
      oldLevel: level,
      newLevel: newName,
    );
    await ref.read(dataSnapshotProvider.notifier).reload();
    setState(() {
      final index = _levels.indexOf(level);
      if (index != -1) _levels[index] = newName;
    });
  }

  Future<void> _deleteLevel(BuildContext context, Tag tag, String level) async {
    final repository = ref.read(repositoryProvider);
    final affected = await repository.peopleAtTagLevel(tag, level);
    final otherLevels = tag.levels.where((l) => l != level).toList();

    if (otherLevels.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Can\'t delete the only remaining level. Add another level first.',
            ),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final reassignTo = await _confirmDeleteAndPickReassignment(
      context,
      level: level,
      affected: affected,
      otherLevels: otherLevels,
    );
    if (reassignTo == null) return; // user cancelled

    await repository.deleteTagLevel(
      tag: tag,
      levelToDelete: level,
      reassignTo: reassignTo,
    );
    await ref.read(dataSnapshotProvider.notifier).reload();
    setState(() => _levels.remove(level));
  }

  /// Shows who's affected (if anyone) and, if so, asks which other level
  /// to move them to before confirming the delete. Returns the chosen
  /// reassignment level, or null if the user cancelled.
  Future<String?> _confirmDeleteAndPickReassignment(
    BuildContext context, {
    required String level,
    required List<Person> affected,
    required List<String> otherLevels,
  }) async {
    String reassignTo = otherLevels.first;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Delete "$level"?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (affected.isEmpty)
                    const Text('No one currently has this level.')
                  else ...[
                    Text(
                      '${affected.length} ${affected.length == 1 ? 'person' : 'people'} '
                      'currently at this level: '
                      '${affected.map((p) => p.name).join(', ')}.',
                    ),
                    const SizedBox(height: 12),
                    const Text('Move them to:'),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: reassignTo,
                      isExpanded: true,
                      items: [
                        for (final option in otherLevels)
                          DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => reassignTo = value);
                        }
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(reassignTo),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _promptForText(
    BuildContext context, {
    required String title,
    String? hintText,
    String? initialValue,
  }) {
    final controller = TextEditingController(text: initialValue ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hintText),
          onSubmitted: (value) =>
              Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return _buildForm(context, null);
    }

    final snapshotAsync = ref.watch(dataSnapshotProvider);
    return switch (snapshotAsync) {
      AsyncData(:final value) => _buildForm(
          context,
          value.tagById(widget.tagId!),
        ),
      AsyncError(:final error) => Scaffold(
          appBar: AppBar(title: const Text('Edit Tag')),
          body: Center(child: Text('Could not load your data: $error')),
        ),
      _ => Scaffold(
          appBar: AppBar(title: const Text('Edit Tag')),
          body: const Center(child: CircularProgressIndicator()),
        ),
    };
  }

  Widget _buildForm(BuildContext context, Tag? existing) {
    if (widget.isEditing && existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Tag')),
        body: const Center(child: Text('This tag no longer exists.')),
      );
    }
    if (existing != null) {
      _initializeFrom(existing);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Tag' : 'New Tag'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => _saveNameAndNewLevels(existing),
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Tag name',
              border: OutlineInputBorder(),
            ),
            autofocus: !widget.isEditing,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Levels', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add level',
                onPressed: () => _addLevel(context),
              ),
            ],
          ),
          Text(
            'First = most enthusiastic. Renaming or deleting a level here '
            'applies immediately and updates everyone who has it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_levels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No levels yet — add at least one.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final level in _levels)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(level),
                  trailing: widget.isEditing && existing != null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Rename',
                              onPressed: () =>
                                  _renameLevel(context, existing, level),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () =>
                                  _deleteLevel(context, existing, level),
                            ),
                          ],
                        )
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove',
                          onPressed: () =>
                              setState(() => _levels.remove(level)),
                        ),
                ),
              ),
        ],
      ),
    );
  }
}
