import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/person.dart';
import '../providers/data_providers.dart';

/// Create-or-edit form for a Person. When [personId] is null this creates
/// a new person; when supplied, it loads and edits the existing one.
/// Same form either way — the only behavioral difference is which
/// repository call happens on save.
class PersonEditorScreen extends ConsumerStatefulWidget {
  final String? personId;

  const PersonEditorScreen({super.key, this.personId});

  bool get isEditing => personId != null;

  @override
  ConsumerState<PersonEditorScreen> createState() =>
      _PersonEditorScreenState();
}

class _PersonEditorScreenState extends ConsumerState<PersonEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _platformsController;
  late TextEditingController _notesController;
  List<InterestTag> _interests = [];
  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _platformsController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _platformsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _initializeFrom(Person person) {
    if (_isInitialized) return;
    _nameController.text = person.name;
    _platformsController.text = person.platforms.join(', ');
    _notesController.text = person.notes;
    _interests = [...person.interests];
    _isInitialized = true;
  }

  List<String> get _platformsList => _platformsController.text
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final repository = ref.read(repositoryProvider);

    try {
      if (widget.isEditing) {
        final existing = await repository.people.load(widget.personId!);
        if (existing == null) {
          throw StateError('Person ${widget.personId} no longer exists.');
        }
        final updated = existing.copyWith(
          name: _nameController.text.trim(),
          platforms: _platformsList,
          notes: _notesController.text.trim(),
          interests: _interests,
        );
        await repository.people.save(updated);
      } else {
        await repository.people.create(
          name: _nameController.text.trim(),
          platforms: _platformsList,
          notes: _notesController.text.trim(),
          interests: _interests,
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

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(dataSnapshotProvider);

    return switch (snapshotAsync) {
      AsyncData(:final value) => _buildForm(
          context,
          widget.isEditing ? value.personById(widget.personId!) : null,
          value.allTagsInUse,
        ),
      AsyncError(:final error) => Scaffold(
          appBar: AppBar(title: const Text('Edit Person')),
          body: Center(child: Text('Could not load your data: $error')),
        ),
      _ => Scaffold(
          appBar: AppBar(title: const Text('Edit Person')),
          body: const Center(child: CircularProgressIndicator()),
        ),
    };
  }

  Widget _buildForm(
    BuildContext context,
    Person? existing,
    List<String> availableTags,
  ) {
    if (widget.isEditing && existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Person')),
        body: const Center(child: Text('This person no longer exists.')),
      );
    }
    if (existing != null) {
      _initializeFrom(existing);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Person' : 'New Person'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? 'Name is required'
                      : null,
              autofocus: !widget.isEditing,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _platformsController,
              decoration: const InputDecoration(
                labelText: 'Platforms (comma-separated)',
                hintText: 'Signal, Instagram',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Standing constraints, preferences, context',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Interests',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add interest',
                  onPressed: _addInterest,
                ),
              ],
            ),
            if (_interests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No interests added yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final interest in _interests)
                _EditableInterestRow(
                  interest: interest,
                  availableTags: availableTags,
                  onChanged: (updated) => setState(() {
                    final index = _interests.indexOf(interest);
                    _interests[index] = updated;
                  }),
                  onRemove: () => setState(() {
                    _interests.remove(interest);
                  }),
                ),
          ],
        ),
      ),
    );
  }

  void _addInterest() {
    setState(() {
      _interests.add(
        const InterestTag(tag: '', level: InterestLevel.lovesIt),
      );
    });
  }
}

class _EditableInterestRow extends StatefulWidget {
  final InterestTag interest;
  final List<String> availableTags;
  final void Function(InterestTag) onChanged;
  final VoidCallback onRemove;

  const _EditableInterestRow({
    required this.interest,
    required this.availableTags,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_EditableInterestRow> createState() => _EditableInterestRowState();
}

class _EditableInterestRowState extends State<_EditableInterestRow> {
  late TextEditingController _notesController;

  /// True while showing the inline "name your new tag" text field instead
  /// of the "+" chip.
  bool _creatingNewTag = false;
  late TextEditingController _newTagController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.interest.notes);
    _newTagController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _newTagController.dispose();
    super.dispose();
  }

  void _emitNotesChange() {
    widget.onChanged(widget.interest.copyWith(notes: _notesController.text.trim()));
  }

  void _selectTag(String tag) {
    widget.onChanged(widget.interest.copyWith(tag: tag));
  }

  void _startCreatingNewTag() {
    setState(() {
      _creatingNewTag = true;
      _newTagController.clear();
    });
  }

  void _confirmNewTag() {
    final newTag = _newTagController.text.trim();
    if (newTag.isNotEmpty) {
      _selectTag(newTag);
    }
    setState(() => _creatingNewTag = false);
  }

  @override
  Widget build(BuildContext context) {
    // The current tag might not be in availableTags yet — e.g. it was
    // just created on this row, or this row is being edited on a person
    // who already had a tag no one else currently uses. Always include
    // it so the selection is visible rather than silently unmatched.
    final chipOptions = {
      ...widget.availableTags,
      if (widget.interest.tag.isNotEmpty) widget.interest.tag,
    }.toList()
      ..sort();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in chipOptions)
                        ChoiceChip(
                          label: Text(tag),
                          selected: widget.interest.tag == tag,
                          onSelected: (_) => _selectTag(tag),
                        ),
                      if (_creatingNewTag)
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _newTagController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'New tag name',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _confirmNewTag(),
                          ),
                        )
                      else
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('New'),
                          onPressed: _startCreatingNewTag,
                        ),
                      if (_creatingNewTag)
                        IconButton(
                          icon: const Icon(Icons.check),
                          tooltip: 'Confirm new tag',
                          onPressed: _confirmNewTag,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final level in InterestLevel.values)
                  ChoiceChip(
                    label: Text(level.label),
                    selected: widget.interest.level == level,
                    onSelected: (_) => widget.onChanged(
                      widget.interest.copyWith(level: level),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Flat trails only',
                isDense: true,
              ),
              onChanged: (_) => _emitNotesChange(),
            ),
          ],
        ),
      ),
    );
  }
}
