/// A problem encountered while loading one file during a directory scan.
/// Collected rather than thrown immediately, so one bad file doesn't
/// prevent loading everything else.
class LoadIssue {
  final String relativePath;
  final String message;

  const LoadIssue({required this.relativePath, required this.message});

  @override
  String toString() => '$relativePath: $message';
}

/// The result of loading a collection of files (people, groups, or events):
/// the successfully parsed items, plus any issues from files that failed
/// to parse. [issues] being non-empty doesn't mean the load "failed" —
/// it means some files were skipped. Callers (UI layer) decide how loudly
/// to surface that.
class LoadResult<T> {
  final List<T> items;
  final List<LoadIssue> issues;

  const LoadResult({required this.items, required this.issues});

  bool get hasIssues => issues.isNotEmpty;
}
