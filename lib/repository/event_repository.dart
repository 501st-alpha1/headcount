import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/event.dart';
import '../models/simple_date.dart';
import '../models/slug.dart';
import 'exceptions.dart';
import 'load_result.dart';

/// Reads and writes Event files under
/// <dataRoot>/events/<YYYY>/<MM>/<YYYY-MM-DD>-<id>.toml.
///
/// Events are located by walking the whole events/ tree rather than by
/// computing a path from id alone, since an event's id doesn't encode
/// its date (only its file path does) — the in-memory Event object is
/// what ties id and date together.
class EventRepository {
  final String dataRoot;

  EventRepository(this.dataRoot);

  String get _eventsDir => p.join(dataRoot, 'events');

  /// The full path for [event], derived from its id and date.
  String pathFor(Event event) => p.join(dataRoot, event.relativePath);

  /// Loads every event file found anywhere under events/**/*.toml.
  /// Malformed files are skipped and reported in LoadResult.issues.
  Future<LoadResult<Event>> loadAll() async {
    final dir = Directory(_eventsDir);
    if (!await dir.exists()) {
      return const LoadResult(items: [], issues: []);
    }

    final events = <Event>[];
    final issues = <LoadIssue>[];

    final entries = await dir
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('.toml'))
        .toList();

    for (final entry in entries) {
      final relativePath = p.relative(entry.path, from: dataRoot);
      try {
        final content = await File(entry.path).readAsString();
        events.add(Event.fromTomlString(content));
      } catch (e) {
        issues.add(LoadIssue(relativePath: relativePath, message: '$e'));
      }
    }

    return LoadResult(items: events, issues: issues);
  }

  /// Loads a single event by id. Since the file's location depends on its
  /// date (which we don't know yet), this scans the tree once. For
  /// individual lookups in hot paths, prefer loading via loadAll() and
  /// searching in memory instead of calling this repeatedly.
  Future<Event?> load(String id) async {
    final result = await loadAll();
    for (final event in result.items) {
      if (event.id == id) return event;
    }
    return null;
  }

  /// Writes [event] to its correct path (derived from its id + date),
  /// creating year/month folders as needed. If [previous] is supplied
  /// (the event's prior state, e.g. before a date edit) and its computed
  /// path differs from the new one, the old file is removed after the
  /// new one is written successfully — this is the move/rename behavior
  /// triggered by changing an event's date.
  ///
  /// [knownPersonIds] is used to reject writes with dangling person_id
  /// references; pass null to skip this check (e.g. when the caller has
  /// already validated).
  Future<void> save(
    Event event, {
    Event? previous,
    Set<String>? knownPersonIds,
  }) async {
    if (knownPersonIds != null) {
      final dangling = event.guests
          .map((g) => g.personId)
          .where((id) => !knownPersonIds.contains(id))
          .toSet();
      if (dangling.isNotEmpty) {
        throw DanglingReferenceException(
          'Event "${event.id}" has guest(s) referencing unknown '
          'person_id(s): ${dangling.join(', ')}. Create the person first, '
          'or remove them from the guest list.',
        );
      }
    }

    final newPath = pathFor(event);
    final newFile = File(newPath);
    await newFile.parent.create(recursive: true);
    await newFile.writeAsString(event.toTomlString());

    if (previous != null) {
      final oldPath = pathFor(previous);
      if (oldPath != newPath) {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
        await _cleanupEmptyMonthFolder(p.dirname(oldPath));
      }
    }
  }

  /// Creates a new event, generating a unique id from [name] if [id]
  /// isn't supplied. Uniqueness is checked against all existing event
  /// ids regardless of date, since ids are meant to be globally unique
  /// (the date prefix is a filesystem/readability convenience, not part
  /// of identity).
  Future<Event> create({
    required String name,
    required SimpleDate date,
    String? id,
    String description = '',
    bool pinned = true,
  }) async {
    final existing = await _existingIds();
    final resolvedId = id ?? uniqueSlug(slugify(name), existing);
    if (existing.contains(resolvedId)) {
      throw DuplicateIdException(
        'An event with id "$resolvedId" already exists.',
      );
    }
    final event = Event(
      id: resolvedId,
      name: name,
      date: date,
      description: description,
      pinned: pinned,
    );
    await save(event);
    return event;
  }

  /// Deletes [event]'s file. Also removes the containing month folder if
  /// it's now empty, per the design doc's "tidy tree" preference.
  Future<void> delete(Event event) async {
    final path = pathFor(event);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await _cleanupEmptyMonthFolder(p.dirname(path));
  }

  /// Removes [monthDirPath] if it exists and is empty, then checks
  /// whether its parent year folder is now also empty and removes that
  /// too. Silently does nothing if the folder doesn't exist or isn't
  /// empty — this is best-effort tidiness, not load-bearing.
  Future<void> _cleanupEmptyMonthFolder(String monthDirPath) async {
    final monthDir = Directory(monthDirPath);
    if (!await monthDir.exists()) return;
    final monthContents = await monthDir.list().toList();
    if (monthContents.isNotEmpty) return;
    await monthDir.delete();

    final yearDir = monthDir.parent;
    if (!await yearDir.exists()) return;
    final yearContents = await yearDir.list().toList();
    if (yearContents.isEmpty) {
      await yearDir.delete();
    }
  }

  Future<Set<String>> _existingIds() async {
    final result = await loadAll();
    return result.items.map((e) => e.id).toSet();
  }
}
