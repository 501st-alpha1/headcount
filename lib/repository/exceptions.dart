/// Thrown when a write would create or leave a dangling reference —
/// e.g. an Event's guest list contains a person_id that has no
/// corresponding file in people/, or a Group's member_ids contains an
/// unknown person_id.
class DanglingReferenceException implements Exception {
  final String message;
  const DanglingReferenceException(this.message);

  @override
  String toString() => 'DanglingReferenceException: $message';
}

/// Thrown when attempting to create a person/event/group whose id already
/// exists. Callers should generate a unique slug (see slug.dart) before
/// calling create — this exception is a last-resort guard, not the
/// expected way to handle collisions.
class DuplicateIdException implements Exception {
  final String message;
  const DuplicateIdException(this.message);

  @override
  String toString() => 'DuplicateIdException: $message';
}

/// Thrown when the configured data directory doesn't exist and couldn't
/// be created, or exists but isn't writable.
class DataDirectoryException implements Exception {
  final String message;
  const DataDirectoryException(this.message);

  @override
  String toString() => 'DataDirectoryException: $message';
}
