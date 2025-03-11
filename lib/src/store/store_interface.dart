/// Base interface for TusStore implementations
abstract class TusStore {
  /// Store a new [fingerprint] and its upload [url].
  Future<void> set(String fingerprint, Uri url);

  /// Retrieve an upload's Uri for a [fingerprint].
  /// If no matching entry is found this method will return `null`.
  Future<Uri?> get(String fingerprint);

  /// Remove an entry from the store using an upload's [fingerprint].
  Future<void> remove(String fingerprint);
}