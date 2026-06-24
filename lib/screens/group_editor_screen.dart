import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../models/person.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';

/// Create-or-edit form for a Group: name, notes, and membership. When
/// [groupId] is null this creates a new group; when supplied, it loads
/// and edits the existing one. Membership is edited via a searchable
/// checkbox list of all people — straightforward at the personal scale
/// this app is designed for.
class GroupEditorScreen extends ConsumerStatefulWidget {
  final String? groupId;

  const GroupEditorScreen({super.key, this.groupId});

  bool get isEditing => groupId != null;

  @override
  ConsumerState<GroupEditorScreen> createState() => _GroupEditorScreenState();
}

class _GroupEditorScreenState extends ConsumerState<GroupEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _notesController;
  final _memberSearchController = TextEditingController();
  String _memberQuery = '';
  Set<String> _memberIds = {};
  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  void _initializeFrom(Group group) {
    if (_isInitialized) return;
    _nameController.text = group.name;
    _notesController.text = group.notes;
    _memberIds = group.memberIds.toSet();
    _isInitialized = true;
  }

  Future<void> _save(Group? existing) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final repository = ref.read(repositoryProvider);

    try {
      if (widget.isEditing) {
        if (existing == null) {
          throw StateError('Group ${widget.groupId} no longer exists.');
        }
        final updated = existing.copyWith(
          name: _nameController.text.trim(),
          notes: _notesController.text.trim(),
          memberIds: _memberIds.toList(),
        );
        await repository.saveGroup(updated);
      } else {
        await repository.groups.create(
          name: _nameController.text.trim(),
          notes: _notesController.text.trim(),
          memberIds: _memberIds.toList(),
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
          widget.isEditing ? value.groupById(widget.groupId!) : null,
          value.people,
        ),
      AsyncError(:final error) => Scaffold(
          appBar: AppBar(title: const Text('Edit Group')),
          body: Center(child: Text('Could not load your data: $error')),
        ),
      _ => Scaffold(
          appBar: AppBar(title: const Text('Edit Group')),
          body: const Center(child: CircularProgressIndicator()),
        ),
    };
  }

  Widget _buildForm(
    BuildContext context,
    Group? existing,
    List<Person> allPeople,
  ) {
    if (widget.isEditing && existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Group')),
        body: const Center(child: Text('This group no longer exists.')),
      );
    }
    if (existing != null) {
      _initializeFrom(existing);
    }

    final sortedPeople = [...allPeople]
      ..sort((a, b) => a.name.compareTo(b.name));
    final filteredPeople = _memberQuery.isEmpty
        ? sortedPeople
        : sortedPeople
            .where((p) =>
                p.name.toLowerCase().contains(_memberQuery.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Group' : 'New Group'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => _save(existing),
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
              labelText: 'Group name',
              hintText: 'Book Club',
              border: OutlineInputBorder(),
            ),
            autofocus: !widget.isEditing,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Meets monthly, mostly responsive on Signal',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Members', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              Text(
                '${_memberIds.length} selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (allPeople.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No people yet — add some from the People screen first.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else ...[
            TextField(
              controller: _memberSearchController,
              decoration: InputDecoration(
                hintText: 'Search people',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) => setState(() => _memberQuery = value),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final person in filteredPeople)
                    CheckboxListTile(
                      title: Text(person.name),
                      value: _memberIds.contains(person.id),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _memberIds.add(person.id);
                        } else {
                          _memberIds.remove(person.id);
                        }
                      }),
                    ),
                  if (filteredPeople.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No matches for "$_memberQuery".',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
