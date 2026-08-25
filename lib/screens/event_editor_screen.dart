import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/guest.dart';
import '../models/event.dart';
import '../models/event_question.dart';
import '../models/simple_date.dart';
import '../providers/data_providers.dart';
import '../repository/repository.dart';

/// Create-or-edit form for an Event. When [eventId] is null this creates
/// a new event; when supplied, it loads and edits the existing one,
/// passing the original as `previous` on save so EventRepository can
/// move the file if the date changed.
class EventEditorScreen extends ConsumerStatefulWidget {
  final String? eventId;

  const EventEditorScreen({super.key, this.eventId});

  bool get isEditing => eventId != null;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  List<EventQuestion> _questions = [];
  SimpleDate _date = SimpleDate.today();
  bool _pinned = true;
  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _initializeFrom(Event event) {
    if (_isInitialized) return;
    _nameController.text = event.name;
    _descriptionController.text = event.description;
    _date = event.date;
    _pinned = event.pinned;
    _questions = [...event.questions];
    _isInitialized = true;
  }

  Future<void> _pickDate() async {
    final initial = DateTime(_date.year, _date.month, _date.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // A wide range: this app has no inherent floor/ceiling on event
      // dates (you might log a past gathering, or plan far ahead).
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5),
    );
    if (picked != null) {
      setState(() {
        _date = SimpleDate(year: picked.year, month: picked.month, day: picked.day);
      });
    }
  }

  Future<void> _save(Event? existing) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final repository = ref.read(repositoryProvider);

    try {
      if (widget.isEditing) {
        if (existing == null) {
          throw StateError('Event ${widget.eventId} no longer exists.');
        }
        final updated = existing.copyWith(
          name: _nameController.text.trim(),
          date: _date,
          description: _descriptionController.text.trim(),
          pinned: _pinned,
          questions: _questions,
        );
        await repository.saveEvent(updated, previous: existing);
      } else {
        await repository.events.create(
          name: _nameController.text.trim(),
          date: _date,
          description: _descriptionController.text.trim(),
          pinned: _pinned,
          questions: _questions,
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
    if (!widget.isEditing) {
      return _buildForm(context, null);
    }

    final snapshotAsync = ref.watch(dataSnapshotProvider);
    return switch (snapshotAsync) {
      AsyncData(:final value) => _buildForm(
          context,
          _findEvent(value, widget.eventId!),
        ),
      AsyncError(:final error) => Scaffold(
          appBar: AppBar(title: const Text('Edit Event')),
          body: Center(child: Text('Could not load your data: $error')),
        ),
      _ => Scaffold(
          appBar: AppBar(title: const Text('Edit Event')),
          body: const Center(child: CircularProgressIndicator()),
        ),
    };
  }

  Event? _findEvent(DataSnapshot snapshot, String id) {
    for (final event in snapshot.events) {
      if (event.id == id) return event;
    }
    return null;
  }

  Future<void> _addQuestion() async {
    final result = await _showQuestionDialog();

    if (result == null) return;

    setState(() {
        _questions.add(
          EventQuestion(
            id: const Uuid().v4(),
            label: result.$1,
            type: result.$2,
          ),
        );
    });
  }

  Future<void> _editQuestion(EventQuestion question) async {
    final result = await _showQuestionDialog(question);

    if (result == null) return;

    setState(() {
        final index = _questions.indexWhere((q) => q.id == question.id);
        if (index == -1) return;

        _questions[index] = question.copyWith(
          label: result.$1,
          type: result.$2,
        );
    });
  }

  Future<(String, EventQuestionType)?> _showQuestionDialog([
      EventQuestion? question,
  ]) async {
    final controller = TextEditingController(text: question?.label ?? '');
    var type = question?.type ?? EventQuestionType.checkbox;

    final result = await showDialog<(String, EventQuestionType)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                question == null ? 'Add question' : 'Edit question',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Question',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<EventQuestionType>(
                    value: type,
                    decoration: const InputDecoration(
                      labelText: 'Answer type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: EventQuestionType.checkbox,
                        child: Text('Checkbox'),
                      ),
                      DropdownMenuItem(
                        value: EventQuestionType.text,
                        child: Text('Text'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => type = value);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final label = controller.text.trim();
                    if (label.isEmpty) return;
                    Navigator.pop(context, (label, type));
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<void> _deleteQuestion(
    EventQuestion? question,
    Event event,
  ) async {
    // This might need UI handling, not sure.
    if (question == null) return;

    final hasAnswers = (event?.guests ?? const <Guest>[]).any(
      (guest) => guest.answers.containsKey(question!.id),
    );

    if (hasAnswers) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This question cannot be deleted because guests have answers.',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
        _questions.removeWhere((q) => q.id == question!.id);
    });
  }

  Widget _buildForm(BuildContext context, Event? existing) {
    if (widget.isEditing && existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Event')),
        body: const Center(child: Text('This event no longer exists.')),
      );
    }
    if (existing != null) {
      _initializeFrom(existing);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Event' : 'New Event'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => _save(existing),
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
                labelText: 'Event name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Name is required'
                  : null,
              autofocus: !widget.isEditing,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_date.toIsoString()),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Location, what to bring, etc.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pinned'),
              subtitle: const Text(
                'Show on the home screen (until a few days after the event)',
              ),
              value: _pinned,
              onChanged: (value) => setState(() => _pinned = value),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Guest questions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addQuestion,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_questions.isEmpty)
            Text(
              'Optional questions you can track for each guest.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
            else
            ..._questions.map(
              (question) => Card(
                child: ListTile(
                  title: Text(question.label),
                  subtitle: Text(
                    question.type == EventQuestionType.checkbox
                    ? 'Checkbox'
                    : 'Text answer',
                  ),
                  onTap: () => _editQuestion(question),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete question',
                    onPressed: () => _deleteQuestion(question, existing!),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
