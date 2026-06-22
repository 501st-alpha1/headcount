import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/person.dart';
import '../models/slug.dart';
import 'exceptions.dart';
import 'load_result.dart';

/// Reads and writes Person files under <dataRoot>/people/<id>.toml.
///
/// This class only touches the filesystem and knows nothing about events
/// or groups — cross-entity checks (like "does this person_id exist")
/// are the caller's job (see EventRepository, GroupRepository), since
/// PersonRepository alone has no way to know what's safe to delete.
class PersonRepository {
  final String dataRoot;

  PersonRepository(this.dataRoot);

  String get _peopleDir => p.join(dataRoot, 'people');

  String pathFor(String id) => p.join(_peopleDir, '$id.toml');

  /// Loads every person file in people/. Files that fail to parse are
  /// skipped and reported in LoadResult.issues rather than throwing,
  /// so one bad file doesn't block loading everyone else.
  Future<LoadResult<Person>> loadAll() async {
    final dir = Directory(_peopleDir);
    if (!await dir.exists()) {
      return const LoadResult(items: [], issues: []);
    }

    final people = <Person>[];
    final issues = <LoadIssue>[];

    final entries = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.toml'))
        .toList();

    for (final entry in entries) {
      final relativePath = p.relative(entry.path, from: dataRoot);
      try {
        final content = await File(entry.path).readAsString();
        people.add(Person.fromTomlString(content));
      } catch (e) {
        issues.add(LoadIssue(relativePath: relativePath, message: '$e'));
      }
    }

    return LoadResult(items: people, issues: issues);
  }

  /// Loads a single person by id, or null if no such file exists.
  Future<Person?> load(String id) async {
    final file = File(pathFor(id));
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return Person.fromTomlString(content);
  }

  /// Writes [person] to disk, creating people/ if needed. Overwrites any
  /// existing file with the same id.
  Future<void> save(Person person) async {
    final dir = Directory(_peopleDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(pathFor(person.id));
    await file.writeAsString(person.toTomlString());
  }

  /// Creates a new person, generating a unique id from [name] if one
  /// isn't supplied. Throws DuplicateIdException if [id] is explicitly
  /// given and already taken — callers that want auto-uniquification
  /// should leave [id] null and let this method handle it.
  Future<Person> create({
    required String name,
    String? id,
    List<String> platforms = const [],
    String notes = '',
  }) async {
    final existing = await _existingIds();
    final resolvedId = id ?? uniqueSlug(slugify(name), existing);
    if (existing.contains(resolvedId)) {
      throw DuplicateIdException(
        'A person with id "$resolvedId" already exists.',
      );
    }
    final person = Person(
      id: resolvedId,
      name: name,
      platforms: platforms,
      notes: notes,
    );
    await save(person);
    return person;
  }

  /// Deletes the file for person [id]. Does nothing if it doesn't exist.
  /// Callers are responsible for checking this person isn't referenced
  /// by any event or group first (see Repository.deletePerson for the
  /// checked version used by the rest of the app).
  Future<void> delete(String id) async {
    final file = File(pathFor(id));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Set<String>> _existingIds() async {
    final result = await loadAll();
    return result.items.map((p) => p.id).toSet();
  }
}
