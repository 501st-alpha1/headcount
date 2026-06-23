import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/slug.dart';
import '../models/tag.dart';
import 'exceptions.dart';
import 'load_result.dart';

/// Reads and writes Tag definition files under <dataRoot>/tags/<id>.toml.
///
/// Unlike people/groups/events, tag files can come into existence two
/// ways: explicitly via create() (e.g. from the Tags List screen), or
/// implicitly via Repository's auto-migration of tags that are in use on
/// some person's interests but don't have a definition file yet (see
/// Repository.loadAll). This repository itself doesn't know about that
/// migration — it just reads and writes whatever files exist.
class TagRepository {
  final String dataRoot;

  TagRepository(this.dataRoot);

  String get _tagsDir => p.join(dataRoot, 'tags');

  String pathFor(String id) => p.join(_tagsDir, '$id.toml');

  Future<LoadResult<Tag>> loadAll() async {
    final dir = Directory(_tagsDir);
    if (!await dir.exists()) {
      return const LoadResult(items: [], issues: []);
    }

    final tags = <Tag>[];
    final issues = <LoadIssue>[];

    final entries = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.toml'))
        .toList();

    for (final entry in entries) {
      final relativePath = p.relative(entry.path, from: dataRoot);
      try {
        final content = await File(entry.path).readAsString();
        tags.add(Tag.fromTomlString(content));
      } catch (e) {
        issues.add(LoadIssue(relativePath: relativePath, message: '$e'));
      }
    }

    return LoadResult(items: tags, issues: issues);
  }

  Future<Tag?> load(String id) async {
    final file = File(pathFor(id));
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return Tag.fromTomlString(content);
  }

  Future<void> save(Tag tag) async {
    final dir = Directory(_tagsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(pathFor(tag.id));
    await file.writeAsString(tag.toTomlString());
  }

  /// Creates a new tag, generating a unique id from [name] if [id] isn't
  /// supplied. Defaults to [Tag.defaultLevels] if [levels] isn't given —
  /// every tag needs at least a starting level set to be usable.
  Future<Tag> create({
    required String name,
    String? id,
    List<String>? levels,
  }) async {
    final existing = await _existingIds();
    final resolvedId = id ?? uniqueSlug(slugify(name), existing);
    if (existing.contains(resolvedId)) {
      throw DuplicateIdException(
        'A tag with id "$resolvedId" already exists.',
      );
    }
    final tag = Tag(
      id: resolvedId,
      name: name,
      levels: levels ?? Tag.defaultLevels,
    );
    await save(tag);
    return tag;
  }

  Future<void> delete(String id) async {
    final file = File(pathFor(id));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Set<String>> _existingIds() async {
    final result = await loadAll();
    return result.items.map((t) => t.id).toSet();
  }
}
