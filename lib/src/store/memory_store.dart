import 'dart:async';
import 'dart:developer';
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
  bool _debug = false;
  
  /// Create a new memory store with optional debug logging
  TusMemoryStore({bool debug = false}) : _debug = debug;
  
  /// Internal logging method that respects the debug flag
  void _log(String message) {
    if (_debug) {
      log('[TusMemoryStore] $message');
    }
  }
  
  @override
  void setDebug(bool value) {
    _debug = value;
    _log('Debug logging ${value ? 'enabled' : 'disabled'}');
  }
  
  @override
  bool isDebugEnabled() {
    return _debug;
  }

  @override
  Future<void> set(String fingerprint, Uri url) async {
    _log('Storing URL for fingerprint: $fingerprint');
    _log('URL: $url');
    store[fingerprint] = url;
    _log('URL stored successfully in memory');
  }

  @override
  Future<Uri?> get(String fingerprint) async {
    _log('Getting URL for fingerprint: $fingerprint');
    final result = store[fingerprint];
    if (result != null) {
      _log('Found URL: $result');
    } else {
      _log('No URL found for fingerprint');
    }
    return result;
  }

  @override
  Future<void> remove(String fingerprint) async {
    _log('Removing entry for fingerprint: $fingerprint');
    final existed = store.containsKey(fingerprint);
    store.remove(fingerprint);
    _log('${existed ? 'Entry removed' : 'No entry found to remove'}');
  }
}