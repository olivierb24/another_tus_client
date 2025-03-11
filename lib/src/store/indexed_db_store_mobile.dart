import 'dart:async';
import 'store_interface.dart';

/// Stub implementation of [TusIndexedDBStore] for mobile platforms.
class TusIndexedDBStore implements TusStore {
  final String dbName;
  final String storeName;
  final int dbVersion;

  TusIndexedDBStore({
    this.dbName = 'tus_uploads',
    this.storeName = 'files',
    this.dbVersion = 1,
  });

  @override
  Future<void> set(String fingerprint, Uri url) async {
    throw UnsupportedError('TusIndexedDBStore is only supported on web platforms');
  }

  @override
  Future<Uri?> get(String fingerprint) async {
    throw UnsupportedError('TusIndexedDBStore is only supported on web platforms');
  }

  @override
  Future<void> remove(String fingerprint) async {
    throw UnsupportedError('TusIndexedDBStore is only supported on web platforms');
  }
}