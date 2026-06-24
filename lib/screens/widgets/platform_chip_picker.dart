import 'package:flutter/material.dart';

/// A row of selectable platform chips (e.g. "Signal", "Instagram") plus
/// an inline "+ New" chip for adding one that doesn't exist yet. Used by
/// both PersonEditorScreen (multi-select) and GroupEditorScreen
/// (single-select for the group's default platform) — [multiSelect]
/// switches between the two behaviors.
///
/// This widget is intentionally dumb: it doesn't know about Repository
/// or persistence. A newly-typed platform is just added to [selected]
/// and reported via [onChanged]/[onCreateNew] — callers decide what, if
/// anything, needs to be saved (a brand-new platform on a Person doesn't
/// need any separate "platform" entity created anywhere, since platforms
/// aren't their own model — they're just strings that happen to be
/// reused across people/groups, same spirit as tags but without a
/// dedicated definition file).
class PlatformChipPicker extends StatefulWidget {
  final List<String> availablePlatforms;
  final Set<String> selected;
  final bool multiSelect;
  final void Function(Set<String> selected) onChanged;

  const PlatformChipPicker({
    super.key,
    required this.availablePlatforms,
    required this.selected,
    required this.onChanged,
    this.multiSelect = true,
  });

  @override
  State<PlatformChipPicker> createState() => _PlatformChipPickerState();
}

class _PlatformChipPickerState extends State<PlatformChipPicker> {
  bool _creatingNew = false;
  late TextEditingController _newPlatformController;

  @override
  void initState() {
    super.initState();
    _newPlatformController = TextEditingController();
  }

  @override
  void dispose() {
    _newPlatformController.dispose();
    super.dispose();
  }

  void _toggle(String platform) {
    final updated = {...widget.selected};
    if (widget.multiSelect) {
      if (updated.contains(platform)) {
        updated.remove(platform);
      } else {
        updated.add(platform);
      }
    } else {
      updated
        ..clear()
        ..add(platform);
    }
    widget.onChanged(updated);
  }

  void _startCreatingNew() {
    setState(() {
      _creatingNew = true;
      _newPlatformController.clear();
    });
  }

  void _confirmNew() {
    final name = _newPlatformController.text.trim();
    if (name.isNotEmpty) {
      _toggle(name);
    }
    setState(() => _creatingNew = false);
  }

  @override
  Widget build(BuildContext context) {
    // Always include anything currently selected, even if it's not (yet)
    // in availablePlatforms — covers the moment right after creating a
    // new one, and editing a person/group whose platform isn't used by
    // anyone else.
    final chipOptions = {
      ...widget.availablePlatforms,
      ...widget.selected,
    }.toList()
      ..sort();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final platform in chipOptions)
          ChoiceChip(
            label: Text(platform),
            selected: widget.selected.contains(platform),
            onSelected: (_) => _toggle(platform),
          ),
        if (_creatingNew)
          SizedBox(
            width: 140,
            child: TextField(
              controller: _newPlatformController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'New platform',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _confirmNew(),
            ),
          )
        else
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('New'),
            onPressed: _startCreatingNew,
          ),
        if (_creatingNew)
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Confirm new platform',
            onPressed: _confirmNew,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
