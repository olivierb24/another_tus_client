import 'dart:async';
import 'dart:developer';
import 'dart:js_interop';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;
import 'store_interface.dart';

/// [TusIndexedDBStore] uses browser IndexedDB for storing upload URLs.
/// Useful for larger or more complex data than localStorage can handle.
class TusIndexedDBStore implements TusStore {
  final String dbName;
  final String storeName;
  final int dbVersion;
  bool _debug = false;

  /// Reference to the opened IndexedDB database
  web.IDBDatabase? _db;

  /// Create a new IndexedDB store with optional debug logging
  TusIndexedDBStore({
    this.dbName = 'tus_uploads',
    this.storeName = 'files',
    this.dbVersion = 1,
    bool debug = false,
  }) : _debug = debug;

  /// Internal logging method that respects the debug flag
  void _log(String message) {
    if (_debug) {
      log('[TusIndexedDBStore] $message');
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

  /// Opens (or creates) the DB if not already open
  Future<web.IDBDatabase> _openDatabase() async {
    if (!kIsWeb) {
      _log('Error: IndexedDB is only supported in web contexts');
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    if (_db != null) {
      _log('Database already open, reusing existing connection');
      return _db!;
    }

    _log('Opening IndexedDB database: $dbName (version $dbVersion)');
    final completer = Completer<web.IDBDatabase>();

    try {
      final request = web.window.indexedDB.open(dbName, dbVersion);
      _log('Open request initiated');

      request.onupgradeneeded = ((web.Event event) {
        _log('Database upgrade needed, creating object store if needed');
        final db = request.result;
        if (db is web.IDBDatabase) {
          if (!db.objectStoreNames.contains(storeName)) {
            _log('Creating object store: $storeName');
            db.createObjectStore(storeName);
          } else {
            _log('Object store already exists: $storeName');
          }
        }
      }).toJS;

      request.onsuccess = ((web.Event event) {
        _log('Database opened successfully');
        final result = request.result;
        if (result is web.IDBDatabase) {
          _db = result;
          completer.complete(result);
        } else {
          _log('Error: Unexpected result type: ${result.runtimeType}');
          completer.completeError('Unexpected result type');
        }
      }).toJS;

      request.onerror = ((web.Event event) {
        _log('Error opening database: ${request.error}');
        completer.completeError('Failed to open IndexedDB: ${request.error}');
      }).toJS;
    } catch (e) {
      _log('Exception opening database: $e');
      completer.completeError('Error opening IndexedDB: $e');
    }

    return completer.future;
  }

  @override
  Future<void> set(String fingerprint, Uri url) async {
    _log('Storing URL for fingerprint: $fingerprint');
    _log('URL: $url');
    
    if (!kIsWeb) {
      _log('Error: IndexedDB is only supported in web contexts');
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    _log('Opening database');
    final db = await _openDatabase();
    _log('Starting transaction');
    final txn = db.transaction(storeName.toJS, 'readwrite');
    final store = txn.objectStore(storeName);

    final completer = Completer<void>();

    try {
      _log('Putting data in store');
      final putRequest = store.put(url.toString().toJS, fingerprint.toJS);

      putRequest.onsuccess = ((web.Event event) {
        _log('URL stored successfully in IndexedDB');
        completer.complete();
      }).toJS;

      putRequest.onerror = ((web.Event event) {
        _log('Error storing URL: ${putRequest.error}');
        completer.completeError(
          'Failed to store URL in IndexedDB: ${putRequest.error}',
        );
      }).toJS;
    } catch (e) {
      _log('Exception in set operation: $e');
      completer.completeError('Error in set operation: $e');
    }

    return completer.future;
  }

  @override
  Future<Uri?> get(String fingerprint) async {
    _log('Getting URL for fingerprint: $fingerprint');
    
    if (!kIsWeb) {
      _log('Error: IndexedDB is only supported in web contexts');
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    _log('Opening database');
    final db = await _openDatabase();
    _log('Starting read transaction');
    final txn = db.transaction(storeName.toJS, 'readonly');
    final store = txn.objectStore(storeName);

    final completer = Completer<Uri?>();

    try {
      _log('Getting data from store');
      final getRequest = store.get(fingerprint.toJS);

      getRequest.onsuccess = ((web.Event event) {
        final value = getRequest.result;
        if (value != null && value is String && (value as String).isNotEmpty) {
          _log('Found URL: ${value as String}');
          completer.complete(Uri.parse(value as String));
        } else {
          _log('No URL found for fingerprint');
          completer.complete(null);
        }
      }).toJS;

      getRequest.onerror = ((web.Event event) {
        _log('Error retrieving URL: ${getRequest.error}');
        completer.completeError(
          'Failed to retrieve URL from IndexedDB: ${getRequest.error}',
        );
      }).toJS;
    } catch (e) {
      _log('Exception in get operation: $e');
      completer.completeError('Error in get operation: $e');
    }

    return completer.future;
  }

  @override
  Future<void> remove(String fingerprint) async {
    _log('Removing entry for fingerprint: $fingerprint');
    
    if (!kIsWeb) {
      _log('Error: IndexedDB is only supported in web contexts');
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    _log('Opening database');
    final db = await _openDatabase();
    _log('Starting write transaction');
    final txn = db.transaction(storeName.toJS, 'readwrite');
    final store = txn.objectStore(storeName);

    final completer = Completer<void>();

    try {
      _log('Deleting data from store');
      final delRequest = store.delete(fingerprint.toJS);

      delRequest.onsuccess = ((web.Event event) {
        _log('Entry removed successfully');
        completer.complete();
      }).toJS;

      delRequest.onerror = ((web.Event event) {
        _log('Error removing entry: ${delRequest.error}');
        completer.completeError(
          'Failed to remove URL from IndexedDB: ${delRequest.error}',
        );
      }).toJS;
    } catch (e) {
      _log('Exception in remove operation: $e');
      completer.completeError('Error in remove operation: $e');
    }

    return completer.future;
  }
}