import 'dart:io';

import 'package:headcount/repository/exceptions.dart';
import 'package:headcount/services/data_directory_setup.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('headcount_setup_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ensureDataDirectoryStructure', () {
    test('creates people/, groups/, and events/ under a brand-new root',
        () async {
      final root = '${tempDir.path}/fresh-data';
      await ensureDataDirectoryStructure(root);

      expect(await Directory('$root/people').exists(), isTrue);
      expect(await Directory('$root/groups').exists(), isTrue);
      expect(await Directory('$root/events').exists(), isTrue);
    });

    test('is a no-op (does not throw) when run twice on the same root',
        () async {
      final root = '${tempDir.path}/fresh-data';
      await ensureDataDirectoryStructure(root);
      await ensureDataDirectoryStructure(root);

      expect(await Directory('$root/people').exists(), isTrue);
    });

    test('does not disturb existing files in an already-set-up directory',
        () async {
      final root = '${tempDir.path}/existing-data';
      await ensureDataDirectoryStructure(root);

      final personFile = File('$root/people/alice-chen.toml');
      await personFile.writeAsString('id = "alice-chen"\nname = "Alice"\n');

      await ensureDataDirectoryStructure(root);

      expect(await personFile.exists(), isTrue);
      expect(await personFile.readAsString(), contains('alice-chen'));
    });

    test('throws DataDirectoryException if the path is an existing file, not a folder',
        () async {
      final filePath = '${tempDir.path}/not-a-directory';
      await File(filePath).writeAsString('just a file');

      expect(
        () => ensureDataDirectoryStructure(filePath),
        throwsA(isA<DataDirectoryException>()),
      );
    });
  });
}
