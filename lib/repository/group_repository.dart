import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/group.dart';
import '../models/slug.dart';
import 'exceptions.dart';
import 'load_result.dart';

/// Reads and writes Group files under <dataRoot>/groups/<id>.toml.
///
/// Like PersonRepository, this class doesn't validate member_ids against
/// the people/ directory — that cross-check happens one layer up, in the
/// combined Repository, since GroupRepository alone can't see people/.
class GroupRepository {
  final String dataRoot;

  GroupRepository(this.dataRoot);

  String get _groupsDir => p.join(dataRoot, 'groups');

  String pathFor(String id) => p.join(_groupsDir, '$id.toml');

  Future<LoadResult<Group>> loadAll() async {
    final dir = Directory(_groupsDir);
    if (!await dir.exists()) {
      return const LoadResult(items: [], issues: []);
    }

    final groups = <Group>[];
    final issues = <LoadIssue>[];

    final entries = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.toml'))
        .toList();

    for (final entry in entries) {
      final relativePath = p.relative(entry.path, from: dataRoot);
      try {
        final content = await File(entry.path).readAsString();
        groups.add(Group.fromTomlString(content));
      } catch (e) {
        issues.add(LoadIssue(relativePath: relativePath, message: '$e'));
      }
    }

    return LoadResult(items: groups, issues: issues);
  }

  Future<Group?> load(String id) async {
    final file = File(pathFor(id));
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return Group.fromTomlString(content);
  }

  Future<void> save(Group group) async {
    final dir = Directory(_groupsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(pathFor(group.id));
    await file.writeAsString(group.toTomlString());
  }

  /// Creates a new group, generating a unique id from [name] if [id]
  /// isn't supplied.
  Future<Group> create({
    required String name,
    String? id,
    List<String> memberIds = const [],
    String notes = '',
  }) async {
    final existing = await _existingIds();
    final resolvedId = id ?? uniqueSlug(slugify(name), existing);
    if (existing.contains(resolvedId)) {
      throw DuplicateIdException(
        'A group with id "$resolvedId" already exists.',
      );
    }
    final group = Group(
      id: resolvedId,
      name: name,
      memberIds: memberIds,
      notes: notes,
    );
    await save(group);
    return group;
  }

  Future<void> delete(String id) async {
    final file = File(pathFor(id));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Set<String>> _existingIds() async {
    final result = await loadAll();
    return result.items.map((g) => g.id).toSet();
  }
}
