import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/repository.dart';
import '../services/app_settings.dart';
import '../services/data_directory_setup.dart';

/// The loaded AppSettings instance, available once app startup completes.
/// main.dart awaits AppSettings.load() before runApp so this is always
/// ready by the time any widget reads it — no AsyncValue/loading state
/// needed here.
final appSettingsProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError(
    'appSettingsProvider must be overridden in main.dart with the '
    'AppSettings instance loaded at startup.',
  );
});

/// The currently configured data directory path, or null if no directory
/// has been chosen yet (first launch, before the user picks one or the
/// fallback kicks in). Watching this is how the rest of the app reacts to
/// the user changing their data directory in Settings.
class DataDirectoryNotifier extends Notifier<String?> {
  @override
  String? build() {
    return ref.read(appSettingsProvider).dataDirectoryPath;
  }

  /// Sets a new data directory, ensuring its folder structure exists
  /// first, and persists the choice so it survives restarts.
  Future<void> setPath(String path) async {
    await ensureDataDirectoryStructure(path);
    await ref.read(appSettingsProvider).setDataDirectoryPath(path);
    state = path;
  }
}

final dataDirectoryProvider =
    NotifierProvider<DataDirectoryNotifier, String?>(
        DataDirectoryNotifier.new);

/// The Repository for the currently configured data directory. Only
/// valid to read once dataDirectoryProvider is non-null — screens should
/// gate on that first (see main.dart's routing between the first-launch
/// screen and the home screen).
final repositoryProvider = Provider<Repository>((ref) {
  final path = ref.watch(dataDirectoryProvider);
  if (path == null) {
    throw StateError(
      'repositoryProvider read before a data directory was configured. '
      'Check dataDirectoryProvider first.',
    );
  }
  return Repository(path);
});

/// The current snapshot of all people/groups/events loaded from disk.
/// This is an AsyncNotifier so the UI can show loading/error states
/// naturally, and so any screen can trigger a reload after a write by
/// calling `ref.invalidate(dataSnapshotProvider)` or
/// `ref.read(dataSnapshotProvider.notifier).reload()`.
class DataSnapshotNotifier extends AsyncNotifier<DataSnapshot> {
  @override
  Future<DataSnapshot> build() async {
    final repository = ref.watch(repositoryProvider);
    return repository.loadAll();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final dataSnapshotProvider =
    AsyncNotifierProvider<DataSnapshotNotifier, DataSnapshot>(
        DataSnapshotNotifier.new);
