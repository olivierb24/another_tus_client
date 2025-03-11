import 'dart:async';
import 'store_interface.dart';

/// This class is used to lookup a [fingerprint] with the
/// corresponding [file] entries in a [Map].
///
/// This functionality is used to allow resuming uploads.
///
/// This store **will not** keep the values after your application crashes or
/// restarts.
class TusMemoryStore implements TusStore {
  Map<String, Uri> store = {};

  @override
  Future<void> set(String fingerprint, Uri url) async {
    store[fingerprint] = url;
  }

  @override
  Future<Uri?> get(String fingerprint) async {
    return store[fingerprint];
  }

  @override
  Future<void> remove(String fingerprint) async {
    store.remove(fingerprint);
  }
}