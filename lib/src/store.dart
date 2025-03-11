// Export interfaces and implementations
export 'store/store_interface.dart';
export 'store/memory_store.dart';
export 'store/file_store.dart';
// Conditionally export IndexedDBStore implementation
export 'store/indexed_db_store_web.dart' 
    if (dart.library.io) 'store/indexed_db_store_mobile.dart';