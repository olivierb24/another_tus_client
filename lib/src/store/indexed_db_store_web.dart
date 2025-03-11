import 'dart:async';
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

  /// Reference to the opened IndexedDB database
  web.IDBDatabase? _db;

  TusIndexedDBStore({
    this.dbName = 'tus_uploads',
    this.storeName = 'files',
    this.dbVersion = 1,
  });

  /// Opens (or creates) the DB if not already open
  Future<web.IDBDatabase> _openDatabase() async {
    if (!kIsWeb) {
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    if (_db != null) {
      return _db!;
    }

    final completer = Completer<web.IDBDatabase>();

    try {
      final request = web.window.indexedDB.open(dbName, dbVersion);

      request.onupgradeneeded = ((web.Event event) {
        final db = request.result;
        if (db is web.IDBDatabase) {
          if (!db.objectStoreNames.contains(storeName)) {
            db.createObjectStore(storeName);
          }
        }
      }).toJS;

      request.onsuccess = ((web.Event event) {
        final result = request.result;
        if (result is web.IDBDatabase) {
          _db = result;
          completer.complete(result);
        } else {
          completer.completeError('Unexpected result type');
        }
      }).toJS;

      request.onerror = ((web.Event event) {
        completer.completeError('Failed to open IndexedDB: ${request.error}');
      }).toJS;
    } catch (e) {
      completer.completeError('Error opening IndexedDB: $e');
    }

    return completer.future;
  }

  @override
  Future<void> set(String fingerprint, Uri url) async {
    if (!kIsWeb) {
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    final db = await _openDatabase();
    final txn = db.transaction(storeName.toJS, 'readwrite');
    final store = txn.objectStore(storeName);

    final completer = Completer<void>();

    try {
      final putRequest = store.put(url.toString().toJS, fingerprint.toJS);

      putRequest.onsuccess = ((web.Event event) {
        completer.complete();
      }).toJS;

      putRequest.onerror = ((web.Event event) {
        completer.completeError(
          'Failed to store URL in IndexedDB: ${putRequest.error}',
        );
      }).toJS;
    } catch (e) {
      completer.completeError('Error in set operation: $e');
    }

    return completer.future;
  }

  @override
  Future<Uri?> get(String fingerprint) async {
    if (!kIsWeb) {
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    final db = await _openDatabase();
    final txn = db.transaction(storeName.toJS, 'readonly');
    final store = txn.objectStore(storeName);

    final completer = Completer<Uri?>();

    try {
      final getRequest = store.get(fingerprint.toJS);

      getRequest.onsuccess = ((web.Event event) {
        final value = getRequest.result;
        if (value != null && value is String && (value as String).isNotEmpty) {
          completer.complete(Uri.parse(value as String));
        } else {
          completer.complete(null);
        }
      }).toJS;

      getRequest.onerror = ((web.Event event) {
        completer.completeError(
          'Failed to retrieve URL from IndexedDB: ${getRequest.error}',
        );
      }).toJS;
    } catch (e) {
      completer.completeError('Error in get operation: $e');
    }

    return completer.future;
  }

  @override
  Future<void> remove(String fingerprint) async {
    if (!kIsWeb) {
      throw UnsupportedError('IndexedDB is only supported in web contexts');
    }

    final db = await _openDatabase();
    final txn = db.transaction(storeName.toJS, 'readwrite');
    final store = txn.objectStore(storeName);

    final completer = Completer<void>();

    try {
      final delRequest = store.delete(fingerprint.toJS);

      delRequest.onsuccess = ((web.Event event) {
        completer.complete();
      }).toJS;

      delRequest.onerror = ((web.Event event) {
        completer.completeError(
          'Failed to remove URL from IndexedDB: ${delRequest.error}',
        );
      }).toJS;
    } catch (e) {
      completer.completeError('Error in remove operation: $e');
    }

    return completer.future;
  }
}