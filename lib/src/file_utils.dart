// Export interfaces
export 'file_utils/file_utils_interface.dart';

// Conditionally export implementations
export 'file_utils/file_utils_web.dart' if (dart.library.io) 'file_utils/file_utils_mobile.dart';