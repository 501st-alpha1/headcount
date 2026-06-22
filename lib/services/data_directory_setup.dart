import 'dart:io';

import 'package:path/path.dart' as p;

import '../repository/exceptions.dart';

/// Ensures [dataDirectoryPath] exists and has the people/, groups/, and
/// events/ subfolders the repository layer expects. Safe to call on a
/// directory that's already fully set up — each check is a no-op if the
/// folder already exists.
///
/// Throws DataDirectoryException if the path exists but isn't a directory,
/// or if creation fails (e.g. permission denied).
Future<void> ensureDataDirectoryStructure(String dataDirectoryPath) async {
  final root = Directory(dataDirectoryPath);

  if (await root.exists()) {
    final stat = await root.stat();
    if (stat.type != FileSystemEntityType.directory) {
      throw DataDirectoryException(
        '$dataDirectoryPath exists but is not a directory.',
      );
    }
  }

  try {
    await root.create(recursive: true);
    for (final subfolder in const ['people', 'groups', 'events']) {
      await Directory(p.join(dataDirectoryPath, subfolder))
          .create(recursive: true);
    }
  } catch (e) {
    throw DataDirectoryException(
      'Could not set up data directory at $dataDirectoryPath: $e',
    );
  }
}
