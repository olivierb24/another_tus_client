import 'dart:async';
import 'dart:developer';
import 'store_interface.dart';

/// Stub implementation of [TusIndexedDBStore] for mobile platforms.
class TusIndexedDBStore implements TusStore {
  final String dbName;
  final String storeName;
  final int dbVersion;
  bool _debug = false;

  TusIndexedDBStore({
    this.dbName = 'tus_uploads',
    this.storeName = 'files',
    this.dbVersion = 1,
    bool debug = false,
  }) : _debug = debug;

  /// Internal logging method that respects the debug flag
  void _log(String message) {
    if (_debug) {
      log('[TusIndexedDBStore-Stub] $message');
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
    _log('Attempted to store URL for fingerprint: $fingerprint (not supported on this platform)');
    throw UnsupportedError('TusIndexedDBStore is only supported on web platforms');
  }

  @override
  Future<Uri?> get(String fingerprint) async {
    _log('Attempted to get URL for fingerprint: $fingerprint (not supported on this platform)');
    throw UnsupportedError('TusIndexedDBStore is only supported on web platforms');
  }

  @override
  Future<void> remove(String fingerprint) async {
    _log('Attempted to remove entry for fingerprint: $fingerprint (not supported on this platform)');
    throw UnsupportedError('TusIndexedDBStore is only supported on web platforms');
  }
}