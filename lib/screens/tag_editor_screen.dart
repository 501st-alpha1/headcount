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
/// Rename and delete apply immediately (they cascade to every person
/// using the tag, so staging them as a diff would be complex). Adding
/// new levels and reordering are staged into the Save button — neither
/// affects any person's data, so there's no reason to write immediately.
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
  /// The staged dependsOn value — empty string means "root tag."
  /// Applied on Save alongside name and new levels.
  String _dependsOn = '';
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
    _dependsOn = tag.dependsOn;
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
        // _levels holds the current order (possibly reordered by drag)
        // plus any newly-added levels. Renames/deletes already happened
        // on disk immediately — re-read to get the latest disk state,
        // then apply our staged order on top of it: keep any levels that
        // survived rename/delete in the user's chosen order, appending
        // anything newly added that isn't on disk yet.
        final latest = await repository.tags.load(existing.id) ?? existing;
        final latestSet = latest.levels.toSet();
        // Levels that exist on disk AND are in _levels, in _levels' order.
        final reordered = _levels.where(latestSet.contains).toList();
        // Brand-new levels (not yet on disk).
        final newlyAdded = _levels.where((l) => !latestSet.contains(l));
        final updated = latest.copyWith(
          name: _nameController.text.trim(),
          levels: [...reordered, ...newlyAdded],
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed header: name + levels section label
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      'Levels',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add level',
                      onPressed: () => _addLevel(context),
                    ),
                  ],
                ),
                Text(
                  'First = most enthusiastic. Drag to reorder. '
                  'Renaming or deleting applies immediately.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // Levels list — flexible so it fills remaining space
          Expanded(
            child: _levels.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No levels yet — add at least one.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ReorderableListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _levels.removeAt(oldIndex);
                        _levels.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (final level in _levels)
                        Card(
                          key: ValueKey(level),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            // Drag handle on the left
                            leading: const Icon(
                              Icons.drag_handle,
                              color: Colors.grey,
                            ),
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
          ),
        ],
      ),
    );
  }
}
