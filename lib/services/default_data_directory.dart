import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Computes the fallback data directory used when the user backs out of
/// the directory picker on first launch. This is an ordinary
/// app-local-storage folder (not chosen by the user, not necessarily a
/// great place for a Git repo they'll want to access from a desktop
/// terminal) — it exists so the app is never blocked from starting, not
/// as the recommended long-term home for their data. The Settings screen
/// lets them switch to a real directory at any time.
Future<String> defaultDataDirectoryPath() async {
  final appSupportDir = await getApplicationSupportDirectory();
  return p.join(appSupportDir.path, 'rsvp-data');
}
